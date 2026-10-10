import Foundation
import NikuCueDomain

/// File plumbing for manual backups (docs/02 §7). Validation lives in the Domain (`BackupValidator`);
/// replacement is the repository's atomic `replaceAll`. Nothing leaves the device unless the user shares the file.
struct BackupService {
    let habitService: HabitService
    let appVersion: String

    /// Writes `nikucue-backup-v1.json` to a temporary location the Share Sheet / Files picker can hand out.
    func exportToTemporaryFile() async throws -> URL {
        let document = try await habitService.exportBackup(appVersion: appVersion)
        let data = try document.encoded()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NikuCueBackup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(BackupDocument.fileName)
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Reads and validates a picked file without touching the database. Rejects files over the size limit before reading them fully.
    func preview(fileAt url: URL) throws -> Result<BackupDocument, BackupValidationError> {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > BackupValidator.maxBytes {
            return .failure(.tooLarge(bytes: size, max: BackupValidator.maxBytes))
        }
        let data = try Data(contentsOf: url)
        return BackupValidator.validate(data: data)
    }

    /// Replaces everything with a previously previewed document. Reminders come back disabled.
    func restore(_ document: BackupDocument) async throws {
        try await habitService.importBackup(data: try document.encoded())
    }

    /// Removes the temporary export after sharing.
    func cleanupTemporaryExports() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NikuCueBackup", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }
}
