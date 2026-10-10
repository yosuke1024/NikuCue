import NikuCueDomain
import SwiftUI

/// One day's breakdown with corrections inside the seven-day window (docs/02 §3–§4, docs/03 §4).
/// Pushed from the month grid as `DayDetailView(day:)`; `DayDetailContent` owns the view model.
struct DayDetailView: View {
    @EnvironmentObject private var container: AppContainer
    let day: DayKey

    var body: some View {
        DayDetailContent(container: container, day: day)
    }
}

struct DayDetailContent: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var vm: DayDetailViewModel

    init(container: AppContainer, day: DayKey) {
        _vm = StateObject(wrappedValue: DayDetailViewModel(container: container, day: day))
    }

    private var formatting: HistoryDateFormatting {
        HistoryDateFormatting(locale: localizer.locale, timeZone: container.clock.timeZone)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                feedback
                rows
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localizer.t("history.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .animation(.easeInOut(duration: 0.2), value: vm.showSaved)
    }

    // MARK: Header

    /// Full date in the presentation locale (Thai Buddhist year allowed); the key itself is never shown or parsed.
    private var header: some View {
        Text(formatting.dayTitle(vm.day))
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var feedback: some View {
        if let key = vm.errorKey {
            noticeLine(key, systemImage: "exclamationmark.triangle")
        }
        if vm.showSaved {
            noticeLine("home.saved", systemImage: "checkmark.circle.fill")
        }
        if let summary = vm.summary {
            if summary.isEditable {
                Text(localizer.t("history.editHelp"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(localizer.t("history.readOnly"), systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        if let summary = vm.summary {
            if summary.rows.isEmpty {
                // Nothing was scheduled that day: a quiet note, never a zero score (docs/02 §4).
                Label(localizer.t("history.notScheduled"), systemImage: "leaf")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(summary.rows) { row in
                        DayDetailRow(row: row,
                                     isEditable: summary.isEditable,
                                     isBusy: vm.busyHabitIds.contains(row.id),
                                     onDone: { Task { await vm.apply(.done, to: row.id) } },
                                     onRest: { Task { await vm.apply(.skipped, to: row.id) } },
                                     onUndo: { Task { await vm.apply(.clear, to: row.id) } })
                    }
                }
                if let line = vm.progressLine(localizer: localizer) {
                    Label(line, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func noticeLine(_ key: String, systemImage: String) -> some View {
        Label(localizer.t(key), systemImage: systemImage)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One habit on the chosen day: category icon, name, status (icon + label) and, inside the editable window,
/// the correction buttons for its current status (docs/02 §3 table). Tapping the row itself never writes.
struct DayDetailRow: View {
    @EnvironmentObject private var localizer: Localizer
    let row: HomeHabitRow
    let isEditable: Bool
    let isBusy: Bool
    let onDone: () -> Void
    let onRest: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: HabitCategoryIcon.symbol(for: row.habit.category))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, minHeight: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.habit.name)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.habit.category != .custom {
                        Text(localizer.t(HabitCategoryIcon.labelKey(for: row.habit.category)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Label(localizer.t(HistoryGlyph.labelKey(for: row.status)), systemImage: HistoryGlyph.symbol(for: row.status))
                        .font(.subheadline)
                        .foregroundStyle(row.status == .done ? Color.accentColor : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isEditable {
                controls
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch row.status {
            case .pending:
                actionButton("common.done", systemImage: "checkmark.circle", action: onDone)
                actionButton("common.rest", systemImage: "moon.zzz", action: onRest)
            case .done:
                actionButton("common.undo", systemImage: "arrow.uturn.backward", action: onUndo)
            case .skipped:
                actionButton("common.done", systemImage: "checkmark.circle", action: onDone)
                actionButton("common.undo", systemImage: "arrow.uturn.backward", action: onUndo)
            case .notScheduled:
                EmptyView()
            }
        }
    }

    private func actionButton(_ key: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(localizer.t(key), systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
        .accessibilityHint(row.habit.name)
    }
}
