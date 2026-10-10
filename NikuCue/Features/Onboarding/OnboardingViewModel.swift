import Combine
import Foundation
import NikuCueDomain

/// Onboarding O01–O05 state (docs/02 §1, docs/03 §1).
///
/// Every completed step persists `onboardingStep` through `AppState` so a crash resumes at the same step.
/// The cat's name, the first habit and the reminder are written only through `AppState`,
/// `HabitEditorViewModel` and `HabitService`; nothing here touches the repository, shows ads or sells anything.
@MainActor
final class OnboardingViewModel: ObservableObject {
    /// Pages pushed on top of the intro (O01 is the navigation root).
    enum Page: Hashable {
        case demo, name, habit, reminder
    }

    @Published var path: [Page]
    /// True while a save or the OS permission prompt is in flight; buttons are disabled, never the whole screen.
    @Published private(set) var isBusy = false

    // MARK: O02 name

    @Published var nameText: String
    /// Localization key of the error under the name field (`settings.nameInvalid`, `error.save`).
    @Published var nameErrorKey: String?

    // MARK: O03 first habit

    let editor: HabitEditorViewModel
    /// The habit saved in this flow (or before a crash). While set, the step shows a summary instead of the form
    /// so that Back → Next can never create a second habit.
    @Published private(set) var createdHabit: Habit?
    private var didCheckExistingHabit = false

    // MARK: O04 reminder

    @Published var reminderTime: Date
    @Published var reminderWeekdays: WeekdaySet = .everyDay
    /// The OS permission was refused: show `reminder.denied` and let the person continue.
    @Published private(set) var reminderDenied = false
    @Published var reminderErrorKey: String?
    @Published var finishErrorKey: String?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        let clock = container.clock
        let today = CalendarService(clock: clock).dayKey(for: clock.now)
        editor = HabitEditorViewModel(mode: .create, service: container.habitService, today: today)
        reminderTime = OnboardingViewModel.defaultReminderDate(now: clock.now, timeZone: clock.timeZone)
        path = OnboardingViewModel.initialPath(for: container.appState.preferences.onboardingStep)
        nameText = container.appState.companion.nickname ?? ""
    }

    /// Resume point after a crash: the persisted step with the pages before it, so Back still works.
    static func initialPath(for step: OnboardingStep) -> [Page] {
        switch step {
        case .intro, .finished: return []
        case .name: return [.name]
        case .habit: return [.name, .habit]
        case .reminder: return [.name, .habit, .reminder]
        }
    }

    /// 20:00 local on the current day; the person changes it with the picker. Not a recommendation.
    static func defaultReminderDate(now: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
    }

    /// Time zone used by the time picker and for reading hour/minute back (never parsed from displayed text).
    var timeZone: TimeZone { container.clock.timeZone }

    private var controller: CatSceneController { container.scene.controller }

    // MARK: Navigation

    func back() {
        guard !isBusy, !path.isEmpty else { return }
        path.removeLast()
    }

    // MARK: O01 intro

    func startTapped() {
        guard !isBusy else { return }
        path = [.name]
        Task { await self.persist(step: .name) }
    }

    /// "Meet your cat first": demo only, never writes a record (docs/02 §1).
    func demoTapped() {
        guard !isBusy else { return }
        path = [.demo]
    }

    /// The intro's `onAppear`. With a restored path (resume after a crash) the root is not visible, so nothing starts.
    func introAppeared() {
        guard path.isEmpty else { return }
        enterIntroScene()
    }

    /// The intro shows the shared cat scene: room tint for the hour, Reduce Motion from preferences/OS, ambient idle.
    func enterIntroScene() {
        let timeOfDay = container.currentTimeOfDay
        container.scene.setTimeOfDay(timeOfDay, animated: false)
        controller.reduceMotion = container.appState.effectiveReduceMotion
        controller.enterScene(ambient: timeOfDay.ambient)
    }

    /// The demo presents the same scene and manages its own lifecycle, and Home takes the scene over once onboarding
    /// is finished; pause only when the cat really leaves the screen for a cat-less step.
    func introDisappeared() {
        guard path.last != .demo, !container.appState.preferences.isOnboardingComplete else { return }
        controller.leaveScene()
    }

    /// `CatDemoView` pauses the shared scene in its `onDisappear`, which runs after the pop transition and therefore
    /// after the intro's `onAppear`. Re-enter once the transition has settled so the cat keeps breathing on O01.
    func pathChanged(from old: [Page], to new: [Page]) {
        guard new.isEmpty, old.last == .demo else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, self.path.isEmpty else { return }
            self.enterIntroScene()
        }
    }

    // MARK: O02 name

    /// Blank keeps the localized default; otherwise 1–16 grapheme clusters (docs/02 §1 O02).
    func submitName() async {
        guard !isBusy else { return }
        nameErrorKey = nil
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, case .failure = HabitValidation.validateNickname(trimmed) {
            nameErrorKey = "settings.nameInvalid"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await container.appState.setNickname(trimmed.isEmpty ? nil : trimmed)
        } catch HabitServiceError.validation {
            nameErrorKey = "settings.nameInvalid"
            return
        } catch {
            nameErrorKey = "error.save"
            return
        }
        await persist(step: .habit)
        path.append(.habit)
    }

    // MARK: O03 first habit

    /// After a crash the habit may already exist (step `.reminder` was persisted): show it instead of the form.
    func loadExistingHabitIfNeeded() async {
        guard createdHabit == nil, !didCheckExistingHabit else { return }
        didCheckExistingHabit = true
        if let snapshot = try? await container.habitService.homeSnapshot(), let first = snapshot.activeHabits.first {
            createdHabit = first
        }
    }

    func submitHabit() async {
        guard !isBusy else { return }
        if createdHabit == nil {
            isBusy = true
            let saved = await editor.save()
            isBusy = false
            guard let saved else { return } // editor.error carries the key
            createdHabit = saved
            reminderWeekdays = editor.effectiveWeekdays
        }
        await persist(step: .reminder)
        if path.last != .reminder { path.append(.reminder) }
    }

    // MARK: O04 reminder

    func toggleReminderDay(_ iso: Int) {
        reminderWeekdays = reminderWeekdays.toggling(iso)
        if !reminderWeekdays.isEmpty { reminderErrorKey = nil }
    }

    /// "Confirm": the OS prompt is requested only here (docs/02 §1 O04, docs/07 §4). Authorized → one slot is saved,
    /// reminders are enabled and the pending requests are reconciled; denied → explain once and continue.
    func confirmReminder() async {
        guard !isBusy else { return }
        reminderErrorKey = nil
        finishErrorKey = nil
        guard !reminderWeekdays.isEmpty else {
            reminderErrorKey = "habit.daysInvalid"
            return
        }
        isBusy = true
        defer { isBusy = false }
        let status = await container.notifications.requestAuthorization()
        switch status {
        case .authorized, .provisional:
            let time = timeComponents(of: reminderTime)
            let slot = ReminderSlot(enabled: true, hour: time.hour, minute: time.minute, weekdays: reminderWeekdays)
            do {
                try await container.habitService.saveReminderSlots([slot])
                try await container.appState.updatePreferences { $0.remindersEnabled = true }
            } catch {
                reminderErrorKey = "error.save"
                return
            }
            do {
                _ = try await container.notifications.reconcile(
                    slots: [slot],
                    remindersEnabled: true,
                    title: container.localizer.t("reminder.notificationTitle"),
                    body: container.localizer.t("reminder.notificationBody"))
            } catch {
                reminderErrorKey = "error.notification"
                return
            }
            await completeOnboarding()
        case .denied, .notDetermined:
            reminderDenied = true
        }
    }

    /// "Not now" or the button after a denial: nothing is requested or saved for reminders.
    func finishTapped() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await completeOnboarding()
    }

    // MARK: O05 finish

    /// Marks onboarding finished; RootView then shows Home. On failure the person can retry (data is unchanged).
    private func completeOnboarding() async {
        finishErrorKey = nil
        do {
            try await container.appState.updatePreferences { $0.onboardingStep = .finished }
        } catch {
            finishErrorKey = "error.save"
        }
    }

    // MARK: Helpers

    /// Resume aid only: a failure here must not block the person (the final step is handled by `completeOnboarding`).
    private func persist(step: OnboardingStep) async {
        try? await container.appState.updatePreferences { $0.onboardingStep = step }
    }

    private func timeComponents(of date: Date) -> (hour: Int, minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = container.clock.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0, components.minute ?? 0)
    }
}
