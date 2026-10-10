import Foundation

/// Versioned, unencrypted JSON backup (`nikucue-backup-v1.json`, docs/02 §7).
///
/// Never contains purchase entitlements, ad consent, test flags, device identifiers or diagnostics.
/// Reminder slots are exported but always restored disabled.
public struct BackupDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let fileName = "nikucue-backup-v1.json"

    public var schemaVersion: Int
    public var appVersion: String
    public var exportedAtUTC: Date
    public var habits: [Habit]
    public var scheduleVersions: [HabitScheduleVersion]
    public var records: [HabitDayRecord]
    public var companion: CompanionProfile
    public var preferences: UserPreferences
    public var reminderSlots: [ReminderSlot]

    public init(schemaVersion: Int = BackupDocument.currentSchemaVersion, appVersion: String, exportedAtUTC: Date,
                habits: [Habit], scheduleVersions: [HabitScheduleVersion], records: [HabitDayRecord],
                companion: CompanionProfile, preferences: UserPreferences, reminderSlots: [ReminderSlot]) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAtUTC = exportedAtUTC
        self.habits = habits
        self.scheduleVersions = scheduleVersions
        self.records = records
        self.companion = companion
        self.preferences = preferences
        self.reminderSlots = reminderSlots
    }

    /// The exact top-level keys a v1 document may contain. Anything else (e.g. entitlement flags) is rejected.
    public static let allowedTopLevelKeys: Set<String> = [
        "schemaVersion", "appVersion", "exportedAtUTC", "habits", "scheduleVersions", "records",
        "companion", "preferences", "reminderSlots"
    ]

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func encoded() throws -> Data {
        try BackupDocument.encoder().encode(self)
    }

    /// Copy prepared for import: reminders off, first-session flag kept, onboarding considered finished.
    public func normalizedForImport() -> BackupDocument {
        var copy = self
        copy.reminderSlots = reminderSlots.map { slot in
            var s = slot
            s.enabled = false
            return s
        }
        copy.preferences.remindersEnabled = false
        return copy
    }
}
