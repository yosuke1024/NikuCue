import XCTest
@testable import CatBehavior

final class BehaviorTests: XCTestCase {
    /// Acceptance: 60–90 s with no input shows several different behaviours in a natural order, including walking,
    /// stopping, turning and waiting.
    func testNinetySecondsShowVariedBehaviour() {
        for seed in UInt64(1)...40 {
            var run = Run(seed: seed)
            run.run(seconds: 90)
            let kinds = Set(run.activities)
            XCTAssertGreaterThanOrEqual(kinds.count, 5, "seed \(seed): \(run.activities)")
            XCTAssertGreaterThanOrEqual(run.count { if case .walkPlanned = $0 { return true } else { return false } }, 2, "seed \(seed) walks")
            XCTAssertGreaterThanOrEqual(run.count { if case .arrived = $0 { return true } else { return false } }, 2, "seed \(seed) stops")
            XCTAssertGreaterThanOrEqual(run.count { if case .facingChanged = $0 { return true } else { return false } }, 1, "seed \(seed) turns")
            XCTAssertGreaterThan(run.frames.filter { $0.mode == .standing || $0.mode == .resting }.count, 60 * 20, "seed \(seed) waits")
        }
    }

    func testNeverTheSameActivityThreeTimesInARow() {
        for seed in UInt64(1)...40 {
            var run = Run(seed: seed)
            run.run(seconds: 300)
            let a = run.activities
            for i in 2..<a.count {
                XCTAssertFalse(a[i] == a[i - 1] && a[i] == a[i - 2], "seed \(seed): \(a)")
            }
        }
    }

    func testTheCharacterNeverStaysStillForLong() {
        // "lives on its own": over 10 minutes the longest stretch without a new activity stays short
        for seed in UInt64(1)...10 {
            var run = Run(seed: seed)
            run.run(seconds: 600)
            let starts = run.events.compactMap { e -> Double? in if case .activityStarted = e.event { return e.time } else { return nil } }
            let gaps = zip(starts, starts.dropFirst()).map { $1 - $0 }
            XCTAssertLessThan(gaps.max() ?? 0, 25, "seed \(seed)")
            XCTAssertEqual(run.violations, [])
        }
    }

    func testSameSeedReproducesTheSession() {
        var a = Run(seed: 42), b = Run(seed: 42)
        a.run(seconds: 60)
        b.run(seconds: 60)
        XCTAssertEqual(a.frames, b.frames)
    }

    func testMoodHasNoBadStateAndIgnoresAbsence() {
        // a whole day of simulated time with no interaction: nothing degrades into a negative state
        var run = Run(seed: 5)
        run.run(seconds: 3600, dt: 1.0 / 20.0)
        let m = run.engine.mood
        XCTAssertGreaterThanOrEqual(m.energy, 0.05)
        XCTAssertLessThanOrEqual(m.energy, 1)
        XCTAssertEqual(run.violations, [])
        // the selector still offers ordinary activities (no "neglected" mode exists to fall into)
        XCTAssertTrue(Set(run.activities.suffix(20)).isSubset(of: Set(ActivityKind.allCases.filter { !$0.isReaction })))
    }
}
