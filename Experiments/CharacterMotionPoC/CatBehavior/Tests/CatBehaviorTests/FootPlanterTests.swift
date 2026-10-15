import XCTest
@testable import CatBehavior

final class FootPlanterTests: XCTestCase {
    private func state(time: Double, serial: Int, mix: Double, mode: MotorMode = .standing, facing: Facing = .right) -> RenderState {
        RenderState(time: time, x: 0, facing: facing,
                    base: BaseTrack(clip: "idle", duration: 1, loop: true, startTime: 0, mix: mix, serial: serial, freezePrevious: false),
                    baseTimeScale: 1, baseClipTime: 0, look: nil, lookOutMix: 0.3, mode: mode, activity: .idle,
                    reducedMotion: false, paused: false)
    }

    /// A blend that would drag a grounded foot 100 units keeps it planted, then moves it with a lifted step.
    func testGroundedFootStaysDuringABlendThenSteps() {
        var planter = FootPlanter(groundTolerance: 17)
        _ = planter.solve([Point(x: 0, y: 0)], state: state(time: 0, serial: 1, mix: 0.2))
        var t = 0.0
        var outputs: [Point] = []
        // clip change at t = 0.5: the animation slides the foot from 0 to 100 over the 0.25 s blend
        for i in 1...60 {
            t = Double(i) / 60
            let serial = t >= 0.5 ? 2 : 1
            let animatedX = t < 0.5 ? 0 : min(100, (t - 0.5) / 0.25 * 100)
            outputs.append(planter.solve([Point(x: animatedX, y: 0)], state: state(time: t, serial: serial, mix: 0.25))[0])
        }
        let duringBlend = outputs.enumerated().filter { let tt = Double($0.offset + 1) / 60; return tt >= 0.5 && tt < 0.75 }
        XCTAssertTrue(duringBlend.allSatisfy { abs($0.element.x) < 1e-9 }, "planted during the blend")
        XCTAssertGreaterThan(outputs.map(\.y).max() ?? 0, 17, "the catch-up is a lifted step, not a slide")
        XCTAssertEqual(outputs.last!.x, 100, accuracy: 1e-9)
        XCTAssertEqual(outputs.last!.y, 0, accuracy: 1e-9)
    }

    func testSteadyWalkingIsLeftToTheAnimation() {
        var planter = FootPlanter(groundTolerance: 17)
        for i in 0..<30 {
            let p = Point(x: Double(i) * 5, y: 0)
            let walk = planter.solve([p], state: state(time: Double(i) / 60, serial: 3, mix: 0.0, mode: .walking))
            XCTAssertEqual(walk[0], p)
        }
    }

    /// The mirror on a turn's first frame would move a foot 200 units in one frame; it steps there instead.
    func testFeetStepAcrossTheTurnMirror() {
        var planter = FootPlanter(groundTolerance: 17)
        _ = planter.solve([Point(x: 111, y: 0)], state: state(time: 0, serial: 1, mix: 0.2))
        var previous = Point(x: 111, y: 0)
        var lifted = false
        for i in 1...40 {
            let t = Double(i) / 60
            let q = planter.solve([Point(x: -111, y: 0)], state: state(time: t, serial: 2, mix: 0.06, mode: t < 0.27 ? .turning : .standing,
                                                                     facing: .left))[0]
            if q.y <= 17 && previous.y <= 17 { XCTAssertLessThan(abs(q.x - previous.x), 1e-6, "a grounded foot never moves (t=\(t))") }
            if q.y > 17 { lifted = true }
            previous = q
        }
        XCTAssertTrue(lifted)
        XCTAssertEqual(previous.x, -111, accuracy: 1e-9)
    }
}
