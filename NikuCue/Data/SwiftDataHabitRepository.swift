import Foundation
import NikuCueDomain
import SwiftData

/// SwiftData implementation of `HabitRepository`. All writes are serialized by the actor and saved in
/// one transaction; any error rolls the context back so the previous data set stays intact (docs/06 §4).
@ModelActor
actor SwiftDataHabitRepository: HabitRepository {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Reads

    func habits() async throws -> [Habit] {
        try fetchAll(HabitModel.self).compactMap(\.domain).sorted { ($0.sortOrder, $0.createdAtUTC) < ($1.sortOrder, $1.createdAtUTC) }
    }

    func scheduleVersions() async throws -> [HabitScheduleVersion] {
        try fetchAll(ScheduleVersionModel.self).compactMap(\.domain)
    }

    func records(from: DayKey, to: DayKey) async throws -> [HabitDayRecord] {
        let lower = from.string, upper = to.string
        let descriptor = FetchDescriptor<DayRecordModel>(predicate: #Predicate { $0.dayKey >= lower && $0.dayKey <= upper })
        return try modelContext.fetch(descriptor).compactMap(\.domain).sorted { $0.recordKey < $1.recordKey }
    }

    func allRecords() async throws -> [HabitDayRecord] {
        try fetchAll(DayRecordModel.self).compactMap(\.domain).sorted { $0.recordKey < $1.recordKey }
    }

    // MARK: Habit writes

    func createHabit(_ habit: Habit, schedule: HabitScheduleVersion) async throws {
        try write {
            guard try self.habitModel(id: habit.id) == nil else { throw RepositoryError.invalidData("duplicate habit id") }
            guard schedule.habitId == habit.id else { throw RepositoryError.invalidData("schedule habit mismatch") }
            self.modelContext.insert(HabitModel(habit))
            self.modelContext.insert(ScheduleVersionModel(schedule))
        }
    }

    func updateHabit(_ habit: Habit) async throws {
        try write {
            guard let model = try self.habitModel(id: habit.id) else { throw RepositoryError.notFound }
            model.name = habit.name
            model.categoryRaw = habit.category.rawValue
            model.sortOrder = habit.sortOrder
        }
    }

    func upsertScheduleVersion(_ version: HabitScheduleVersion) async throws {
        try write {
            guard try self.habitModel(id: version.habitId) != nil else { throw RepositoryError.notFound }
            let habitId = version.habitId
            let day = version.effectiveFromDayKey.string
            let existing = try self.modelContext.fetch(FetchDescriptor<ScheduleVersionModel>(
                predicate: #Predicate { $0.habitId == habitId && $0.effectiveFromDayKey == day }))
            if let model = existing.first {
                model.isActive = version.isActive
                model.weekdayMask = version.weekdays.mask
                for duplicate in existing.dropFirst() { self.modelContext.delete(duplicate) }
            } else {
                self.modelContext.insert(ScheduleVersionModel(version))
            }
        }
    }

    func reorderHabits(ids: [UUID]) async throws {
        try write {
            for (order, id) in ids.enumerated() {
                try self.habitModel(id: id)?.sortOrder = order
            }
        }
    }

    func deleteHabit(id: UUID) async throws {
        try write {
            guard let model = try self.habitModel(id: id) else { throw RepositoryError.notFound }
            for v in try self.modelContext.fetch(FetchDescriptor<ScheduleVersionModel>(predicate: #Predicate { $0.habitId == id })) {
                self.modelContext.delete(v)
            }
            for r in try self.modelContext.fetch(FetchDescriptor<DayRecordModel>(predicate: #Predicate { $0.habitId == id })) {
                self.modelContext.delete(r)
            }
            self.modelContext.delete(model)
        }
    }

    // MARK: Status

    func setStatus(habitId: UUID, dayKey: DayKey, desired: DesiredStatus, recordedAt: Date,
                   timeZoneID: String, expectedRevision: Int?) async throws -> StatusWriteResult {
        try write {
            guard try self.habitModel(id: habitId) != nil else { throw RepositoryError.notFound }
            let key = HabitDayRecord.recordKey(habitId: habitId, dayKey: dayKey)
            let models = try self.modelContext.fetch(FetchDescriptor<DayRecordModel>(predicate: #Predicate { $0.recordKey == key }))
            let model = models.first
            for duplicate in models.dropFirst() { self.modelContext.delete(duplicate) } // defensive: unique key must hold
            let existing = model?.domain
            if let expected = expectedRevision, let current = existing, current.revision != expected {
                throw RepositoryError.revisionConflict(expected: expected, actual: current.revision)
            }
            return InMemoryHabitRepository.apply(desired: desired, to: existing, habitId: habitId, dayKey: dayKey,
                                                 recordedAt: recordedAt, timeZoneID: timeZoneID) { updated in
                if let updated {
                    if let model { model.update(from: updated) } else { self.modelContext.insert(DayRecordModel(updated)) }
                } else if let model {
                    self.modelContext.delete(model)
                }
            }
        }
    }

    // MARK: Singletons

    func companionProfile() async throws -> CompanionProfile {
        try blob(SingletonBlobModel.companionKey, default: CompanionProfile())
    }

    func saveCompanionProfile(_ profile: CompanionProfile) async throws {
        try write { try self.storeBlob(SingletonBlobModel.companionKey, value: profile) }
    }

    func preferences() async throws -> UserPreferences {
        try blob(SingletonBlobModel.preferencesKey, default: UserPreferences())
    }

    func savePreferences(_ preferences: UserPreferences) async throws {
        try write { try self.storeBlob(SingletonBlobModel.preferencesKey, value: preferences) }
    }

    func reminderSlots() async throws -> [ReminderSlot] {
        try fetchAll(ReminderSlotModel.self).sorted { $0.sortOrder < $1.sortOrder }.map(\.domain)
    }

    func saveReminderSlots(_ slots: [ReminderSlot]) async throws {
        try write {
            for model in try self.fetchAll(ReminderSlotModel.self) { self.modelContext.delete(model) }
            for (order, slot) in slots.prefix(ReminderPlanner.maxSlots).enumerated() {
                self.modelContext.insert(ReminderSlotModel(slot, sortOrder: order))
            }
        }
    }

    // MARK: Bulk

    func replaceAll(with document: BackupDocument) async throws {
        let normalized = document.normalizedForImport()
        try write {
            try self.deleteEverything()
            for habit in normalized.habits { self.modelContext.insert(HabitModel(habit)) }
            for version in normalized.scheduleVersions { self.modelContext.insert(ScheduleVersionModel(version)) }
            for record in normalized.records { self.modelContext.insert(DayRecordModel(record)) }
            try self.storeBlob(SingletonBlobModel.companionKey, value: normalized.companion)
            try self.storeBlob(SingletonBlobModel.preferencesKey, value: normalized.preferences)
            for (order, slot) in normalized.reminderSlots.prefix(ReminderPlanner.maxSlots).enumerated() {
                self.modelContext.insert(ReminderSlotModel(slot, sortOrder: order))
            }
        }
    }

    func deleteAllUserData() async throws {
        try write { try self.deleteEverything() }
    }

    // MARK: Helpers

    private func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }

    private func habitModel(id: UUID) throws -> HabitModel? {
        try modelContext.fetch(FetchDescriptor<HabitModel>(predicate: #Predicate { $0.id == id })).first
    }

    private func blob<T: Decodable>(_ key: String, default value: T) throws -> T {
        guard let model = try modelContext.fetch(FetchDescriptor<SingletonBlobModel>(predicate: #Predicate { $0.key == key })).first else {
            return value
        }
        return try decoder.decode(T.self, from: model.payload)
    }

    private func storeBlob<T: Encodable>(_ key: String, value: T) throws {
        let data = try encoder.encode(value)
        if let model = try modelContext.fetch(FetchDescriptor<SingletonBlobModel>(predicate: #Predicate { $0.key == key })).first {
            model.payload = data
        } else {
            modelContext.insert(SingletonBlobModel(key: key, payload: data))
        }
    }

    private func deleteEverything() throws {
        for m in try fetchAll(DayRecordModel.self) { modelContext.delete(m) }
        for m in try fetchAll(ScheduleVersionModel.self) { modelContext.delete(m) }
        for m in try fetchAll(HabitModel.self) { modelContext.delete(m) }
        for m in try fetchAll(SingletonBlobModel.self) { modelContext.delete(m) }
        for m in try fetchAll(ReminderSlotModel.self) { modelContext.delete(m) }
    }

    /// Runs `body`, then saves. On any error the context is rolled back and the error is mapped to `RepositoryError`.
    private func write<T>(_ body: () throws -> T) throws -> T {
        do {
            let result = try body()
            if modelContext.hasChanges { try modelContext.save() }
            return result
        } catch let error as RepositoryError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw RepositoryError.persistenceFailed(String(describing: error))
        }
    }
}
