import NikuCueDomain
import SwiftUI

/// Create / edit sheet (docs/02 §2, docs/03 §3). Save and Cancel live in the navigation bar, so the keyboard
/// never hides them. Name and category apply immediately; weekday changes, archive and resume take effect
/// tomorrow and the sheet always says so while editing.
///
/// `HabitEditorSheet` reads the container from the environment and hands it to `HabitEditorContent`, which
/// owns the view model (`@StateObject` cannot be built from an `@EnvironmentObject` inside `init`).
struct HabitEditorSheet: View {
    @EnvironmentObject private var container: AppContainer
    let target: HomeViewModel.EditorTarget
    @State private var versions: [HabitScheduleVersion]?

    var body: some View {
        Group {
            if let versions {
                HabitEditorContent(container: container, target: target, versions: versions)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task {
            // Current weekdays / archived state come from the schedule versions (docs/02 §2).
            versions = (try? await container.habitService.scheduleVersions()) ?? []
        }
    }
}

struct HabitEditorContent: View {
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: HabitEditorViewModel

    init(container: AppContainer, target: HomeViewModel.EditorTarget, versions: [HabitScheduleVersion]) {
        let mode: HabitEditorViewModel.Mode
        switch target {
        case .new: mode = .create
        case .edit(let habit): mode = .edit(habit)
        }
        // Same day key the service would compute; never parsed back from a displayed date.
        let today = CalendarService(clock: container.clock).dayKey(for: container.clock.now)
        _vm = StateObject(wrappedValue: HabitEditorViewModel(mode: mode, service: container.habitService, today: today, versions: versions))
    }

    private var editedHabit: Habit? {
        if case .edit(let habit) = vm.mode { return habit }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = vm.error, error == .generic || error == .limit {
                    Section {
                        errorLabel(error.key)
                    }
                }
                nameSection
                categorySection
                daysSection
                if editedHabit != nil {
                    archiveSection
                    deleteSection
                }
            }
            .navigationTitle(editedHabit == nil ? localizer.t("habit.new") : localizer.t("common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizer.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.t("common.save")) {
                        Task {
                            if await vm.save() != nil { dismiss() }
                        }
                    }
                    .disabled(!vm.canSave || vm.isSaving)
                }
            }
            // Second step of the delete confirmation (docs/02 §2).
            .alert(Text(localizer.t("habit.deleteTitle")), isPresented: $vm.showDeleteConfirmation) {
                Button(localizer.t("common.delete"), role: .destructive) {
                    Task {
                        if await vm.delete() { dismiss() }
                    }
                }
                Button(localizer.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(localizer.t("habit.deleteBody"))
            }
            .interactiveDismissDisabled(vm.isSaving)
        }
    }

    // MARK: Name

    private var nameSection: some View {
        Section {
            TextField(localizer.t("habit.namePlaceholder"), text: $vm.name)
                .submitLabel(.done)
                .frame(minHeight: 44)
        } header: {
            Text(localizer.t("habit.name"))
        } footer: {
            if showNameGuidance {
                Label(localizer.t("habit.nameInvalid"), systemImage: "exclamationmark.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 1–40 extended grapheme clusters: shown after a failed save, or live once the name is too long.
    private var showNameGuidance: Bool {
        if vm.error == .name { return true }
        return vm.name.trimmingCharacters(in: .whitespacesAndNewlines).count > HabitValidation.nameMaxGraphemes
    }

    // MARK: Category

    private var categorySection: some View {
        Section(localizer.t("habit.category")) {
            ForEach(HabitCategory.allCases, id: \.self) { category in
                categoryRow(category)
            }
        }
    }

    private func categoryRow(_ category: HabitCategory) -> some View {
        let selected = vm.category == category
        return Button {
            vm.category = category
        } label: {
            HStack(spacing: 12) {
                Image(systemName: HabitCategoryIcon.symbol(for: category))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                Text(localizer.t(HabitCategoryIcon.labelKey(for: category)))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Days

    private var daysSection: some View {
        Section {
            Toggle(localizer.t("habit.everyDay"), isOn: Binding(get: { vm.everyDay }, set: { vm.setEveryDay($0) }))
                .frame(minHeight: 44)
            if !vm.everyDay {
                weekdayChips
            }
        } header: {
            Text(localizer.t("habit.days"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if vm.effectiveWeekdays.isEmpty || vm.error == .days {
                    Label(localizer.t("habit.daysInvalid"), systemImage: "exclamationmark.circle")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if editedHabit != nil {
                    // Always visible while editing (docs/03 §3): there is no way to change only today's schedule.
                    Text(localizer.t("habit.scheduleHelp"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// ISO Monday = 1 … Sunday = 7, labelled from the presentation locale's calendar (Thai / Japanese names included).
    private var weekdayChips: some View {
        let short = weekdaySymbols(short: true)
        let long = weekdaySymbols(short: false)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(1...7, id: \.self) { iso in
                weekdayChip(iso: iso, short: short[iso % 7], long: long[iso % 7])
            }
        }
        .padding(.vertical, 4)
    }

    private func weekdayChip(iso: Int, short: String, long: String) -> some View {
        let selected = vm.weekdays.contains(isoWeekday: iso)
        return Button {
            vm.toggle(iso)
        } label: {
            VStack(spacing: 2) {
                Text(short)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(selected ? Color.accentColor : Color.secondary)
        .accessibilityLabel(long)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// `Calendar` symbols are Sunday-first (index 0 … 6); ISO weekday `iso` maps to index `iso % 7`.
    private func weekdaySymbols(short: Bool) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = localizer.locale
        let symbols = short ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "", count: 7) }
        return symbols
    }

    // MARK: Archive / resume (edit mode)

    private var archiveSection: some View {
        Section {
            if vm.isArchived {
                Button {
                    Task {
                        if await vm.resume() { dismiss() }
                    }
                } label: {
                    Label(localizer.t("habit.resume"), systemImage: "arrow.uturn.forward")
                        .frame(minHeight: 44)
                }
            } else {
                Button {
                    Task {
                        if await vm.archive() { dismiss() }
                    }
                } label: {
                    Label(localizer.t("habit.archive"), systemImage: "archivebox")
                        .frame(minHeight: 44)
                }
            }
        } footer: {
            if !vm.isArchived {
                Text(localizer.t("habit.archiveHelp"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Delete (first step of the two-step confirmation)

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                vm.showDeleteConfirmation = true
            } label: {
                Label(localizer.t("common.delete"), systemImage: "trash")
                    .frame(minHeight: 44)
            }
        }
    }

    private func errorLabel(_ key: String) -> some View {
        Label(localizer.t(key), systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }
}
