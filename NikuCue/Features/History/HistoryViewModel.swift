import Combine
import Foundation
import NikuCueDomain
import SwiftUI

/// A displayed month in the Gregorian calendar (the calendar of the stored day keys, docs/07 §5).
/// Presentation may still show a Thai Buddhist year; the key never does.
struct YearMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    init?(year: Int, month: Int) {
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        self.year = year
        self.month = month
    }

    init(containing day: DayKey) {
        self.year = day.year
        self.month = day.month
    }

    var firstDay: DayKey? { DayKey(year: year, month: month, day: 1) }
    var dayCount: Int { DayKey.daysInMonth(year: year, month: month) }

    var previous: YearMonth? {
        month == 1 ? YearMonth(year: year - 1, month: 12) : YearMonth(year: year, month: month - 1)
    }

    var next: YearMonth? {
        month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1)
    }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}

/// One cell of the seven-column month grid. `day == nil` is a leading blank before the first day of the month.
struct HistoryCell: Identifiable {
    let id: Int
    let day: DayKey?
    let kind: DayKind?
    let isToday: Bool
}

/// SF Symbol and label key for calendar kinds and day statuses. Status is always a shape plus a label,
/// never colour alone, and there is no red failure mark for unrecorded days (docs/03 §4).
enum HistoryGlyph {
    static func symbol(for kind: DayKind) -> String? {
        switch kind {
        case .hasDone: return "checkmark.circle.fill"
        case .restOnly: return "moon.zzz"
        case .unrecorded: return "circle"
        case .notScheduled: return "circle.fill" // rendered as a small dot
        case .future: return nil
        }
    }

    static func labelKey(for kind: DayKind) -> String? {
        switch kind {
        case .hasDone: return "history.done"
        case .restOnly: return "history.skipped"
        case .unrecorded: return "history.pending"
        case .notScheduled: return "history.notScheduled"
        case .future: return nil
        }
    }

    static func symbol(for status: DayStatus) -> String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "moon.zzz"
        case .pending: return "circle"
        case .notScheduled: return "minus.circle"
        }
    }

    static func labelKey(for status: DayStatus) -> String {
        switch status {
        case .done: return "history.done"
        case .skipped: return "history.skipped"
        case .pending: return "history.pending"
        case .notScheduled: return "history.notScheduled"
        }
    }
}

/// Display-only date formatting in the presentation locale (a Thai Buddhist year is fine here).
/// Dates come from `CalendarService.date(startOf:)` and are never parsed back into day keys.
struct HistoryDateFormatting {
    let locale: Locale
    let timeZone: TimeZone
    private let calendarService: CalendarService

    init(locale: Locale, timeZone: TimeZone) {
        self.locale = locale
        self.timeZone = timeZone
        self.calendarService = CalendarService(timeZone: timeZone)
    }

    /// e.g. "October 2026" / "ตุลาคม 2569" / "2026年10月".
    func monthTitle(_ month: YearMonth) -> String {
        guard let first = month.firstDay else { return "" }
        let formatter = makeFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: calendarService.date(startOf: first))
    }

    /// Full date for a day header and for VoiceOver.
    func dayTitle(_ day: DayKey) -> String {
        let formatter = makeFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: calendarService.date(startOf: day))
    }

    /// Short weekday names ordered Monday … Sunday (`Calendar` symbols are Sunday-first; ISO `iso` maps to index `iso % 7`).
    func weekdayHeaders() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "", count: 7) }
        return (1...7).map { symbols[$0 % 7] }
    }

    private func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = locale.calendar
        formatter.timeZone = timeZone
        return formatter
    }
}

/// Month calendar state (docs/02 §4, docs/03 §4). Reads only; corrections happen in `DayDetailViewModel`.
/// Nothing here talks to the cat coordinator: history never triggers reactions.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var displayed: YearMonth
    @Published private(set) var today: DayKey
    @Published private(set) var kinds: [DayKey: DayKind] = [:]
    @Published private(set) var distinctDoneDays = 0
    @Published private(set) var isLoading = false
    /// Localization key of the error to show (e.g. `error.database`).
    @Published var errorKey: String?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        let day = CalendarService(timeZone: container.clock.timeZone).dayKey(for: container.clock.now)
        today = day
        displayed = YearMonth(containing: day)
    }

    /// Months after the current one hold only future days, so navigation stops at today's month.
    var canShowNextMonth: Bool { displayed < YearMonth(containing: today) }

    func load() async {
        isLoading = kinds.isEmpty
        defer { isLoading = false }
        do {
            today = await container.habitService.today()
            kinds = try await container.habitService.monthKinds(year: displayed.year, month: displayed.month)
            distinctDoneDays = try await container.habitService.distinctDoneDays()
            errorKey = nil
        } catch {
            errorKey = "error.database"
        }
    }

    func showPreviousMonth() async {
        guard let previous = displayed.previous else { return }
        displayed = previous
        kinds = [:]
        await load()
    }

    func showNextMonth() async {
        guard canShowNextMonth, let next = displayed.next else { return }
        displayed = next
        kinds = [:]
        await load()
    }

    /// Grid starting on Monday: leading blanks, then one cell per day of the month.
    var cells: [HistoryCell] {
        guard let first = displayed.firstDay else { return [] }
        let calendar = CalendarService(timeZone: container.clock.timeZone)
        let leading = calendar.isoWeekday(of: first) - 1
        var result: [HistoryCell] = []
        if leading > 0 {
            for index in 0..<leading {
                result.append(HistoryCell(id: index, day: nil, kind: nil, isToday: false))
            }
        }
        for dayNumber in 1...displayed.dayCount {
            guard let day = DayKey(year: displayed.year, month: displayed.month, day: dayNumber) else { continue }
            result.append(HistoryCell(id: leading + dayNumber, day: day, kind: kinds[day], isToday: day == today))
        }
        return result
    }
}
