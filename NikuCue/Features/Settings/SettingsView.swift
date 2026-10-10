import NikuCueDomain
import SwiftUI

/// Settings (docs/02 §8, docs/03 §5): cat name, language, haptics, Reduce Motion, reminders, ad removal,
/// ad privacy (P10), backup, privacy, help, version, diagnostics and the two-step full delete.
/// No sales pop-ups and no ads here. `HomeView` pushes `SettingsView()` with no arguments.
struct SettingsView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        SettingsContent(container: container)
    }
}

struct SettingsContent: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var vm: SettingsViewModel
    @ObservedObject private var appState: AppState
    @FocusState private var nameFieldFocused: Bool

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: SettingsViewModel(container: container))
        self.appState = container.appState
    }

    var body: some View {
        Form {
            if let key = vm.errorKey {
                Section {
                    errorLabel(key)
                }
            }
            catNameSection
            displaySection
            remindersSection
            purchaseSection
            dataSection
            helpSection
            aboutSection
            deleteSection
        }
        .navigationTitle(localizer.t("home.settings"))
        .navigationBarTitleDisplayMode(.inline)
        // Second step of the delete confirmation (docs/02 §8).
        .alert(Text(localizer.t("settings.deleteAllTitle")), isPresented: $vm.showDeleteConfirmation) {
            Button(localizer.t("common.delete"), role: .destructive) {
                Task { await vm.deleteAllData() }
            }
            Button(localizer.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(localizer.t("settings.deleteAllBody"))
        }
        .onAppear { vm.syncNicknameDraft() }
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused {
                Task { await vm.commitNickname() }
            }
        }
    }

    // MARK: Cat name

    private var catNameSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(localizer.t("settings.catName"), text: $vm.nicknameDraft, prompt: Text(localizer.t("cat.defaultName")))
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await vm.commitNickname() } }
                    .frame(minHeight: 44)
                if vm.showNameSaved {
                    Label(localizer.t("home.saved"), systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text(localizer.t("settings.catName"))
        } footer: {
            if let key = vm.nicknameErrorKey {
                Label(localizer.t(key), systemImage: "exclamationmark.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Language / haptics / motion

    private var displaySection: some View {
        Section {
            Picker(localizer.t("settings.language"), selection: languageBinding) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(vm.languageLabel(language, localizer: localizer)).tag(language)
                }
            }
            .frame(minHeight: 44)
            Toggle(localizer.t("settings.haptics"), isOn: hapticsBinding)
                .frame(minHeight: 44)
            Toggle(localizer.t("settings.reduceMotion"), isOn: reduceMotionBinding)
                .frame(minHeight: 44)
        } footer: {
            Text(localizer.t("settings.reduceMotionHelp"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { appState.preferences.language },
                set: { value in Task { await vm.setLanguage(value) } })
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(get: { appState.preferences.hapticsEnabled },
                set: { value in Task { await vm.setHaptics(value) } })
    }

    private var reduceMotionBinding: Binding<Bool> {
        Binding(get: { appState.preferences.reduceMotion },
                set: { value in Task { await vm.setReduceMotion(value) } })
    }

    private var diagnosticsBinding: Binding<Bool> {
        Binding(get: { appState.preferences.diagnosticsEnabled },
                set: { value in Task { await vm.setDiagnostics(value) } })
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            // Written by the notifications agent (NikuCue/Features/Settings/ReminderSettingsView.swift).
            NavigationLink {
                ReminderSettingsView()
            } label: {
                Label(localizer.t("settings.notifications"), systemImage: "bell")
                    .frame(minHeight: 44)
            }
        }
    }

    // MARK: Purchase / ad privacy

    private var purchaseSection: some View {
        Section {
            NavigationLink {
                PurchaseView()
            } label: {
                Label(localizer.t("purchase.title"), systemImage: "xmark.rectangle")
                    .frame(minHeight: 44)
            }
            // P10: opens the UMP privacy options form once the ads SDK is linked. Disabled until then.
            Button {
            } label: {
                Label(localizer.t("settings.adPrivacy"), systemImage: "shield")
                    .frame(minHeight: 44)
            }
            .disabled(true)
        }
    }

    // MARK: Backup / privacy

    private var dataSection: some View {
        Section {
            NavigationLink {
                BackupView()
            } label: {
                Label(localizer.t("settings.backup"), systemImage: "externaldrive")
                    .frame(minHeight: 44)
            }
            NavigationLink {
                PrivacyView()
            } label: {
                Label(localizer.t("settings.privacy"), systemImage: "lock")
                    .frame(minHeight: 44)
            }
        }
    }

    // MARK: Help

    /// Support contact appears only once the owner replaced the placeholders; the ad report row waits for P10.
    private var helpSection: some View {
        Section {
            if let url = vm.supportURL {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(localizer.t("settings.help"), systemImage: "questionmark.circle")
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
            }
            if let mail = vm.supportMailURL, let email = vm.supportEmail {
                Link(destination: mail) {
                    Label(email, systemImage: "envelope")
                        .frame(minHeight: 44)
                }
            }
            Button {
            } label: {
                Label(localizer.t("settings.reportAd"), systemImage: "exclamationmark.bubble")
                    .frame(minHeight: 44)
            }
            .disabled(true)
        } header: {
            Text(localizer.t("settings.help"))
        }
    }

    // MARK: Version / diagnostics

    private var aboutSection: some View {
        Section {
            LabeledContent(localizer.t("settings.version")) {
                Text(vm.versionText)
            }
            .frame(minHeight: 44)
            Toggle(localizer.t("settings.diagnostics"), isOn: diagnosticsBinding)
                .frame(minHeight: 44)
        } footer: {
            Text(localizer.t("settings.diagnosticsHelp"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Delete all (first step)

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                vm.showDeleteConfirmation = true
            } label: {
                Label(localizer.t("settings.deleteAll"), systemImage: "trash")
                    .frame(minHeight: 44)
            }
            .disabled(vm.isDeleting)
        }
    }

    private func errorLabel(_ key: String) -> some View {
        Label(localizer.t(key), systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }
}
