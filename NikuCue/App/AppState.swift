import Combine
import Foundation
import NikuCueDomain
import SwiftUI

/// Observable app-wide state mirrored from the store: preferences, companion profile, entitlement and
/// the flags the ad gate needs. Writes go through `HabitService`; this type never caches unlocks.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var preferences = UserPreferences()
    @Published private(set) var companion = CompanionProfile()
    @Published var entitlement: EntitlementState = .unknown
    @Published var isHomeVisible = false {
        didSet { if isHomeVisible { hasShownHome = true } }
    }
    /// Home has been displayed at least once this launch (docs/08 §2 first-session rule); not persisted.
    @Published private(set) var hasShownHome = false
    /// Set when preferences/companion could not be read; RootView offers retry instead of restarting onboarding.
    @Published private(set) var loadError: String?
    @Published var isModalPresented = false
    @Published var isSceneActive = true
    @Published private(set) var hasLoaded = false
    /// The last Home day seen by the UI; used to detect midnight crossings (QA Q11).
    @Published private(set) var displayedDay: DayKey?

    private let habitService: HabitService
    private let localizer: Localizer

    init(habitService: HabitService, localizer: Localizer) {
        self.habitService = habitService
        self.localizer = localizer
    }

    func load() async {
        loadError = nil
        do {
            preferences = try await habitService.preferences()
            companion = try await habitService.companionProfile()
            localizer.setPreference(preferences.language)
            localizer.setNickname(companion.nickname)
        } catch {
            // Never treat a read failure as a fresh install (docs/03 §6): keep the error and let the user retry.
            loadError = String(describing: error)
        }
        hasLoaded = true
    }

    func updatePreferences(_ mutate: (inout UserPreferences) -> Void) async throws {
        var copy = preferences
        mutate(&copy)
        try await habitService.savePreferences(copy)
        preferences = copy
        localizer.setPreference(copy.language)
    }

    func refreshCompanion() async {
        if let c = try? await habitService.companionProfile() {
            companion = c
            localizer.setNickname(c.nickname)
        }
    }

    func setNickname(_ raw: String?) async throws {
        try await habitService.setNickname(raw)
        await refreshCompanion()
    }

    func noteDisplayedDay(_ day: DayKey) {
        displayedDay = day
    }

    /// Only a backgrounding after onboarding completed and Home was shown ends the first real session (docs/08 §2).
    func markFirstSessionFinishedIfNeeded() async {
        guard preferences.isOnboardingComplete, !preferences.hasFinishedFirstSession, hasShownHome else { return }
        try? await updatePreferences { $0.hasFinishedFirstSession = true }
    }

    var effectiveReduceMotion: Bool {
        preferences.reduceMotion || UIAccessibility.isReduceMotionEnabled
    }
}
