import Foundation

public struct HomeHabitRow: Identifiable, Hashable, Sendable {
    public let habit: Habit
    public let status: DayStatus
    public let record: HabitDayRecord?
    public var id: UUID { habit.id }

    public init(habit: Habit, status: DayStatus, record: HabitDayRecord?) {
        self.habit = habit
        self.status = status
        self.record = record
    }
}

/// Everything Home needs for one day.
public struct HomeSnapshot: Hashable, Sendable {
    public let dayKey: DayKey
    public let rows: [HomeHabitRow]
    public let activeHabits: [Habit]
    public let archivedHabits: [Habit]
    public let progress: DayProgress
    public let distinctDoneDays: Int
    public let companion: CompanionProfile
    public let reactionSnapshot: ReactionSnapshot

    public init(dayKey: DayKey, rows: [HomeHabitRow], activeHabits: [Habit], archivedHabits: [Habit], progress: DayProgress,
                distinctDoneDays: Int, companion: CompanionProfile, reactionSnapshot: ReactionSnapshot) {
        self.dayKey = dayKey
        self.rows = rows
        self.activeHabits = activeHabits
        self.archivedHabits = archivedHabits
        self.progress = progress
        self.distinctDoneDays = distinctDoneDays
        self.companion = companion
        self.reactionSnapshot = reactionSnapshot
    }

    /// True when the five-active-habit limit is reached today (a slot may free up tomorrow).
    public var isAtActiveLimit: Bool { activeHabits.count >= HabitValidation.maxActiveHabits }
}

/// One day as shown in History.
public struct DaySummary: Hashable, Sendable {
    public let dayKey: DayKey
    public let rows: [HomeHabitRow]
    public let progress: DayProgress
    public let isEditable: Bool

    public init(dayKey: DayKey, rows: [HomeHabitRow], progress: DayProgress, isEditable: Bool) {
        self.dayKey = dayKey
        self.rows = rows
        self.progress = progress
        self.isEditable = isEditable
    }
}

/// Shape of a calendar cell (docs/03 §4): distinguished by kind, never by colour alone.
public enum DayKind: String, Sendable, Equatable {
    case hasDone, restOnly, unrecorded, notScheduled, future
}

public struct WriteOutcome: Sendable, Equatable {
    public let write: StatusWriteResult
    public let progress: DayProgress
    public let distinctDoneDays: Int
    /// The event to hand to the reaction engine, if the write produced one. History corrections
    /// produce `.historyCorrected`, which yields no reaction.
    public let event: CatEvent?
    public let snapshot: ReactionSnapshot

    public init(write: StatusWriteResult, progress: DayProgress, distinctDoneDays: Int, event: CatEvent?, snapshot: ReactionSnapshot) {
        self.write = write
        self.progress = progress
        self.distinctDoneDays = distinctDoneDays
        self.event = event
        self.snapshot = snapshot
    }
}

public enum HabitServiceError: Error, Equatable, Sendable {
    case validation(HabitValidationError)
    case notScheduled
    case outsideEditableWindow
    case futureDay
    case notFound
    case duplicateReminder
    case backup(BackupValidationError)
    case repository(RepositoryError)
    case unknown(String)
}

/// Orchestrates validation → serialized idempotent save → aggregation → cat event (docs/02 §3).
/// All writes go through here; the UI never talks to the repository directly.
public actor HabitService {
    private let repository: any HabitRepository
    private let clock: any Clock

    public init(repository: any HabitRepository, clock: any Clock) {
        self.repository = repository
        self.clock = clock
    }

    public var calendar: CalendarService { CalendarService(timeZone: clock.timeZone) }
    public func today() -> DayKey { calendar.dayKey(for: clock.now) }
    public func now() -> Date { clock.now }

    // MARK: Reads

    public func homeSnapshot() async throws -> HomeSnapshot {
        try await wrap {
            let day = self.today()
            let cal = self.calendar
            let habits = try await self.repository.habits()
            let versions = try await self.repository.scheduleVersions()
            let records = try await self.repository.allRecords()
            let companion = try await self.repository.companionProfile()
            let scheduled = ScheduleResolver.scheduledHabits(on: day, habits: habits, versions: versions, calendar: cal)
            let rows = scheduled.map { habit -> HomeHabitRow in
                let record = records.first { $0.habitId == habit.id && $0.dayKey == day }
                let status = ProgressCalculator.status(of: habit, on: day, versions: versions, records: records, calendar: cal)
                return HomeHabitRow(habit: habit, status: status, record: record)
            }
            let active = ScheduleResolver.activeHabits(on: day, habits: habits, versions: versions)
            let archived = habits.filter { h in !active.contains(where: { $0.id == h.id }) }
            let progress = ProgressCalculator.progress(on: day, habits: habits, versions: versions, records: records, calendar: cal)
            let distinct = ProgressCalculator.distinctDoneDays(records: records)
            let snapshot = ReactionSnapshot(dayKey: day, progress: progress, distinctDoneDays: distinct,
                                            seenMilestones: companion.seenMilestones,
                                            allDoneShownToday: companion.allDoneShownDayKeys.contains(day),
                                            greetedToday: companion.lastHomeDayKey == day)
            return HomeSnapshot(dayKey: day, rows: rows, activeHabits: active, archivedHabits: archived, progress: progress,
                                distinctDoneDays: distinct, companion: companion, reactionSnapshot: snapshot)
        }
    }

    public func daySummary(_ day: DayKey) async throws -> DaySummary {
        try await wrap {
            let cal = self.calendar
            let today = self.today()
            let habits = try await self.repository.habits()
            let versions = try await self.repository.scheduleVersions()
            let records = try await self.repository.records(from: day, to: day)
            let scheduled = ScheduleResolver.scheduledHabits(on: day, habits: habits, versions: versions, calendar: cal)
            let rows = scheduled.map { habit -> HomeHabitRow in
                let record = records.first { $0.habitId == habit.id }
                let status: DayStatus = record.map { $0.status == .done ? .done : .skipped } ?? .pending
                return HomeHabitRow(habit: habit, status: status, record: record)
            }
            let progress = ProgressCalculator.progress(on: day, habits: habits, versions: versions, records: records, calendar: cal)
            return DaySummary(dayKey: day, rows: rows, progress: progress,
                              isEditable: day <= today && ProgressCalculator.isEditable(day: day, today: today, calendar: cal))
        }
    }

    /// Calendar cells for one month.
    public func monthKinds(year: Int, month: Int) async throws -> [DayKey: DayKind] {
        try await wrap {
            let cal = self.calendar
            let today = self.today()
            guard let first = DayKey(year: year, month: month, day: 1),
                  let last = DayKey(year: year, month: month, day: DayKey.daysInMonth(year: year, month: month)) else { return [:] }
            let habits = try await self.repository.habits()
            let versions = try await self.repository.scheduleVersions()
            let records = try await self.repository.records(from: first, to: last)
            var result: [DayKey: DayKind] = [:]
            for day in cal.dayKeys(from: first, through: last) {
                if day > today { result[day] = .future; continue }
                let progress = ProgressCalculator.progress(on: day, habits: habits, versions: versions, records: records, calendar: cal)
                if !progress.hasSchedule { result[day] = .notScheduled }
                else if progress.done > 0 { result[day] = .hasDone }
                else if progress.skipped > 0 { result[day] = .restOnly }
                else { result[day] = .unrecorded }
            }
            return result
        }
    }

    public func distinctDoneDays() async throws -> Int {
        try await wrap { ProgressCalculator.distinctDoneDays(records: try await self.repository.allRecords()) }
    }

    // MARK: Habit CRUD

    public func createHabit(name: String, category: HabitCategory, weekdays: WeekdaySet) async throws -> Habit {
        let cleanName = try validatedName(name)
        if case .failure(let e) = HabitValidation.validateWeekdays(weekdays) { throw HabitServiceError.validation(e) }
        return try await wrap {
            let day = self.today()
            let habits = try await self.repository.habits()
            let versions = try await self.repository.scheduleVersions()
            let active = ScheduleResolver.activeHabits(on: day, habits: habits, versions: versions)
            guard active.count < HabitValidation.maxActiveHabits else {
                throw HabitServiceError.validation(.activeLimitReached(max: HabitValidation.maxActiveHabits))
            }
            let order = (habits.map(\.sortOrder).max() ?? -1) + 1
            let habit = Habit(name: cleanName, category: category, sortOrder: order, createdAtUTC: self.clock.now, startDayKey: day)
            let version = HabitScheduleVersion(habitId: habit.id, effectiveFromDayKey: day, isActive: true, weekdays: weekdays)
            try await self.repository.createHabit(habit, schedule: version)
            return habit
        }
    }

    /// Name and category changes apply immediately; history shows the current name (docs/02 §2).
    public func updateHabit(id: UUID, name: String, category: HabitCategory) async throws {
        let cleanName = try validatedName(name)
        try await wrap {
            guard var habit = try await self.repository.habits().first(where: { $0.id == id }) else { throw HabitServiceError.notFound }
            habit.name = cleanName
            habit.category = category
            try await self.repository.updateHabit(habit)
        }
    }

    /// Weekday changes take effect tomorrow; today's schedule is never rewritten.
    public func changeWeekdays(id: UUID, weekdays: WeekdaySet) async throws {
        if case .failure(let e) = HabitValidation.validateWeekdays(weekdays) { throw HabitServiceError.validation(e) }
        try await wrap {
            let tomorrow = self.calendar.dayKey(byAdding: 1, to: self.today())
            let versions = try await self.repository.scheduleVersions()
            guard let current = ScheduleResolver.latestVersion(for: id, in: versions) else { throw HabitServiceError.notFound }
            let version = HabitScheduleVersion(habitId: id, effectiveFromDayKey: tomorrow, isActive: current.isActive, weekdays: weekdays)
            try await self.repository.upsertScheduleVersion(version)
        }
    }

    /// Hides the habit from tomorrow. Today stays due and can be finished with "Rest today".
    public func archive(id: UUID) async throws {
        try await wrap {
            let tomorrow = self.calendar.dayKey(byAdding: 1, to: self.today())
            let versions = try await self.repository.scheduleVersions()
            guard let current = ScheduleResolver.latestVersion(for: id, in: versions) else { throw HabitServiceError.notFound }
            let version = HabitScheduleVersion(habitId: id, effectiveFromDayKey: tomorrow, isActive: false, weekdays: current.weekdays)
            try await self.repository.upsertScheduleVersion(version)
        }
    }

    /// Re-activates from tomorrow with the given weekdays. The archived period never becomes "missed".
    public func resume(id: UUID, weekdays: WeekdaySet) async throws {
        if case .failure(let e) = HabitValidation.validateWeekdays(weekdays) { throw HabitServiceError.validation(e) }
        try await wrap {
            let tomorrow = self.calendar.dayKey(byAdding: 1, to: self.today())
            let habits = try await self.repository.habits()
            let versions = try await self.repository.scheduleVersions()
            guard habits.contains(where: { $0.id == id }) else { throw HabitServiceError.notFound }
            let activeTomorrow = ScheduleResolver.activeHabits(on: tomorrow, habits: habits, versions: versions).filter { $0.id != id }
            guard activeTomorrow.count < HabitValidation.maxActiveHabits else {
                throw HabitServiceError.validation(.activeLimitReached(max: HabitValidation.maxActiveHabits))
            }
            let version = HabitScheduleVersion(habitId: id, effectiveFromDayKey: tomorrow, isActive: true, weekdays: weekdays)
            try await self.repository.upsertScheduleVersion(version)
        }
    }

    public func reorder(ids: [UUID]) async throws {
        try await wrap { try await self.repository.reorderHabits(ids: ids) }
    }

    public func deleteHabit(id: UUID) async throws {
        try await wrap { try await self.repository.deleteHabit(id: id) }
    }

    // MARK: Records

    public func markDone(habitId: UUID) async throws -> WriteOutcome { try await setStatus(habitId: habitId, day: today(), desired: .done) }
    public func markSkipped(habitId: UUID) async throws -> WriteOutcome { try await setStatus(habitId: habitId, day: today(), desired: .skipped) }
    public func undo(habitId: UUID) async throws -> WriteOutcome { try await setStatus(habitId: habitId, day: today(), desired: .clear) }

    /// Writes one status. Pressing Done repeatedly never creates a second record or a second event.
    public func setStatus(habitId: UUID, day: DayKey, desired: DesiredStatus) async throws -> WriteOutcome {
        try await wrap {
            let cal = self.calendar
            let today = self.today()
            guard day <= today else { throw HabitServiceError.futureDay }
            guard ProgressCalculator.isEditable(day: day, today: today, calendar: cal) else { throw HabitServiceError.outsideEditableWindow }
            let habits = try await self.repository.habits()
            let versions = try await self.repository.scheduleVersions()
            guard let habit = habits.first(where: { $0.id == habitId }) else { throw HabitServiceError.notFound }
            guard ScheduleResolver.isScheduled(habit: habit, on: day, versions: versions, calendar: cal) else {
                throw HabitServiceError.notScheduled
            }
            let write = try await self.repository.setStatus(habitId: habitId, dayKey: day, desired: desired,
                                                            recordedAt: self.clock.now, timeZoneID: self.clock.timeZone.identifier,
                                                            expectedRevision: nil)
            let records = try await self.repository.allRecords()
            let progressToday = ProgressCalculator.progress(on: today, habits: habits, versions: versions, records: records, calendar: cal)
            let progressDay = day == today ? progressToday
                : ProgressCalculator.progress(on: day, habits: habits, versions: versions, records: records, calendar: cal)
            let distinct = ProgressCalculator.distinctDoneDays(records: records)
            var companion = try await self.repository.companionProfile()

            var event: CatEvent?
            if day == today {
                if write.newlyCompleted {
                    event = CatEvent(kind: .completionCommitted, occurredAt: self.clock.now, dayKey: day, habitId: habitId,
                                     category: habit.category, revision: write.revision)
                } else if write.newlySkipped {
                    event = CatEvent(kind: .skipCommitted, occurredAt: self.clock.now, dayKey: day, habitId: habitId,
                                     category: habit.category, revision: write.revision)
                } else if write.changed, desired == .clear, write.previousStatus == .done {
                    event = CatEvent(kind: .completionUndone, occurredAt: self.clock.now, dayKey: day, habitId: habitId,
                                     category: habit.category, revision: write.revision)
                }
            } else if write.changed {
                event = CatEvent(kind: .historyCorrected, occurredAt: self.clock.now, dayKey: day, habitId: habitId,
                                 category: habit.category, revision: write.revision)
                // A milestone reached through a correction is recorded quietly, never replayed (docs/05 §4).
                if let reached = Milestones.newlyReached(distinctDoneDays: distinct, seen: companion.seenMilestones) {
                    for t in Milestones.thresholds where t <= reached { companion.seenMilestones.insert(t) }
                    try await self.repository.saveCompanionProfile(companion)
                }
            }
            let snapshot = ReactionSnapshot(dayKey: today, progress: progressToday, distinctDoneDays: distinct,
                                            seenMilestones: companion.seenMilestones,
                                            allDoneShownToday: companion.allDoneShownDayKeys.contains(today),
                                            greetedToday: companion.lastHomeDayKey == today)
            return WriteOutcome(write: write, progress: progressDay, distinctDoneDays: distinct, event: event, snapshot: snapshot)
        }
    }

    // MARK: Companion

    /// Called on the first Home display of a foreground session. Decides greeting vs welcome-back
    /// (3+ days since the last Home day) and records today as the last Home day.
    public func sceneEntered() async throws -> (event: CatEvent, snapshot: ReactionSnapshot) {
        try await wrap {
            let day = self.today()
            var companion = try await self.repository.companionProfile()
            let greetedToday = companion.lastHomeDayKey == day
            var kind: CatEventKind = .sceneEntered
            if let last = companion.lastHomeDayKey, last < day, self.calendar.days(from: last, to: day) >= 3 {
                kind = .welcomeBack
            }
            if companion.lastHomeDayKey != day {
                companion.lastHomeDayKey = day
                if companion.firstOpenedAtUTC == nil { companion.firstOpenedAtUTC = self.clock.now }
                try await self.repository.saveCompanionProfile(companion)
            }
            let records = try await self.repository.allRecords()
            let habits = try await self.repository.habits()
            let versions = try await self.repository.scheduleVersions()
            let progress = ProgressCalculator.progress(on: day, habits: habits, versions: versions, records: records, calendar: self.calendar)
            let snapshot = ReactionSnapshot(dayKey: day, progress: progress,
                                            distinctDoneDays: ProgressCalculator.distinctDoneDays(records: records),
                                            seenMilestones: companion.seenMilestones,
                                            allDoneShownToday: companion.allDoneShownDayKeys.contains(day),
                                            greetedToday: greetedToday)
            return (CatEvent(kind: kind, occurredAt: self.clock.now, dayKey: day), snapshot)
        }
    }

    /// Records that a milestone / all-done celebration actually started (docs/05 §4).
    public func markShown(milestone: Int?, allDoneDay: DayKey?) async throws {
        guard milestone != nil || allDoneDay != nil else { return }
        try await wrap {
            var companion = try await self.repository.companionProfile()
            if let m = milestone { companion.seenMilestones.insert(m) }
            if let d = allDoneDay { companion.allDoneShownDayKeys.insert(d) }
            try await self.repository.saveCompanionProfile(companion)
        }
    }

    /// `nil` or blank restores the default localized name.
    public func setNickname(_ raw: String?) async throws {
        var companion = try await wrap { try await self.repository.companionProfile() }
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch HabitValidation.validateNickname(raw) {
            case .success(let n):
                companion.nickname = n
                companion.didCustomizeName = true
            case .failure(let e):
                throw HabitServiceError.validation(e)
            }
        } else {
            companion.nickname = nil
            companion.didCustomizeName = false
        }
        let final = companion
        try await wrap { try await self.repository.saveCompanionProfile(final) }
    }

    public func companionProfile() async throws -> CompanionProfile { try await wrap { try await self.repository.companionProfile() } }
    public func preferences() async throws -> UserPreferences { try await wrap { try await self.repository.preferences() } }
    public func savePreferences(_ p: UserPreferences) async throws { try await wrap { try await self.repository.savePreferences(p) } }
    public func reminderSlots() async throws -> [ReminderSlot] { try await wrap { try await self.repository.reminderSlots() } }

    public func saveReminderSlots(_ slots: [ReminderSlot]) async throws {
        guard slots.count <= ReminderPlanner.maxSlots else { throw HabitServiceError.validation(.noWeekdays) }
        guard slots.allSatisfy(\.isValid) else { throw HabitServiceError.validation(.noWeekdays) }
        guard !ReminderPlanner.hasDuplicate(slots) else { throw HabitServiceError.duplicateReminder }
        try await wrap { try await self.repository.saveReminderSlots(slots) }
    }

    // MARK: Backup / reset

    public func exportBackup(appVersion: String) async throws -> BackupDocument {
        try await wrap { try await self.repository.exportDocument(appVersion: appVersion, now: self.clock.now) }
    }

    /// Validates first; the repository replaces everything atomically or not at all.
    @discardableResult
    public func importBackup(data: Data) async throws -> BackupDocument {
        switch BackupValidator.validate(data: data) {
        case .failure(let e):
            throw HabitServiceError.backup(e)
        case .success(let doc):
            try await wrap { try await self.repository.replaceAll(with: doc) }
            return doc
        }
    }

    public func deleteAllUserData() async throws {
        try await wrap { try await self.repository.deleteAllUserData() }
    }

    // MARK: Helpers

    private func validatedName(_ raw: String) throws -> String {
        switch HabitValidation.validateName(raw) {
        case .success(let n): return n
        case .failure(let e): throw HabitServiceError.validation(e)
        }
    }

    private func wrap<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let e as HabitServiceError {
            throw e
        } catch let e as RepositoryError {
            throw HabitServiceError.repository(e)
        } catch {
            throw HabitServiceError.unknown(String(describing: error))
        }
    }
}
