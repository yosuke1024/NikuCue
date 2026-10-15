import CatBehavior
import Foundation

/// Unattended input for Simulator recordings. Taps go through `StageModel.tap`, the same path as the tap gesture,
/// and are drawn as labelled rings so a recording never passes them off as a person's touches.
@MainActor
final class ScriptedInput {
    enum Action {
        case tapCharacter
        case tapFloor(fraction: Double)
        case tapBehind
        case celebrate
        case rest
        case tapSpam(count: Int, over: Double)
    }

    private var timeline: [(at: Double, action: Action)]
    private var spam: (remaining: Int, interval: Double, next: Double)?

    init?(scenario: String?) {
        switch scenario {
        case "interaction":
            timeline = [
                (8, .tapCharacter),
                (16, .tapFloor(fraction: 0.9)),
                (26, .celebrate),
                (27.5, .tapSpam(count: 10, over: 2.0)),
                (36, .tapBehind),
                (46, .rest),
                (55, .celebrate),
                (55.4, .celebrate),
                (70, .tapFloor(fraction: 0.12)),
                (80, .tapCharacter),
            ]
        case "reducedMotion":
            timeline = [(12, .tapCharacter), (20, .celebrate), (30, .tapFloor(fraction: 0.85))]
        default:
            return nil                         // "autonomous", "lifecycle", "flipbook": no input at all
        }
    }

    func fire(elapsed: Double, model: StageModel) {
        if var s = spam, elapsed >= s.next {
            tapCharacter(model)
            s.remaining -= 1
            s.next += s.interval
            spam = s.remaining > 0 ? s : nil
        }
        while let first = timeline.first, elapsed >= first.at {
            timeline.removeFirst()
            switch first.action {
            case .tapCharacter: tapCharacter(model)
            case .tapFloor(let f):
                model.tap(at: Point(x: model.stage.minX + (model.stage.maxX - model.stage.minX) * f, y: 0), scripted: true)
            case .tapBehind:
                let behind = model.state.x - model.state.facing.sign * 650
                model.tap(at: Point(x: min(max(behind, 100), model.stage.maxX - 100), y: 0), scripted: true)
            case .celebrate: model.celebrate()
            case .rest: model.encourageRest()
            case .tapSpam(let count, let over):
                spam = (count, over / Double(count), elapsed)
            }
        }
    }

    private func tapCharacter(_ model: StageModel) {
        let y = model.state.mode == .hopping ? 700.0 : 420.0
        model.tap(at: Point(x: model.state.x, y: y), scripted: true)
    }
}
