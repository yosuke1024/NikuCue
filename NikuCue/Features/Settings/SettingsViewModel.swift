import Combine
import Foundation
import NikuCueDomain
import UIKit

/// Settings screen logic (docs/02 §8, docs/03 §5). Every write goes through `AppState` / `HabitService`;
/// side effects (haptics switch, Reduce Motion on the scene, reminder text after a language change,
/// notification cancellation after a full delete) are applied here after the save succeeds.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var nicknameDraft: String
    /// `settings.nameInvalid` or `error.save`.
    @Published var nicknameErrorKey: String?
    @Published private(set) var showNameSaved = false
    /// Localization key of a general error (`error.save`, `error.notification`).
    @Published var errorKey: String?
    @Published var showDeleteConfirmation = false
    @Published private(set) var isDeleting = false

    static let savedIndicatorDuration: TimeInterval = 2

    private let container: AppContainer
    private var isSavingName = false
    private var savedTimer: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
        nicknameDraft = container.appState.companion.nickname ?? ""
    }

    var appState: AppState { container.appState }
    var configuration: AppConfiguration { container.configuration }

    // MARK: Cat name

    /// Resets the draft to the stored nickname (empty when the default name is in use).
    func syncNicknameDraft() {
        nicknameDraft = appState.companion.nickname ?? ""
    }

    /// Saves on commit. Blank restores the localized default; 1–16 extended graphemes otherwise (docs/02 O02).
    func commitNickname() async {
        guard !isSavingName else { return }
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let desired: String? = trimmed.isEmpty ? nil : trimmed
        guard desired != appState.companion.nickname else {
            nicknameDraft = desired ?? ""
            return
        }
        isSavingName = true
        defer { isSavingName = false }
        nicknameErrorKey = nil
        do {
            try await appState.setNickname(desired)
            nicknameDraft = appState.companion.nickname ?? ""
            flashNameSaved()
        } catch HabitServiceError.validation {
            nicknameErrorKey = "settings.nameInvalid"
        } catch {
            nicknameErrorKey = "error.save"
        }
    }

    // MARK: Language

    /// Picker labels: the device-setting option is localized; the three languages show their own name.
    /// The autonyms come from the OS (`Locale.localizedString(forLanguageCode:)`), with the task-specified fallbacks.
    func languageLabel(_ language: AppLanguage, localizer: Localizer) -> String {
        switch language {
        case .system: return localizer.t("settings.system")
        case .th: return SettingsViewModel.autonym(code: "th", fallback: "ไทย")
        case .en: return SettingsViewModel.autonym(code: "en", fallback: "English")
        case .ja: return SettingsViewModel.autonym(code: "ja", fallback: "日本語")
        }
    }

    private static func autonym(code: String, fallback: String) -> String {
        let name = Locale(identifier: code).localizedString(forLanguageCode: code) ?? ""
        return name.isEmpty ? fallback : name
    }

    func setLanguage(_ language: AppLanguage) async {
        guard language != appState.preferences.language else { return }
        errorKey = nil
        do {
            try await appState.updatePreferences { $0.language = language }
        } catch {
            errorKey = "error.save"
            return
        }
        await reconcileReminderText()
    }

    /// Pending reminders are re-registered with the new language's text (docs/07 §3, QA Q21).
    /// `AppState.updatePreferences` already switched the shared localizer, so the strings below are in the new language.
    private func reconcileReminderText() async {
        do {
            let slots = try await container.habitService.reminderSlots()
            let localizer = container.localizer
            _ = try await container.notifications.reconcile(slots: slots,
                                                            remindersEnabled: appState.preferences.remindersEnabled,
                                                            title: localizer.t("reminder.notificationTitle"),
                                                            body: localizer.t("reminder.notificationBody"))
        } catch {
            errorKey = "error.notification"
        }
    }

    // MARK: Toggles

    func setHaptics(_ enabled: Bool) async {
        await update { $0.hapticsEnabled = enabled }
        container.haptics.isEnabled = appState.preferences.hapticsEnabled
    }

    func setReduceMotion(_ enabled: Bool) async {
        await update { $0.reduceMotion = enabled }
        applyReduceMotion()
    }

    /// App setting OR OS setting (docs/03 §7).
    func applyReduceMotion() {
        container.scene.controller.reduceMotion = appState.preferences.reduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    func setDiagnostics(_ enabled: Bool) async {
        await update { $0.diagnosticsEnabled = enabled }
    }

    private func update(_ mutate: (inout UserPreferences) -> Void) async {
        errorKey = nil
        do {
            try await appState.updatePreferences(mutate)
        } catch {
            errorKey = "error.save"
        }
    }

    // MARK: About / help

    var versionText: String {
        "\(configuration.marketingVersion) (\(configuration.buildNumber))"
    }

    /// Support links appear only once the owner replaced the placeholders (CLAUDE.md: never guess URLs).
    var supportURL: URL? { SettingsViewModel.configuredURL(configuration.supportURL) }

    var supportEmail: String? {
        configuration.supportEmail.contains(AppConfiguration.placeholderMarker) ? nil : configuration.supportEmail
    }

    var supportMailURL: URL? {
        guard let email = supportEmail, !email.isEmpty else { return nil }
        return URL(string: "mailto:\(email)")
    }

    var hasSupportContact: Bool { supportURL != nil || supportMailURL != nil }

    static func configuredURL(_ raw: String) -> URL? {
        guard !raw.contains(AppConfiguration.placeholderMarker),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    // MARK: Delete all

    /// Second step of the two-step confirmation: habits, records, companion, preferences and reminders go;
    /// the StoreKit entitlement is not stored here and survives (docs/02 §8). `AppState.load()` then shows onboarding.
    func deleteAllData() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        errorKey = nil
        do {
            try await container.habitService.deleteAllUserData()
        } catch {
            errorKey = "error.save"
            return
        }
        await container.notifications.cancelAll()
        container.haptics.isEnabled = true
        await appState.load()
        applyReduceMotion()
        container.reevaluateAdGate()
    }

    private func flashNameSaved() {
        savedTimer?.cancel()
        showNameSaved = true
        savedTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SettingsViewModel.savedIndicatorDuration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.showNameSaved = false
        }
    }
}
