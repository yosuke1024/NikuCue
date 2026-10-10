import Foundation

/// A calendar day stored as `YYYY-MM-DD` in the proleptic Gregorian calendar with ASCII digits.
///
/// This is the only day representation persisted by NikuCue (docs/07 §5). Presentation may use the
/// Thai Buddhist calendar, but the stored year never becomes 2569.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a key from Gregorian components. Returns `nil` when the components do not form a valid date.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1,
              day <= DayKey.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses the strict `YYYY-MM-DD` form (exactly 10 ASCII characters).
    public init?(string: String) {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for i in range {
                let v = scalars[i].value
                guard v >= 48, v <= 57 else { return nil }
                value = value * 10 + Int(v - 48)
            }
            return value
        }
        guard let y = number(0..<4), let m = number(5..<7), let d = number(8..<10) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var string: String {
        func pad(_ v: Int, _ width: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public var description: String { string }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    // MARK: Codable (single string value)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = DayKey(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid DayKey: \(raw)")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    // MARK: Helpers

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }
}
