import Foundation
import NikuCueDomain
import SpriteKit

/// Builds keyed `SKAction`s from the keyframe tracks in `animations.json` (docs/04 §5).
///
/// Every value is applied relative to the node's rest transform, so clips can be cancelled at any
/// time and the rig restored with `CatRig.resetToRest()`. Keys are unique per clip/node/property, so
/// the same infinite action is never stacked twice.
@MainActor
struct AnimationLibrary {
    let spec: AnimationSpec

    struct ScheduledAction {
        let node: SKNode
        let key: String
        let action: SKAction
    }

    static func key(clip: String, node: String, property: String) -> String {
        "clip.\(clip).\(node).\(property)"
    }

    /// Actions for one clip. Loop clips return `repeatForever` actions.
    func actions(for clip: AnimationSpec.Clip, reducedMotion: Bool, rig: CatRig) -> [ScheduledAction] {
        let tracks = reducedMotion ? clip.reducedMotionTracks : clip.tracks
        let duration = max(0.001, clip.duration)
        let blend = spec.expressionBlend
        var result: [ScheduledAction] = []
        for track in tracks {
            guard let node = rig.node(track.node), let rest = rig.rest[track.node] else { continue }
            let property = track.property
            let base: SKAction
            if property == "expression" {
                let box = ExpressionBox()
                base = SKAction.customAction(withDuration: duration) { [weak rig] _, elapsed in
                    guard let rig else { return }
                    let ms = Double(elapsed) * 1000
                    if let name = KeyframeSampler.name(track, at: ms), let expression = Expression(rawValue: name),
                       box.last != expression {
                        box.last = expression
                        rig.setExpression(expression, blend: blend)
                    }
                }
            } else {
                base = SKAction.customAction(withDuration: duration) { node, elapsed in
                    let ms = Double(elapsed) * 1000
                    guard let value = KeyframeSampler.number(track, at: ms) else { return }
                    let v = CGFloat(value)
                    switch property {
                    case "rotation": node.zRotation = rest.zRotation + v * .pi / 180
                    case "offsetX": node.position.x = rest.position.x + v
                    case "offsetY": node.position.y = rest.position.y + v
                    case "scaleX": node.xScale = rest.xScale * v
                    case "scaleY": node.yScale = rest.yScale * v
                    case "scale":
                        node.xScale = rest.xScale * v
                        node.yScale = rest.yScale * v
                    case "alpha": node.alpha = rest.alpha * v
                    default: break
                    }
                }
            }
            let action = clip.loop ? SKAction.repeatForever(base) : base
            result.append(ScheduledAction(node: node, key: AnimationLibrary.key(clip: clip.id, node: track.node, property: property), action: action))
        }
        return result
    }

    /// One blink: both eyes close and open over `durationMs` (ambient only; stopped during interactions).
    func blinkActions(rig: CatRig) -> [ScheduledAction] {
        let blink = spec.ambient.blink
        let half = max(0.01, blink.durationMs / 2000)
        let closed = CGFloat(blink.closedScaleY)
        return ["eyeL", "eyeR"].compactMap { id -> ScheduledAction? in
            guard let node = rig.node(id), let rest = rig.rest[id] else { return nil }
            let close = SKAction.scaleY(to: rest.yScale * closed, duration: half)
            let open = SKAction.scaleY(to: rest.yScale, duration: half)
            close.timingMode = .easeIn
            open.timingMode = .easeOut
            return ScheduledAction(node: node, key: "blink.\(id)", action: .sequence([close, open]))
        }
    }

    /// Random blink interval from the contract, using a seeded generator so tests are repeatable.
    func nextBlinkInterval<G: RandomNumberGenerator>(using rng: inout G) -> TimeInterval {
        let range = spec.ambient.blink.intervalMs
        let lo = range.first ?? 4000
        let hi = range.count > 1 ? range[1] : 7000
        return Double.random(in: lo...max(lo, hi), using: &rng) / 1000
    }

    private final class ExpressionBox {
        var last: Expression?
    }
}
