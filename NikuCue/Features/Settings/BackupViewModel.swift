import Combine
import Foundation
import NikuCueDomain

/// Manual backup / import flow (docs/02 §7): export to a temporary file the Share Sheet hands out,
/// validate a picked file without touching the database, preview counts, two-step confirmation,
/// atomic replace, then reminders off. Failures keep the current data and say so.
@MainActor
final class BackupViewModel: ObservableObject {
    enum Notice: Equatable {
        case success(String)
        case failure(String)

        var key: String {
            switch self {
            case .success(let key), .failure(let key): return key
            }
        }

        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    /// Set once the export file exists; the view then shows a `ShareLink` for it.
    @Published private(set) var exportURL: URL?
    @Published private(set) var isPreparingExport = false
    @Published var showImporter = false
    /// Validated document waiting for the user's confirmation.
    @Published private(set) var pendingDocument: BackupDocument?
    @Published var showReplaceConfirmation = false
    @Published private(set) var isRestoring = false
    @Published private(set) var notice: Notice?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    var previewHabitCount: Int? { pendingDocument?.habits.count }

    // MARK: Export

    func prepareExport() async {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }
        notice = nil
        do {
            exportURL = try await container.backupService.exportToTemporaryFile()
        } catch {
            exportURL = nil
            notice = .failure("error.save")
        }
    }

    // MARK: Import

    /// Result of `.fileImporter`. The file is validated in full before anything is shown (docs/03 §6).
    func handleImport(_ result: Result<URL, Error>) {
        notice = nil
        pendingDocument = nil
        switch result {
        case .failure:
            notice = .failure("backup.invalid")
        case .success(let url):
            do {
                switch try container.backupService.preview(fileAt: url) {
                case .success(let document):
                    pendingDocument = document
                case .failure(let error):
                    notice = .failure(BackupViewModel.key(for: error))
                }
            } catch {
                notice = .failure("backup.invalid")
            }
        }
    }

    /// First step: the preview's confirm button opens the replace alert.
    func requestRestore() {
        guard pendingDocument != nil else { return }
        showReplaceConfirmation = true
    }

    func cancelPreview() {
        pendingDocument = nil
    }

    /// Second step: replace everything atomically, cancel our pending notifications (restored reminders start
    /// disabled), then reload app state so the nickname, language and preferences follow the import.
    func confirmRestore() async {
        guard let document = pendingDocument, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        notice = nil
        do {
            try await container.backupService.restore(document)
        } catch HabitServiceError.backup(let error) {
            notice = .failure(BackupViewModel.key(for: error))
            return
        } catch {
            notice = .failure("backup.invalid") // the replace is atomic: existing data is unchanged
            return
        }
        pendingDocument = nil
        await container.notifications.cancelAll()
        await container.appState.load()
        container.haptics.isEnabled = container.appState.preferences.hapticsEnabled
        container.reevaluateAdGate()
        notice = .success("backup.restored")
    }

    /// Called when the screen goes away: the temporary export is removed.
    func cleanup() {
        exportURL = nil
        container.backupService.cleanupTemporaryExports()
    }

    private static func key(for error: BackupValidationError) -> String {
        if case .tooLarge = error { return "backup.tooLarge" }
        return "backup.invalid"
    }
}
