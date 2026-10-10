import NikuCueDomain
import SwiftData
import XCTest
@testable import NikuCue

/// Storage-layer behaviour of the SwiftData repository (P04 acceptance: atomic save, rollback, restart, import).
final class SwiftDataRepositoryTests: XCTestCase {
    let day = DayKey(string: "2026-10-10")!

    func makeRepository() throws -> SwiftDataHabitRepository {
        SwiftDataHabitRepository(modelContainer: try NikuCueStore.makeContainer(inMemory: true))
    }

    func habit(_ name: String = "Water") -> (Habit, HabitScheduleVersion) {
        let h = Habit(name: name, category: .water, sortOrder: 0, createdAtUTC: Date(timeIntervalSince1970: 1_000), startDayKey: day)
        return (h, HabitScheduleVersion(habitId: h.id, effectiveFromDayKey: day, isActive: true, weekdays: .everyDay))
    }

    func testCreateReadUpdateDelete() async throws {
        let repo = try makeRepository()
        let (h, v) = habit()
        try await repo.createHabit(h, schedule: v)
        let habits = try await repo.habits()
        XCTAssertEqual(habits, [h])
        let versions = try await repo.scheduleVersions()
        XCTAssertEqual(versions, [v])
        var renamed = h
        renamed.name = "Water 2"
        try await repo.updateHabit(renamed)
        let afterRename = try await repo.habits().first?.name
        XCTAssertEqual(afterRename, "Water 2")
        var tomorrow = v
        tomorrow = HabitScheduleVersion(habitId: h.id, effectiveFromDayKey: DayKey(string: "2026-10-11")!, isActive: false, weekdays: .everyDay)
        try await repo.upsertScheduleVersion(tomorrow)
        try await repo.upsertScheduleVersion(tomorrow) // same effective day → replaced, not duplicated
        let count = try await repo.scheduleVersions().count
        XCTAssertEqual(count, 2)
        try await repo.deleteHabit(id: h.id)
        let remaining = try await repo.habits().count
        XCTAssertEqual(remaining, 0)
        let remainingVersions = try await repo.scheduleVersions().count
        XCTAssertEqual(remainingVersions, 0)
    }

    func testStatusWritesAreIdempotentAndUnique() async throws { // Q02
        let repo = try makeRepository()
        let (h, v) = habit()
        try await repo.createHabit(h, schedule: v)
        var newly = 0
        for _ in 0..<10 {
            let r = try await repo.setStatus(habitId: h.id, dayKey: day, desired: .done, recordedAt: Date(), timeZoneID: "Asia/Bangkok", expectedRevision: nil)
            if r.newlyCompleted { newly += 1 }
        }
        XCTAssertEqual(newly, 1)
        let records = try await repo.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.revision, 1)
        let skip = try await repo.setStatus(habitId: h.id, dayKey: day, desired: .skipped, recordedAt: Date(), timeZoneID: "Asia/Bangkok", expectedRevision: nil)
        XCTAssertTrue(skip.newlySkipped)
        XCTAssertEqual(skip.revision, 2)
        do {
            _ = try await repo.setStatus(habitId: h.id, dayKey: day, desired: .done, recordedAt: Date(), timeZoneID: "UTC", expectedRevision: 1)
            XCTFail("stale revision must be rejected")
        } catch RepositoryError.revisionConflict(let expected, let actual) {
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        }
        let clear = try await repo.setStatus(habitId: h.id, dayKey: day, desired: .clear, recordedAt: Date(), timeZoneID: "UTC", expectedRevision: nil)
        XCTAssertTrue(clear.changed)
        let after = try await repo.allRecords().count
        XCTAssertEqual(after, 0)
        do {
            _ = try await repo.setStatus(habitId: UUID(), dayKey: day, desired: .done, recordedAt: Date(), timeZoneID: "UTC", expectedRevision: nil)
            XCTFail("unknown habit")
        } catch RepositoryError.notFound {}
    }

    func testSingletonsAndReminderSlots() async throws {
        let repo = try makeRepository()
        let initial = try await repo.companionProfile()
        XCTAssertEqual(initial, CompanionProfile())
        try await repo.saveCompanionProfile(CompanionProfile(nickname: "มะลิ", didCustomizeName: true, seenMilestones: [3], allDoneShownDayKeys: [day]))
        let saved = try await repo.companionProfile()
        XCTAssertEqual(saved.nickname, "มะลิ")
        XCTAssertEqual(saved.seenMilestones, [3])
        XCTAssertEqual(saved.allDoneShownDayKeys, [day])
        var prefs = UserPreferences()
        prefs.language = .th
        prefs.onboardingStep = .finished
        try await repo.savePreferences(prefs)
        let loaded = try await repo.preferences()
        XCTAssertEqual(loaded, prefs)
        let slots = [ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: .everyDay), ReminderSlot(enabled: false, hour: 21, minute: 30, weekdays: WeekdaySet(isoWeekdays: [6, 7]))]
        try await repo.saveReminderSlots(slots)
        let readBack = try await repo.reminderSlots()
        XCTAssertEqual(readBack, slots)
    }

    func testReplaceAllAndDeleteAll() async throws { // Q33 / Q34
        let repo = try makeRepository()
        let (h, v) = habit()
        try await repo.createHabit(h, schedule: v)
        _ = try await repo.setStatus(habitId: h.id, dayKey: day, desired: .done, recordedAt: Date(), timeZoneID: "UTC", expectedRevision: nil)
        let (h2, v2) = habit("Read")
        let document = BackupDocument(appVersion: "t", exportedAtUTC: Date(), habits: [h2], scheduleVersions: [v2], records: [],
                                      companion: CompanionProfile(nickname: "Momo"), preferences: UserPreferences(remindersEnabled: true),
                                      reminderSlots: [ReminderSlot(enabled: true, hour: 7, minute: 0, weekdays: .everyDay)])
        try await repo.replaceAll(with: document)
        let habits = try await repo.habits()
        XCTAssertEqual(habits.map(\.id), [h2.id])
        let records = try await repo.allRecords().count
        XCTAssertEqual(records, 0)
        let slots = try await repo.reminderSlots()
        XCTAssertEqual(slots.map(\.enabled), [false], "restored reminders start disabled")
        let prefs = try await repo.preferences()
        XCTAssertFalse(prefs.remindersEnabled)
        try await repo.deleteAllUserData()
        let empty = try await repo.habits().isEmpty
        XCTAssertTrue(empty)
        let companion = try await repo.companionProfile()
        XCTAssertEqual(companion, CompanionProfile())
    }

    func testDataSurvivesReopeningTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let schema = Schema(versionedSchema: NikuCueSchemaV1.self)
        let (h, v) = habit()
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("t", schema: schema, url: url, cloudKitDatabase: .none)])
            let repo = SwiftDataHabitRepository(modelContainer: container)
            try await repo.createHabit(h, schedule: v)
            _ = try await repo.setStatus(habitId: h.id, dayKey: day, desired: .done, recordedAt: Date(), timeZoneID: "UTC", expectedRevision: nil)
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration("t", schema: schema, url: url, cloudKitDatabase: .none)])
        let repo = SwiftDataHabitRepository(modelContainer: reopened)
        let habits = try await repo.habits()
        XCTAssertEqual(habits.map(\.id), [h.id])
        let records = try await repo.allRecords()
        XCTAssertEqual(records.first?.status, .done)
    }

    func testServiceOnTopOfSwiftDataRepository() async throws {
        let repo = try makeRepository()
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_791_600_000), timeZone: TimeZone(identifier: "Asia/Bangkok")!)
        let service = HabitService(repository: repo, clock: clock)
        let habit = try await service.createHabit(name: "Water", category: .water, weekdays: .everyDay)
        let outcome = try await service.markDone(habitId: habit.id)
        XCTAssertEqual(outcome.event?.kind, .completionCommitted)
        let again = try await service.markDone(habitId: habit.id)
        XCTAssertNil(again.event)
        let home = try await service.homeSnapshot()
        XCTAssertEqual(home.progress.done, 1)
    }
}
