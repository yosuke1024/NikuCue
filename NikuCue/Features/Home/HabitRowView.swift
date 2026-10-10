import NikuCueDomain
import SwiftUI

/// SF Symbol and label key for each category. Icons are always shown together with a label (docs/03 §3).
enum HabitCategoryIcon {
    static func symbol(for category: HabitCategory) -> String {
        switch category {
        case .water: return "drop"
        case .stretch: return "figure.walk"
        case .read: return "book"
        case .tidy: return "tray"
        case .custom: return "star"
        }
    }

    /// Localization key `habit.category.<raw>`.
    static func labelKey(for category: HabitCategory) -> String {
        "habit.category.\(category.rawValue)"
    }
}

/// One of today's habits (docs/03 §2). Only the explicit buttons write; tapping the row itself never marks
/// anything. Status is shown with an icon and a text label, never with colour alone.
struct HabitRowView: View {
    @EnvironmentObject private var localizer: Localizer
    let row: HomeHabitRow
    /// A write for this habit is in flight: the Done / Undo buttons are disabled so a double tap cannot start a second write.
    let isBusy: Bool
    let onDone: () -> Void
    let onUndo: () -> Void
    let onRest: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: HabitCategoryIcon.symbol(for: row.habit.category))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .padding(.top, 12)
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
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            primaryControl
                .padding(.top, 6)
            menu
                .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        switch row.status {
        case .done:
            HStack(spacing: 12) {
                Label(localizer.t("common.done"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
                undoButton
            }
        case .skipped:
            HStack(spacing: 12) {
                Label(localizer.t("history.skipped"), systemImage: "moon.zzz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                undoButton
            }
        case .pending, .notScheduled:
            EmptyView()
        }
    }

    /// Clears a done record (quiet undo) or a rest day (docs/02 §3).
    private var undoButton: some View {
        Button {
            onUndo()
        } label: {
            Text(localizer.t("common.undo"))
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isBusy)
    }

    // MARK: Controls

    @ViewBuilder
    private var primaryControl: some View {
        switch row.status {
        case .done:
            // Filled check: an indicator, not a button. Undo is the text button in the status line.
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)
        case .pending, .skipped:
            Button {
                onDone()
            } label: {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(localizer.t("common.done"))
            .accessibilityHint(row.habit.name)
        case .notScheduled:
            EmptyView()
        }
    }

    private var menu: some View {
        Menu {
            if row.status == .pending {
                Button {
                    onRest()
                } label: {
                    Label(localizer.t("common.rest"), systemImage: "moon.zzz")
                }
                .disabled(isBusy)
            }
            Button {
                onEdit()
            } label: {
                Label(localizer.t("common.edit"), systemImage: "pencil")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(localizer.t("common.edit"))
        .accessibilityHint(row.habit.name)
    }
}
