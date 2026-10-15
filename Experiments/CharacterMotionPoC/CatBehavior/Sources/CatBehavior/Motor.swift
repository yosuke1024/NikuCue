// The body: position, facing and the base clip (track 0). Every change of position goes through `advance`, where
// root movement and walk-clip time are the same quantity (distance = groundSpeed × clip time), so a planted foot
// cannot slide and the root cannot jump. Facing only changes on the first frame of the turn clip.

public enum MotorMode: String, Sendable, Equatable, Codable {
    case standing, resting, walking, turning, hopping
}

/// The base-track clip the renderer should be playing. A new `serial` means "start this clip now".
public struct BaseTrack: Sendable, Equatable {
    public var clip: String
    public var duration: Double
    public var loop: Bool
    /// Clip time (seconds) at the start of the frame in which the clip starts.
    public var startTime: Double
    /// Cross-fade from the previous clip.
    public var mix: Double
    public var serial: Int
    /// Freeze the outgoing clip during the cross-fade (a stopping walk must not keep stepping in place).
    public var freezePrevious: Bool
}

struct Motor: Sendable {
    let profile: MotionProfile
    private(set) var mode: MotorMode = .standing
    private(set) var x: Double
    private(set) var facing: Facing
    private(set) var track: BaseTrack
    /// Seconds into the current base clip, after the last `advance`.
    private(set) var clipTime: Double = 0
    /// Effective playback rate of the base clip during the last `advance` (what the renderer must use).
    private(set) var timeScale: Double = 1
    private(set) var modeTime: Double = 0
    private(set) var events: [EngineEvent] = []

    private var walkOrigin: Double = 0
    private(set) var walkTarget: Double = 0
    private var cruise: Double = 1
    /// Current walk playback rate (rate limited; the reported `timeScale` can be lower on the arrival frame).
    private var walkTs: Double = 0
    /// 0 = idle breathing at normal speed, 1 = resting (slow breathing); eased, never stepped.
    private var restLevel: Double = 0

    init(profile: MotionProfile, x: Double, facing: Facing) {
        self.profile = profile
        self.x = x
        self.facing = facing
        track = BaseTrack(clip: profile.idle.name, duration: profile.idle.duration, loop: true, startTime: 0, mix: 0,
                          serial: 1, freezePrevious: false)
    }

    var walk: LocomotionSpec { profile.walk }
    var walkPhase: Double { fract(clipTime / walk.clip.duration) }
    var isStanding: Bool { mode == .standing || mode == .resting }
    /// Feet off the ground: a hop is never cut here.
    var isAirborne: Bool { mode == .hopping && profile.hopAirborne.contains(clipTime) }
    var walkDirection: Facing { facing }
    var remainingWalk: Double { mode == .walking ? max(0, (walkTarget - x) * facing.sign) : 0 }

    mutating func drainEvents() -> [EngineEvent] {
        defer { events.removeAll() }
        return events
    }

    private mutating func play(_ clip: ClipSpec, loop: Bool, startTime: Double = 0, mix: Double, freezePrevious: Bool = false) {
        track = BaseTrack(clip: clip.name, duration: clip.duration, loop: loop, startTime: startTime, mix: mix,
                          serial: track.serial + 1, freezePrevious: freezePrevious)
        clipTime = startTime
        events.append(.clipStarted(clip.name, mix: mix))
    }

    private mutating func enter(_ m: MotorMode) {
        mode = m
        modeTime = 0
    }

    /// Stand (idle) or rest. Reuses the running loop when it is already the right clip, so breathing never restarts.
    mutating func stand(resting: Bool, mix: Double? = nil, freezePrevious: Bool = false) {
        let target = resting ? profile.rest : profile.idle
        let sameLoop = track.loop && track.clip == target.name && isStanding
        if !sameLoop {
            let defaultMix = resting ? profile.mix.idleToRest : profile.mix.walkToIdle
            play(target, loop: true, mix: mix ?? defaultMix, freezePrevious: freezePrevious)
        }
        enter(resting ? .resting : .standing)
    }

    /// Starts walking towards `target` from `startPhase` (both chosen by the navigator so the walk ends inside the
    /// blend window). Facing must already point there.
    mutating func startWalk(to target: Double, startPhase: Double, cruise requested: Double) {
        precondition(isStanding, "walks start from standing")
        walkOrigin = x
        walkTarget = target
        cruise = clamp(requested, walk.minTimeScale, walk.maxTimeScale)
        walkTs = walk.minTimeScale
        play(walk.clip, loop: true, startTime: startPhase * walk.clip.duration, mix: profile.mix.idleToWalk)
        enter(.walking)
        events.append(.walkPlanned(from: x, to: target))
    }

    /// Moves the destination of a running walk in the same direction (target already aligned to the current phase).
    mutating func retarget(to target: Double, cruise requested: Double? = nil) {
        guard mode == .walking else { return }
        walkTarget = target
        if let requested { cruise = clamp(requested, walk.minTimeScale, walk.maxTimeScale) }
        events.append(.walkPlanned(from: x, to: target))
    }

    /// Interrupt: end the running walk as soon as it can stop without sliding: after the braking distance, at the
    /// first point inside the blend window.
    mutating func stopSoon() {
        guard mode == .walking else { return }
        let minimum = max(1, walk.brakingDistance(from: walkTs))
        let d = walk.distanceToBlendWindow(from: walkPhase, minimum: minimum)
        guard d < remainingWalk else { return }
        walkTarget = x + facing.sign * d
        events.append(.stopRequested(x: walkTarget, phase: fract(walkPhase + d / walk.strideLength)))
    }

    var brakingDistance: Double { mode == .walking ? walk.brakingDistance(from: walkTs) : 0 }

    mutating func startTurn() {
        precondition(isStanding, "turns start from standing")
        facing = facing.flipped
        play(profile.turn, loop: false, mix: profile.mix.toTurn)
        enter(.turning)
        events.append(.facingChanged(facing))
    }

    mutating func startHop() {
        precondition(isStanding, "hops start from standing")
        play(profile.hop, loop: false, mix: profile.mix.toHop)
        enter(.hopping)
    }

    enum Completion: Equatable { case none, arrived, turnFinished, hopFinished }

    /// Integrates one frame. Root position changes only here.
    mutating func advance(_ dt: Double) -> Completion {
        modeTime += dt
        switch mode {
        case .standing, .resting:
            let goal: Double = mode == .resting ? 1 : 0
            let rate = dt / max(0.05, profile.mix.idleToRest)
            restLevel = goal > restLevel ? min(goal, restLevel + rate) : max(goal, restLevel - rate)
            // a separate rest clip plays at its own speed; resting on the idle clip slows its breathing
            let slowed = profile.rest.name == profile.idle.name ? 1 + (profile.restTimeScale - 1) * Ease.smooth(restLevel) : 1
            timeScale = track.clip == profile.idle.name ? slowed : (mode == .resting ? profile.restTimeScale : 1)
            clipTime += dt * timeScale
            return .none

        case .walking:
            let stride = walk.strideLength
            let remaining = remainingWalk
            if remaining <= 0 {                    // arrived last frame; the engine stands on its next decision
                timeScale = 0
                return .arrived
            }
            let travelled = max(0, (x - walkOrigin) * facing.sign)
            let lo = walk.minTimeScale
            let up = lo + (cruise - lo) * Ease.smooth(travelled / (stride * 0.35))
            let down = lo + (cruise - lo) * Ease.smooth(remaining / (stride * 0.45))
            // the ramps give the shape; the rate limit guarantees no sudden speed change (retargets, interrupts)
            let step = walk.timeScaleRate * dt
            let ts = clamp(clamp(min(up, down), walkTs - step, walkTs + step), lo, walk.maxTimeScale)
            walkTs = ts
            var distance = ts * walk.groundSpeed * dt
            var arrived = false
            if distance >= remaining {
                distance = remaining
                arrived = true
            }
            x += facing.sign * distance
            let clipAdvance = distance / walk.groundSpeed
            clipTime += clipAdvance
            timeScale = dt > 0 ? clipAdvance / dt : 0
            if arrived {
                events.append(.arrived(x: x, phase: walkPhase))
                return .arrived
            }
            return .none

        case .turning:
            timeScale = 1
            clipTime += dt
            return clipTime >= profile.turn.duration ? .turnFinished : .none

        case .hopping:
            timeScale = 1
            clipTime += dt
            return clipTime >= profile.hop.duration ? .hopFinished : .none
        }
    }
}
