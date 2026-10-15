import Foundation
import XCTest
@testable import CatBehavior

final class InterruptTests: XCTestCase {
    private func runUntilWalking(_ run: inout Run, limit: Double = 60) {
        let end = run.engine.time + limit
        while run.engine.mode != .walking && run.engine.time < end { run.step(1.0 / 60.0) }
    }

    func testPetWhileWalkingGlancesAtOnceThenStopsOnAPlantedFoot() {
        var run = Run(seed: 2)
        runUntilWalking(&run)
        XCTAssertEqual(run.engine.mode, .walking)
        // ensure a stop is still ahead (not arriving this frame)
        run.step(1.0 / 60.0)
        let tap = Point(x: run.engine.x + run.engine.facing.sign * 200, y: 400)
        run.send(.pet(at: tap))
        run.step(1.0 / 60.0)
        XCTAssertNotNil(run.frames.last?.look, "the gaze answers within one frame")
        let sentAt = run.engine.time
        run.run(seconds: 3)
        guard let applied = run.events.first(where: { $0.event == .stimulusApplied(.pet) }) else {
            return XCTFail("pet never applied: \(run.events.map(\.event))")
        }
        // worst case: braking distance plus almost a whole cycle to the next window, at walking pace
        XCTAssertLessThanOrEqual(applied.time - sentAt, 2.0, "the body answers within two seconds (the gaze at once)")
        let stops = run.events.compactMap { e -> Double? in if case .arrived(_, let p) = e.event { return p } else { return nil } }
        let w = run.profile.walk.blendWindow
        XCTAssertTrue(stops.allSatisfy { $0 > w.lowerBound - 1e-6 && $0 < w.upperBound + 1e-6 }, "\(stops)")
        XCTAssertEqual(run.violations, [])
    }

    func testTapSpamOnTheCharacterIsCalm() {
        var run = Run(seed: 9)
        run.run(seconds: 5)
        for i in 0..<30 {
            run.send(.pet(at: Point(x: run.engine.x, y: 300 + Double(i))))
            run.run(seconds: 0.1)
        }
        let applied = run.count { $0 == .stimulusApplied(.pet) }
        XCTAssertGreaterThanOrEqual(applied, 1)
        XCTAssertLessThanOrEqual(applied, 3, "2 s cooldown over 3 s of tapping")
        XCTAssertGreaterThan(run.count { if case .stimulusAcknowledged(.pet, _) = $0 { return true } else { return false } }, 20)
        XCTAssertEqual(run.violations, [])
    }

    func testCelebrateWaitsForAHopToLandAndQueuesBehindACelebration() {
        var run = Run(seed: 4)
        run.run(seconds: 3)
        run.send(.celebrate)
        // wait until airborne
        let end = run.engine.time + 5
        while !(run.engine.mode == .hopping) && run.engine.time < end { run.step(1.0 / 60.0) }
        XCTAssertEqual(run.engine.mode, .hopping)
        run.send(.celebrate)                       // second habit done while in the air
        run.send(.pet(at: Point(x: run.engine.x, y: 400)))
        run.run(seconds: 12)
        XCTAssertEqual(run.count { $0 == .stimulusApplied(.celebrate) }, 2, "one waiting slot")
        XCTAssertEqual(run.count(isClip(run.profile.hop.name)), 2)
        // no hop was ever cut short: each hop clip is followed by at least its duration before the next clip
        let hops = run.events.filter { isClip(run.profile.hop.name)($0.event) }.map(\.time)
        let clipStarts = run.events.filter { if case .clipStarted = $0.event { return true } else { return false } }.map(\.time)
        for h in hops {
            let next = clipStarts.first { $0 > h + 1e-9 } ?? .infinity
            XCTAssertGreaterThanOrEqual(next - h, run.profile.hop.duration - 1.0 / 60.0)
        }
        XCTAssertEqual(run.violations, [])
    }

    func testCallAheadWhileWalkingRetargetsWithoutStopping() {
        var run = Run(seed: 2, width: 2400, startX: 400, facing: .right)
        runUntilWalking(&run)
        guard run.engine.facing == .right, run.engine.x < 1400 else { return }   // seed-dependent; skip if walking left
        let stopsBefore = run.count { if case .stopRequested = $0 { return true } else { return false } }
        run.send(.call(to: Point(x: 2100, y: 0)))
        run.step(1.0 / 60.0)
        XCTAssertEqual(run.engine.mode, .walking)
        XCTAssertEqual(run.engine.activity, .callReaction)
        XCTAssertEqual(run.count { if case .stopRequested = $0 { return true } else { return false } }, stopsBefore)
        run.run(seconds: 8)
        // it arrives within one stride of the call point (stops are stride-aligned), then lives on by itself
        let arrival = run.events.compactMap { e -> Double? in if case .arrived(let x, _) = e.event { return x } else { return nil } }.first
        XCTAssertEqual(try XCTUnwrap(arrival), 2100, accuracy: run.profile.walk.strideLength)
        XCTAssertEqual(run.violations, [])
    }

    func testCallBehindStopsTurnsAndWalks() {
        var run = Run(seed: 6, startX: 1200, facing: .right)
        run.run(seconds: 0.5)
        run.send(.call(to: Point(x: 250, y: 0)))
        run.run(seconds: 10)
        XCTAssertTrue(run.events.contains { $0.event == .facingChanged(.left) })
        XCTAssertLessThan(run.engine.x, 900)
        XCTAssertEqual(run.violations, [])
    }

    /// Random taps, calls and celebrations at random moments for 20 simulated minutes: nothing breaks.
    func testRandomInterruptFuzz() {
        for seed in UInt64(1)...12 {
            var run = Run(seed: seed)
            var rng = SplitMix64(seed: seed &* 31)
            var t = 0.0
            while t < 1200 {
                let dt = rng.between(1.0 / 120.0, 1.0 / 30.0)
                if rng.chance(0.01) {
                    switch Int(rng.unit() * 4) {
                    case 0: run.send(.pet(at: Point(x: run.engine.x + rng.between(-300, 300), y: rng.between(0, 700))))
                    case 1: run.send(.call(to: Point(x: rng.between(0, 2400), y: rng.between(0, 300))))
                    case 2: run.send(.celebrate)
                    default: run.send(.encourageRest)
                    }
                }
                if rng.chance(0.0005) { run.engine.setReducedMotion(!run.engine.reducedMotion) }
                run.step(dt)
                t += dt
            }
            XCTAssertEqual(run.violations, [], "seed \(seed)")
            let starts = run.events.compactMap { e -> Double? in if case .activityStarted = e.event { return e.time } else { return nil } }
            XCTAssertLessThan(zip(starts, starts.dropFirst()).map { $1 - $0 }.max() ?? 0, 30, "seed \(seed) got stuck")
        }
    }
}

final class InterruptLatencyTests: XCTestCase {
    /// How long the body takes to answer a tap that arrives at a random moment of a walk (the gaze answers at once).
    func testInterruptLatencyDistribution() {
        var latencies: [Double] = []
        for seed in UInt64(1)...60 {
            var run = Run(seed: seed)
            var rng = SplitMix64(seed: seed &+ 1000)
            while run.engine.mode != .walking { run.step(1.0 / 60.0) }
            run.run(seconds: rng.between(0.1, 1.2))
            guard run.engine.mode == .walking else { continue }
            let sent = run.engine.time
            run.send(.pet(at: Point(x: run.engine.x, y: 400)))
            run.run(seconds: 4)
            if let a = run.events.first(where: { $0.event == .stimulusApplied(.pet) }) { latencies.append(a.time - sent) }
            XCTAssertEqual(run.violations, [], "seed \(seed)")
        }
        latencies.sort()
        XCTAssertGreaterThan(latencies.count, 30)
        let median = latencies[latencies.count / 2], worst = latencies.last ?? 0
        print(String(format: "INTERRUPT_LATENCY n=%d median=%.2fs p90=%.2fs max=%.2fs", latencies.count, median,
                     latencies[Int(Double(latencies.count) * 0.9)], worst))
        XCTAssertLessThan(worst, 2.0)
    }
}
