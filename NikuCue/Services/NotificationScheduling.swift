import Foundation
import NikuCueDomain

enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined, denied, authorized, provisional
}

/// Boundary for local reminders (docs/07). The real implementation talks to UserNotifications; tests and
/// previews use `MockNotificationScheduler`.
protocol NotificationScheduling: AnyObject, Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    /// Shows the OS prompt (only when the user chose to set a reminder, docs/07 §4).
    func requestAuthorization() async -> NotificationAuthorization
    /// Diff-applies the desired requests inside our identifier prefix; never touches other apps' requests.
    func reconcile(slots: [ReminderSlot], remindersEnabled: Bool, title: String, body: String) async throws -> ReconcileReport
    func cancelAll() async
    func pendingOwnIdentifiers() async -> [String]
}

struct ReconcileReport: Equatable, Sendable {
    var added: Int
    var removed: Int
    var pending: Int
}

/// In-memory stand-in used by unit tests and SwiftUI previews.
final class MockNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Set<String> = []
    var status: NotificationAuthorization = .notDetermined
    var grantOnRequest = true
    private(set) var reconcileCalls = 0

    init() {}

    func authorizationStatus() async -> NotificationAuthorization { lock.withLock { status } }

    func requestAuthorization() async -> NotificationAuthorization {
        lock.withLock {
            if status == .notDetermined { status = grantOnRequest ? .authorized : .denied }
            return status
        }
    }

    func reconcile(slots: [ReminderSlot], remindersEnabled: Bool, title: String, body: String) async throws -> ReconcileReport {
        lock.withLock {
            reconcileCalls += 1
            let desired = ReminderPlanner.requests(for: slots, remindersEnabled: remindersEnabled)
            let diff = ReminderPlanner.diff(pendingIdentifiers: pending, desired: desired)
            for spec in diff.toAdd { pending.insert(spec.identifier) }
            for id in diff.toRemove { pending.remove(id) }
            return ReconcileReport(added: diff.toAdd.count, removed: diff.toRemove.count, pending: pending.count)
        }
    }

    func cancelAll() async {
        lock.withLock { pending = pending.filter { !ReminderPlanner.isOwnIdentifier($0) } }
    }

    func pendingOwnIdentifiers() async -> [String] {
        lock.withLock { pending.filter(ReminderPlanner.isOwnIdentifier).sorted() }
    }
}
