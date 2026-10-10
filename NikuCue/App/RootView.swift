import NikuCueDomain
import SwiftUI

/// Entry screen. Until P05 ships Onboarding/Home, the root is the cat demo (P01) with the gallery (P02).
struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    let startupError: String?

    var body: some View {
        NavigationStack {
            if let startupError {
                ContentUnavailableView("Resources", systemImage: "exclamationmark.triangle", description: Text(startupError))
            } else {
                CatDemoView()
            }
        }
    }
}
