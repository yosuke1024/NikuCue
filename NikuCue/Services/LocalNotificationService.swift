import Foundation
import NikuCueDomain
import UserNotifications

/// UserNotifications implementation (docs/07 §3). One repeating calendar trigger per slot × weekday,
/// at most 14, stable identifiers, diff-applied so repeated reconciles never duplicate (QA Q18).
final class LocalNotificationService: NotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorization {
        map(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if !granted { return .denied }
        } catch {
            return .denied
        }
        return map(await center.notificationSettings().authorizationStatus)
    }

    func reconcile(slots: [ReminderSlot], remindersEnabled: Bool, title: String, body: String) async throws -> ReconcileReport {
        let desired = ReminderPlanner.requests(for: slots, remindersEnabled: remindersEnabled)
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let diff = ReminderPlanner.diff(pendingIdentifiers: Set(pending), desired: desired)
        if !diff.toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.toRemove)
        }
        // Text changes (language switch) replace existing requests in place: same identifier, new content (QA Q21).
        let existingById = Dictionary(uniqueKeysWithValues: (await center.pendingNotificationRequests()).map { ($0.identifier, $0) })
        var added = 0
        for spec in desired {
            if let existing = existingById[spec.identifier],
               existing.content.title == title, existing.content.body == body, !diff.toAdd.contains(spec) {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            // No badge, no sound in v1 (docs/07 §1).
            var components = DateComponents()
            components.weekday = spec.appleWeekday
            components.hour = spec.hour
            components.minute = spec.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(identifier: spec.identifier, content: content, trigger: trigger))
            added += 1
        }
        let after = await pendingOwnIdentifiers()
        return ReconcileReport(added: added, removed: diff.toRemove.count, pending: after.count)
    }

    func cancelAll() async {
        let own = await pendingOwnIdentifiers()
        if !own.isEmpty { center.removePendingNotificationRequests(withIdentifiers: own) }
    }

    func pendingOwnIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier).filter(ReminderPlanner.isOwnIdentifier).sorted()
    }

    private func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .authorized, .ephemeral: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

/// Keeps foreground banners from covering the current screen and routes taps to Home (docs/07 §4).
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onReminderTapped: (() -> Void)?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [] // in the foreground the app keeps its current screen
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        guard ReminderPlanner.isOwnIdentifier(id) else { return }
        await MainActor.run { onReminderTapped?() }
    }
}
