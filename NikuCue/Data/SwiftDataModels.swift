import Foundation
import NikuCueDomain
import SwiftData

// SwiftData persistence models (docs/06 §3). Domain structs are the API; these classes are storage only.
// CloudKit is never configured (docs/06 §1, S03). Purchase entitlements are not stored here.

@Model
final class HabitModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRaw: String
    var sortOrder: Int
    var createdAtUTC: Date
    var startDayKey: String

    init(id: UUID, name: String, categoryRaw: String, sortOrder: Int, createdAtUTC: Date, startDayKey: String) {
        self.id = id
        self.name = name
        self.categoryRaw = categoryRaw
        self.sortOrder = sortOrder
        self.createdAtUTC = createdAtUTC
        self.startDayKey = startDayKey
    }

    convenience init(_ habit: Habit) {
        self.init(id: habit.id, name: habit.name, categoryRaw: habit.category.rawValue, sortOrder: habit.sortOrder,
                  createdAtUTC: habit.createdAtUTC, startDayKey: habit.startDayKey.string)
    }

    var domain: Habit? {
        guard let category = HabitCategory(rawValue: categoryRaw), let start = DayKey(string: startDayKey) else { return nil }
        return Habit(id: id, name: name, category: category, sortOrder: sortOrder, createdAtUTC: createdAtUTC, startDayKey: start)
    }
}

@Model
final class ScheduleVersionModel {
    @Attribute(.unique) var id: UUID
    var habitId: UUID
    var effectiveFromDayKey: String
    var isActive: Bool
    var weekdayMask: Int

    init(id: UUID, habitId: UUID, effectiveFromDayKey: String, isActive: Bool, weekdayMask: Int) {
        self.id = id
        self.habitId = habitId
        self.effectiveFromDayKey = effectiveFromDayKey
        self.isActive = isActive
        self.weekdayMask = weekdayMask
    }

    convenience init(_ v: HabitScheduleVersion) {
        self.init(id: v.id, habitId: v.habitId, effectiveFromDayKey: v.effectiveFromDayKey.string, isActive: v.isActive, weekdayMask: v.weekdays.mask)
    }

    var domain: HabitScheduleVersion? {
        guard let day = DayKey(string: effectiveFromDayKey) else { return nil }
        return HabitScheduleVersion(id: id, habitId: habitId, effectiveFromDayKey: day, isActive: isActive, weekdays: WeekdaySet(mask: weekdayMask))
    }
}

@Model
final class DayRecordModel {
    /// `habitId:dayKey` — unique in the store and additionally enforced by the repository's serialized upsert.
    @Attribute(.unique) var recordKey: String
    var habitId: UUID
    var dayKey: String
    var statusRaw: String
    var recordedAtUTC: Date
    var timeZoneID: String
    var revision: Int

    init(recordKey: String, habitId: UUID, dayKey: String, statusRaw: String, recordedAtUTC: Date, timeZoneID: String, revision: Int) {
        self.recordKey = recordKey
        self.habitId = habitId
        self.dayKey = dayKey
        self.statusRaw = statusRaw
        self.recordedAtUTC = recordedAtUTC
        self.timeZoneID = timeZoneID
        self.revision = revision
    }

    convenience init(_ r: HabitDayRecord) {
        self.init(recordKey: r.recordKey, habitId: r.habitId, dayKey: r.dayKey.string, statusRaw: r.status.rawValue,
                  recordedAtUTC: r.recordedAtUTC, timeZoneID: r.timeZoneID, revision: r.revision)
    }

    func update(from r: HabitDayRecord) {
        statusRaw = r.status.rawValue
        recordedAtUTC = r.recordedAtUTC
        timeZoneID = r.timeZoneID
        revision = r.revision
    }

    var domain: HabitDayRecord? {
        guard let day = DayKey(string: dayKey), let status = RecordStatus(rawValue: statusRaw) else { return nil }
        return HabitDayRecord(habitId: habitId, dayKey: day, status: status, recordedAtUTC: recordedAtUTC, timeZoneID: timeZoneID, revision: revision)
    }
}

/// Singleton rows (companion profile, preferences) are stored as one JSON blob each, keyed by name.
/// Codable Domain structs are the schema; adding a field keeps old rows readable through defaults.
@Model
final class SingletonBlobModel {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }

    static let companionKey = "companionProfile.v1"
    static let preferencesKey = "userPreferences.v1"
}

@Model
final class ReminderSlotModel {
    @Attribute(.unique) var id: UUID
    var enabled: Bool
    var hour: Int
    var minute: Int
    var weekdayMask: Int
    var sortOrder: Int

    init(id: UUID, enabled: Bool, hour: Int, minute: Int, weekdayMask: Int, sortOrder: Int) {
        self.id = id
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.weekdayMask = weekdayMask
        self.sortOrder = sortOrder
    }

    convenience init(_ s: ReminderSlot, sortOrder: Int) {
        self.init(id: s.id, enabled: s.enabled, hour: s.hour, minute: s.minute, weekdayMask: s.weekdays.mask, sortOrder: sortOrder)
    }

    var domain: ReminderSlot {
        ReminderSlot(id: id, enabled: enabled, hour: hour, minute: minute, weekdays: WeekdaySet(mask: weekdayMask))
    }
}

/// Current schema. Future versions add a `VersionedSchema` and a `SchemaMigrationPlan` here (docs/06 §3 MigrationPlan).
enum NikuCueSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [HabitModel.self, ScheduleVersionModel.self, DayRecordModel.self, SingletonBlobModel.self, ReminderSlotModel.self]
    }
}

enum NikuCueMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NikuCueSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum NikuCueStore {
    static let fileName = "NikuCue.store"

    /// Local-only container in Application Support. Never deletes an existing store on failure (docs/03 §6).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NikuCueSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("NikuCueInMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = support.appendingPathComponent(fileName)
            configuration = ModelConfiguration("NikuCue", schema: schema, url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: NikuCueMigrationPlan.self, configurations: [configuration])
    }
}
