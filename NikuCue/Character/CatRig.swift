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
    private(set) var expression: Expression = .neutral
    private let art: CharacterArtProvider
    private let pixelsPerUnit: CGFloat
    /// Parts with expression variants keep two sprites so expressions can cross-fade.
    private var variantSprites: [String: (front: SKSpriteNode, back: SKSpriteNode)] = [:]

    init(spec: RigSpec, art: CharacterArtProvider, pixelsPerUnit: CGFloat) {
        self.spec = spec
        self.art = art
        self.pixelsPerUnit = pixelsPerUnit
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
            parent.addChild(node)
            nodes[child.id] = node
            rest[child.id] = RestTransform(position: node.position, zRotation: 0, xScale: 1, yScale: 1, alpha: node.alpha)
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
            apply(partId: n.id, expression: expression, to: front)
            back.alpha = 0
            return container
        }
        let sprite = SKSpriteNode()
        apply(partId: n.id, expression: nil, to: sprite)
        return sprite
    }

    private func apply(partId: String, expression: Expression?, to sprite: SKSpriteNode) {
        guard let part = art.art(for: partId, expression: expression, pixelsPerUnit: pixelsPerUnit) else {
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
    /// never reset here. Actions are not removed here; callers remove them by key first.
    func resetToRest() {
        for (id, node) in nodes where node !== root {
            rest[id]?.apply(to: node)
        }
    }

    /// Switches the facial expression with a short cross-fade (docs/04 §5: 80–120 ms blend).
    func setExpression(_ new: Expression, blend: TimeInterval) {
        guard new != expression else { return }
        expression = new
        for (partId, pair) in variantSprites {
            // the previous look moves to the back sprite and fades out while the new one fades in
            pair.back.texture = pair.front.texture
            pair.back.size = pair.front.size
            pair.back.anchorPoint = pair.front.anchorPoint
            pair.back.removeAllActions()
            pair.front.removeAllActions()
            apply(partId: partId, expression: new, to: pair.front)
            if blend <= 0 {
                pair.back.alpha = 0
                pair.front.alpha = 1
            } else {
                pair.back.alpha = 1
                pair.front.alpha = 0
                pair.back.run(.fadeOut(withDuration: blend), withKey: "expression.fade")
                pair.front.run(.fadeIn(withDuration: blend), withKey: "expression.fade")
            }
        }
    }

    /// A heart sprite for the milestone clip (max three at a time, spawned by the controller).
    func makeHeart() -> SKSpriteNode? {
        guard let part = art.art(for: "heart", expression: nil, pixelsPerUnit: pixelsPerUnit) else { return nil }
        let sprite = SKSpriteNode(texture: part.texture, size: part.size)
        sprite.anchorPoint = part.anchorPoint
        sprite.zPosition = 20
        return sprite
    }

    /// Character bounds in design units from the contract (docs/04 §3: about 760 × 720 within the 1024 canvas).
    var designSize: CGSize { CGSize(width: 760, height: 760) }
    var groundY: CGFloat { CGFloat(spec.canvas.rootGroundY) }
}
