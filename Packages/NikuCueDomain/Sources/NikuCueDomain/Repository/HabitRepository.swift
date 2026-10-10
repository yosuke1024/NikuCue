import Foundation

public enum DesiredStatus: String, Sendable, Equatable {
    case done, skipped, clear
}

/// Result of one idempotent status write (docs/06 §4).
public struct StatusWriteResult: Equatable, Sendable {
    public let record: HabitDayRecord?
    public let previousStatus: RecordStatus?
    /// Something was actually written (done→done is `false`).
    public let changed: Bool
    /// The record became `done` with this write (never true for done→done).
    public let newlyCompleted: Bool
    /// The record became `skipped` with this write.
    public let newlySkipped: Bool
    public let revision: Int

    public init(record: HabitDayRecord?, previousStatus: RecordStatus?, changed: Bool, newlyCompleted: Bool, newlySkipped: Bool, revision: Int) {
        self.record = record
        self.previousStatus = previousStatus
        self.changed = changed
        self.newlyCompleted = newlyCompleted
        self.newlySkipped = newlySkipped
        self.revision = revision
    }
}

public enum RepositoryError: Error, Equatable, Sendable {
    case persistenceFailed(String)
    case notFound
    case revisionConflict(expected: Int, actual: Int)
    case invalidData(String)
}

/// Everything persisted on device. Implementations serialize writes in one actor and keep
/// `habitId:dayKey` unique without relying on the store's unique attribute alone.
public protocol HabitRepository: Sendable {
    func habits() async throws -> [Habit]
    func scheduleVersions() async throws -> [HabitScheduleVersion]
    func records(from: DayKey, to: DayKey) async throws -> [HabitDayRecord]
    func allRecords() async throws -> [HabitDayRecord]

    func createHabit(_ habit: Habit, schedule: HabitScheduleVersion) async throws
    func updateHabit(_ habit: Habit) async throws
    /// Inserts a version, or replaces the existing version with the same habitId + effectiveFromDayKey.
    func upsertScheduleVersion(_ version: HabitScheduleVersion) async throws
    func reorderHabits(ids: [UUID]) async throws
    /// Removes the habit, its versions and its records.
    func deleteHabit(id: UUID) async throws

    /// Idempotent upsert. `expectedRevision` (when given) must match the stored revision or the
    /// write fails with `revisionConflict`. `.clear` removes the record.
    func setStatus(habitId: UUID, dayKey: DayKey, desired: DesiredStatus, recordedAt: Date,
                   timeZoneID: String, expectedRevision: Int?) async throws -> StatusWriteResult

    func companionProfile() async throws -> CompanionProfile
    func saveCompanionProfile(_ profile: CompanionProfile) async throws
    func preferences() async throws -> UserPreferences
    func savePreferences(_ preferences: UserPreferences) async throws
    func reminderSlots() async throws -> [ReminderSlot]
    func saveReminderSlots(_ slots: [ReminderSlot]) async throws

    /// Atomically replaces every user record with the (already validated) document. On failure the
    /// previous data set stays intact.
    func replaceAll(with document: BackupDocument) async throws
    /// Deletes habits, versions, records, companion profile, preferences and reminder slots.
    /// Purchase entitlements are not stored here and therefore survive (docs/02 §8).
    func deleteAllUserData() async throws
}

public extension HabitRepository {
    func exportDocument(appVersion: String, now: Date) async throws -> BackupDocument {
        BackupDocument(appVersion: appVersion, exportedAtUTC: now, habits: try await habits(),
                       scheduleVersions: try await scheduleVersions(), records: try await allRecords(),
                       companion: try await companionProfile(), preferences: try await preferences(),
                       reminderSlots: try await reminderSlots())
    }
}
