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
        stopInteraction()
        queue.discardAll()
        _ = queue.enqueue(intent)
        start(intent)
    }

    private func start(_ intent: ReactionIntent) {
        guard let clip = library.spec.clip(intent.clip) else {
            _ = queue.finishCurrent { _ in false }
            return
        }
        stopAmbient()
        stopInteraction()
        rig.resetToRest()
        currentClip = intent.clip
        // Clips with an expression track set their own expression on the first frame; avoid a double crossfade.
        let tracks = reduceMotion ? clip.reducedMotionTracks : clip.tracks
        if !tracks.contains(where: { $0.property == "expression" }) {
            rig.setExpression(clip.defaultExpression, blend: library.spec.expressionBlend)
        }
        running = library.actions(for: clip, reducedMotion: reduceMotion, rig: rig)
        for item in running { item.node.run(item.action, withKey: item.key) }
        if intent.clip == .milestone, let hearts = clip.hearts { spawnHearts(hearts) }
        onReactionStarted?(intent)
        if !intent.messageKey.isEmpty { showMessage(intent.messageKey, dwellMs: intent.textDwellMs) }

        let work = DispatchWorkItem { [weak self] in self?.finishCurrent() }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + clip.duration, execute: work)
    }

    private func finishCurrent() {
        finishWork = nil
        stopInteraction()
        guard !isPaused else { queue.discardAll(); return }
        let next = queue.finishCurrent { [weak self] intent in self?.isStillValid?(intent) ?? true }
        if let next {
            start(next)
        } else {
            currentClip = ambient == .dozing ? .doze : .idle
            startAmbient()
        }
    }

    private func stopInteraction() {
        finishWork?.cancel()
        finishWork = nil
        for item in running { item.node.removeAction(forKey: item.key) }
        running = []
        removeHearts()
        rig.resetToRest()
    }

    // MARK: Ambient

    private func startAmbient() {
        stopAmbient()
        let clipId: ClipID = ambient == .dozing ? .doze : .idle
        currentClip = clipId
        guard let clip = library.spec.clip(clipId) else { return }
        rig.resetToRest()
        rig.setExpression(clip.defaultExpression, blend: library.spec.expressionBlend)
        ambientActions = library.actions(for: clip, reducedMotion: reduceMotion, rig: rig)
        for item in ambientActions { item.node.run(item.action, withKey: item.key) }
        if clipId == .idle && !reduceMotion { scheduleBlink() }
    }

    private func restartAmbient() {
        guard !queue.isBusy else { return }
        startAmbient()
    }

    private func stopAmbient() {
        for item in ambientActions { item.node.removeAction(forKey: item.key) }
        ambientActions = []
        hostNode.removeAction(forKey: "blink.schedule")
        for id in ["eyeL", "eyeR"] { rig.node(id)?.removeAction(forKey: "blink.\(id)") }
        rig.resetToRest()
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

    private func showMessage(_ key: String, dwellMs: Int) {
        dwellWork?.cancel()
        messageKey = key
        let work = DispatchWorkItem { [weak self] in self?.messageKey = nil }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(dwellMs) / 1000, execute: work)
    }

    private func clearMessage() {
        dwellWork?.cancel()
        dwellWork = nil
        messageKey = nil
    }

    /// For diagnostics/tests: number of actions currently attached to rig nodes (QA Q40: must stay bounded).
    var activeActionCount: Int {
        rig.nodes.values.reduce(0) { $0 + ($1.hasActions() ? 1 : 0) } + (hostNode.hasActions() ? 1 : 0)
    }
}
