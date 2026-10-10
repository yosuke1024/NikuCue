import Combine
import Foundation
import NikuCueDomain

/// Create / edit sheet state (docs/02 §2, docs/03 §3). Name and category apply immediately; weekday
/// changes, archive and resume take effect tomorrow and the sheet always says so.
@MainActor
final class HabitEditorViewModel: ObservableObject {
    enum Mode: Equatable {
        case create
        case edit(Habit)
    }

    enum SaveError: Equatable {
        case name, days, limit, generic
        var key: String {
            switch self {
            case .name: return "habit.nameInvalid"
            case .days: return "habit.daysInvalid"
            case .limit: return "habit.limit"
            case .generic: return "error.save"
            }
        }
    }

    let mode: Mode
    @Published var name: String
    @Published var category: HabitCategory
    @Published var everyDay: Bool
    @Published var weekdays: WeekdaySet
    @Published private(set) var currentWeekdays: WeekdaySet?
    @Published private(set) var isArchived = false
    @Published var error: SaveError?
    @Published private(set) var isSaving = false
    @Published var showDeleteConfirmation = false

    private let service: HabitService
    private let today: DayKey

    init(mode: Mode, service: HabitService, today: DayKey, versions: [HabitScheduleVersion] = []) {
        self.mode = mode
        self.service = service
        self.today = today
        switch mode {
        case .create:
            name = ""
            category = .custom
            everyDay = true
            weekdays = .everyDay
        case .edit(let habit):
            name = habit.name
            category = habit.category
            let latest = ScheduleResolver.latestVersion(for: habit.id, in: versions)
            let days = latest?.weekdays ?? .everyDay
            weekdays = days
            everyDay = days.isEveryDay
            currentWeekdays = days
            isArchived = latest.map { !$0.isActive } ?? false
        }
    }

    /// Prefills the name from a template (onboarding O03).
    func applyTemplate(category: HabitCategory, name: String) {
        self.category = category
        self.name = name
    }

    func toggle(_ iso: Int) {
        weekdays = weekdays.toggling(iso)
        everyDay = weekdays.isEveryDay
    }

    func setEveryDay(_ on: Bool) {
        everyDay = on
        if on { weekdays = .everyDay }
    }

    var effectiveWeekdays: WeekdaySet { everyDay ? .everyDay : weekdays }

    var canSave: Bool {
        if case .failure = HabitValidation.validateName(name) { return false }
        return !effectiveWeekdays.isEmpty
    }

    /// Returns the saved habit, or nil when validation failed (error is set).
    @discardableResult
    func save() async -> Habit? {
        error = nil
        guard case .success(let cleanName) = HabitValidation.validateName(name) else { error = .name; return nil }
        guard !effectiveWeekdays.isEmpty else { error = .days; return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                return try await service.createHabit(name: cleanName, category: category, weekdays: effectiveWeekdays)
            case .edit(let habit):
                try await service.updateHabit(id: habit.id, name: cleanName, category: category)
                if let current = currentWeekdays, current != effectiveWeekdays, !isArchived {
                    try await service.changeWeekdays(id: habit.id, weekdays: effectiveWeekdays)
                }
                var updated = habit
                updated.name = cleanName
                updated.category = category
                return updated
            }
        } catch HabitServiceError.validation(.activeLimitReached) {
            error = .limit
        } catch HabitServiceError.validation(.noWeekdays) {
            error = .days
        } catch HabitServiceError.validation {
            error = .name
        } catch {
            self.error = .generic
        }
        return nil
    }

    func archive() async -> Bool {
        guard case .edit(let habit) = mode else { return false }
        do {
            try await service.archive(id: habit.id)
            isArchived = true
            return true
        } catch {
            self.error = .generic
            return false
        }
    }

    func resume() async -> Bool {
        guard case .edit(let habit) = mode else { return false }
        do {
            try await service.resume(id: habit.id, weekdays: effectiveWeekdays)
            isArchived = false
            return true
        } catch HabitServiceError.validation(.activeLimitReached) {
            error = .limit
        } catch {
            self.error = .generic
        }
        return false
    }

    /// Permanent delete after the two-step confirmation (docs/02 §2).
    func delete() async -> Bool {
        guard case .edit(let habit) = mode else { return false }
        do {
            try await service.deleteHabit(id: habit.id)
            return true
        } catch {
            self.error = .generic
            return false
        }
    }
}
