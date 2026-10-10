import NikuCueDomain
import SwiftUI

@main
struct NikuCueApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var container: AppContainer
    private let startupError: String?

    init() {
        do {
            let built = try AppContainer()
            _container = StateObject(wrappedValue: built)
            startupError = nil
        } catch {
            // Bundled contracts are build-time inputs; failing to load them is a packaging bug.
            _container = StateObject(wrappedValue: AppContainer.fallback())
            startupError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(startupError: startupError)
                .environmentObject(container)
                .environmentObject(container.localizer)
                .onChange(of: scenePhase) { _, phase in
                    // Pause the cat whenever the app is not active; never replay stale reactions on return (docs/04 §5).
                    container.scene.controller.setPaused(phase != .active)
                    container.scene.isPaused = phase != .active
                }
        }
    }
}

extension AppContainer {
    /// Last-resort container when resources cannot be loaded; RootView shows the error instead of the app.
    static func fallback() -> AppContainer {
        // swiftlint:disable:next force_try
        try! AppContainer(configuration: .current, repository: InMemoryHabitRepository(), clock: SystemClock())
    }
}
