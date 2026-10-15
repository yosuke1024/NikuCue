import Foundation
import XCTest
@testable import CatBehavior

/// The reaction guards that the broader interrupt tests do not reach on their own: a reaction never starts in the air
/// or in the middle of a turn, a waiting reaction keeps its place against a less important one, a pet answers the
/// touched spot of the body, and Reduce Motion cuts a walk short on a planted foot.
final class GuardTests: XCTestCase {
    private let frame = 1.0 / 60.0

    /// Steps until `condition` holds (or `limit` seconds pass). Returns whether it held.
    @discardableResult
    private func advance(_ run: inout Run, until condition: (Run) -> Bool, limit: Double = 120) -> Bool {
        let end = run.engine.time + limit
        while !condition(run) && run.engine.time < end { run.step(frame) }
        return condition(run)
    }

    private func lastClipStart(_ run: Run, _ name: String) -> Double? {
        run.events.last { isClip(name)($0.event) }?.time
    }

    private func appliedTime(_ run: Run, _ kind: StimulusKind, after t: Double) -> Double? {
        run.events.first { $0.time >= t && $0.event == .stimulusApplied(kind) }?.time
    }

    func testPetDuringAnAutonomousHopWaitsForTheLanding() throws {
        var found = false
        for seed in UInt64(1)...40 {
            var run = Run(seed: seed)
            // an autonomous hop (play), not a celebration: nothing of higher priority is running
            guard advance(&run, until: { $0.engine.mode == .hopping && $0.engine.activity == .play }, limit: 240) else { continue }
            let hopStart = try XCTUnwrap(lastClipStart(run, run.profile.hop.name))
            let sent = run.engine.time
            run.send(.pet(at: Point(x: run.engine.x, y: 700)))
            run.run(seconds: 4)
            let applied = try XCTUnwrap(appliedTime(run, .pet, after: sent), "seed \(seed)")
            XCTAssertGreaterThanOrEqual(applied, hopStart + run.profile.hop.duration - frame - 1e-9,
                                        "seed \(seed): the pet reaction must wait for the landing")
            XCTAssertEqual(run.violations, [], "seed \(seed)")
            found = true
            break
        }
        XCTAssertTrue(found, "no autonomous hop in 40 seeds")
    }

    func testPetDuringATurnWaitsForTheTurnToFinish() throws {
        var found = false
        for seed in UInt64(1)...40 {
            var run = Run(seed: seed)
            // a turn that is not part of a reaction
            guard advance(&run, until: { $0.engine.mode == .turning && $0.engine.activity != .petReaction }, limit: 240) else { continue }
            let turnStart = try XCTUnwrap(lastClipStart(run, run.profile.turn.name))
            let sent = run.engine.time
            run.send(.pet(at: Point(x: run.engine.x, y: 400)))
            run.run(seconds: 3)
            let applied = try XCTUnwrap(appliedTime(run, .pet, after: sent), "seed \(seed)")
            XCTAssertGreaterThanOrEqual(applied, turnStart + run.profile.turn.duration - frame - 1e-9,
                                        "seed \(seed): the pet reaction must wait for the turn")
            XCTAssertEqual(run.violations, [], "seed \(seed)")
            found = true
            break
        }
        XCTAssertTrue(found, "no autonomous turn in 40 seeds")
    }

    func testAWaitingCelebrationKeepsItsPlaceAgainstACall() {
        var run = Run(seed: 2)
        advance(&run, until: { $0.engine.mode == .walking })
        run.step(frame)
        run.send(.celebrate)                                   // waits: the walk first stops on a planted foot
        run.send(.call(to: Point(x: 100, y: 0)))               // less important: a glance only
        XCTAssertTrue(run.events.contains { $0.event == .stimulusAcknowledged(.call, reason: "busy") })
        run.run(seconds: 8)
        XCTAssertNotNil(appliedTime(run, .celebrate, after: 0))
        XCTAssertNil(appliedTime(run, .call, after: 0), "the call must not replace the waiting celebration")
        XCTAssertEqual(run.violations, [])
    }

    func testPetWhileWalkingAnswersTheTouchedSpotNotTheFloorBehind() throws {
        // tap the middle of the body while it walks: by the time the feet are planted the body has moved on,
        // but the touched spot moved with it, so there is no turn back
        var checked = 0
        for seed in UInt64(1)...60 where checked < 8 {
            var run = Run(seed: seed, width: 3600, startX: 300, facing: .right)      // a long room: long walks
            guard advance(&run, until: { $0.engine.mode == .walking }, limit: 240) else { continue }
            run.step(frame)
            guard run.engine.mode == .walking else { continue }
            let sent = run.engine.time
            let startX = run.engine.x
            run.send(.pet(at: Point(x: startX, y: 400)))
            run.run(seconds: 4)
            guard let applied = appliedTime(run, .pet, after: sent) else { continue }
            let movedBeforeReacting = abs((run.frames.first { $0.time >= applied }?.x ?? startX) - startX)
            guard movedBeforeReacting > run.profile.characterHeight * 0.35 else { continue }   // the old code turned here
            let turns = run.events.filter { e in
                if case .facingChanged = e.event { return e.time >= sent && e.time <= applied + 2.2 } else { return false }
            }
            XCTAssertEqual(turns.count, 0, "seed \(seed): moved \(movedBeforeReacting) before reacting, then turned back")
            XCTAssertEqual(run.violations, [], "seed \(seed)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no walk long enough to move away from the tap")
    }

    func testTurningOnReducedMotionMidWalkCutsTheWalkShortOnAPlantedFoot() throws {
        var checked = 0
        for seed in UInt64(1)...60 where checked < 5 {
            var control = Run(seed: seed, width: 3600, startX: 300, facing: .right)
            guard advance(&control, until: { $0.engine.mode == .walking }, limit: 240) else { continue }
            control.step(frame)
            guard control.engine.mode == .walking else { continue }
            let switchAt = control.engine.time
            // the walk's planned end, without Reduce Motion
            control.run(seconds: 10)
            guard let plannedEnd = control.events.first(where: { e in
                if case .arrived = e.event { return e.time > switchAt } else { return false }
            }), plannedEnd.time - switchAt > 2.5 else { continue }            // only walks with a long way to go

            var run = Run(seed: seed, width: 3600, startX: 300, facing: .right)
            advance(&run, until: { $0.engine.mode == .walking }, limit: 240)
            run.step(frame)
            XCTAssertEqual(run.engine.time, switchAt, accuracy: 1e-9)
            run.engine.setReducedMotion(true)
            run.run(seconds: 10)
            // a walk that has only just started can stop in the same frame (motor events carry the frame's start time)
            let arrival = try XCTUnwrap(run.events.first { e in
                if case .arrived = e.event { return e.time >= switchAt - 1.0 / 60.0 - 1e-9 } else { return false }
            }, "seed \(seed)")
            guard case .arrived(_, let phase) = arrival.event else { return XCTFail() }
            XCTAssertLessThan(arrival.time, plannedEnd.time - 0.5, "seed \(seed): Reduce Motion must cut the walk short")
            let w = run.profile.walk.blendWindow
            XCTAssertTrue(phase > w.lowerBound - 1e-6 && phase < w.upperBound + 1e-6, "seed \(seed): stop phase \(phase)")
            XCTAssertEqual(run.frames.filter { $0.time > arrival.time + 0.1 && ($0.mode == .walking || $0.mode == .hopping) }.count, 0)
            XCTAssertEqual(run.violations, [], "seed \(seed)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no long walk found")
    }
}
