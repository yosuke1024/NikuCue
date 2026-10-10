import Foundation

/// Explicit Gregorian calendar arithmetic in one time zone.
///
/// All conversions between `Date` and `DayKey` go through this type so that day keys are always
/// Gregorian/ASCII and day differences are never computed as `seconds / 86400` (docs/07 §5).
public struct CalendarService: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 2 // Monday, matches ISO weekday numbering
        self.calendar = cal
    }

    public init(clock: Clock) {
        self.init(timeZone: clock.timeZone)
    }

    /// The local calendar day containing `date` in this service's time zone.
    public func dayKey(for date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // Components from a valid Date always form a valid Gregorian day.
        return DayKey(year: c.year!, month: c.month!, day: c.day!)!
    }

    /// Start of the given day (00:00 local, or the first valid instant on DST gap days).
    public func date(startOf key: DayKey) -> Date {
        var c = DateComponents()
        c.year = key.year
        c.month = key.month
        c.day = key.day
        c.hour = 0
        c.minute = 0
        c.second = 0
        return calendar.date(from: c)!
    }

    /// ISO weekday: Monday = 1 … Sunday = 7.
    public func isoWeekday(of key: DayKey) -> Int {
        let apple = calendar.component(.weekday, from: date(startOf: key)) // Sunday = 1 … Saturday = 7
        return apple == 1 ? 7 : apple - 1
    }

    /// Apple `Calendar` weekday (Sunday = 1 … Saturday = 7) from an ISO weekday (docs/07 §3).
    public static func appleWeekday(fromISO iso: Int) -> Int {
        precondition((1...7).contains(iso), "ISO weekday out of range")
        return iso % 7 + 1
    }

    /// ISO weekday from an Apple `Calendar` weekday.
    public static func isoWeekday(fromApple apple: Int) -> Int {
        precondition((1...7).contains(apple), "Apple weekday out of range")
        return apple == 1 ? 7 : apple - 1
    }

    public func dayKey(byAdding days: Int, to key: DayKey) -> DayKey {
        let d = calendar.date(byAdding: .day, value: days, to: date(startOf: key))!
        return dayKey(for: d)
    }

    /// Whole calendar days from `from` to `to` (positive when `to` is later).
    public func days(from: DayKey, to: DayKey) -> Int {
        let a = calendar.startOfDay(for: date(startOf: from))
        let b = calendar.startOfDay(for: date(startOf: to))
        return calendar.dateComponents([.day], from: a, to: b).day!
    }

    /// Inclusive list of day keys.
    public func dayKeys(from: DayKey, through: DayKey) -> [DayKey] {
        guard from <= through else { return [] }
        var keys: [DayKey] = []
        var cursor = from
        while cursor <= through {
            keys.append(cursor)
            cursor = dayKey(byAdding: 1, to: cursor)
        }
        return keys
    }

    /// First day of the month containing `key`, and the number of days in that month.
    public func monthRange(containing key: DayKey) -> (first: DayKey, dayCount: Int) {
        let first = DayKey(year: key.year, month: key.month, day: 1)!
        return (first, DayKey.daysInMonth(year: key.year, month: key.month))
    }

    /// Local hour (0–23) of `date` in this time zone, used for the room's morning/day/night tint.
    public func hour(of date: Date) -> Int {
        calendar.component(.hour, from: date)
    }
}
