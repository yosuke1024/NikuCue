// What the engine needs to know about one character's clips. The numbers come from measuring the skeleton
// (tools/measure_profile.mjs) rather than from guesses, so a new character (e.g. production Mali) is supported by
// re-running the measurement on its export, not by changing the engine.

/// A clip referenced by name, with its length at timeScale 1.
public struct ClipSpec: Sendable, Equatable, Codable {
    public var name: String
    public var duration: Double
    public init(name: String, duration: Double) {
        self.name = name
        self.duration = duration
    }
}

/// A phase where both feet are down, with the cost (units a foot must slide) of blending from it into idle.
public struct StopPhase: Sendable, Equatable, Codable {
    public var phase: Double
    public var cost: Double
    public init(phase: Double, cost: Double) {
        self.phase = phase
        self.cost = cost
    }
}

/// A looping locomotion clip authored in place. While it plays the root moves at `groundSpeed × timeScale`, which
/// keeps planted feet still; therefore distance and clip phase are locked: one cycle always covers `strideLength`.
public struct LocomotionSpec: Sendable, Equatable, Codable {
    public var clip: ClipSpec
    public var groundSpeed: Double
    /// Double-support phases with their blend-to-idle cost (reference; costly ones are never used).
    public var stopPhases: [StopPhase]
    /// Phase whose foot layout is closest to idle.
    public var enterPhase: Double
    /// Phases where every grounded foot is within a few units of its idle position: walks start and stop
    /// anywhere in here (a foot in the air just sets down during the blend).
    public var blendWindow: ClosedRange<Double>
    /// Playback rates the clip still looks right at (slower reads as slow motion, faster as scurrying).
    public var minTimeScale: Double
    public var maxTimeScale: Double
    /// Largest change of playback rate per second (no sudden speed changes on retargets or interrupts).
    public var timeScaleRate: Double

    public init(clip: ClipSpec, groundSpeed: Double, stopPhases: [StopPhase], enterPhase: Double,
                blendWindow: ClosedRange<Double>, minTimeScale: Double, maxTimeScale: Double, timeScaleRate: Double) {
        self.clip = clip
        self.groundSpeed = groundSpeed
        self.stopPhases = stopPhases
        self.enterPhase = enterPhase
        self.blendWindow = blendWindow
        self.minTimeScale = minTimeScale
        self.maxTimeScale = maxTimeScale
        self.timeScaleRate = timeScaleRate
    }

    public var strideLength: Double { groundSpeed * clip.duration }

    public func inBlendWindow(_ phase: Double) -> Bool { blendWindow.contains(fract(phase)) }

    /// Distance needed to slow from `timeScale` to the slowest rate at `timeScaleRate`.
    public func brakingDistance(from timeScale: Double) -> Double {
        let lo = minTimeScale
        return groundSpeed * max(0, timeScale * timeScale - lo * lo) / (2 * timeScaleRate)
    }

    /// Shortest distance ≥ `minimum` after which a walk now at `phase` is inside the blend window.
    public func distanceToBlendWindow(from phase: Double, minimum: Double) -> Double {
        let end = fract(phase + minimum / strideLength)
        if inBlendWindow(end) { return minimum }
        return minimum + fract(blendWindow.lowerBound - end) * strideLength
    }
}

/// Blend times between clips (seconds). Short enough to read as one motion, long enough to never pop.
public struct MixSpec: Sendable, Equatable, Codable {
    public var idleToWalk: Double
    public var walkToIdle: Double
    public var toTurn: Double
    public var turnToIdle: Double
    public var toHop: Double
    public var hopToIdle: Double
    public var idleToRest: Double
    public var lookIn: Double
    public var lookOut: Double

    public init(idleToWalk: Double, walkToIdle: Double, toTurn: Double, turnToIdle: Double, toHop: Double,
                hopToIdle: Double, idleToRest: Double, lookIn: Double, lookOut: Double) {
        self.idleToWalk = idleToWalk
        self.walkToIdle = walkToIdle
        self.toTurn = toTurn
        self.turnToIdle = turnToIdle
        self.toHop = toHop
        self.hopToIdle = hopToIdle
        self.idleToRest = idleToRest
        self.lookIn = lookIn
        self.lookOut = lookOut
    }
}

public struct MotionProfile: Sendable, Equatable, Codable {
    public var name: String
    /// Setup-pose height, used to scale distances that are expressed in "body heights".
    public var characterHeight: Double
    /// Half the footprint width: the root keeps this far from the stage edges.
    public var halfWidth: Double
    public var idle: ClipSpec
    /// Calm resting loop (nap / unwind). May be the idle clip played slower.
    public var rest: ClipSpec
    public var restTimeScale: Double
    public var walk: LocomotionSpec
    /// In-place turn. Facing flips on the first frame of this clip (the clip swings the body through).
    public var turn: ClipSpec
    /// Happy hop (in place). Feet are off the ground in `hopAirborne` (seconds): a hop is never cut there.
    public var hop: ClipSpec
    public var hopAirborne: ClosedRange<Double>
    /// Additive "look at" overlay on track 1, aimed at a target point by the renderer (IK/transform constraint).
    public var look: ClipSpec?
    public var lookAlpha: Double
    /// Height of the eyes above the floor, where gaze targets on the floor are lifted from.
    public var eyeHeight: Double
    public var mix: MixSpec

    public init(name: String, characterHeight: Double, halfWidth: Double, idle: ClipSpec, rest: ClipSpec,
                restTimeScale: Double, walk: LocomotionSpec, turn: ClipSpec, hop: ClipSpec,
                hopAirborne: ClosedRange<Double>, look: ClipSpec?, lookAlpha: Double, eyeHeight: Double,
                mix: MixSpec) {
        self.name = name
        self.characterHeight = characterHeight
        self.halfWidth = halfWidth
        self.idle = idle
        self.rest = rest
        self.restTimeScale = restTimeScale
        self.walk = walk
        self.turn = turn
        self.hop = hop
        self.hopAirborne = hopAirborne
        self.look = look
        self.lookAlpha = lookAlpha
        self.eyeHeight = eyeHeight
        self.mix = mix
    }
}

extension MotionProfile {
    /// Official Spine sample "spineboy" (spine-runtimes @ spine-ts-4.3.13), measured by tools/measure_profile.mjs
    /// (Profiles/spineboy.measured.json). Evaluation only: the sample art is non-commercial and never ships.
    /// `CatBehaviorTests.ProfileTests` checks these values against the measured JSON.
    public static let spineboyEvaluation = MotionProfile(
        name: "spineboy (evaluation sample)",
        characterHeight: 686.2,
        halfWidth: 210,
        idle: ClipSpec(name: "idle", duration: 1.6667),
        rest: ClipSpec(name: "idle", duration: 1.6667),
        restTimeScale: 0.45,
        walk: LocomotionSpec(
            clip: ClipSpec(name: "walk", duration: 1.0),
            groundSpeed: 473.64,
            stopPhases: [StopPhase(phase: 0.035, cost: 243.62), StopPhase(phase: 0.515, cost: 37.25)],
            enterPhase: 0.4933,
            blendWindow: 0.3783...0.5067,
            minTimeScale: 0.32,
            maxTimeScale: 1.2,
            timeScaleRate: 2.5
        ),
        turn: ClipSpec(name: "idle-turn", duration: 0.2667),
        hop: ClipSpec(name: "jump", duration: 1.3333),
        hopAirborne: 0.0217...1.1767,
        look: ClipSpec(name: "aim", duration: 0),
        lookAlpha: 0.55,
        eyeHeight: 560,
        mix: MixSpec(idleToWalk: 0.22, walkToIdle: 0.25, toTurn: 0.06, turnToIdle: 0.15, toHop: 0.12,
                     hopToIdle: 0.2, idleToRest: 0.4, lookIn: 0.3, lookOut: 0.35)
    )
}
