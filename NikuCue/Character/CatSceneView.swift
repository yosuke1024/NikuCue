import NikuCueDomain
import SpriteKit
import SwiftUI

/// SwiftUI host for the single `CatScene`. The speech bubble is SwiftUI text, never baked into the scene (docs/03 §2).
struct CatSceneView: View {
    let scene: CatScene
    var isPaused: Bool
    var accessibilityLabel: String
    var accessibilityValue: String
    var onPet: () -> Void

    var body: some View {
        SpriteView(scene: scene, isPaused: isPaused, preferredFramesPerSecond: 30, options: [.ignoresSiblingOrder])
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onPet() }
            .onAppear { scene.onTap = onPet }
    }
}
