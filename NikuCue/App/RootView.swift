import NikuCueDomain
import SwiftUI

/// Entry screen: store/read error → retry screen (nothing is deleted); onboarding not finished → onboarding; otherwise Home.
struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject private var appState: AppState
    let startupError: String?
    /// Rebuilds the composition root (re-opens the store). Provided by `AppRoot`.
    let onRetry: () -> Void

    init(container: AppContainer, startupError: String?, onRetry: @escaping () -> Void) {
        self.appState = container.appState
        self.startupError = startupError
        self.onRetry = onRetry
    }

    var body: some View {
        Group {
            if let startupError {
                ContentUnavailableView("Resources", systemImage: "exclamationmark.triangle", description: Text(startupError))
            } else if let dbError = container.databaseError {
                DatabaseErrorView(detail: dbError, onRetry: onRetry)
            } else if !appState.hasLoaded {
                ProgressView()
            } else if let loadError = appState.loadError {
                DatabaseErrorView(detail: loadError) { Task { await appState.load() } }
            } else if appState.preferences.isOnboardingComplete {
                HomeView()
            } else {
                OnboardingFlow()
            }
        }
        .task { await appState.load() }
    }
}

/// The store could not be opened or read. Nothing is deleted; the user can retry in place (docs/03 §6).
struct DatabaseErrorView: View {
    @EnvironmentObject private var localizer: Localizer
    @EnvironmentObject private var container: AppContainer
    let detail: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
            Text(localizer.t("error.database"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(localizer.t("common.retry")) { onRetry() }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            // Support route (docs/03 §6) appears once the owner has set a real support address.
            if !container.configuration.supportEmail.contains(AppConfiguration.placeholderMarker) {
                Text(container.configuration.supportEmail)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
            if AppConfiguration.isDebugBuild {
                Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
