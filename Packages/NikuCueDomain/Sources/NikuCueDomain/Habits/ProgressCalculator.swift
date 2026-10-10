import Foundation

/// Today's counts, with `skipped` kept apart from `done` (docs/02 §4).
public struct DayProgress: Hashable, Sendable {
    public let scheduled: Int
    public let done: Int
    public let skipped: Int

    public init(scheduled: Int, done: Int, skipped: Int) {
        self.scheduled = scheduled
        self.done = done
        self.skipped = skipped
    }

    public static let empty = DayProgress(scheduled: 0, done: 0, skipped: 0)

    public var pending: Int { max(0, scheduled - done - skipped) }
    public var hasSchedule: Bool { scheduled > 0 }
    /// Every scheduled habit is done (never true for an empty schedule).
    public var isAllDone: Bool { scheduled > 0 && done == scheduled }
    /// Every scheduled habit is done or skipped, at least one of each (docs/05 §4 rule 3).
    public var isAllResolved: Bool { scheduled > 0 && pending == 0 && skipped > 0 && done > 0 }
}

public enum Milestones {
    public static let thresholds: [Int] = [3, 7, 14]

    /// The single newly reached threshold, if any, that has not been shown yet.
    /// When several are unseen (e.g. after a restore), the highest reached one is returned.
    public static func newlyReached(distinctDoneDays: Int, seen: Set<Int>) -> Int? {
        thresholds.filter { distinctDoneDays >= $0 && !seen.contains($0) }.max()
    }
}

public enum ProgressCalculator {
    public static func status(of habit: Habit, on day: DayKey, versions: [HabitScheduleVersion],
                              records: [HabitDayRecord], calendar: CalendarService) -> DayStatus {
        guard ScheduleResolver.isScheduled(habit: habit, on: day, versions: versions, calendar: calendar) else {
            return .notScheduled
        }
        if let record = records.first(where: { $0.habitId == habit.id && $0.dayKey == day }) {
            return record.status == .done ? .done : .skipped
        }
        return .pending
    }

    public static func progress(on day: DayKey, habits: [Habit], versions: [HabitScheduleVersion],
                                records: [HabitDayRecord], calendar: CalendarService) -> DayProgress {
        let scheduled = ScheduleResolver.scheduledHabits(on: day, habits: habits, versions: versions, calendar: calendar)
        var done = 0, skipped = 0
        for habit in scheduled {
            if let record = records.first(where: { $0.habitId == habit.id && $0.dayKey == day }) {
                if record.status == .done { done += 1 } else { skipped += 1 }
            }
        }
        return DayProgress(scheduled: scheduled.count, done: done, skipped: skipped)
    }

    /// "Days with a little win": distinct day keys with at least one `done` record.
    /// Five completions on one day count once; skipped-only days count zero (docs/02 §4).
    public static func distinctDoneDays(records: [HabitDayRecord]) -> Int {
        Set(records.filter { $0.status == .done }.map(\.dayKey)).count
    }

    /// Inclusive range of days that may be edited: today and the six days before it (docs/02 §4).
    public static func editableWindow(today: DayKey, calendar: CalendarService) -> ClosedRange<DayKey> {
        calendar.dayKey(byAdding: -(HabitValidation.editableDays - 1), to: today)...today
    }

    public static func isEditable(day: DayKey, today: DayKey, calendar: CalendarService) -> Bool {
        editableWindow(today: today, calendar: calendar).contains(day)
    }
}
