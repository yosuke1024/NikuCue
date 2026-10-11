import Foundation
import NikuCueDomain
import SpriteKit

/// Rest transform of a rig node, restored after every clip (docs/04 §5).
struct RestTransform {
    var position: CGPoint
    var zRotation: CGFloat
    var xScale: CGFloat
    var yScale: CGFloat
    var alpha: CGFloat

    @MainActor
    func apply(to node: SKNode) {
        node.position = position
        node.zRotation = zRotation
        node.xScale = xScale
        node.yScale = yScale
        node.alpha = alpha
    }
}

/// The SpriteKit node tree built from `character_spec.json`. Node ids come from the contract; the
/// art comes from a `CharacterArtProvider`. Nothing here writes to the database.
@MainActor
final class CatRig {
    let spec: RigSpec
    let root: SKNode
    private(set) var nodes: [String: SKNode] = [:]
    private(set) var rest: [String: RestTransform] = [:]
    /// Current look: an expression name (parts rig) or a pose name (whole-body rig).
    private(set) var look: String
    var expression: Expression { Expression(rawValue: look) ?? .neutral }
    private let art: CharacterArtProvider
    private let pixelsPerUnit: CGFloat
    /// Parts with expression variants keep two sprites so expressions can cross-fade.
    private var variantSprites: [String: (front: SKSpriteNode, back: SKSpriteNode)] = [:]

    init(spec: RigSpec, art: CharacterArtProvider, pixelsPerUnit: CGFloat) {
        self.spec = spec
        self.art = art
        self.pixelsPerUnit = pixelsPerUnit
        self.look = spec.look(for: .neutral)
        root = SKNode()
        root.name = spec.rootNode?.id ?? "root"
        nodes[root.name!] = root
        if let rootNode = spec.rootNode {
            rest[rootNode.id] = RestTransform(position: .zero, zRotation: 0, xScale: 1, yScale: 1, alpha: 1)
            build(children: spec.children(of: rootNode.id), under: root)
        }
    }

    private func build(children: [RigSpec.Node], under parent: SKNode) {
        for child in children {
            let node = makeNode(child)
            node.name = child.id
            node.position = CGPoint(x: child.position[0], y: child.position[1])
            node.zPosition = CGFloat(child.z)
            node.alpha = CGFloat(child.opacity ?? 1)
            if let scale = child.scale { node.setScale(CGFloat(scale)) }
            parent.addChild(node)
            nodes[child.id] = node
            rest[child.id] = RestTransform(position: node.position, zRotation: 0, xScale: node.xScale, yScale: node.yScale, alpha: node.alpha)
            build(children: spec.children(of: child.id), under: node)
        }
    }

    private func makeNode(_ n: RigSpec.Node) -> SKNode {
        guard !n.isPivot else { return SKNode() }
        if art.hasVariants(n.id) {
            let container = SKNode()
            let back = SKSpriteNode()
            let front = SKSpriteNode()
            back.zPosition = 0
            front.zPosition = 0.01
            container.addChild(back)
            container.addChild(front)
            variantSprites[n.id] = (front, back)
            apply(partId: n.id, look: look, to: front)
            back.alpha = 0
            return container
        }
        let sprite = SKSpriteNode()
        apply(partId: n.id, look: nil, to: sprite)
        return sprite
    }

    private func apply(partId: String, look: String?, to sprite: SKSpriteNode) {
        guard let part = art.art(for: partId, look: look, pixelsPerUnit: pixelsPerUnit) else {
            sprite.texture = nil
            sprite.size = .zero
            return
        }
        sprite.texture = part.texture
        sprite.size = part.size
        sprite.anchorPoint = part.anchorPoint
    }

    func node(_ id: String) -> SKNode? { nodes[id] }

    /// Restores every rig node's rest transform. The root is owned by the scene (layout scale/position) and is
    /// never reset here. Clip actions are not removed here; callers remove them by key first.
    func resetToRest() {
        for (id, node) in nodes where node !== root {
            node.removeAction(forKey: CatRig.restEaseKey)
            rest[id]?.apply(to: node)
        }
    }

    static let restEaseKey = "rest.ease"
    /// Per node id, the track properties the next clip drives (`offsetX`, `rotation`, `scaleY`, ...).
    typealias ControlledProperties = [String: Set<String>]

    /// Prepares the rig for a new clip: properties the clip drives snap to rest (their track takes over on the
    /// next frame), everything else eases back over `duration`, so a swaying tail or a breathing body never jumps
    /// when a reaction interrupts the ambient loop.
    func settle(toRestOver duration: TimeInterval, controlled: ControlledProperties) {
        for (id, node) in nodes where node !== root {
            guard let target = rest[id] else { continue }
            node.removeAction(forKey: CatRig.restEaseKey)
            let driven = controlled[id] ?? []
            let drivesX = driven.contains("scale") || driven.contains("scaleX")
            let drivesY = driven.contains("scale") || driven.contains("scaleY")
            if driven.contains("offsetX") { node.position.x = target.position.x }
            if driven.contains("offsetY") { node.position.y = target.position.y }
            if driven.contains("rotation") { node.zRotation = target.zRotation }
            if drivesX { node.xScale = target.xScale }
            if drivesY { node.yScale = target.yScale }
            if driven.contains("alpha") { node.alpha = target.alpha }
            var actions: [SKAction] = []
            if !driven.contains("offsetX"), abs(node.position.x - target.position.x) > 0.01 { actions.append(.moveTo(x: target.position.x, duration: duration)) }
            if !driven.contains("offsetY"), abs(node.position.y - target.position.y) > 0.01 { actions.append(.moveTo(y: target.position.y, duration: duration)) }
            if !driven.contains("rotation"), abs(node.zRotation - target.zRotation) > 0.0005 { actions.append(.rotate(toAngle: target.zRotation, duration: duration, shortestUnitArc: true)) }
            if !drivesX, abs(node.xScale - target.xScale) > 0.0005 { actions.append(.scaleX(to: target.xScale, duration: duration)) }
            if !drivesY, abs(node.yScale - target.yScale) > 0.0005 { actions.append(.scaleY(to: target.yScale, duration: duration)) }
            if !driven.contains("alpha"), abs(node.alpha - target.alpha) > 0.005 { actions.append(.fadeAlpha(to: target.alpha, duration: duration)) }
            guard !actions.isEmpty else { continue }
            if duration <= 0 { target.apply(to: node); continue }
            let ease = SKAction.group(actions)
            ease.timingMode = .easeInEaseOut
            node.run(ease, withKey: CatRig.restEaseKey)
        }
    }

    /// Switches the facial expression (mapped to a pose on the whole-body rig) with a short cross-fade.
    func setExpression(_ new: Expression, blend: TimeInterval) {
        setLook(spec.look(for: new), blend: blend)
    }

    /// Switches the look (expression or pose) with a cross-fade: docs/04 §5 asks for 80–120 ms on the parts rig,
    /// the whole-body asset README for 120–220 ms. Faces are never morphed, only faded.
    func setLook(_ new: String, blend: TimeInterval) {
        guard new != look, spec.expressions.contains(new) else { return }
        look = new
        for (partId, pair) in variantSprites {
            // the previous look moves to the back sprite and fades out while the new one fades in
            pair.back.texture = pair.front.texture
            pair.back.size = pair.front.size
            pair.back.anchorPoint = pair.front.anchorPoint
            pair.back.removeAllActions()
            pair.front.removeAllActions()
            apply(partId: partId, look: new, to: pair.front)
            if blend <= 0 {
                pair.back.alpha = 0
                pair.back.texture = nil
                pair.front.alpha = 1
            } else {
                // A switch during a running fade carries the current alpha instead of snapping the half-faded
                // texture to 1 (visible on whole-body portraits). The faded-out texture is released afterwards.
                pair.back.alpha = pair.front.alpha
                pair.front.alpha = 0
                let release = SKAction.run { [weak back = pair.back] in back?.texture = nil }
                pair.back.run(.sequence([.fadeOut(withDuration: blend), release]), withKey: "expression.fade")
                pair.front.run(.fadeIn(withDuration: blend), withKey: "expression.fade")
            }
        }
    }

    /// A heart sprite for the milestone clip (max three at a time, spawned by the controller).
    func makeHeart() -> SKSpriteNode? {
        guard let part = art.art(for: "heart", look: nil, pixelsPerUnit: pixelsPerUnit) else { return nil }
        let sprite = SKSpriteNode(texture: part.texture, size: part.size)
        sprite.anchorPoint = part.anchorPoint
        sprite.zPosition = 20
        return sprite
    }

    /// Character bounds in design units: the whole-body rig states them; the parts rig uses the docs/04 §3 guide (≈760 × 760).
    var designSize: CGSize {
        if let d = spec.designSize, d.count == 2 { return CGSize(width: d[0], height: d[1]) }
        return CGSize(width: 760, height: 760)
    }

    /// Whether the rig has independently animated eyes (the whole-body rig does not; no fake blinks).
    var hasEyeParts: Bool { nodes["eyeL"] != nil && nodes["eyeR"] != nil }
    var groundY: CGFloat { CGFloat(spec.canvas.rootGroundY) }
}
