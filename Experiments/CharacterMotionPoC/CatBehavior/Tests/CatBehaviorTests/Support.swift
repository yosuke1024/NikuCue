import Foundation
import XCTest
@testable import CatBehavior

/// Runs an engine with a frame clock and checks the physical invariants on every frame.
struct Run {
    var engine: CatBehaviorEngine
    var frames: [RenderState] = []
    var events: [TimedEvent] = []
    var violations: [String] = []
    private var last: RenderState?

    init(seed: UInt64, width: Double = 1800, startX: Double? = nil, facing: Facing = .right) {
        let profile = MotionProfile.spineboyEvaluation
        engine = CatBehaviorEngine(profile: profile, stage: .evaluationRoom(width: width, height: 1500), seed: seed,
                                   startX: startX, facing: facing)
        events = engine.drainEvents()
    }

    var profile: MotionProfile { engine.profile }

    mutating func step(_ dt: Double) {
        let state = engine.step(dt)
        events += engine.drainEvents()
        check(state, dt: dt)
        frames.append(state)
        last = state
    }

    mutating func run(seconds: Double, dt: Double = 1.0 / 60.0, every: ((inout Run, Double) -> Void)? = nil) {
        let end = engine.time + seconds
        while engine.time < end - 1e-9 {
            every?(&self, engine.time)
            step(dt)
            if engine.isPaused { break }
        }
    }

    mutating func send(_ s: Stimulus) {
        engine.send(s)
        events += engine.drainEvents()
    }

    private mutating func check(_ s: RenderState, dt: Double) {
        let stepDt = s.paused ? 0 : min(dt, engine.config.maxStep)
        let gs = profile.walk.groundSpeed
        guard let p = last else { return }
        let dx = abs(s.x - p.x)
        func fail(_ m: String) { violations.append(String(format: "t=%.3f %@", s.time, m)) }
        if !s.x.isFinite || !s.baseTimeScale.isFinite { fail("non-finite state") }
        // planted feet: while walking, the root moves exactly as far as the walk clip says
        if s.mode == .walking {
            let expected = gs * s.baseTimeScale * stepDt
            if abs(dx - expected) > 1e-6 { fail("walk slide: dx \(dx) vs clip \(expected)") }
        } else if dx > 1e-9 {
            fail("root moved \(dx) while \(s.mode.rawValue)")
        }
        // no teleport: never faster than the fastest walk
        if dx > gs * profile.walk.maxTimeScale * engine.config.maxStep + 1e-6 { fail("teleport \(dx)") }
        // facing flips only on the frame a turn clip starts
        if s.facing != p.facing && !(s.base.clip == profile.turn.name && s.base.serial != p.base.serial) {
            fail("facing flipped outside a turn start (\(s.base.clip))")
        }
        // every walk ends inside the blend window (whatever path ended it)
        if p.mode == .walking && s.mode != .walking {
            let phase = fract(p.baseClipTime / profile.walk.clip.duration)
            let w = profile.walk.blendWindow
            if phase < w.lowerBound - 1e-6 || phase > w.upperBound + 1e-6 { fail("walk ended at phase \(phase)") }
        }
        // the gaze never aims behind the body (one frame of walking as tolerance)
        if let look = s.look, (look.target.x - s.x) * s.facing.sign < -profile.characterHeight * 0.1 - 12 {
            fail("gaze behind the body: \(look.target.x) vs x \(s.x) facing \(s.facing)")
        }
        // every clip change is blended
        if s.base.serial != p.base.serial && s.base.mix <= 0 { fail("clip \(s.base.clip) started without a mix") }
        // never leaves the floor
        let floor = Navigator(stage: engine.stage, profile: profile).floor
        if !floor.contains(s.x) && abs(s.x - floor.lowerBound) > 1e-6 && abs(s.x - floor.upperBound) > 1e-6 {
            fail("left the floor at \(s.x)")
        }
    }

    var activities: [ActivityKind] {
        events.compactMap { if case .activityStarted(let k) = $0.event { return k } else { return nil } }
    }

    func count(_ match: (EngineEvent) -> Bool) -> Int { events.filter { match($0.event) }.count }
}

func isClip(_ name: String) -> (EngineEvent) -> Bool {
    { if case .clipStarted(let n, _) = $0 { return n == name } else { return false } }
}
