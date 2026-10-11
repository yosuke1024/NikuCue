import Combine
import Foundation
import NikuCueDomain
import SpriteKit

/// Turns `ReactionIntent`s into rig actions. Owns the display queue (one running + one waiting),
/// the ambient state, pause/resume and Reduce Motion. It never writes to the database (docs/06 §5).
@MainActor
final class CatSceneController: ObservableObject {
    let rig: CatRig
    let library: AnimationLibrary
    private(set) var queue = ReactionQueue()

    /// Message key of the bubble currently shown (cleared after the reaction's dwell time, not when motion ends).
    @Published private(set) var messageKey: String?
    @Published private(set) var currentClip: ClipID = .idle
    @Published private(set) var ambient: CatAmbientState = .idle
    @Published var reduceMotion: Bool = false {
        didSet { if reduceMotion != oldValue { restartAmbient() } }
    }
    /// Independent reasons to pause; the controller runs only while none is active (docs/04 §5).
    enum PauseReason: Hashable {
        case sceneInactive   // app not active (scenePhase)
        case modal           // purchase / consent sheet in front of the cat
        case sceneLeft       // Home (or the demo) is not on screen
    }
    private var pauseReasons: Set<PauseReason> = []
    var isPaused: Bool { !pauseReasons.isEmpty }
    /// Which screen currently drives the scene ("home", "demo", "gallery", "onboarding"). Leaves from another
    /// owner are ignored, so NavigationStack appear/disappear ordering cannot pause the newly shown screen.
    private(set) var sceneOwner: String?

    /// Called when a reaction actually starts (used to record milestone / all-done tokens).
    var onReactionStarted: ((ReactionIntent) -> Void)?
    /// Re-validation of a waiting intent right before it starts (stale revision, other day, undone).
    var isStillValid: ((ReactionIntent) -> Bool)?

    private var running: [AnimationLibrary.ScheduledAction] = []
    private var ambientActions: [AnimationLibrary.ScheduledAction] = []
    private var finishWork: DispatchWorkItem?
    private var dwellWork: DispatchWorkItem?
    /// Pending start of a queued reaction after the inter-reaction beat (`reactionGapMs`).
    private var gapWork: DispatchWorkItem?
    /// Pending speech bubble (`messageAtMs`): the cat reacts first, then speaks.
    private var messageWork: DispatchWorkItem?
    /// Linger of the finished reaction's look, from its clip (`lingerMs`).
    private var runningLinger: TimeInterval = 0
    static let lingerKey = "ambient.linger"
    private var rng: SeededRandomNumberGenerator
    private var heartNodes: [SKNode] = []
    private let hostNode: SKNode

    init(rig: CatRig, library: AnimationLibrary, host: SKNode, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.rig = rig
        self.library = library
        self.hostNode = host
        self.rng = SeededRandomNumberGenerator(seed: seed)
        startAmbient()
    }

    // MARK: Scene lifecycle

    /// A screen became visible: it takes ownership, ambient restarts; nothing stale is replayed (docs/05 §3).
    func enterScene(ambient state: CatAmbientState, owner: String = "home") {
        sceneOwner = owner
        pauseReasons.remove(.sceneLeft)
        queue.discardAll()
        stopInteraction()
        ambient = state
        clearMessage()
        if !isPaused { startAmbient() }
    }

    /// The owning screen left: drop queued reactions, stop actions. Ignored when another screen already took over.
    func leaveScene(owner: String = "home") {
        guard sceneOwner == nil || sceneOwner == owner else { return }
        sceneOwner = nil
        pause(.sceneLeft)
    }

    func pause(_ reason: PauseReason) {
        let wasPaused = isPaused
        pauseReasons.insert(reason)
        guard !wasPaused else { return }
        queue.discardAll()
        stopInteraction()
        stopAmbient()
        clearMessage()
    }

    func resume(_ reason: PauseReason) {
        guard pauseReasons.contains(reason) else { return }
        pauseReasons.remove(reason)
        guard !isPaused else { return }
        startAmbient()
    }

    /// App activity (scenePhase). Other pause reasons (modal, scene left) stay in force independently.
    func setPaused(_ paused: Bool) {
        if paused { pause(.sceneInactive) } else { resume(.sceneInactive) }
    }

    /// Time-of-day changed (night → doze). Never interrupts a running interaction.
    func setAmbient(_ state: CatAmbientState) {
        guard state != ambient else { return }
        ambient = state
        if !queue.isBusy { restartAmbient() }
    }

    // MARK: Reactions

    func handle(_ intent: ReactionIntent) {
        guard !isPaused else { return }
        switch queue.enqueue(intent) {
        case .startNow(let i): start(i)
        case .queued, .dropped: break
        }
    }

    /// An undo arrived: cancel the celebration for that habit/day and return to ambient quietly. A still-valid
    /// waiting reaction (another habit) starts next instead of being stranded.
    func cancelReactions(habitId: UUID, dayKey: DayKey) {
        let cancelledRunning = queue.cancel { $0.event.habitId == habitId && $0.event.dayKey == dayKey }
        if cancelledRunning {
            stopInteraction()
            clearMessage()
            if let next = queue.finishCurrent(isStillValid: { [weak self] intent in self?.isStillValid?(intent) ?? true }) {
                start(next)
            } else {
                startAmbient()
            }
        }
    }

    /// Demo/gallery entry point: plays a clip directly with no reaction bookkeeping.
    func playDemo(_ clip: ClipID, messageKey: String? = nil, dayKey: DayKey) {
        let event = CatEvent(kind: .userRequestedEncouragement, occurredAt: Date(), dayKey: dayKey, isDemo: true)
        let intent = ReactionIntent(reactionId: "demo.\(clip.rawValue)", clip: clip, expression: clip.defaultExpression,
                                    priority: 0, messageKey: messageKey ?? "", textDwellMs: 4000, event: event)
        if clip == .idle || clip == .doze {
            queue.discardAll()
            stopInteraction()
            ambient = clip == .doze ? .dozing : .idle
            startAmbient()
            return
        }
        // start() stops ambient/interaction without resetting and then settles the rig, so the demo path eases a
        // swaying tail or a breathing body back exactly like a real reaction instead of snapping it.
        stopInteraction(resetting: false)
        queue.discardAll()
        _ = queue.enqueue(intent)
        start(intent)
    }

    private func start(_ intent: ReactionIntent) {
        guard let clip = library.spec.clip(intent.clip) else {
            _ = queue.finishCurrent { _ in false }
            return
        }
        stopAmbient(resetting: false)
        stopInteraction(resetting: false)
        currentClip = intent.clip
        let tracks = reduceMotion ? clip.reducedMotionTracks : clip.tracks
        // Driven properties snap to rest (their track takes over next frame); the rest (idle tail sway, breathing)
        // ease back over the blend time so the reaction never starts with a jump.
        var controlled: CatRig.ControlledProperties = [:]
        for track in tracks { controlled[track.node, default: []].insert(track.property) }
        rig.settle(toRestOver: library.spec.expressionBlend, controlled: controlled)
        // The look at t = 0 is applied synchronously: the expression track's SKAction only evaluates once an SKView
        // drives the scene, and the pose must not lag a frame behind the clip. Later keyframes still come from the
        // track; `setLook` ignores same-look calls, so there is no double cross-fade.
        let initialLook = tracks.first { $0.property == "expression" }.flatMap { KeyframeSampler.name($0, at: 0) } ?? clip.defaultLook
        rig.setLook(initialLook, blend: library.spec.expressionBlend)
        running = library.actions(for: clip, reducedMotion: reduceMotion, rig: rig)
        for item in running { item.node.run(item.action, withKey: item.key) }
        if intent.clip == .milestone, let hearts = clip.hearts { spawnHearts(hearts) }
        onReactionStarted?(intent)
        if !intent.messageKey.isEmpty {
            showMessage(intent.messageKey, dwellMs: intent.textDwellMs, after: reduceMotion ? 0 : clip.messageDelay)
        }
        runningLinger = clip.linger

        let work = DispatchWorkItem { [weak self] in self?.finishCurrent() }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + clip.duration, execute: work)
    }

    /// Ends the running reaction (called when its clip time is over; internal so tests can drive it without a clock).
    /// The ambient loop resumes at once with the reaction's last look held for the clip's linger. A queued reaction
    /// starts after a short beat (`reactionGapMs`) and is re-validated at that moment.
    func finishCurrent() {
        finishWork = nil
        let heldLook = rig.look
        let linger = runningLinger
        runningLinger = 0
        stopInteraction()
        guard !isPaused else { queue.discardAll(); return }
        let next = queue.finishCurrent { [weak self] intent in self?.isStillValid?(intent) ?? true }
        guard let next else {
            startAmbient(holding: heldLook, for: linger)
            return
        }
        let gap = library.spec.reactionGap
        guard gap > 0 else { start(next); return }
        startAmbient(holding: heldLook, for: max(linger, gap))
        let work = DispatchWorkItem { [weak self] in self?.startAfterGap(next) }
        gapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: work)
    }

    private func startAfterGap(_ intent: ReactionIntent) {
        gapWork = nil
        guard !isPaused, queue.current == intent else { return }
        if isStillValid?(intent) ?? true {
            start(intent)
            return
        }
        // Undone or stale during the beat: drop it quietly (the ambient loop is already running).
        if let next = queue.finishCurrent(isStillValid: { [weak self] i in self?.isStillValid?(i) ?? true }) {
            start(next)
        } else {
            currentClip = ambient == .dozing ? .doze : .idle
        }
    }

    private func stopInteraction(resetting: Bool = true) {
        finishWork?.cancel()
        finishWork = nil
        gapWork?.cancel()
        gapWork = nil
        for item in running { item.node.removeAction(forKey: item.key) }
        running = []
        removeHearts()
        if resetting { rig.resetToRest() }
    }

    // MARK: Ambient

    /// Starts the ambient loop. `heldLook` (the look a reaction ended on) stays for `hold` seconds while breathing
    /// resumes, then cross-fades to the ambient look; the hold is an ambient action, so a new reaction, a pause or a
    /// time-of-day change cancels it.
    private func startAmbient(holding heldLook: String? = nil, for hold: TimeInterval = 0) {
        stopAmbient()
        let clipId: ClipID = ambient == .dozing ? .doze : .idle
        currentClip = clipId
        guard let clip = library.spec.clip(clipId) else { return }
        rig.resetToRest()
        let blend = library.spec.expressionBlend
        if let heldLook, hold > 0, heldLook != clip.defaultLook, rig.look == heldLook {
            let target = clip.defaultLook
            let release = SKAction.run { [weak self] in self?.rig.setLook(target, blend: blend) }
            hostNode.run(.sequence([.wait(forDuration: hold), release]), withKey: CatSceneController.lingerKey)
        } else {
            rig.setLook(clip.defaultLook, blend: blend)
        }
        ambientActions = library.actions(for: clip, reducedMotion: reduceMotion, rig: rig)
        for item in ambientActions { item.node.run(item.action, withKey: item.key) }
        // Blinks exist only on the parts rig; whole-body textures are never stretched to fake one (asset README §6).
        if clipId == .idle && !reduceMotion && rig.hasEyeParts && (library.spec.ambient.blink.enabled ?? true) { scheduleBlink() }
    }

    private func restartAmbient() {
        guard !queue.isBusy else { return }
        startAmbient()
    }

    private func stopAmbient(resetting: Bool = true) {
        for item in ambientActions { item.node.removeAction(forKey: item.key) }
        ambientActions = []
        hostNode.removeAction(forKey: "blink.schedule")
        hostNode.removeAction(forKey: CatSceneController.lingerKey)
        for id in ["eyeL", "eyeR"] { rig.node(id)?.removeAction(forKey: "blink.\(id)") }
        if resetting { rig.resetToRest() }
    }

    private func scheduleBlink() {
        let interval = library.nextBlinkInterval(using: &rng)
        let wait = SKAction.wait(forDuration: interval)
        let blink = SKAction.run { [weak self] in
            guard let self, !self.queue.isBusy, !self.isPaused else { return }
            for item in self.library.blinkActions(rig: self.rig) { item.node.run(item.action, withKey: item.key) }
            self.scheduleBlink()
        }
        hostNode.run(.sequence([wait, blink]), withKey: "blink.schedule")
    }

    // MARK: Hearts (milestone only, max three, never full screen)

    private func spawnHearts(_ hearts: AnimationSpec.Hearts) {
        removeHearts()
        if reduceMotion {
            guard let heart = rig.makeHeart() else { return }
            heart.position = CGPoint(x: hearts.reducedMotion.position[0], y: hearts.reducedMotion.position[1])
            heart.setScale(CGFloat(hearts.reducedMotion.scale))
            rig.root.addChild(heart)
            heartNodes = [heart]
            return
        }
        for (index, delayMs) in hearts.spawnAtMs.prefix(hearts.max).enumerated() {
            guard index < hearts.positions.count, let heart = rig.makeHeart() else { continue }
            let p = hearts.positions[index]
            heart.position = CGPoint(x: p[0], y: p[1])
            heart.alpha = 0
            heart.setScale(CGFloat(hearts.scale) * 0.6)
            rig.root.addChild(heart)
            heartNodes.append(heart)
            let life = hearts.lifeMs / 1000
            let appear = SKAction.group([.fadeIn(withDuration: life * 0.15), .scale(to: CGFloat(hearts.scale), duration: life * 0.3)])
            let rise = SKAction.moveBy(x: 0, y: CGFloat(hearts.riseUnits), duration: life)
            rise.timingMode = .easeOut
            let fade = SKAction.sequence([.wait(forDuration: life * 0.15), .fadeOut(withDuration: life * 0.85)])
            heart.run(.sequence([.wait(forDuration: delayMs / 1000), .group([appear, rise, fade]), .removeFromParent()]), withKey: "heart")
        }
    }

    private func removeHearts() {
        for h in heartNodes { h.removeAllActions(); h.removeFromParent() }
        heartNodes = []
    }

    // MARK: Message bubble

    /// Shows the bubble after `delay` (the dwell time starts when it appears, docs/05 §6: readable ~4 s).
    private func showMessage(_ key: String, dwellMs: Int, after delay: TimeInterval = 0) {
        messageWork?.cancel()
        messageWork = nil
        guard delay > 0 else { presentMessage(key, dwellMs: dwellMs); return }
        let work = DispatchWorkItem { [weak self] in
            self?.messageWork = nil
            self?.presentMessage(key, dwellMs: dwellMs)
        }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func presentMessage(_ key: String, dwellMs: Int) {
        dwellWork?.cancel()
        messageKey = key
        let work = DispatchWorkItem { [weak self] in self?.messageKey = nil }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(dwellMs) / 1000, execute: work)
    }

    private func clearMessage() {
        messageWork?.cancel()
        messageWork = nil
        dwellWork?.cancel()
        dwellWork = nil
        messageKey = nil
    }

    /// For diagnostics/tests: number of actions currently attached to rig nodes (QA Q40: must stay bounded).
    var activeActionCount: Int {
        rig.nodes.values.reduce(0) { $0 + ($1.hasActions() ? 1 : 0) } + (hostNode.hasActions() ? 1 : 0)
    }
}
