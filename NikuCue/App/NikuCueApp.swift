import NikuCueDomain
import SwiftUI
import UserNotifications

@main
struct NikuCueApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var root = AppRoot()

    var body: some Scene {
        WindowGroup {
            if let container = root.container {
                RootView(container: container, startupError: nil, onRetry: { root.retry() })
                    .id(ObjectIdentifier(container)) // a rebuilt container gets a fresh view tree
                    .environmentObject(container)
                    .environmentObject(container.localizer)
                    .onChange(of: scenePhase) { _, phase in
                        // Pause the cat whenever the app is not active; never replay stale reactions on return (docs/04 §5).
                        container.appState.isSceneActive = phase == .active
                        container.scene.controller.setPaused(phase != .active)
                        container.scene.isPaused = phase != .active
                        container.reevaluateAdGate()
                        if phase == .background {
                            Task { await container.appState.markFirstSessionFinishedIfNeeded() }
                        }
                    }
            } else {
                // Bundled contracts are build-time inputs; failing to load them is a packaging bug, shown instead of crashing.
                ContentUnavailableView("Resources", systemImage: "exclamationmark.triangle", description: Text(root.startupError ?? "unknown"))
            }
        }
    }
}

/// Builds the container; keeps the failure message when the bundled resources cannot be loaded.
/// `retry()` rebuilds the whole composition (re-opens the store). Nothing on disk is ever deleted (docs/03 §6).
@MainActor
final class AppRoot: ObservableObject {
    @Published private(set) var container: AppContainer?
    @Published private(set) var startupError: String?

    init() { build() }

    func retry() { build() }

    private func build() {
        do {
            container = try AppContainer()
            startupError = nil
        } catch {
            container = nil
            startupError = String(describing: error)
        }
    }
}
