import Foundation
import XCTest
@testable import CatBehavior

/// The built-in spineboy profile must equal what tools/measure_profile.mjs measured from the official export.
final class ProfileTests: XCTestCase {
    func testBuiltInProfileMatchesTheMeasurement() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Profiles/spineboy.measured.json").standardizedFileURL
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let p = MotionProfile.spineboyEvaluation
        let walk = try XCTUnwrap((json["locomotion"] as? [String: Any])?["walk"] as? [String: Any])
        XCTAssertEqual(p.walk.groundSpeed, try XCTUnwrap(walk["groundSpeed"] as? Double), accuracy: 0.01)
        XCTAssertEqual(p.walk.clip.duration, try XCTUnwrap(walk["duration"] as? Double), accuracy: 1e-4)
        XCTAssertEqual(p.walk.enterPhase, try XCTUnwrap(walk["enterPhase"] as? Double), accuracy: 1e-4)
        let stops = try XCTUnwrap(walk["stopPhases"] as? [[String: Double]])
        XCTAssertEqual(p.walk.stopPhases.map(\.phase), stops.map { $0["phase"]! })
        XCTAssertEqual(p.walk.stopPhases.map(\.cost), stops.map { $0["cost"]! })
        let durations = try XCTUnwrap(json["durations"] as? [String: Double])
        for clip in [p.idle, p.turn, p.hop] {
            XCTAssertEqual(clip.duration, try XCTUnwrap(durations[clip.name]), accuracy: 1e-4, clip.name)
        }
        let jump = try XCTUnwrap(((json["reactions"] as? [String: Any])?["jump"] as? [String: Any])?["airborne"] as? [Double])
        XCTAssertEqual(p.hopAirborne.lowerBound, jump[0], accuracy: 1e-4)
        XCTAssertEqual(p.hopAirborne.upperBound, jump[1], accuracy: 1e-4)
        let bounds = try XCTUnwrap(json["setupBounds"] as? [String: Double])
        XCTAssertEqual(p.characterHeight, try XCTUnwrap(bounds["height"]), accuracy: 0.1)
        let window = try XCTUnwrap(walk["blendWindow"] as? [Double])
        XCTAssertEqual(p.walk.blendWindow.lowerBound, window[0], accuracy: 1e-4)
        XCTAssertEqual(p.walk.blendWindow.upperBound, window[1], accuracy: 1e-4)
        XCTAssertTrue(p.walk.blendWindow.contains(p.walk.enterPhase))
    }
}
