import Foundation
import XCTest
@testable import CatBehavior

/// Same scenario as web/crosscheck_wasm.mjs: the WebAssembly build must produce the identical session.
final class CrossCheckTests: XCTestCase {
    func testTraceForCrossCheck() throws {
        var engine = CatBehaviorEngine(profile: .spineboyEvaluation, stage: .evaluationRoom(width: 1800, height: 1500),
                                       seed: 7, startX: 720, facing: .right)
        var lines: [String] = []
        for i in 1...(90 * 60) {
            if i == 30 * 60 { engine.send(.pet(at: Point(x: 900, y: 400))) }
            if i == 50 * 60 { engine.send(.celebrate) }
            let s = engine.step(1.0 / 60.0)
            if i % 60 == 0 {
                lines.append("\(i / 60) \(String(format: "%.6f", s.x)) \(s.mode.rawValue) \(s.base.clip) \(s.base.serial) \(s.activity.rawValue)")
            }
        }
        let path = ProcessInfo.processInfo.environment["CROSSCHECK_OUT"] ?? NSTemporaryDirectory() + "native_trace.txt"
        try lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        if let wasm = ProcessInfo.processInfo.environment["CROSSCHECK_WASM"] {
            XCTAssertEqual(try String(contentsOfFile: wasm, encoding: .utf8), lines.joined(separator: "\n") + "\n")
        }
    }
}
