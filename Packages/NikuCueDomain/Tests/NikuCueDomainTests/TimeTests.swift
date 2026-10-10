import Foundation
import XCTest
@testable import NikuCueDomain

final class DayKeyTests: XCTestCase {
    func testParsesStrictFormat() {
        XCTAssertEqual(DayKey(string: "2026-10-10")?.string, "2026-10-10")
        XCTAssertEqual(DayKey(string: "2024-02-29")?.day, 29)
        XCTAssertNil(DayKey(string: "2023-02-29"))
        XCTAssertNil(DayKey(string: "2026-13-01"))
        XCTAssertNil(DayKey(string: "2026-10-1"))
        XCTAssertNil(DayKey(string: "2569-10-10x"))
        XCTAssertNil(DayKey(string: "๒๕๖๙-10-10")) // Thai digits are not accepted as keys
        XCTAssertNil(DayKey(string: "2026/10/10"))
    }

    func testOrderingAndCodable() throws {
        let a = Fixtures.day("2026-10-09"), b = Fixtures.day("2026-10-10"), c = Fixtures.day("2027-01-01")
        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, c)
        let data = try JSONEncoder().encode([b])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-10-10\"]")
        XCTAssertEqual(try JSONDecoder().decode([DayKey].self, from: data), [b])
        XCTAssertThrowsError(try JSONDecoder().decode(DayKey.self, from: Data("\"2026-1-1\"".utf8)))
    }
}

final class CalendarServiceTests: XCTestCase {
    func testLocalDayDependsOnTimeZoneNotOnUTC() {
        let instant = Fixtures.date("2026-10-09T18:30:00Z") // 01:30 Bangkok on the 10th, 00:00 Kolkata, 14:30 New York on the 9th
        XCTAssertEqual(CalendarService(timeZone: Fixtures.bangkok).dayKey(for: instant).string, "2026-10-10")
        XCTAssertEqual(CalendarService(timeZone: Fixtures.kolkata).dayKey(for: instant).string, "2026-10-10")
        XCTAssertEqual(CalendarService(timeZone: Fixtures.newYork).dayKey(for: instant).string, "2026-10-09")
        XCTAssertEqual(CalendarService(timeZone: Fixtures.tokyo).dayKey(for: instant).string, "2026-10-10")
    }

    func testMidnightBoundary() {
        let cal = CalendarService(timeZone: Fixtures.bangkok)
        XCTAssertEqual(cal.dayKey(for: Fixtures.date("2026-10-10T16:59:59Z")).string, "2026-10-10") // 23:59:59 local
        XCTAssertEqual(cal.dayKey(for: Fixtures.date("2026-10-10T17:00:00Z")).string, "2026-10-11") // 00:00 local
    }

    func testIsoWeekdayAndAppleConversion() {
        let cal = CalendarService(timeZone: Fixtures.bangkok)
        XCTAssertEqual(cal.isoWeekday(of: Fixtures.day("2026-10-10")), 6) // Saturday
        XCTAssertEqual(cal.isoWeekday(of: Fixtures.day("2026-10-11")), 7) // Sunday
        XCTAssertEqual(cal.isoWeekday(of: Fixtures.day("2026-10-12")), 1) // Monday
        XCTAssertEqual(CalendarService.appleWeekday(fromISO: 1), 2)
        XCTAssertEqual(CalendarService.appleWeekday(fromISO: 6), 7)
        XCTAssertEqual(CalendarService.appleWeekday(fromISO: 7), 1)
        for iso in 1...7 { XCTAssertEqual(CalendarService.isoWeekday(fromApple: CalendarService.appleWeekday(fromISO: iso)), iso) }
    }

    func testDayArithmeticAcrossDST() {
        let cal = CalendarService(timeZone: Fixtures.newYork)
        // 2026-03-08: clocks spring forward in New York (23-hour day); 2026-11-01: fall back (25-hour day).
        XCTAssertEqual(cal.dayKey(byAdding: 1, to: Fixtures.day("2026-03-07")).string, "2026-03-08")
        XCTAssertEqual(cal.dayKey(byAdding: 1, to: Fixtures.day("2026-03-08")).string, "2026-03-09")
        XCTAssertEqual(cal.days(from: Fixtures.day("2026-03-07"), to: Fixtures.day("2026-03-09")), 2)
        XCTAssertEqual(cal.days(from: Fixtures.day("2026-10-31"), to: Fixtures.day("2026-11-02")), 2)
        XCTAssertEqual(cal.days(from: Fixtures.day("2026-11-02"), to: Fixtures.day("2026-10-31")), -2)
        // The naive seconds/86400 computation under-counts the 23-hour spring-forward day; calendar arithmetic does not.
        // March 8 2026 is the 23-hour day (clocks jump at 02:00), so midnight 8th → midnight 9th is 23 h.
        let start = cal.date(startOf: Fixtures.day("2026-03-08"))
        let end = cal.date(startOf: Fixtures.day("2026-03-09"))
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
        XCTAssertEqual(Int(end.timeIntervalSince(start) / 86400), 0, "naive division gives 0 for a 23-hour day")
        XCTAssertEqual(cal.days(from: Fixtures.day("2026-03-08"), to: Fixtures.day("2026-03-09")), 1)
        XCTAssertEqual(cal.dayKeys(from: Fixtures.day("2026-02-27"), through: Fixtures.day("2026-03-02")).map(\.string),
                       ["2026-02-27", "2026-02-28", "2026-03-01", "2026-03-02"])
    }

    func testRepeatedHourOnFallBackStaysOnSameDay() {
        let cal = CalendarService(timeZone: Fixtures.newYork)
        // 01:30 EDT and 01:30 EST (one hour later) are both 2026-11-01.
        XCTAssertEqual(cal.dayKey(for: Fixtures.date("2026-11-01T05:30:00Z")).string, "2026-11-01")
        XCTAssertEqual(cal.dayKey(for: Fixtures.date("2026-11-01T06:30:00Z")).string, "2026-11-01")
    }

    func testThaiBuddhistPresentationKeepsGregorianKey() {
        let cal = CalendarService(timeZone: Fixtures.bangkok)
        let key = cal.dayKey(for: Fixtures.date("2026-10-10T05:00:00Z"))
        XCTAssertEqual(key.string, "2026-10-10")
        var thai = Calendar(identifier: .buddhist)
        thai.timeZone = Fixtures.bangkok
        let year = thai.component(.year, from: cal.date(startOf: key))
        XCTAssertEqual(year, 2569, "Buddhist calendar shows 2569 while the stored key stays 2026")
    }

    func testTravelKeepsExistingKeysAndUsesCurrentLocalDay() {
        let clock = Fixtures.clock("2026-10-10T16:30:00Z", zone: Fixtures.bangkok) // 23:30 Bangkok
        let bangkokDay = CalendarService(clock: clock).dayKey(for: clock.now)
        XCTAssertEqual(bangkokDay.string, "2026-10-10")
        clock.timeZone = Fixtures.tokyo // 01:30 next day in Tokyo
        let tokyoDay = CalendarService(clock: clock).dayKey(for: clock.now)
        XCTAssertEqual(tokyoDay.string, "2026-10-11")
        XCTAssertEqual(bangkokDay.string, "2026-10-10", "a key computed earlier does not change")
    }

    func testTimeOfDayBands() {
        XCTAssertEqual(TimeOfDay(hour: 5), .morning)
        XCTAssertEqual(TimeOfDay(hour: 10), .morning)
        XCTAssertEqual(TimeOfDay(hour: 11), .day)
        XCTAssertEqual(TimeOfDay(hour: 18), .day)
        XCTAssertEqual(TimeOfDay(hour: 19), .night)
        XCTAssertEqual(TimeOfDay(hour: 4), .night)
        XCTAssertEqual(TimeOfDay(hour: 23).ambient, .dozing)
    }
}
