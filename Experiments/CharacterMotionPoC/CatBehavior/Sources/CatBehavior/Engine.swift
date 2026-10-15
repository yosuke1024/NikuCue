// The behaviour engine: chooses activities, runs their plans on the motor, and lets the person interrupt at any
// time without breaking the body. Renderers read `RenderState` every frame and apply it (Spine track 0/1 and the
// skeleton's x / scaleX, or a SpriteKit flipbook); they never decide anything themselves.

/// Something the person (or the habit layer) did.
public enum Stimulus: Sendable, Equatable {
    /// Tap on the character.
    case pet(at: Point)
    /// Tap on the room: "come here".
    case call(to: Point)
    /// A habit was completed (from the reaction engine): celebrate together.
    case celebrate
    /// A habit was skipped: calm "resting is fine" (never sadness).
    case encourageRest

    public var kind: StimulusKind {
        switch self {
        case .pet: return .pet
        case .call: return .call
        case .celebrate: return .celebrate
        case .encourageRest: return .encourageRest
        }
    }

    var priority: Int {
        switch self {
        case .celebrate: return 3
        case .pet, .encourageRest: return 2
        case .call: return 1
        }
    }
}

public enum StimulusKind: String, Sendable, Equatable, Codable {
    case pet, call, celebrate, encourageRest
}

public enum EngineEvent: Sendable, Equatable {
    case activityStarted(ActivityKind)
    case activityFinished(ActivityKind)
    case clipStarted(String, mix: Double)
    case facingChanged(Facing)
    case walkPlanned(from: Double, to: Double)
    case stopRequested(x: Double, phase: Double)
    case arrived(x: Double, phase: Double)
    case stimulusReceived(StimulusKind)
    /// The body starts its reaction.
    case stimulusApplied(StimulusKind)
    /// Answered with a glance only (busy with something more important, or a repeated tap during cooldown).
    case stimulusAcknowledged(StimulusKind, reason: String)
    case stimulusDropped(StimulusKind, reason: String)
    case paused(Bool)
    case reducedMotion(Bool)
}

public struct TimedEvent: Sendable, Equatable {
    public var time: Double
    public var event: EngineEvent
}

/// Track-1 "look at" overlay. A new `serial` starts it; nil means fade it out over `RenderState.lookOutMix`.
public struct LookOutput: Sendable, Equatable {
    public var clip: String
    public var alpha: Double
    public var mixIn: Double
    public var serial: Int
    /// Smoothed gaze point in stage units (the renderer aims the IK target bone here).
    public var target: Point
}

public struct RenderState: Sendable, Equatable {
    public var time: Double
    /// Root position on the floor (stage units) and facing (skeleton scaleX sign).
    public var x: Double
    public var facing: Facing
    public var base: BaseTrack
    /// Playback rate of the base clip for this frame (locomotion: exactly matches the root's movement).
    public var baseTimeScale: Double
    /// Where the engine expects the base clip to be after this frame (renderers can check drift against it).
    public var baseClipTime: Double
    public var look: LookOutput?
    public var lookOutMix: Double
    public var mode: MotorMode
    public var activity: ActivityKind
    public var reducedMotion: Bool
    public var paused: Bool
}

struct Gaze: Sendable {
    private(set) var active = false
    private(set) var serial = 0
    private(set) var current = Point(x: 0, y: 0)
    private(set) var target = Point(x: 0, y: 0)
    private var holdUntil: Double = -1

    /// Look at `p` until `until` (engine time). Re-aiming while active glides instead of snapping.
    mutating func look(at p: Point, until: Double, from origin: Point) {
        if !active {
            active = true
            serial += 1
            current = origin
        }
        target = p
        holdUntil = max(holdUntil, until)
    }

    mutating func stop() {
        active = false
        holdUntil = -1
    }

    mutating func advance(_ dt: Double, now: Double) {
        guard active else { return }
        if now >= holdUntil {
            active = false
            return
        }
        // critically damped follow, time constant ~0.12 s: the head turns, it does not jump
        let k = 1 - 1 / (1 + dt / 0.12 + (dt / 0.12) * (dt / 0.12) * 0.5)
        current.x += (target.x - current.x) * k
        current.y += (target.y - current.y) * k
    }
}

public struct EngineConfig: Sendable, Equatable {
    /// Longest frame the engine integrates; a longer hitch slows the motion instead of jumping it.
    public var maxStep: Double = 1.0 / 20.0
    /// A repeated tap on the character within this time only gets a glance.
    public var petCooldown: Double = 2.0
    public var glanceSeconds: Double = 0.9

    public init() {}
}

public struct CatBehaviorEngine: Sendable {
    public let profile: MotionProfile
    public let stage: StageLayout
    public let config: EngineConfig
    public private(set) var time: Double = 0
    public private(set) var mood = Mood()
    public private(set) var isPaused = false
    public private(set) var reducedMotion = false

    private var motor: Motor
    private var navigator: Navigator
    private var builder: PlanBuilder
    private var selector = ActivitySelector()
    private var rng: SplitMix64
    private var plan: Plan?
    private var pending: Stimulus?
    /// Where a waiting pet touched the body, relative to the root and the facing at the time of the tap (the body
    /// may walk on before it can react; the reaction answers the touched spot, not the empty floor behind).
    private var pendingPetOffset: Double = 0
    /// The next step is the first after a pause: it integrates nothing (the time away is not motion).
    private var resumeFrame = false
    private var lastCompletion: Motor.Completion = .none
    private var gaze = Gaze()
    private var petCooldownUntil: Double = -1
    private var events: [TimedEvent] = []

    public init(profile: MotionProfile, stage: StageLayout, seed: UInt64, startX: Double? = nil,
                facing: Facing = .right, config: EngineConfig = EngineConfig()) {
        self.profile = profile
        self.stage = stage
        self.config = config
        navigator = Navigator(stage: stage, profile: profile)
        builder = PlanBuilder(profile: profile, stage: stage)
        rng = SplitMix64(seed: seed)
        let x = navigator.clampToFloor(startX ?? (stage.minX + stage.maxX) / 2)
        motor = Motor(profile: profile, x: x, facing: facing)
        startPlan(builder.plan(.settle, x: x, facing: facing, rng: &rng))
    }

    // MARK: Inputs

    public mutating func send(_ stimulus: Stimulus) {
        log(.stimulusReceived(stimulus.kind))
        guard !isPaused else {
            log(.stimulusDropped(stimulus.kind, reason: "paused"))
            return
        }
        // the gaze answers at once, whatever the body is doing
        glance(at: stimulus)
        if case .pet = stimulus, time < petCooldownUntil {
            log(.stimulusAcknowledged(.pet, reason: "cooldown"))
            return
        }
        // One waiting slot (like ReactionQueue): a more important reaction running or waiting keeps its place.
        // Equal priority: a celebration queues behind a celebration, a new "come here" replaces the old one,
        // a pet / rest answer already running just gets the glance.
        let running = plan.map { reactionPriority($0.kind) } ?? 0
        if let waiting = pending, waiting.priority > stimulus.priority {
            log(.stimulusAcknowledged(stimulus.kind, reason: "busy"))
            return
        }
        if running > stimulus.priority || (running == stimulus.priority && stimulus.kind != .celebrate && stimulus.kind != .call) {
            log(.stimulusAcknowledged(stimulus.kind, reason: "busy"))
            return
        }
        if let waiting = pending { log(.stimulusDropped(waiting.kind, reason: "replaced")) }
        pending = stimulus
        if case .pet(let p) = stimulus { pendingPetOffset = (p.x - motor.x) * motor.facing.sign }
    }

    public mutating func setReducedMotion(_ on: Bool) {
        guard on != reducedMotion else { return }
        reducedMotion = on
        log(.reducedMotion(on))
        if on, motor.mode == .walking {
            motor.stopSoon()
            plan?.truncateAfterCurrent()
        }
    }

    /// App backgrounded / screen left: nothing advances, waiting reactions are discarded and a running reaction ends
    /// after the step it is in (a hop still lands), so nothing old is replayed on return (docs/05 §3). The first
    /// frame after resuming counts from zero, whatever time the host reports for it.
    public mutating func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            if let p = pending {
                log(.stimulusDropped(p.kind, reason: "paused"))
                pending = nil
            }
            if let kind = plan?.kind, reactionPriority(kind) > 0 { plan?.truncateAfterCurrent() }
        } else {
            resumeFrame = true
        }
        log(.paused(paused))
    }

    public mutating func drainEvents() -> [TimedEvent] {
        defer { events.removeAll() }
        return events
    }

    // MARK: Frame

    public mutating func step(_ rawDt: Double) -> RenderState {
        guard !isPaused else { return render() }
        let dt = resumeFrame ? 0 : clamp(rawDt, 0, config.maxStep)
        resumeFrame = false
        // decisions use the state at the start of the frame; clips started here begin at this frame's start
        handleCompletion(lastCompletion)
        handlePending()
        if plan == nil { chooseNext() }
        runPlan(dt)
        // integration
        lastCompletion = motor.advance(dt)
        time += dt
        gaze.advance(dt, now: time)
        // walking past what it was looking at: the look ends rather than twisting over the shoulder
        if gaze.active, isBehind(gaze.target) || isBehind(gaze.current) { gaze.stop() }
        mood.tick(dt, mode: motor.mode)
        for e in motor.drainEvents() { events.append(TimedEvent(time: time - dt, event: e)) }
        return render()
    }

    public var x: Double { motor.x }
    public var facing: Facing { motor.facing }
    public var mode: MotorMode { motor.mode }
    public var activity: ActivityKind { plan?.kind ?? .idle }

    // MARK: Plans

    private mutating func chooseNext() {
        let available = Set(stage.spots.map(\.kind))
        let kind = selector.choose(mood: mood, time: time, reducedMotion: reducedMotion, available: available, rng: &rng)
        startPlan(builder.plan(kind, x: motor.x, facing: motor.facing, rng: &rng))
    }

    private mutating func startPlan(_ p: Plan) {
        if let old = plan {
            log(.activityFinished(old.kind))
            mood.finished(old.kind)
        }
        plan = p
        selector.record(p.kind, at: time)
        log(.activityStarted(p.kind))
    }

    private mutating func finishPlan() {
        if let old = plan {
            log(.activityFinished(old.kind))
            mood.finished(old.kind)
        }
        plan = nil
    }

    private mutating func handleCompletion(_ c: Motor.Completion) {
        lastCompletion = .none
        switch c {
        case .none:
            break
        case .arrived:
            motor.stand(resting: false, mix: profile.mix.walkToIdle, freezePrevious: true)
            if var p = plan, case .walk = p.current { p.advanceStep(); plan = p }
        case .turnFinished:
            motor.stand(resting: false, mix: profile.mix.turnToIdle)
            if var p = plan {
                if p.turningFirst {
                    p.turningFirst = false           // the step that needed the turn starts now
                } else if case .face = p.current {
                    p.advanceStep()
                } else if case .faceTowards = p.current {
                    p.advanceStep()
                }
                plan = p
            }
        case .hopFinished:
            motor.stand(resting: false, mix: profile.mix.hopToIdle)
            if var p = plan, case .hop = p.current { p.advanceStep(); plan = p }
        }
        if plan?.isFinished == true { finishPlan() }
    }

    private func reactionPriority(_ kind: ActivityKind) -> Int {
        switch kind {
        case .celebrateReaction: return 3
        case .petReaction, .restReaction: return 2
        case .callReaction: return 1
        default: return 0
        }
    }

    private mutating func handlePending() {
        guard let s = pending else { return }
        let running = plan.map { reactionPriority($0.kind) } ?? 0
        // an equal-priority reaction (e.g. a second celebration) waits for the running one to finish
        if running >= s.priority, !(s.kind == .call && plan?.kind == .callReaction), plan != nil {
            return
        }
        switch motor.mode {
        case .turning, .hopping:
            return                                   // a turn (0.27 s) or a hop finishes first; the glance already answered
        case .walking:
            if case .call(let p) = s, !reducedMotion, retargetWalk(towards: p) {
                pending = nil
                return
            }
            motor.stopSoon()
            plan?.truncateAfterCurrent()
            return                                   // the reaction starts once the feet are planted
        case .standing, .resting:
            pending = nil
            var reaction = s
            if case .pet(let p) = s {
                petCooldownUntil = time + config.petCooldown
                reaction = .pet(at: Point(x: motor.x + pendingPetOffset * motor.facing.sign, y: p.y))
            }
            startPlan(builder.reaction(reaction, x: motor.x, facing: motor.facing))
            log(.stimulusApplied(s.kind))
        }
    }

    /// "Come here" while already walking that way: keep walking and move the destination (no stop, no restart).
    private mutating func retargetWalk(towards p: Point) -> Bool {
        let direction = motor.facing.towards(p.x, from: motor.x)
        guard direction == motor.facing, abs(p.x - motor.x) > profile.walk.strideLength * 0.3,
              let walk = navigator.plannedWalk(from: motor.x, desiredX: p.x, startPhases: [motor.walkPhase],
                                               tolerance: profile.walk.strideLength,
                                               minimumDistance: max(motor.brakingDistance, profile.walk.strideLength * 0.25))
        else { return false }
        motor.retarget(to: walk.target, cruise: 1.05)
        var reaction = builder.reaction(.call(to: p), x: motor.x, facing: motor.facing)
        // the walk is already running: resume the new plan at its walk step
        if let i = reaction.steps.firstIndex(where: { if case .walk = $0 { return true } else { return false } }) {
            reaction.index = i
            reaction.started = true
        }
        startPlan(reaction)
        log(.stimulusApplied(.call))
        return true
    }

    private mutating func runPlan(_ dt: Double) {
        var guardCount = 0
        while var p = plan, let step = p.current, guardCount < 8 {
            guardCount += 1
            if p.turningFirst { return }                // the step starts when its turn finishes (handleCompletion)
            if !p.started {
                let done = start(step, plan: &p)
                plan = p
                if done {
                    p.advanceStep()
                    plan = p
                    if p.isFinished { finishPlan(); return }
                    continue
                }
                return
            }
            p.stepTime += dt
            switch step {
            case .stand(let s), .rest(let s):
                if p.stepTime >= s { p.advanceStep() }
            case .look(_, let s):
                if p.stepTime >= s {
                    gaze.stop()
                    p.advanceStep()
                }
            case .walk, .face, .faceTowards, .hop:
                break                                    // completed by motor events
            }
            plan = p
            if p.isFinished { finishPlan(); return }
            if p.started { return }                      // still running this step
        }
    }

    /// Starts a step. Returns true when it completes immediately (nothing to do).
    private mutating func start(_ step: Step, plan p: inout Plan) -> Bool {
        p.started = true
        p.stepTime = 0
        switch step {
        case .walk(let desiredX, let tolerance, let cruise):
            guard !reducedMotion, motor.isStanding else { return true }
            guard let walk = navigator.plannedWalk(from: motor.x, desiredX: desiredX, startPhases: navigator.standingStartPhases,
                                                   tolerance: tolerance) else { return true }
            let direction = motor.facing.towards(walk.target, from: motor.x)
            if direction != motor.facing {
                p.started = false
                p.turningFirst = true
                gaze.stop()
                motor.startTurn()
                return false
            }
            gaze.stop()
            motor.startWalk(to: walk.target, startPhase: walk.startPhase, cruise: cruise)
            return false
        case .face(let f):
            guard f != motor.facing, motor.isStanding else { return true }
            gaze.stop()
            motor.startTurn()
            return false
        case .faceTowards(let tx):
            guard motor.facing.towards(tx, from: motor.x) != motor.facing, motor.isStanding else { return true }
            gaze.stop()
            motor.startTurn()
            return false
        case .stand:
            if motor.isStanding { motor.stand(resting: false) }
            return false
        case .rest:
            if motor.isStanding { motor.stand(resting: true) }
            return false
        case .look(let target, let seconds):
            if motor.mode == .resting { motor.stand(resting: false) }
            gaze.look(at: ahead(target), until: time + seconds, from: eyePoint)
            return false
        case .hop:
            if reducedMotion || !motor.isStanding {
                // Reduce Motion: no jump; a long look at the person carries the joy instead
                p.steps[p.index] = .look(at: stage.userPoint, seconds: 1.0)
                gaze.look(at: ahead(stage.userPoint), until: time + 1.0, from: eyePoint)
                return false
            }
            gaze.stop()
            motor.startHop()
            return false
        }
    }

    /// The head only looks forward (it cannot twist over the shoulder): a target clearly behind the body, such as
    /// the person's spot when the character faces away from it, is mirrored in front, so the look goes ahead/up.
    private func ahead(_ p: Point) -> Point {
        guard isBehind(p) else { return p }
        return Point(x: motor.x + (motor.x - p.x), y: p.y)
    }

    private func isBehind(_ p: Point) -> Bool {
        (p.x - motor.x) * motor.facing.sign < -profile.characterHeight * 0.1
    }

    private var eyePoint: Point {
        Point(x: motor.x + motor.facing.sign * profile.characterHeight * 0.4, y: profile.eyeHeight)
    }

    private mutating func glance(at s: Stimulus) {
        let p: Point
        switch s {
        case .pet(let at): p = at
        case .call(let to): p = Point(x: to.x, y: max(to.y, 40))
        case .celebrate, .encourageRest: p = stage.userPoint
        }
        // only look forward: a point behind the character is answered by the turn of the reaction itself
        guard motor.facing.towards(p.x, from: motor.x) == motor.facing || abs(p.x - motor.x) < profile.characterHeight * 0.2 else { return }
        gaze.look(at: p, until: time + config.glanceSeconds, from: eyePoint)
    }

    private mutating func log(_ e: EngineEvent) {
        events.append(TimedEvent(time: time, event: e))
    }

    private func render() -> RenderState {
        var look: LookOutput?
        if gaze.active, let clip = profile.look {
            look = LookOutput(clip: clip.name, alpha: profile.lookAlpha, mixIn: profile.mix.lookIn, serial: gaze.serial,
                              target: gaze.current)
        }
        return RenderState(time: time, x: motor.x, facing: motor.facing, base: motor.track,
                           baseTimeScale: isPaused ? 0 : motor.timeScale, baseClipTime: motor.clipTime, look: look,
                           lookOutMix: profile.mix.lookOut, mode: motor.mode, activity: plan?.kind ?? .idle,
                           reducedMotion: reducedMotion, paused: isPaused)
    }
}
