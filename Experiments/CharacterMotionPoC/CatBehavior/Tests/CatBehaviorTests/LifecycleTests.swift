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
        XCTAssertLessThanOrEqual(abs(run.engine.x - before.x), run.profile.walk.groundSpeed * run.profile.walk.maxTimeScale / 20 + 1e-6)
        run.run(seconds: 20)
        XCTAssertEqual(run.count { $0 == .stimulusApplied(.celebrate) }, 0, "a stale reaction is never replayed")
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
