import Foundation
import XCTest
@testable import CatBehavior

final class LifecycleTests: XCTestCase {
    func testPauseFreezesEverythingAndDropsWaitingReactions() {
        var run = Run(seed: 2)
        while run.engine.mode != .walking { run.step(1.0 / 60.0) }
        run.send(.celebrate)
        let before = run.engine.step(0)
        run.engine.setPaused(true)
        for _ in 0..<600 { run.step(1.0 / 60.0) }          // 10 s in the background
        XCTAssertEqual(run.engine.x, before.x)
        XCTAssertEqual(run.engine.time, before.time, accuracy: 1e-12)
        XCTAssertEqual(run.frames.last?.baseTimeScale, 0)
        XCTAssertTrue(run.events.contains { $0.event == .stimulusDropped(.celebrate, reason: "paused") })
        run.engine.setPaused(false)
        run.step(5.0)                                       // first frame after resume reports a long delta
        XCTAssertEqual(run.engine.time, before.time, accuracy: 1e-12, "the time away is not integrated")
        XCTAssertEqual(run.engine.x, before.x)
        run.run(seconds: 20)
        XCTAssertEqual(run.count { $0 == .stimulusApplied(.celebrate) }, 0, "a stale reaction is never replayed")
        XCTAssertEqual(run.violations, [])
    }

    func testPauseEndsARunningCelebrationAfterTheHopLands() throws {
        var run = Run(seed: 4)
        run.run(seconds: 3)
        run.send(.celebrate)
        let end = run.engine.time + 6
        while run.engine.mode != .hopping && run.engine.time < end { run.step(1.0 / 60.0) }
        XCTAssertEqual(run.engine.activity, .celebrateReaction)
        XCTAssertEqual(run.engine.mode, .hopping)
        run.engine.setPaused(true)
        for _ in 0..<600 { run.step(1.0 / 60.0) }
        run.engine.setPaused(false)
        let resumed = run.engine.time
        run.run(seconds: 4)
        // the hop lands (no jump cut), then the celebration ends instead of carrying on with its remaining steps
        let finished = try XCTUnwrap(run.events.first { $0.time >= resumed && $0.event == .activityFinished(.celebrateReaction) })
        XCTAssertLessThanOrEqual(finished.time - resumed, run.profile.hop.duration + 0.1)
        XCTAssertEqual(run.violations, [])
    }

    func testReducedMotionNeverWalksOrHops() {
        for seed in UInt64(1)...20 {
            var run = Run(seed: seed)
            run.engine.setReducedMotion(true)
            run.run(seconds: 90) { r, t in
                if Int(t * 60) % 600 == 0 { r.send(.celebrate) }
                if Int(t * 60) % 900 == 0 { r.send(.call(to: Point(x: 100, y: 0))) }
            }
            XCTAssertEqual(run.frames.filter { $0.mode == .walking || $0.mode == .hopping }.count, 0, "seed \(seed)")
            XCTAssertGreaterThanOrEqual(Set(run.activities).count, 3, "seed \(seed): still alive in place")
            XCTAssertEqual(run.violations, [])
        }
    }

    func testEngineHasNoFoundationDependency() throws {
        // the engine must stay portable to WebAssembly and free of UI/SDK imports (CLAUDE.md: pure domain logic)
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/CatBehavior").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for f in files where f.pathExtension == "swift" {
            let text = try String(contentsOf: f, encoding: .utf8)
            for line in text.split(separator: "\n") where line.hasPrefix("import ") {
                XCTFail("\(f.lastPathComponent): \(line)")
            }
        }
    }
}
