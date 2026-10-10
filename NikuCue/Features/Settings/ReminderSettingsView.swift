import NikuCueDomain
import SwiftUI
import UIKit

/// Reminder settings (docs/07 §1, §3, §4; docs/02 §1 O04): one switch, up to two times with weekdays, and the two
/// notes that reminders follow the chosen days even when today is already recorded and that delivery depends on
/// iPhone settings. Pushed from Settings inside its navigation stack.
///
/// `ReminderSettingsView` reads the container from the environment and hands it to `ReminderSettingsContent`,
/// which owns the view model (`@StateObject` cannot be built from an `@EnvironmentObject` inside `init`).
struct ReminderSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ReminderSettingsContent(container: container)
    }
}

/// The actual screen. Every write goes through `ReminderSettingsViewModel`; the view never touches the store.
struct ReminderSettingsContent: View {
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var vm: ReminderSettingsViewModel

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: ReminderSettingsViewModel(container: container))
    }

    var body: some View {
        Form {
            switchSection
            if vm.hasLoaded {
                ForEach(vm.slots) { slot in
                    slotSection(slot)
                }
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            addSection
        }
        .navigationTitle(localizer.t("settings.notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await vm.sceneBecameActive() }
        }
    }

    // MARK: Switch

    /// The OS prompt is requested only from this switch (docs/07 §4). A refusal keeps it off and shows the Settings route.
    private var switchSection: some View {
        Section {
            Toggle(isOn: Binding(get: { vm.remindersEnabled }, set: { on in Task { await vm.setRemindersEnabled(on) } })) {
                Text(localizer.t("reminder.enable"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .disabled(vm.isApplyingSwitch || !vm.hasLoaded)
            if vm.showsDeniedNotice {
                notice("reminder.denied", systemImage: "bell.slash")
                    .frame(minHeight: 44)
                Button {
                    openSettings()
                } label: {
                    Label(localizer.t("reminder.openSettings"), systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    // MARK: Slots

    /// One reminder time: picker (device 12/24-hour setting, no forced format), weekday chips, remove.
    private func slotSection(_ slot: ReminderSlot) -> some View {
        Section {
            DatePicker(localizer.t("reminder.time"),
                       selection: Binding(get: { vm.date(forSlot: slot.id) }, set: { vm.setTime(from: $0, for: slot.id) }),
                       displayedComponents: .hourAndMinute)
                .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.t("habit.days"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ReminderWeekdayChips(selected: slot.weekdays, locale: localizer.locale) { iso in
                    vm.toggleWeekday(iso, for: slot.id)
                }
            }
            .padding(.vertical, 4)
            Button(role: .destructive) {
                vm.removeSlot(id: slot.id)
            } label: {
                Label(localizer.t("common.delete"), systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    // MARK: Add, messages and notes

    private var addSection: some View {
        Section {
            Button {
                vm.addSlot()
            } label: {
                Label(localizer.t("reminder.add"), systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(!vm.hasLoaded)
            if vm.errorKey == "error.notification" {
                Button {
                    Task { await vm.retryReconcile() }
                } label: {
                    Label(localizer.t("common.retry"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if vm.showsLimitNotice {
                    notice("reminder.limit", systemImage: "info.circle")
                }
                if let key = vm.errorKey {
                    notice(key, systemImage: "exclamationmark.triangle")
                }
                // Always visible (docs/07 §1): delivery on the chosen days even after recording; OS settings apply.
                Text(localizer.t("reminder.scheduleNote"))
                    .fixedSize(horizontal: false, vertical: true)
                Text(localizer.t("reminder.systemNote"))
                    .fixedSize(horizontal: false, vertical: true)
                #if DEBUG
                if let count = vm.pendingRequestCount {
                    Text("Pending requests: \(count)")
                        .font(.caption.monospaced())
                }
                #endif
            }
        }
    }

    /// Icon + text, wrapping freely so Thai diacritics are never clipped; status never by colour alone.
    private func notice(_ key: String, systemImage: String) -> some View {
        Label(localizer.t(key), systemImage: systemImage)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

/// Seven chips, ISO Monday = 1 … Sunday = 7, labelled from the app locale's calendar symbols (Thai and Japanese
/// names included, presentation only; the stored value is the ISO set). Selection is shown by a check mark and
/// weight as well as tint, and exposed to VoiceOver as `isSelected`. The adaptive grid wraps at large text sizes.
private struct ReminderWeekdayChips: View {
    let selected: WeekdaySet
    let locale: Locale
    let onToggle: (Int) -> Void

    init(selected: WeekdaySet, locale: Locale, onToggle: @escaping (Int) -> Void) {
        self.selected = selected
        self.locale = locale
        self.onToggle = onToggle
    }

    var body: some View {
        let short = symbolsByISO(short: true)
        let long = symbolsByISO(short: false)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(1...7, id: \.self) { iso in
                chip(iso: iso, short: short[iso - 1], long: long[iso - 1])
            }
        }
    }

    private func chip(iso: Int, short: String, long: String) -> some View {
        let isOn = selected.contains(isoWeekday: iso)
        let traits: AccessibilityTraits = isOn ? .isSelected : []
        return Button {
            onToggle(iso)
        } label: {
            VStack(spacing: 2) {
                Text(short)
                    .font(.subheadline.weight(isOn ? .bold : .regular))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(isOn ? Color.accentColor : Color.secondary)
        .accessibilityLabel(long)
        .accessibilityAddTraits(traits)
    }

    /// Index 0 … 6 = ISO Monday … Sunday. `Calendar` symbols are Sunday-first, so ISO `iso` maps to `iso % 7`.
    private func symbolsByISO(short: Bool) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = short ? calendar.shortStandaloneWeekdaySymbols : calendar.standaloneWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "", count: 7) }
        return (1...7).map { symbols[$0 % 7] }
    }
}
