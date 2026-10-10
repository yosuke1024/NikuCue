import NikuCueDomain
import SwiftUI

/// Entry screen: database error → retry screen; onboarding not finished → onboarding; otherwise Home.
struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject private var appState: AppState
    let startupError: String?

    init(container: AppContainer, startupError: String?) {
        self.appState = container.appState
        self.startupError = startupError
    }

    var body: some View {
        Group {
            if let startupError {
                ContentUnavailableView("Resources", systemImage: "exclamationmark.triangle", description: Text(startupError))
            } else if let dbError = container.databaseError {
                DatabaseErrorView(detail: dbError)
            } else if !appState.hasLoaded {
                ProgressView()
            } else if appState.preferences.isOnboardingComplete {
                HomeView()
            } else {
                OnboardingFlow()
            }
        }
        .task { await appState.load() }
    }
}

/// The store could not be opened. Nothing is deleted; the user can retry or contact support (docs/03 §6).
struct DatabaseErrorView: View {
    @EnvironmentObject private var localizer: Localizer
    let detail: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
            Text(localizer.t("error.database")).multilineTextAlignment(.center)
            Button(localizer.t("common.retry")) { exit(0) }  // relaunch reopens the store; data stays on disk
                .buttonStyle(.borderedProminent)
            if AppConfiguration.isDebugBuild {
                Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
