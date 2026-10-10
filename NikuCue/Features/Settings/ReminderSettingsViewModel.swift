import Combine
import Foundation
import NikuCueDomain

/// Reminder settings state (docs/07 §1, §3, §4; docs/02 §1 O04).
///
/// One on/off switch and up to `ReminderPlanner.maxSlots` times, each with a weekday set. Every slot change is
/// saved through `HabitService` and the pending OS requests are reconciled right after. The notification center
/// always mirrors the last set the store accepted (`persistedSlots`): a refused draft (duplicate time, no weekdays)
/// stays visible with its message so the person can fix it, but never reaches the OS.
///
/// The OS permission prompt is requested only when the person turns reminders on (docs/07 §4). A refusal keeps the
/// switch off and shows the iPhone Settings route; a preference is never flipped silently. There are no per-habit
/// reminders, badges or sounds (docs/07 §1).
@MainActor
final class ReminderSettingsViewModel: ObservableObject {
    /// Draft shown in the UI. Equals the persisted set except while the latest change was refused.
    @Published private(set) var slots: [ReminderSlot] = []
    @Published private(set) var remindersEnabled = false
    @Published private(set) var authorization: NotificationAuthorization = .notDetermined
    @Published private(set) var hasLoaded = false
    /// True while the switch is being applied (permission prompt, preference save, reconcile). Only the switch is disabled.
    @Published private(set) var isApplyingSwitch = false
    /// Localization key of the current problem: `reminder.duplicate`, `habit.daysInvalid`, `error.save`,
    /// `error.notification` or `error.database`. Cleared by the next successful change.
    @Published private(set) var errorKey: String?
    /// Permission refused (now, or earlier while reminders are on): show `reminder.denied` and the Settings button.
    @Published private(set) var showsDeniedNotice = false
    /// "Add" was tapped at the limit: show `reminder.limit` until a slot is removed.
    @Published private(set) var showsLimitNotice = false
    /// Our pending OS requests after the last load / reconcile. Shown as a Debug caption only.
    @Published private(set) var pendingRequestCount: Int?

    /// New slots start at 08:00 every day; the person changes it with the picker. Not a recommendation (docs/07 §1).
    static let defaultHour = 8
    static let defaultMinute = 0

    private let container: AppContainer
    /// The last set the store accepted. Reconcile uses this, never the draft.
    private var persistedSlots: [ReminderSlot] = []
    /// Increased on every draft change so only the newest commit reports its outcome and reconciles.
    private var commitGeneration = 0
    /// Commits run one after another in the order the person made the changes.
    private var commitChain: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    var maxSlots: Int { ReminderPlanner.maxSlots }
    var canAddSlot: Bool { slots.count < ReminderPlanner.maxSlots }

    private var isAllowed: Bool {
        authorization == .authorized || authorization == .provisional
    }

    // MARK: Lifecycle

    /// On appear: slots and preference from the store, then the current OS permission (it may have changed in
    /// iPhone Settings). Denied while reminders are on shows the notice; the preference stays as it is.
    func load() async {
        errorKey = nil
        remindersEnabled = container.appState.preferences.remindersEnabled
        do {
            let loaded = try await container.habitService.reminderSlots()
            slots = loaded
            persistedSlots = loaded
        } catch {
            errorKey = "error.database"
        }
        hasLoaded = true
        await refreshAuthorization()
        #if DEBUG
        pendingRequestCount = await container.notifications.pendingOwnIdentifiers().count
        #endif
    }

    func refreshAuthorization() async {
        let status = await container.notifications.authorizationStatus()
        authorization = status
        if status == .denied, remindersEnabled {
            showsDeniedNotice = true
        } else if status == .authorized || status == .provisional {
            showsDeniedNotice = false
        }
    }

    /// Foreground return (for example from iPhone Settings): re-read the permission and, once it is allowed while
    /// reminders are on, make sure the OS holds the requests (docs/07 §3: reconcile after a permission change).
    func sceneBecameActive() async {
        guard hasLoaded, !isApplyingSwitch else { return }
        let before = authorization
        await refreshAuthorization()
        if remindersEnabled, before != authorization, isAllowed {
            await reconcile()
        }
    }

    // MARK: Switch

    /// Turning on: ask for the OS permission only when it was never asked; a refusal keeps the switch off and shows
    /// `reminder.denied`. Allowed → preference saved, every slot re-enabled (restored backups keep them off,
    /// docs/02 §7), then reconcile. Turning off: preference saved, pending requests removed.
    func setRemindersEnabled(_ on: Bool) async {
        guard !isApplyingSwitch, on != remindersEnabled else { return }
        isApplyingSwitch = true
        defer { isApplyingSwitch = false }
        errorKey = nil
        if on {
            var status = await container.notifications.authorizationStatus()
            if status == .notDetermined {
                status = await container.notifications.requestAuthorization()
            }
            authorization = status
            guard isAllowed else {
                showsDeniedNotice = true
                return
            }
            showsDeniedNotice = false
            let reenabled = ReminderSettingsViewModel.enablingAll(persistedSlots)
            if reenabled != persistedSlots {
                do {
                    try await container.habitService.saveReminderSlots(reenabled)
                    persistedSlots = reenabled
                    slots = ReminderSettingsViewModel.enablingAll(slots)
                } catch {
                    errorKey = "error.save"
                    return
                }
            }
        }
        do {
            try await container.appState.updatePreferences { $0.remindersEnabled = on }
            remindersEnabled = on
        } catch {
            errorKey = "error.save"
            return
        }
        await reconcile()
    }

    // MARK: Slots

    func addSlot() {
        guard canAddSlot else {
            showsLimitNotice = true
            return
        }
        showsLimitNotice = false
        slots.append(ReminderSlot(enabled: true, hour: ReminderSettingsViewModel.defaultHour,
                                  minute: ReminderSettingsViewModel.defaultMinute, weekdays: .everyDay))
        scheduleCommit()
    }

    func removeSlot(id: UUID) {
        guard slots.contains(where: { $0.id == id }) else { return }
        slots.removeAll { $0.id == id }
        showsLimitNotice = false
        scheduleCommit()
    }

    /// Hour and minute are read back with the device calendar; nothing is parsed from displayed text.
    func setTime(from date: Date, for id: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == id }),
              let time = ReminderSettingsViewModel.timeComponents(of: date) else { return }
        guard slots[index].hour != time.hour || slots[index].minute != time.minute else { return }
        slots[index].hour = time.hour
        slots[index].minute = time.minute
        scheduleCommit()
    }

    func toggleWeekday(_ iso: Int, for id: UUID) {
        guard (1...7).contains(iso), let index = slots.firstIndex(where: { $0.id == id }) else { return }
        slots[index].weekdays = slots[index].weekdays.toggling(iso)
        scheduleCommit()
    }

    /// Picker value for a slot: today's date at the slot's hour and minute in the device calendar / time zone.
    func date(forSlot id: UUID) -> Date {
        let slot = slots.first { $0.id == id }
        return ReminderSettingsViewModel.date(hour: slot?.hour ?? ReminderSettingsViewModel.defaultHour,
                                              minute: slot?.minute ?? ReminderSettingsViewModel.defaultMinute,
                                              on: container.clock.now)
    }

    /// After `error.notification`: apply the persisted set to the OS again.
    func retryReconcile() async {
        errorKey = nil
        await reconcile()
    }

    // MARK: Helpers

    static func date(hour: Int, minute: Int, on reference: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: reference) ?? reference
    }

    static func timeComponents(of date: Date) -> (hour: Int, minute: Int)? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return (hour, minute)
    }

    static func enablingAll(_ slots: [ReminderSlot]) -> [ReminderSlot] {
        var result: [ReminderSlot] = []
        for slot in slots {
            var copy = slot
            copy.enabled = true
            result.append(copy)
        }
        return result
    }

    private func scheduleCommit() {
        commitGeneration += 1
        let generation = commitGeneration
        let draft = slots
        let previous = commitChain
        commitChain = Task { [weak self] in
            if let previous { await previous.value }
            guard let self else { return }
            await self.commit(draft, generation: generation)
        }
    }

    /// Save → (newest only) message and reconcile. The OS mirrors the last accepted set even when this draft was refused.
    private func commit(_ draft: [ReminderSlot], generation: Int) async {
        var failure: String?
        do {
            try await container.habitService.saveReminderSlots(draft)
            persistedSlots = draft
        } catch HabitServiceError.duplicateReminder {
            failure = "reminder.duplicate"
        } catch HabitServiceError.validation {
            failure = "habit.daysInvalid"
        } catch {
            failure = "error.save"
        }
        guard generation == commitGeneration else { return }
        errorKey = failure
        await reconcile()
    }

    /// Diff-applies the persisted set inside our identifier prefix. Registration errors are shown, not hidden (docs/07 §3).
    private func reconcile() async {
        do {
            let report = try await container.notifications.reconcile(
                slots: persistedSlots,
                remindersEnabled: remindersEnabled,
                title: container.localizer.t("reminder.notificationTitle"),
                body: container.localizer.t("reminder.notificationBody"))
            pendingRequestCount = report.pending
        } catch {
            errorKey = "error.notification"
        }
    }
}
