import Foundation
import XCTest
@testable import NikuCueDomain

final class HabitServiceTests: XCTestCase {
    var repo: InMemoryHabitRepository!
    var clock: ManualClock!
    var service: HabitService!

    override func setUp() async throws {
        repo = InMemoryHabitRepository()
        clock = Fixtures.clock() // Sat 2026-10-10 12:00 Bangkok
        service = HabitService(repository: repo, clock: clock)
    }

    @discardableResult
    func addHabit(_ name: String = "Water", _ category: HabitCategory = .water, _ days: WeekdaySet = .everyDay) async throws -> Habit {
        try await service.createHabit(name: name, category: category, weekdays: days)
    }

    // MARK: Creation / limits

    func testCreateValidatesAndStartsToday() async throws {
        let habit = try await addHabit("  Drink water ")
        XCTAssertEqual(habit.name, "Drink water")
        XCTAssertEqual(habit.startDayKey.string, "2026-10-10")
        let home = try await service.homeSnapshot()
        XCTAssertEqual(home.rows.map(\.id), [habit.id])
        XCTAssertEqual(home.rows.first?.status, .pending)
        XCTAssertEqual(home.progress, DayProgress(scheduled: 1, done: 0, skipped: 0))
    }

    func testCreateRejectsInvalidInput() async throws {
        do { _ = try await addHabit("   "); XCTFail() } catch HabitServiceError.validation(.emptyName) {}
        do { _ = try await addHabit("x", .custom, .none); XCTFail() } catch HabitServiceError.validation(.noWeekdays) {}
    }

    func testFiveActiveLimitAndArchiveFreesSlotTomorrow() async throws {
        var habits: [Habit] = []
        for i in 0..<5 { habits.append(try await addHabit("H\(i)", .custom)) }
        do { _ = try await addHabit("H6"); XCTFail("sixth habit must be rejected") }
        catch HabitServiceError.validation(.activeLimitReached(max: 5)) {}
        try await service.archive(id: habits[0].id)
        do { _ = try await addHabit("H6"); XCTFail("slot frees only tomorrow") }
        catch HabitServiceError.validation(.activeLimitReached(max: 5)) {}
        let home = try await service.homeSnapshot()
        XCTAssertTrue(home.isAtActiveLimit)
        XCTAssertEqual(home.rows.count, 5, "archived-from-tomorrow habit is still due today")
        clock.advance(by: 86_400)
        _ = try await addHabit("H6")
        let tomorrow = try await service.homeSnapshot()
        XCTAssertEqual(tomorrow.activeHabits.count, 5)
        XCTAssertEqual(tomorrow.archivedHabits.map(\.id), [habits[0].id])
        XCTAssertFalse(tomorrow.rows.contains { $0.id == habits[0].id })
    }

    func testWeekdayChangeAppliesTomorrow() async throws { // Q14
        let habit = try await addHabit()
        try await service.changeWeekdays(id: habit.id, weekdays: WeekdaySet(isoWeekdays: [1])) // Mondays only
        let hoisted1 = try await service.homeSnapshot().rows.count
        XCTAssertEqual(hoisted1, 1, "today (Saturday) unchanged")
        clock.advance(by: 86_400) // Sunday
        let hoisted2 = try await service.homeSnapshot().rows.count
        XCTAssertEqual(hoisted2, 0)
        clock.advance(by: 86_400) // Monday
        let hoisted3 = try await service.homeSnapshot().rows.count
        XCTAssertEqual(hoisted3, 1)
        // editing again on the same day replaces the pending version instead of duplicating it
        try await service.changeWeekdays(id: habit.id, weekdays: .everyDay)
        try await service.changeWeekdays(id: habit.id, weekdays: WeekdaySet(isoWeekdays: [2]))
        let versions = try await repo.scheduleVersions().filter { $0.habitId == habit.id }
        XCTAssertEqual(versions.count, 3, "create + Monday version + one replaced pending version")
    }

    func testArchiveThenResumeCreatesNoMissedDays() async throws { // Q15
        let habit = try await addHabit()
        try await service.archive(id: habit.id)
        clock.advance(by: 86_400 * 3)
        let hoisted4 = try await service.homeSnapshot().rows.count
        XCTAssertEqual(hoisted4, 0)
        let hoisted5 = try await service.homeSnapshot().archivedHabits.count
        XCTAssertEqual(hoisted5, 1)
        try await service.resume(id: habit.id, weekdays: .everyDay)
        let hoisted6 = try await service.homeSnapshot().rows.count
        XCTAssertEqual(hoisted6, 0, "resume applies tomorrow")
        clock.advance(by: 86_400)
        let hoisted7 = try await service.homeSnapshot().rows.count
        XCTAssertEqual(hoisted7, 1)
        let kinds = try await service.monthKinds(year: 2026, month: 10)
        XCTAssertEqual(kinds[Fixtures.day("2026-10-12")], .notScheduled, "archived days are not failures")
        XCTAssertEqual(kinds[Fixtures.day("2026-10-10")], .unrecorded)
    }

    // MARK: Writes

    func testDoneTenTimesWritesOnceAndEmitsOneEvent() async throws { // Q02
        let habit = try await addHabit()
        var events = 0
        var revisions = Set<Int>()
        for _ in 0..<10 {
            let outcome = try await service.markDone(habitId: habit.id)
            if outcome.event != nil { events += 1 }
            revisions.insert(outcome.write.revision)
        }
        XCTAssertEqual(events, 1)
        XCTAssertEqual(revisions, [1])
        let hoisted8 = try await repo.allRecords().count
        XCTAssertEqual(hoisted8, 1)
        let hoisted9 = try await service.distinctDoneDays()
        XCTAssertEqual(hoisted9, 1)
        let home = try await service.homeSnapshot()
        XCTAssertEqual(home.progress, DayProgress(scheduled: 1, done: 1, skipped: 0))
        XCTAssertTrue(home.progress.isAllDone)
    }

    func testPersistenceFailureLeavesStateAndProducesNoEvent() async throws { // Q03
        let habit = try await addHabit()
        await repo.setFailNextWrite(true)
        do {
            _ = try await service.markDone(habitId: habit.id)
            XCTFail("expected failure")
        } catch HabitServiceError.repository(.persistenceFailed) {}
        let hoisted10 = try await repo.allRecords().count
        XCTAssertEqual(hoisted10, 0)
        let hoisted11 = try await service.homeSnapshot().rows.first?.status
        XCTAssertEqual(hoisted11, .pending)
        // retry succeeds exactly once
        let outcome = try await service.markDone(habitId: habit.id)
        XCTAssertEqual(outcome.event?.kind, .completionCommitted)
        let hoisted12 = try await repo.allRecords().count
        XCTAssertEqual(hoisted12, 1)
    }

    func testUndoRemovesRecordAndEmitsUndoEvent() async throws { // Q04
        let habit = try await addHabit()
        let done = try await service.markDone(habitId: habit.id)
        XCTAssertEqual(done.event?.kind, .completionCommitted)
        XCTAssertEqual(done.event?.revision, 1)
        let undo = try await service.undo(habitId: habit.id)
        XCTAssertEqual(undo.event?.kind, .completionUndone)
        XCTAssertEqual(undo.event?.habitId, habit.id)
        XCTAssertTrue(undo.write.changed)
        XCTAssertNil(undo.write.record)
        let hoisted13 = try await repo.allRecords().count
        XCTAssertEqual(hoisted13, 0)
        let hoisted14 = try await service.distinctDoneDays()
        XCTAssertEqual(hoisted14, 0)
        let again = try await service.undo(habitId: habit.id)
        XCTAssertNil(again.event, "undoing nothing is silent")
        XCTAssertFalse(again.write.changed)
        XCTAssertEqual(undo.write.revision, 0, "no record remains after undo")
        // redo after undo gets a fresh event; the new record starts at revision 1 again
        let redo = try await service.markDone(habitId: habit.id)
        XCTAssertEqual(redo.event?.kind, .completionCommitted)
        XCTAssertEqual(redo.write.revision, 1)
    }

    func testSkipIsSeparateFromDone() async throws { // Q05
        let a = try await addHabit("A", .custom), b = try await addHabit("B", .custom), c = try await addHabit("C", .custom)
        _ = try await service.markDone(habitId: a.id)
        _ = try await service.markDone(habitId: b.id)
        let skipped = try await service.markSkipped(habitId: c.id)
        XCTAssertEqual(skipped.event?.kind, .skipCommitted)
        XCTAssertEqual(skipped.progress, DayProgress(scheduled: 3, done: 2, skipped: 1))
        XCTAssertFalse(skipped.progress.isAllDone)
        XCTAssertTrue(skipped.progress.isAllResolved)
        // skipped → done is a new completion; done → skipped is not a completion
        let flipped = try await service.markDone(habitId: c.id)
        XCTAssertEqual(flipped.event?.kind, .completionCommitted)
        let back = try await service.markSkipped(habitId: a.id)
        XCTAssertEqual(back.event?.kind, .skipCommitted)
        XCTAssertEqual(back.progress.done, 2)
    }

    func testUnscheduledAndWindowRules() async throws { // Q16
        let habit = try await addHabit("Mon", .custom, WeekdaySet(isoWeekdays: [1]))
        do { _ = try await service.markDone(habitId: habit.id); XCTFail() } catch HabitServiceError.notScheduled {}
        // Build history: habit created 10 days ago, every day
        let old = try await addHabit("Old")
        clock.advance(by: 86_400 * 10) // now 2026-10-20
        let sixAgo = Fixtures.day("2026-10-14"), sevenAgo = Fixtures.day("2026-10-13")
        let corrected = try await service.setStatus(habitId: old.id, day: sixAgo, desired: .done)
        XCTAssertEqual(corrected.event?.kind, .historyCorrected, "history corrections never celebrate")
        XCTAssertEqual(corrected.progress, DayProgress(scheduled: 1, done: 1, skipped: 0))
        do { _ = try await service.setStatus(habitId: old.id, day: sevenAgo, desired: .done); XCTFail() }
        catch HabitServiceError.outsideEditableWindow {}
        do { _ = try await service.setStatus(habitId: old.id, day: Fixtures.day("2026-10-21"), desired: .done); XCTFail() }
        catch HabitServiceError.futureDay {}
        do { _ = try await service.setStatus(habitId: habit.id, day: sixAgo, desired: .done); XCTFail("Wednesday is not a Monday") }
        catch HabitServiceError.notScheduled {}
        let summary = try await service.daySummary(sixAgo)
        XCTAssertTrue(summary.isEditable)
        let hoisted15 = try await service.daySummary(sevenAgo).isEditable
        XCTAssertFalse(hoisted15)
    }

    func testMilestoneReachedByCorrectionIsRecordedQuietly() async throws {
        let habit = try await addHabit()
        clock.advance(by: 86_400 * 3) // 2026-10-13
        _ = try await service.setStatus(habitId: habit.id, day: Fixtures.day("2026-10-11"), desired: .done)
        _ = try await service.setStatus(habitId: habit.id, day: Fixtures.day("2026-10-12"), desired: .done)
        let hoisted16 = try await service.companionProfile().seenMilestones
        XCTAssertEqual(hoisted16, [])
        let third = try await service.setStatus(habitId: habit.id, day: Fixtures.day("2026-10-10"), desired: .done)
        XCTAssertEqual(third.distinctDoneDays, 3)
        XCTAssertEqual(third.event?.kind, .historyCorrected)
        let hoisted17 = try await service.companionProfile().seenMilestones
        XCTAssertEqual(hoisted17, [3], "recorded as reached, not replayed")
        XCTAssertNil(Milestones.newlyReached(distinctDoneDays: third.snapshot.distinctDoneDays, seen: third.snapshot.seenMilestones))
    }

    func testTodayCompletionReachingMilestoneIsLeftForTheEngine() async throws {
        let habit = try await addHabit()
        clock.advance(by: 86_400 * 2) // 2026-10-12; the two earlier days are after creation and inside the window
        for day in ["2026-10-10", "2026-10-11"] {
            _ = try await service.setStatus(habitId: habit.id, day: Fixtures.day(day), desired: .done)
        }
        let outcome = try await service.markDone(habitId: habit.id)
        XCTAssertEqual(outcome.event?.kind, .completionCommitted)
        XCTAssertEqual(outcome.snapshot.distinctDoneDays, 3)
        XCTAssertEqual(outcome.snapshot.seenMilestones, [], "engine decides; markShown records it when displayed")
        try await service.markShown(milestone: 3, allDoneDay: outcome.snapshot.dayKey)
        let companion = try await service.companionProfile()
        XCTAssertEqual(companion.seenMilestones, [3])
        XCTAssertEqual(companion.allDoneShownDayKeys, [Fixtures.day("2026-10-12")])
    }

    // MARK: Scene / companion

    func testGreetingOncePerDayAndWelcomeBackAfterThreeDays() async throws {
        let first = try await service.sceneEntered()
        XCTAssertEqual(first.event.kind, .sceneEntered)
        XCTAssertFalse(first.snapshot.greetedToday)
        let second = try await service.sceneEntered()
        XCTAssertEqual(second.event.kind, .sceneEntered)
        XCTAssertTrue(second.snapshot.greetedToday, "same day: no second long greeting")
        clock.advance(by: 86_400 * 2)
        let hoisted18 = try await service.sceneEntered().event.kind
        XCTAssertEqual(hoisted18, .sceneEntered, "2 days away is a normal greeting")
        clock.advance(by: 86_400 * 3)
        let hoisted19 = try await service.sceneEntered().event.kind
        XCTAssertEqual(hoisted19, .welcomeBack)
        let hoisted20 = try await service.sceneEntered().event.kind
        XCTAssertEqual(hoisted20, .sceneEntered, "welcome back only once")
    }

    func testNicknameValidationAndDefault() async throws {
        try await service.setNickname("  Mali-chan ")
        let hoisted21 = try await service.companionProfile().nickname
        XCTAssertEqual(hoisted21, "Mali-chan")
        let hoisted22 = try await service.companionProfile().didCustomizeName
        XCTAssertTrue(hoisted22)
        do { try await service.setNickname(String(repeating: "x", count: 17)); XCTFail() }
        catch HabitServiceError.validation(.nicknameTooLong(max: 16)) {}
        try await service.setNickname("")
        let hoisted23 = try await service.companionProfile().nickname
        XCTAssertNil(hoisted23)
        let hoisted24 = try await service.companionProfile().didCustomizeName
        XCTAssertFalse(hoisted24)
    }

    func testReminderSlotRules() async throws {
        let a = ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: .everyDay)
        let b = ReminderSlot(enabled: true, hour: 8, minute: 0, weekdays: WeekdaySet(isoWeekdays: [6, 7]))
        do { try await service.saveReminderSlots([a, b]); XCTFail("duplicate time on overlapping days") } catch HabitServiceError.duplicateReminder {}
        try await service.saveReminderSlots([a, ReminderSlot(enabled: true, hour: 21, minute: 30, weekdays: .everyDay)])
        let hoisted25 = try await service.reminderSlots().count
        XCTAssertEqual(hoisted25, 2)
        do { try await service.saveReminderSlots([a, b, a]); XCTFail("max two") } catch HabitServiceError.validation {}
    }

    // MARK: Delete / backup

    func testDeleteHabitCascadesAndRecomputesDays() async throws {
        let a = try await addHabit("A", .custom), b = try await addHabit("B", .custom)
        _ = try await service.markDone(habitId: a.id)
        _ = try await service.markDone(habitId: b.id)
        clock.advance(by: 86_400)
        _ = try await service.markDone(habitId: a.id)
        let hoisted26 = try await service.distinctDoneDays()
        XCTAssertEqual(hoisted26, 2)
        try await service.deleteHabit(id: a.id)
        let hoisted27 = try await service.distinctDoneDays()
        XCTAssertEqual(hoisted27, 1)
        let hoisted28 = try await repo.allRecords().count
        XCTAssertEqual(hoisted28, 1)
        let hoisted29 = try await repo.scheduleVersions().count
        XCTAssertEqual(hoisted29, 1)
    }

    func testBackupRoundTripRestoresWithRemindersOff() async throws { // Q33
        let habit = try await addHabit()
        _ = try await service.markDone(habitId: habit.id)
        try await service.setNickname("Mali")
        try await service.saveReminderSlots([ReminderSlot(enabled: true, hour: 8, minute: 15, weekdays: .everyDay)])
        var prefs = try await service.preferences()
        prefs.remindersEnabled = true
        prefs.onboardingStep = .finished
        try await service.savePreferences(prefs)
        let doc = try await service.exportBackup(appVersion: "0.1")
        let data = try doc.encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("entitlement"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("consent"))

        let fresh = InMemoryHabitRepository()
        let service2 = HabitService(repository: fresh, clock: clock)
        let imported = try await service2.importBackup(data: data)
        XCTAssertEqual(imported.habits.count, 1)
        let hoisted30 = try await service2.homeSnapshot().rows.first?.status
        XCTAssertEqual(hoisted30, .done)
        let hoisted31 = try await service2.companionProfile().nickname
        XCTAssertEqual(hoisted31, "Mali")
        let hoisted32 = try await service2.reminderSlots().map(\.enabled)
        XCTAssertEqual(hoisted32, [false])
        let hoisted33 = try await service2.preferences().remindersEnabled
        XCTAssertFalse(hoisted33)
        let hoisted34 = try await service2.preferences().isOnboardingComplete
        XCTAssertTrue(hoisted34)
    }

    func testImportFailureKeepsOriginalData() async throws { // Q39
        let habit = try await addHabit()
        _ = try await service.markDone(habitId: habit.id)
        let doc = try await service.exportBackup(appVersion: "0.1")
        var other = doc
        other.habits = []
        other.scheduleVersions = []
        other.records = []
        await repo.setFailNextWrite(true)
        do { try await service.importBackup(data: try other.encoded()); XCTFail() }
        catch HabitServiceError.repository(.persistenceFailed) {}
        let hoisted35 = try await repo.habits().count
        XCTAssertEqual(hoisted35, 1)
        let hoisted36 = try await repo.allRecords().count
        XCTAssertEqual(hoisted36, 1)
        do { try await service.importBackup(data: Data("{\"schemaVersion\":1,\"entitlement\":true}".utf8)); XCTFail() }
        catch HabitServiceError.backup(.unexpectedField("entitlement")) {}
        let hoisted37 = try await repo.habits().count
        XCTAssertEqual(hoisted37, 1)
    }

    func testDeleteAllKeepsNothingLocal() async throws { // Q34 (entitlements live outside the repository)
        _ = try await addHabit()
        try await service.setNickname("X")
        try await service.deleteAllUserData()
        let hoisted38 = try await repo.habits().count
        XCTAssertEqual(hoisted38, 0)
        let hoisted39 = try await service.companionProfile().nickname
        XCTAssertNil(hoisted39)
        let hoisted40 = try await service.preferences()
        XCTAssertEqual(hoisted40, UserPreferences())
    }
}
