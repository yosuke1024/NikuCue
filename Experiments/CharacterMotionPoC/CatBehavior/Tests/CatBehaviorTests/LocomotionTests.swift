import XCTest
@testable import CatBehavior

final class LocomotionTests: XCTestCase {
    /// Acceptance: 90 s with no input keeps every physical invariant (planted feet, no teleport, facing only flips
    /// at a turn start, every clip blended, never off the floor) for many seeds.
    func testNinetySecondsWithoutInputKeepsInvariants() {
        for seed in UInt64(1)...40 {
            var run = Run(seed: seed)
            run.run(seconds: 90)
            XCTAssertEqual(run.violations, [], "seed \(seed)")
        }
    }

    func testEveryWalkEndsInsideTheBlendWindow() {
        let walk = MotionProfile.spineboyEvaluation.walk
        var arrivals: [Double] = []
        for seed in UInt64(1)...20 {
            var run = Run(seed: seed)
            run.run(seconds: 90)
            for e in run.events {
                if case .arrived(_, let phase) = e.event { arrivals.append(phase) }
            }
        }
        XCTAssertGreaterThan(arrivals.count, 40)
        for phase in arrivals {
            XCTAssertTrue(phase > walk.blendWindow.lowerBound - 1e-6 && phase < walk.blendWindow.upperBound + 1e-6,
                          "arrival phase \(phase) outside \(walk.blendWindow)")
        }
    }

    func testIrregularFrameTimesAndHitchesNeverTeleport() {
        var run = Run(seed: 7)
        var rng = SplitMix64(seed: 99)
        for i in 0..<6000 {
            // 30–120 fps jitter plus an occasional 0.5 s hitch (a backgrounding glitch, a debugger pause)
            let dt = i % 997 == 0 ? 0.5 : rng.between(1.0 / 120.0, 1.0 / 30.0)
            run.step(dt)
        }
        XCTAssertEqual(run.violations, [])
    }

    func testWalkSpeedStaysWithinBelievablePlaybackRates() {
        var run = Run(seed: 3)
        run.run(seconds: 90)
        // the last frame of a walk covers only the remaining distance (a partial frame), so it is excluded
        let walking = zip(run.frames, run.frames.dropFirst()).filter { $0.mode == .walking && $1.mode == .walking && $1.baseTimeScale > 0 }.map(\.0)
        XCTAssertGreaterThan(walking.count, 600)
        for f in walking {
            XCTAssertGreaterThanOrEqual(f.baseTimeScale, run.profile.walk.minTimeScale - 1e-9)
            XCTAssertLessThanOrEqual(f.baseTimeScale, run.profile.walk.maxTimeScale + 1e-9)
        }
    }

    func testWalkStartsInsideTheBlendWindowAndStopFreezesTheWalk() {
        var run = Run(seed: 11)
        run.run(seconds: 60)
        let profile = run.profile
        var sawStart = false, sawStop = false
        for (prev, cur) in zip(run.frames, run.frames.dropFirst()) where cur.base.serial != prev.base.serial {
            if cur.base.clip == profile.walk.clip.name {
                XCTAssertTrue(profile.walk.blendWindow.contains(cur.base.startTime / profile.walk.clip.duration))
                sawStart = true
            }
            if prev.mode == .walking && cur.base.clip == profile.idle.name {
                XCTAssertTrue(cur.base.freezePrevious, "a stopping walk must not keep stepping during the blend")
                sawStop = true
            }
        }
        XCTAssertTrue(sawStart)
        XCTAssertTrue(sawStop)
    }

    func testNavigatorPlansWalksThatEndInTheBlendWindow() throws {
        let nav = Navigator(stage: .evaluationRoom(width: 2400, height: 1100), profile: .spineboyEvaluation)
        let walk = MotionProfile.spineboyEvaluation.walk
        var exact = 0
        for desired in stride(from: 900.0, through: 2100, by: 25) {
            let plan = try XCTUnwrap(nav.plannedWalk(from: 500, desiredX: desired, startPhases: nav.standingStartPhases,
                                                     tolerance: walk.strideLength))
            XCTAssertTrue(walk.blendWindow.contains(plan.startPhase))
            let end = fract(plan.startPhase + (plan.target - 500) / walk.strideLength)
            XCTAssertGreaterThanOrEqual(end, walk.blendWindow.lowerBound - 1e-9)
            XCTAssertLessThanOrEqual(end, walk.blendWindow.upperBound + 1e-9)
            XCTAssertTrue(nav.floor.contains(plan.target))
            if abs(plan.target - desired) < 0.5 { exact += 1 }
        }
        // start and stop windows together make a good share of distances exactly reachable (not just a lattice)
        XCTAssertGreaterThan(exact, 10)
        // a short hop of 100 units has no slide-free walk → no walk at all instead of a sloppy stop
        XCTAssertNil(nav.plannedWalk(from: 600, desiredX: 700, startPhases: nav.standingStartPhases, tolerance: 20))
    }
}
