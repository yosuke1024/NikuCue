import NikuCueDomain
import SwiftUI
import UIKit

// MARK: - O01 intro

/// The cat sits and introduces itself. "Start" begins the flow; "Meet your cat first" pushes the record-free demo.
struct OnboardingIntroStep: View {
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject var model: OnboardingViewModel
    @ObservedObject var controller: CatSceneController

    init(model: OnboardingViewModel, controller: CatSceneController) {
        _model = ObservedObject(wrappedValue: model)
        _controller = ObservedObject(wrappedValue: controller)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizer.t("onboarding.title"))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                CatRoom(height: 240)
                bubble
                Button {
                    model.startTapped()
                } label: {
                    Text(localizer.t("common.start"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                Button {
                    model.demoTapped()
                } label: {
                    Text(localizer.t("onboarding.demo"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
            }
            .padding(16)
        }
        .navigationTitle(localizer.t("app.name"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.introAppeared() }
        .onDisappear { model.introDisappeared() }
    }

    /// SwiftUI text, never baked into the scene (docs/03 §2). A pet reaction replaces the introduction while it plays.
    private var bubble: some View {
        let message = controller.messageKey.map { localizer.t($0) } ?? localizer.t("onboarding.intro")
        return Text(message)
            .font(.body)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
            .animation(.easeInOut(duration: 0.2), value: controller.messageKey)
    }
}

// MARK: - O02 name

/// Cat nickname: blank keeps the localized default, otherwise 1–16 grapheme clusters (docs/02 §1 O02).
struct OnboardingNameStep: View {
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject var model: OnboardingViewModel
    @FocusState private var isNameFocused: Bool

    init(model: OnboardingViewModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizer.t("onboarding.nameTitle"))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(localizer.t("onboarding.nameHelp"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(localizer.t("settings.catName"), text: $model.nameText, prompt: Text(localizer.t("cat.defaultName")))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { Task { await model.submitName() } }
                    .frame(minHeight: 44)
                    .accessibilityLabel(localizer.t("settings.catName"))
                if let key = model.nameErrorKey {
                    OnboardingNotice(text: localizer.t(key), systemImage: "exclamationmark.circle")
                }
                Button {
                    isNameFocused = false
                    Task { await model.submitName() }
                } label: {
                    Text(localizer.t("common.next"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .modifier(OnboardingStepChrome(model: model))
    }
}

// MARK: - O03 first habit

/// Template or free text, category, weekdays (docs/02 §1 O03, §2). Saves through `HabitEditorViewModel`.
/// Templates come from the localization tables and never prescribe amounts.
struct OnboardingHabitStep: View {
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject var model: OnboardingViewModel
    @ObservedObject var editor: HabitEditorViewModel
    @FocusState private var isNameFocused: Bool

    private struct Template: Identifiable {
        let category: HabitCategory
        let titleKey: String
        var id: String { category.rawValue }
    }

    private static let templates: [Template] = [
        Template(category: .water, titleKey: "template.water"),
        Template(category: .stretch, titleKey: "template.stretch"),
        Template(category: .read, titleKey: "template.read"),
        Template(category: .tidy, titleKey: "template.tidy"),
        Template(category: .custom, titleKey: "habit.category.custom"),
    ]

    init(model: OnboardingViewModel, editor: HabitEditorViewModel) {
        _model = ObservedObject(wrappedValue: model)
        _editor = ObservedObject(wrappedValue: editor)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizer.t("onboarding.habitTitle"))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(localizer.t("onboarding.habitHelp"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let habit = model.createdHabit {
                    savedSummary(habit)
                } else {
                    templateList
                    nameField
                    scheduleSection
                    if let error = editor.error {
                        OnboardingNotice(text: localizer.t(error.key), systemImage: "exclamationmark.circle")
                    }
                }
                Button {
                    isNameFocused = false
                    Task { await model.submitHabit() }
                } label: {
                    Text(localizer.t("common.next"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || editor.isSaving)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .modifier(OnboardingStepChrome(model: model))
        .task { await model.loadExistingHabitIfNeeded() }
    }

    private var templateList: some View {
        VStack(spacing: 8) {
            ForEach(OnboardingHabitStep.templates) { template in
                OnboardingTemplateRow(
                    title: localizer.t(template.titleKey),
                    systemImage: OnboardingHabitStep.symbol(for: template.category),
                    isSelected: editor.category == template.category
                ) {
                    apply(template)
                }
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizer.t("habit.name"))
                .font(.headline)
            TextField(localizer.t("habit.name"), text: $editor.name, prompt: Text(localizer.t("habit.namePlaceholder")))
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($isNameFocused)
                .frame(minHeight: 44)
                .accessibilityLabel(localizer.t("habit.name"))
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { editor.everyDay }, set: { editor.setEveryDay($0) })) {
                Text(localizer.t("habit.everyDay"))
            }
            .frame(minHeight: 44)
            Text(localizer.t("habit.days"))
                .font(.headline)
            OnboardingWeekdayChips(selected: editor.effectiveWeekdays) { editor.toggle($0) }
        }
    }

    /// Shown when the habit already exists (Back from the reminder step, or resume after a crash).
    private func savedSummary(_ habit: Habit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: OnboardingHabitStep.symbol(for: habit.category))
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(localizer.t("habit.category.\(habit.category.rawValue)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label(localizer.t("home.saved"), systemImage: "checkmark.circle.fill")
                    .font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
    }

    private func apply(_ template: Template) {
        editor.error = nil
        if template.category == .custom {
            // Keep text the person typed; only clear a template name so the field is ready for their own words.
            let templateNames = OnboardingHabitStep.templates
                .filter { $0.category != .custom }
                .map { localizer.t($0.titleKey) }
            let name = templateNames.contains(editor.name) ? "" : editor.name
            editor.applyTemplate(category: .custom, name: name)
            isNameFocused = true
        } else {
            editor.applyTemplate(category: template.category, name: localizer.t(template.titleKey))
            isNameFocused = false
        }
    }

    static func symbol(for category: HabitCategory) -> String {
        HabitCategoryIcon.symbol(for: category) // one category → icon map for onboarding, Home and History
    }
}

// MARK: - O04 reminder

/// Value of reminders, a time and weekdays. "Confirm" is the only path to the OS prompt; "Not now" goes to Home.
struct OnboardingReminderStep: View {
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: OnboardingViewModel

    init(model: OnboardingViewModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizer.t("onboarding.reminderTitle"))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(localizer.t("onboarding.reminderHelp"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.reminderDenied {
                    deniedSection
                } else {
                    pickerSection
                    if let key = model.reminderErrorKey {
                        OnboardingNotice(text: localizer.t(key), systemImage: "exclamationmark.circle")
                    }
                    confirmButtons
                }
                if let key = model.finishErrorKey {
                    OnboardingNotice(text: localizer.t(key), systemImage: "exclamationmark.circle")
                }
            }
            .padding(16)
        }
        .modifier(OnboardingStepChrome(model: model))
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizer.t("reminder.time"))
                .font(.headline)
            DatePicker(localizer.t("reminder.time"), selection: $model.reminderTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, localizer.locale)
                .environment(\.timeZone, model.timeZone)
                .frame(maxWidth: .infinity)
            Text(localizer.t("habit.days"))
                .font(.headline)
            OnboardingWeekdayChips(selected: model.reminderWeekdays) { model.toggleReminderDay($0) }
            Text(localizer.t("reminder.systemNote"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await model.confirmReminder() }
            } label: {
                Text(localizer.t("common.confirm"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
            Button {
                Task { await model.finishTapped() }
            } label: {
                Text(localizer.t("common.notNow"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)
        }
    }

    /// Permission refused: explain once, offer iPhone Settings, and let the person continue (docs/03 §6).
    private var deniedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingNotice(text: localizer.t("reminder.denied"), systemImage: "bell.slash")
            Button {
                openSettings()
            } label: {
                Text(localizer.t("reminder.openSettings"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button {
                Task { await model.finishTapped() }
            } label: {
                Text(localizer.t("onboarding.finish"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
