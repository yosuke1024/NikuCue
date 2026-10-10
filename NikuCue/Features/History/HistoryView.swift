import NikuCueDomain
import SwiftUI

/// Month calendar of little wins (docs/03 §4). `HomeView` pushes `HistoryView()` with no arguments; the
/// container comes from the environment and `HistoryContent` owns the view model (a `@StateObject`
/// cannot be built from an `@EnvironmentObject` inside `init`).
struct HistoryView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        HistoryContent(container: container)
    }
}

struct HistoryContent: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var vm: HistoryViewModel

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: HistoryViewModel(container: container))
    }

    private var formatting: HistoryDateFormatting {
        HistoryDateFormatting(locale: localizer.locale, timeZone: container.clock.timeZone)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                daysTogether
                if let key = vm.errorKey {
                    errorLine(key)
                }
                monthNavigation
                weekdayHeader
                grid
                legend
                Text(localizer.t("history.editHelp"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localizer.t("history.title"))
        .navigationBarTitleDisplayMode(.inline)
        // Re-runs after returning from a day's corrections, so the grid reflects them.
        .task { await vm.load() }
    }

    // MARK: Header

    /// "Days with a little win: N" — distinct days with at least one done; rest-only days do not count (docs/02 §4).
    private var daysTogether: some View {
        Label(localizer.t("history.daysTogether", ["count": String(vm.distinctDoneDays)]), systemImage: "pawprint")
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Month navigation

    private var monthNavigation: some View {
        HStack(spacing: 8) {
            Button {
                Task { await vm.showPreviousMonth() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(previousMonthTitle)

            Spacer(minLength: 8)
            Text(formatting.monthTitle(vm.displayed))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)

            Button {
                Task { await vm.showNextMonth() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(!vm.canShowNextMonth)
            .accessibilityLabel(nextMonthTitle)
        }
    }

    /// The buttons are icon-only; VoiceOver reads the month they navigate to (locale-formatted, not hard-coded).
    private var previousMonthTitle: String {
        vm.displayed.previous.map { formatting.monthTitle($0) } ?? ""
    }

    private var nextMonthTitle: String {
        vm.displayed.next.map { formatting.monthTitle($0) } ?? ""
    }

    // MARK: Grid

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(formatting.weekdayHeaders().enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHidden(true) // each cell already reads its full date
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(vm.cells) { cell in
                if let day = cell.day {
                    dayCell(day: day, kind: cell.kind, isToday: cell.isToday)
                } else {
                    Color.clear
                        .frame(minHeight: 44)
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay {
            if vm.isLoading {
                ProgressView()
            }
        }
    }

    /// Future days are dimmed and not tappable (docs/02 §4: never editable); every other day opens its breakdown.
    private func dayCell(day: DayKey, kind: DayKind?, isToday: Bool) -> some View {
        // The kind map is empty while loading, so the day key decides too (future days are never editable, docs/02 §4).
        let isFuture = kind == .future || day > vm.today
        return NavigationLink {
            DayDetailView(day: day)
        } label: {
            HistoryDayCell(dayNumber: String(day.day), kind: kind, isToday: isToday)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(cellAccessibilityLabel(day: day, kind: kind, isToday: isToday))
    }

    private func cellAccessibilityLabel(day: DayKey, kind: DayKind?, isToday: Bool) -> String {
        var parts = [formatting.dayTitle(day)]
        if isToday { parts.append(localizer.t("home.today")) }
        if let kind, let key = HistoryGlyph.labelKey(for: kind) { parts.append(localizer.t(key)) }
        return parts.joined(separator: ", ")
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(localizer.t("history.done")).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
            Label {
                Text(localizer.t("history.skipped")).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "moon.zzz").foregroundStyle(.secondary)
            }
            Label {
                Text(localizer.t("history.pending")).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            Label {
                Text(localizer.t("history.notScheduled")).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func errorLine(_ key: String) -> some View {
        Label(localizer.t(key), systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One day in the month grid: the day number plus a shape for its kind. Today is outlined.
/// Shape and label (via the parent's accessibility label) carry the state; colour is only an extra.
struct HistoryDayCell: View {
    let dayNumber: String
    let kind: DayKind?
    let isToday: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(dayNumber)
                .font(.body)
                .minimumScaleFactor(0.6)
            glyph
                .frame(minHeight: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.vertical, 4)
        .opacity(kind == .future ? 0.4 : 1)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .some(.hasDone):
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        case .some(.restOnly):
            Image(systemName: "moon.zzz")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .some(.unrecorded):
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .some(.notScheduled):
            Circle()
                .fill(Color.secondary)
                .frame(width: 5, height: 5)
        case .some(.future), .none:
            Color.clear
                .frame(width: 14, height: 14)
        }
    }
}
