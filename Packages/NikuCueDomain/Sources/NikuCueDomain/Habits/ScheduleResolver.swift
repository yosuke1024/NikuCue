import Foundation

/// Answers "was/is this habit scheduled on day X?" from the version history (docs/02 §2, docs/06 §3).
public enum ScheduleResolver {
    /// The version in force on `day`: the latest version whose `effectiveFromDayKey <= day`.
    public static func version(for habitId: UUID, on day: DayKey, in versions: [HabitScheduleVersion]) -> HabitScheduleVersion? {
        versions
            .filter { $0.habitId == habitId && $0.effectiveFromDayKey <= day }
            .max { a, b in
                if a.effectiveFromDayKey != b.effectiveFromDayKey { return a.effectiveFromDayKey < b.effectiveFromDayKey }
                return a.id.uuidString < b.id.uuidString
            }
    }

    /// The latest version overall (may be a version taking effect tomorrow).
    public static func latestVersion(for habitId: UUID, in versions: [HabitScheduleVersion]) -> HabitScheduleVersion? {
        versions.filter { $0.habitId == habitId }.max { a, b in
            if a.effectiveFromDayKey != b.effectiveFromDayKey { return a.effectiveFromDayKey < b.effectiveFromDayKey }
            return a.id.uuidString < b.id.uuidString
        }
    }

    public static func isActive(habitId: UUID, on day: DayKey, versions: [HabitScheduleVersion]) -> Bool {
        version(for: habitId, on: day, in: versions)?.isActive ?? false
    }

    public static func isScheduled(habit: Habit, on day: DayKey, versions: [HabitScheduleVersion], calendar: CalendarService) -> Bool {
        guard day >= habit.startDayKey,
              let v = version(for: habit.id, on: day, in: versions), v.isActive else { return false }
        return v.weekdays.contains(isoWeekday: calendar.isoWeekday(of: day))
    }

    /// Habits scheduled on `day`, in sort order.
    public static func scheduledHabits(on day: DayKey, habits: [Habit], versions: [HabitScheduleVersion], calendar: CalendarService) -> [Habit] {
        habits
            .filter { isScheduled(habit: $0, on: day, versions: versions, calendar: calendar) }
            .sorted { ($0.sortOrder, $0.createdAtUTC) < ($1.sortOrder, $1.createdAtUTC) }
    }

    /// Habits counted against the 5-active limit on `day` (active version in force, or becoming active later).
    public static func activeHabits(on day: DayKey, habits: [Habit], versions: [HabitScheduleVersion]) -> [Habit] {
        habits.filter { habit in
            if let current = version(for: habit.id, on: day, in: versions) { return current.isActive }
            // No version yet in force: a habit created today has effectiveFrom == today, so this only
            // happens for versions scheduled strictly in the future; count them as active (slot is taken).
            return latestVersion(for: habit.id, in: versions)?.isActive ?? false
        }
    }

    /// Next day on/after `from` on which the habit is scheduled, searching up to `limitDays` days.
    public static func nextScheduledDay(habit: Habit, from: DayKey, versions: [HabitScheduleVersion], calendar: CalendarService, limitDays: Int = 14) -> DayKey? {
        var cursor = from
        for _ in 0..<limitDays {
            if isScheduled(habit: habit, on: cursor, versions: versions, calendar: calendar) { return cursor }
            cursor = calendar.dayKey(byAdding: 1, to: cursor)
        }
        return nil
    }
}
