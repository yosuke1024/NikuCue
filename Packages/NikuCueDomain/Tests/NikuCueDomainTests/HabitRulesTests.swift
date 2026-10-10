import Foundation
import XCTest
@testable import NikuCueDomain

final class WeekdaySetTests: XCTestCase {
    func testMaskAndMembership() {
        let weekend = WeekdaySet(isoWeekdays: [6, 7])
        XCTAssertTrue(weekend.contains(isoWeekday: 6))
        XCTAssertFalse(weekend.contains(isoWeekday: 1))
        XCTAssertEqual(weekend.isoWeekdays, [6, 7])
        XCTAssertTrue(WeekdaySet.everyDay.isEveryDay)
        XCTAssertEqual(WeekdaySet(isoWeekdays: [0, 8, 3]).isoWeekdays, [3], "out-of-range days are ignored")
        XCTAssertTrue(WeekdaySet.none.isEmpty)
        XCTAssertEqual(weekend.toggling(6).isoWeekdays, [7])
        XCTAssertEqual(weekend.toggling(1).isoWeekdays, [1, 6, 7])
    }
}

final class HabitValidationTests: XCTestCase {
    func testNameCountsGraphemesNotBytes() {
        XCTAssertEqual(try HabitValidation.validateName("  読む  ").get(), "読む")
        XCTAssertEqual(HabitValidation.validateName("   "), .failure(.emptyName))
        XCTAssertEqual(HabitValidation.validateName(String(repeating: "a", count: 41)), .failure(.nameTooLong(max: 40)))
        let thai = String(repeating: "สวัสดี", count: 10) // 10 × 4 grapheme clusters = 40
        XCTAssertEqual(thai.count, 40)
        XCTAssertNoThrow(try HabitValidation.validateName(thai).get())
        let family = String(repeating: "👨‍👩‍👧", count: 16)
        XCTAssertNoThrow(try HabitValidation.validateNickname(family).get(), "16 family emoji = 16 graphemes")
        XCTAssertEqual(HabitValidation.validateNickname(family + "x"), .failure(.nicknameTooLong(max: 16)))
        XCTAssertEqual(HabitValidation.validateNickname(""), .failure(.emptyNickname))
        XCTAssertEqual(HabitValidation.validateWeekdays(.none), .failure(.noWeekdays))
    }
}

final class ScheduleResolverTests: XCTestCase {
    let cal = CalendarService(timeZone: Fixtures.bangkok)
    let d = Fixtures.day

    func makeHabit(start: String) -> Habit {
        Habit(name: "Water", category: .water, sortOrder: 0, createdAtUTC: Fixtures.date("2026-10-01T00:00:00Z"), startDayKey: d(start))
    }

    func testVersionInForceAndWeekdayChangeFromTomorrow() {
        let habit = makeHabit(start: "2026-10-05")
        let v1 = HabitScheduleVersion(habitId: habit.id, effectiveFromDayKey: d("2026-10-05"), isActive: true, weekdays: .everyDay)
        let v2 = HabitScheduleVersion(habitId: habit.id, effectiveFromDayKey: d("2026-10-11"), isActive: true, weekdays: WeekdaySet(isoWeekdays: [1]))
        let versions = [v1, v2]
        XCTAssertEqual(ScheduleResolver.version(for: habit.id, on: d("2026-10-10"), in: versions)?.id, v1.id)
        XCTAssertEqual(ScheduleResolver.version(for: habit.id, on: d("2026-10-11"), in: versions)?.id, v2.id)
        XCTAssertTrue(ScheduleResolver.isScheduled(habit: habit, on: d("2026-10-10"), versions: versions, calendar: cal)) // Sat, everyday
        XCTAssertFalse(ScheduleResolver.isScheduled(habit: habit, on: d("2026-10-11"), versions: versions, calendar: cal)) // Sun, Monday-only from tomorrow
        XCTAssertTrue(ScheduleResolver.isScheduled(habit: habit, on: d("2026-10-12"), versions: versions, calendar: cal)) // Mon
        XCTAssertFalse(ScheduleResolver.isScheduled(habit: habit, on: d("2026-10-04"), versions: versions, calendar: cal), "before creation")
        XCTAssertNil(ScheduleResolver.version(for: habit.id, on: d("2026-10-04"), in: versions))
    }

    func testArchiveAndResumeDoNotCreateMissedDays() {
        let habit = makeHabit(start: "2026-10-01")
        let versions = [
            HabitScheduleVersion(habitId: habit.id, effectiveFromDayKey: d("2026-10-01"), isActive: true, weekdays: .everyDay),
            HabitScheduleVersion(habitId: habit.id, effectiveFromDayKey: d("2026-10-11"), isActive: false, weekdays: .everyDay),
            HabitScheduleVersion(habitId: habit.id, effectiveFromDayKey: d("2026-10-20"), isActive: true, weekdays: .everyDay),
        ]
        XCTAssertTrue(ScheduleResolver.isScheduled(habit: habit, on: d("2026-10-10"), versions: versions, calendar: cal), "archive day itself stays due")
        XCTAssertFalse(ScheduleResolver.isScheduled(habit: habit, on: d("2026-10-15"), versions: versions, calendar: cal))
        XCTAssertFalse(ScheduleResolver.isActive(habitId: habit.id, on: d("2026-10-15"), versions: versions))
        XCTAssertTrue(ScheduleResolver.isScheduled(habit: habit, on: d("2026-10-20"), versions: versions, calendar: cal))
        XCTAssertEqual(ScheduleResolver.activeHabits(on: d("2026-10-10"), habits: [habit], versions: versions).count, 1, "archived-from-tomorrow still counts today")
        XCTAssertEqual(ScheduleResolver.activeHabits(on: d("2026-10-11"), habits: [habit], versions: versions).count, 0)
        XCTAssertEqual(ScheduleResolver.nextScheduledDay(habit: habit, from: d("2026-10-12"), versions: versions, calendar: cal)?.string, "2026-10-20")
    }
}

final class ProgressCalculatorTests: XCTestCase {
    let cal = CalendarService(timeZone: Fixtures.bangkok)
    let today = Fixtures.day("2026-10-10")

    func fixture(count: Int) -> ([Habit], [HabitScheduleVersion]) {
        var habits: [Habit] = [], versions: [HabitScheduleVersion] = []
        for i in 0..<count {
            let h = Habit(name: "H\(i)", category: .custom, sortOrder: i, createdAtUTC: Fixtures.date("2026-10-01T00:00:00Z"), startDayKey: Fixtures.day("2026-10-01"))
            habits.append(h)
            versions.append(HabitScheduleVersion(habitId: h.id, effectiveFromDayKey: h.startDayKey, isActive: true, weekdays: .everyDay))
        }
        return (habits, versions)
    }

    func record(_ h: Habit, _ day: DayKey, _ status: RecordStatus) -> HabitDayRecord {
        HabitDayRecord(habitId: h.id, dayKey: day, status: status, recordedAtUTC: Date(timeIntervalSince1970: 0), timeZoneID: "Asia/Bangkok", revision: 1)
    }

    func testTwoDoneOneSkippedIsNotAllDone() { // Q05
        let (habits, versions) = fixture(count: 3)
        let records = [record(habits[0], today, .done), record(habits[1], today, .done), record(habits[2], today, .skipped)]
        let p = ProgressCalculator.progress(on: today, habits: habits, versions: versions, records: records, calendar: cal)
        XCTAssertEqual(p, DayProgress(scheduled: 3, done: 2, skipped: 1))
        XCTAssertFalse(p.isAllDone)
        XCTAssertTrue(p.isAllResolved)
        XCTAssertEqual(p.pending, 0)
    }

    func testZeroScheduledNeverAllDone() { // Q06
        let p = ProgressCalculator.progress(on: today, habits: [], versions: [], records: [], calendar: cal)
        XCTAssertEqual(p, .empty)
        XCTAssertFalse(p.isAllDone)
        XCTAssertFalse(p.isAllResolved)
        XCTAssertFalse(p.hasSchedule)
    }

    func testAllSkippedIsNotResolvedCelebration() {
        let (habits, versions) = fixture(count: 2)
        let records = [record(habits[0], today, .skipped), record(habits[1], today, .skipped)]
        let p = ProgressCalculator.progress(on: today, habits: habits, versions: versions, records: records, calendar: cal)
        XCTAssertFalse(p.isAllDone)
        XCTAssertFalse(p.isAllResolved, "all_resolved needs at least one done")
    }

    func testFiveDoneOnOneDayCountsOnce() { // Q07
        let (habits, _) = fixture(count: 5)
        var records = habits.map { record($0, today, .done) }
        XCTAssertEqual(ProgressCalculator.distinctDoneDays(records: records), 1)
        records.append(record(habits[0], Fixtures.day("2026-10-09"), .skipped))
        XCTAssertEqual(ProgressCalculator.distinctDoneDays(records: records), 1, "rest-only days do not count")
        records.append(record(habits[0], Fixtures.day("2026-10-01"), .done))
        XCTAssertEqual(ProgressCalculator.distinctDoneDays(records: records), 2, "non-consecutive days still add up")
    }

    func testEditableWindowIsTodayPlusSixDays() { // Q16
        let window = ProgressCalculator.editableWindow(today: today, calendar: cal)
        XCTAssertEqual(window.lowerBound.string, "2026-10-04")
        XCTAssertEqual(window.upperBound.string, "2026-10-10")
        XCTAssertTrue(ProgressCalculator.isEditable(day: Fixtures.day("2026-10-04"), today: today, calendar: cal))
        XCTAssertFalse(ProgressCalculator.isEditable(day: Fixtures.day("2026-10-03"), today: today, calendar: cal))
        XCTAssertFalse(ProgressCalculator.isEditable(day: Fixtures.day("2026-10-11"), today: today, calendar: cal))
    }

    func testMilestones() {
        XCTAssertNil(Milestones.newlyReached(distinctDoneDays: 2, seen: []))
        XCTAssertEqual(Milestones.newlyReached(distinctDoneDays: 3, seen: []), 3)
        XCTAssertNil(Milestones.newlyReached(distinctDoneDays: 5, seen: [3]))
        XCTAssertEqual(Milestones.newlyReached(distinctDoneDays: 7, seen: [3]), 7)
        XCTAssertEqual(Milestones.newlyReached(distinctDoneDays: 20, seen: [3, 7]), 14)
        XCTAssertEqual(Milestones.newlyReached(distinctDoneDays: 9, seen: []), 7, "highest unseen reached")
        XCTAssertNil(Milestones.newlyReached(distinctDoneDays: 100, seen: [3, 7, 14]))
    }
}
