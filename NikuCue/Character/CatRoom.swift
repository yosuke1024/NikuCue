import NikuCueDomain
import SwiftUI

/// The cat room: fixed-height scene with the pet tap wired to the reaction engine.
struct CatRoom: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.scenePhase) private var scenePhase
    var height: CGFloat

    var body: some View {
        CatSceneView(scene: container.scene,
                     isPaused: scenePhase != .active,
                     accessibilityLabel: localizer.t("home.petAccessibility"),
                     accessibilityValue: accessibilityValue,
                     onPet: { container.catCoordinator.petTapped() })
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }

    private var accessibilityValue: String {
        switch container.scene.controller.currentClip {
        case .celebrate, .milestone, .pet: return localizer.t("home.catHappy")
        case .greet: return localizer.t("home.catGreeting")
        default: return localizer.t("home.catResting")
        }
    }
}
