import Foundation
import NikuCueDomain
import SpriteKit
import UIKit

/// Room tints by time of day (REV-006). Presentation only.
enum RoomTheme {
    static func color(for timeOfDay: TimeOfDay) -> UIColor {
        switch timeOfDay {
        case .morning: return UIColor(hex: "#FFF1D6")!
        case .day: return UIColor(hex: "#FBEFD9")!
        case .night: return UIColor(hex: "#D3C6D4")!
        }
    }
}

/// The one visible cat scene. Created once per app and resized, never recreated per screen (docs/04 §5).
@MainActor
final class CatScene: SKScene {
    let rig: CatRig
    let controller: CatSceneController
    /// Tap on the cat (the SwiftUI layer decides whether that becomes a pet reaction).
    var onTap: (() -> Void)?

    private let cushion = SKShapeNode()
    private var timeOfDay: TimeOfDay = .day

    init(size: CGSize, rig: CatRig, library: AnimationLibrary, seed: UInt64) {
        self.rig = rig
        self.controller = CatSceneController(rig: rig, library: library, host: rig.root, seed: seed)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0)
        backgroundColor = RoomTheme.color(for: .day)
        cushion.zPosition = -1
        cushion.fillColor = UIColor(hex: "#EBD6B8")!
        cushion.strokeColor = .clear
        addChild(cushion)
        addChild(rig.root)
        layoutRig()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutRig()
    }

    /// Fits the 760-unit-tall character into the available height with a little head room.
    private func layoutRig() {
        guard size.height > 0, size.width > 0 else { return }
        let design = rig.designSize
        let scale = min(size.height * 0.92 / design.height, size.width * 0.92 / design.width)
        rig.root.setScale(scale)
        // root is the ground centre; keep the shadow a little above the bottom edge
        rig.root.position = CGPoint(x: 0, y: size.height * 0.06)
        let cushionWidth = design.width * 0.62 * scale
        cushion.path = CGPath(ellipseIn: CGRect(x: -cushionWidth / 2, y: rig.root.position.y - 14 * scale,
                                                width: cushionWidth, height: 56 * scale), transform: nil)
    }

    func setTimeOfDay(_ value: TimeOfDay, animated: Bool) {
        guard value != timeOfDay else { return }
        timeOfDay = value
        let target = RoomTheme.color(for: value)
        removeAction(forKey: "room.tint")
        if animated {
            // SKAction.colorize only affects sprites; interpolate the scene background ourselves.
            let from = backgroundColor
            var f: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 1)
            var t: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 1)
            from.getRed(&f.r, green: &f.g, blue: &f.b, alpha: &f.a)
            target.getRed(&t.r, green: &t.g, blue: &t.b, alpha: &t.a)
            let tint = SKAction.customAction(withDuration: 0.6) { node, elapsed in
                let u = min(1, max(0, elapsed / 0.6))
                (node as? SKScene)?.backgroundColor = UIColor(red: f.r + (t.r - f.r) * u, green: f.g + (t.g - f.g) * u,
                                                              blue: f.b + (t.b - f.b) * u, alpha: 1)
            }
            run(.sequence([tint, .run { [weak self] in self?.backgroundColor = target }]), withKey: "room.tint")
        } else {
            backgroundColor = target
        }
        controller.setAmbient(value.ambient)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if rig.root.calculateAccumulatedFrame().insetBy(dx: -20, dy: -20).contains(location) {
            onTap?()
        }
    }
}
