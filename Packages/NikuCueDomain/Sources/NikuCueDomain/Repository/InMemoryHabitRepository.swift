import Foundation

/// Reference implementation used by tests, previews and the no-write demo. Mirrors the semantics the
/// SwiftData repository must provide (serialized writes, idempotent upsert, atomic replace).
public actor InMemoryHabitRepository: HabitRepository {
    private var habitList: [Habit] = []
    private var versionList: [HabitScheduleVersion] = []
    private var recordMap: [String: HabitDayRecord] = [:]
    private var companion = CompanionProfile()
    private var prefs = UserPreferences()
    private var slots: [ReminderSlot] = []

    /// When set, the next write throws `persistenceFailed` and leaves state untouched (QA Q03/Q39).
    public var failNextWrite = false

    public init() {}

    public func setFailNextWrite(_ value: Bool) { failNextWrite = value }

    private func checkFailure() throws {
        if failNextWrite {
            failNextWrite = false
            throw RepositoryError.persistenceFailed("injected failure")
        }
    }

    public func habits() async throws -> [Habit] { habitList.sorted { ($0.sortOrder, $0.createdAtUTC) < ($1.sortOrder, $1.createdAtUTC) } }
    public func scheduleVersions() async throws -> [HabitScheduleVersion] { versionList }
    public func records(from: DayKey, to: DayKey) async throws -> [HabitDayRecord] {
        recordMap.values.filter { $0.dayKey >= from && $0.dayKey <= to }.sorted { $0.recordKey < $1.recordKey }
    }
    public func allRecords() async throws -> [HabitDayRecord] { recordMap.values.sorted { $0.recordKey < $1.recordKey } }

    public func createHabit(_ habit: Habit, schedule: HabitScheduleVersion) async throws {
        try checkFailure()
        guard !habitList.contains(where: { $0.id == habit.id }) else { throw RepositoryError.invalidData("duplicate habit id") }
        guard schedule.habitId == habit.id else { throw RepositoryError.invalidData("schedule habit mismatch") }
        habitList.append(habit)
        versionList.append(schedule)
    }

    public func updateHabit(_ habit: Habit) async throws {
        try checkFailure()
        guard let index = habitList.firstIndex(where: { $0.id == habit.id }) else { throw RepositoryError.notFound }
        habitList[index] = habit
    }

    public func upsertScheduleVersion(_ version: HabitScheduleVersion) async throws {
        try checkFailure()
        guard habitList.contains(where: { $0.id == version.habitId }) else { throw RepositoryError.notFound }
        if let index = versionList.firstIndex(where: { $0.habitId == version.habitId && $0.effectiveFromDayKey == version.effectiveFromDayKey }) {
            versionList[index] = version
        } else {
            versionList.append(version)
        }
    }

    public func reorderHabits(ids: [UUID]) async throws {
        try checkFailure()
        for (order, id) in ids.enumerated() {
            if let index = habitList.firstIndex(where: { $0.id == id }) { habitList[index].sortOrder = order }
        }
    }

    public func deleteHabit(id: UUID) async throws {
        try checkFailure()
        guard habitList.contains(where: { $0.id == id }) else { throw RepositoryError.notFound }
        habitList.removeAll { $0.id == id }
        versionList.removeAll { $0.habitId == id }
        recordMap = recordMap.filter { $0.value.habitId != id }
    }

    public func setStatus(habitId: UUID, dayKey: DayKey, desired: DesiredStatus, recordedAt: Date,
                          timeZoneID: String, expectedRevision: Int?) async throws -> StatusWriteResult {
        try checkFailure()
        guard habitList.contains(where: { $0.id == habitId }) else { throw RepositoryError.notFound }
        let key = HabitDayRecord.recordKey(habitId: habitId, dayKey: dayKey)
        let existing = recordMap[key]
        if let expected = expectedRevision, let current = existing, current.revision != expected {
            throw RepositoryError.revisionConflict(expected: expected, actual: current.revision)
        }
        return InMemoryHabitRepository.apply(desired: desired, to: existing, habitId: habitId, dayKey: dayKey,
                                             recordedAt: recordedAt, timeZoneID: timeZoneID) { updated in
            if let updated { recordMap[key] = updated } else { recordMap.removeValue(forKey: key) }
        }
    }

    /// Shared upsert semantics so the SwiftData implementation can reuse the exact decision table.
    public static func apply(desired: DesiredStatus, to existing: HabitDayRecord?, habitId: UUID, dayKey: DayKey,
                             recordedAt: Date, timeZoneID: String, store: (HabitDayRecord?) -> Void) -> StatusWriteResult {
        let previous = existing?.status
        switch desired {
        case .clear:
            guard existing != nil else {
                return StatusWriteResult(record: nil, previousStatus: nil, changed: false, newlyCompleted: false, newlySkipped: false, revision: 0)
            }
            store(nil)
            // No record remains, so there is no revision to report; a later write starts again at 1.
            return StatusWriteResult(record: nil, previousStatus: previous, changed: true, newlyCompleted: false, newlySkipped: false, revision: 0)
        case .done, .skipped:
            let target: RecordStatus = desired == .done ? .done : .skipped
            if let existing, existing.status == target {
                return StatusWriteResult(record: existing, previousStatus: previous, changed: false, newlyCompleted: false,
                                         newlySkipped: false, revision: existing.revision)
            }
            let record = HabitDayRecord(habitId: habitId, dayKey: dayKey, status: target, recordedAtUTC: recordedAt,
                                        timeZoneID: timeZoneID, revision: (existing?.revision ?? 0) + 1)
            store(record)
            return StatusWriteResult(record: record, previousStatus: previous, changed: true,
                                     newlyCompleted: target == .done, newlySkipped: target == .skipped, revision: record.revision)
        }
    }

    public func companionProfile() async throws -> CompanionProfile { companion }
    public func saveCompanionProfile(_ profile: CompanionProfile) async throws { try checkFailure(); companion = profile }
    public func preferences() async throws -> UserPreferences { prefs }
    public func savePreferences(_ preferences: UserPreferences) async throws { try checkFailure(); prefs = preferences }
    public func reminderSlots() async throws -> [ReminderSlot] { slots }
    public func saveReminderSlots(_ newSlots: [ReminderSlot]) async throws { try checkFailure(); slots = newSlots }

    public func replaceAll(with document: BackupDocument) async throws {
        try checkFailure()
        let normalized = document.normalizedForImport()
        habitList = normalized.habits
        versionList = normalized.scheduleVersions
        recordMap = Dictionary(uniqueKeysWithValues: normalized.records.map { ($0.recordKey, $0) })
        companion = normalized.companion
        prefs = normalized.preferences
        slots = normalized.reminderSlots
    }

    public func deleteAllUserData() async throws {
        try checkFailure()
        habitList = []
        versionList = []
        recordMap = [:]
        companion = CompanionProfile()
        prefs = UserPreferences()
        slots = []
    }
}
