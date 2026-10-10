import Foundation

public enum BackupValidationError: Error, Equatable, Sendable {
    case tooLarge(bytes: Int, max: Int)
    case malformedJSON
    case unsupportedSchemaVersion(Int)
    case unexpectedField(String)
    case tooManyItems(field: String, count: Int, max: Int)
    case invalidHabit(id: UUID, reason: String)
    case invalidScheduleVersion(id: UUID, reason: String)
    case invalidRecord(key: String, reason: String)
    case invalidCompanion(reason: String)
    case invalidReminder(reason: String)
    case duplicate(field: String, value: String)
    case danglingReference(field: String, id: UUID)
}

/// Validates a backup before anything touches the database (docs/02 §7, QA Q32/Q33).
public enum BackupValidator {
    public static let maxBytes = 5 * 1024 * 1024
    public static let maxHabits = 100
    public static let maxScheduleVersions = 5_000
    public static let maxRecords = 50_000
    public static let maxReminderSlots = ReminderPlanner.maxSlots

    public static func validate(data: Data) -> Result<BackupDocument, BackupValidationError> {
        guard data.count <= maxBytes else { return .failure(.tooLarge(bytes: data.count, max: maxBytes)) }

        // Top-level key check with a permissive parse first, so entitlement/consent fields are refused.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.malformedJSON)
        }
        for key in object.keys.sorted() where !BackupDocument.allowedTopLevelKeys.contains(key) {
            return .failure(.unexpectedField(key))
        }
        guard let version = object["schemaVersion"] as? Int else { return .failure(.malformedJSON) }
        guard version == BackupDocument.currentSchemaVersion else { return .failure(.unsupportedSchemaVersion(version)) }

        let document: BackupDocument
        do {
            document = try BackupDocument.decoder().decode(BackupDocument.self, from: data)
        } catch {
            return .failure(.malformedJSON)
        }
        return validate(document: document).map { _ in document.normalizedForImport() }
    }

    public static func validate(document d: BackupDocument) -> Result<Void, BackupValidationError> {
        guard d.schemaVersion == BackupDocument.currentSchemaVersion else {
            return .failure(.unsupportedSchemaVersion(d.schemaVersion))
        }
        if d.habits.count > maxHabits { return .failure(.tooManyItems(field: "habits", count: d.habits.count, max: maxHabits)) }
        if d.scheduleVersions.count > maxScheduleVersions {
            return .failure(.tooManyItems(field: "scheduleVersions", count: d.scheduleVersions.count, max: maxScheduleVersions))
        }
        if d.records.count > maxRecords { return .failure(.tooManyItems(field: "records", count: d.records.count, max: maxRecords)) }
        if d.reminderSlots.count > maxReminderSlots {
            return .failure(.tooManyItems(field: "reminderSlots", count: d.reminderSlots.count, max: maxReminderSlots))
        }

        var habitIds = Set<UUID>()
        for habit in d.habits {
            if !habitIds.insert(habit.id).inserted { return .failure(.duplicate(field: "habits.id", value: habit.id.uuidString)) }
            if case .failure = HabitValidation.validateName(habit.name) {
                return .failure(.invalidHabit(id: habit.id, reason: "name"))
            }
            if habit.name != habit.name.trimmingCharacters(in: .whitespacesAndNewlines) {
                return .failure(.invalidHabit(id: habit.id, reason: "name not trimmed"))
            }
        }

        var versionIds = Set<UUID>()
        var versionKeys = Set<String>()
        var habitsWithVersions = Set<UUID>()
        for v in d.scheduleVersions {
            if !versionIds.insert(v.id).inserted { return .failure(.duplicate(field: "scheduleVersions.id", value: v.id.uuidString)) }
            guard let habit = d.habits.first(where: { $0.id == v.habitId }) else {
                return .failure(.danglingReference(field: "scheduleVersions.habitId", id: v.habitId))
            }
            let key = "\(v.habitId.uuidString):\(v.effectiveFromDayKey.string)"
            if !versionKeys.insert(key).inserted { return .failure(.duplicate(field: "scheduleVersions.effectiveFromDayKey", value: key)) }
            if v.effectiveFromDayKey < habit.startDayKey {
                return .failure(.invalidScheduleVersion(id: v.id, reason: "effective before habit start"))
            }
            if v.isActive && v.weekdays.isEmpty {
                return .failure(.invalidScheduleVersion(id: v.id, reason: "active version without weekdays"))
            }
            habitsWithVersions.insert(v.habitId)
        }
        for habit in d.habits where !habitsWithVersions.contains(habit.id) {
            return .failure(.invalidHabit(id: habit.id, reason: "no schedule version"))
        }

        // Keys later than the export day (+1 for time zones ahead of UTC) cannot be genuine records.
        let latestAllowed = CalendarService(timeZone: TimeZone(identifier: "UTC")!).dayKey(byAdding: 1, to: CalendarService(timeZone: TimeZone(identifier: "UTC")!).dayKey(for: d.exportedAtUTC))
        var recordKeys = Set<String>()
        for r in d.records {
            if r.dayKey > latestAllowed { return .failure(.invalidRecord(key: r.recordKey, reason: "day after export")) }
            if !habitIds.contains(r.habitId) { return .failure(.danglingReference(field: "records.habitId", id: r.habitId)) }
            if !recordKeys.insert(r.recordKey).inserted { return .failure(.duplicate(field: "records.recordKey", value: r.recordKey)) }
            if r.timeZoneID.isEmpty { return .failure(.invalidRecord(key: r.recordKey, reason: "empty timeZoneID")) }
            if r.revision < 1 { return .failure(.invalidRecord(key: r.recordKey, reason: "revision < 1")) }
        }

        if let nickname = d.companion.nickname, case .failure = HabitValidation.validateNickname(nickname) {
            return .failure(.invalidCompanion(reason: "nickname"))
        }
        for m in d.companion.seenMilestones where !Milestones.thresholds.contains(m) {
            return .failure(.invalidCompanion(reason: "unknown milestone \(m)"))
        }

        var slotIds = Set<UUID>()
        for slot in d.reminderSlots {
            if !slotIds.insert(slot.id).inserted { return .failure(.duplicate(field: "reminderSlots.id", value: slot.id.uuidString)) }
            if !(0...23).contains(slot.hour) || !(0...59).contains(slot.minute) || slot.weekdays.isEmpty {
                return .failure(.invalidReminder(reason: "time or weekdays"))
            }
        }
        if ReminderPlanner.hasDuplicate(d.reminderSlots) { return .failure(.invalidReminder(reason: "duplicate")) }
        return .success(())
    }
}
