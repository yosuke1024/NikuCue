import Foundation
import NikuCueDomain

/// UMP consent state as the app needs it (docs/08 §3–§4). Never replaced by a home-made boolean.
enum ConsentStatus: Equatable, Sendable {
    case unknown
    case notRequired
    case required
    case obtained
}

/// Boundary over Google UMP. The real adapter lives in GoogleMobileAdsAdapter.swift and compiles only when the
/// GoogleMobileAds package is linked; until then `MockAdConsentService` keeps the app ad-free.
@MainActor
protocol AdConsentServicing: AnyObject {
    var status: ConsentStatus { get }
    /// True only after a successful consent info update that allows requests (UMP `canRequestAds`).
    var canRequestAds: Bool { get }
    /// True when the privacy options entry point must be offered in Settings.
    var privacyOptionsRequired: Bool { get }
    /// Updates consent info and shows the form if required. Called per launch for free users after the first real session.
    func gatherConsent() async
    /// Opens the privacy options form from Settings.
    func presentPrivacyOptions() async
    func addObserver(_ observer: @escaping () -> Void)
}

@MainActor
final class MockAdConsentService: AdConsentServicing {
    private(set) var status: ConsentStatus = .unknown
    var scriptedStatus: ConsentStatus = .notRequired
    var scriptedCanRequestAds = true
    private(set) var canRequestAds = false
    private(set) var privacyOptionsRequired = false
    private(set) var gatherCalls = 0
    private var observers: [() -> Void] = []

    init() {}

    func gatherConsent() async {
        gatherCalls += 1
        status = scriptedStatus
        canRequestAds = scriptedCanRequestAds && (status == .notRequired || status == .obtained)
        privacyOptionsRequired = status == .obtained
        observers.forEach { $0() }
    }

    func presentPrivacyOptions() async {}

    func addObserver(_ observer: @escaping () -> Void) { observers.append(observer) }

    func simulateWithdrawal() {
        status = .required
        canRequestAds = false
        observers.forEach { $0() }
    }
}

/// Decides when the one Home banner may exist and asks the ad adapter to load/destroy it (docs/08 §2–§3).
/// Recomputed whenever entitlement, consent or Home visibility changes; owned/unknown means no request.
@MainActor
final class BannerService: ObservableObject {
    @Published private(set) var isBannerActive = false
    /// Height reserved on Home while the banner is active; fixed per Home session (docs/08 §2).
    @Published private(set) var reservedHeight: CGFloat = 0
    private(set) var requestCount = 0

    private let configuration: AppConfiguration
    private let consent: any AdConsentServicing
    private let sdkPrivacyConfigurationVerified: Bool
    private let adapter: any BannerAdapting

    init(configuration: AppConfiguration, consent: any AdConsentServicing, adapter: any BannerAdapting, sdkPrivacyConfigurationVerified: Bool) {
        self.configuration = configuration
        self.consent = consent
        self.adapter = adapter
        self.sdkPrivacyConfigurationVerified = sdkPrivacyConfigurationVerified
    }

    func inputs(appState: AppState) -> AdGateInputs {
        AdGateInputs(configValid: adapter.isConfigured && !configuration.bannerAdUnitID.contains(AppConfiguration.placeholderMarker),
                     entitlement: appState.entitlement,
                     onboardingComplete: appState.preferences.isOnboardingComplete,
                     firstRealSessionFinished: appState.preferences.hasFinishedFirstSession,
                     homeVisible: appState.isHomeVisible,
                     sceneActive: appState.isSceneActive,
                     canRequestAds: consent.canRequestAds,
                     sdkPrivacyConfigurationVerified: sdkPrivacyConfigurationVerified)
    }

    /// Applies the gate: starts exactly one banner when allowed, destroys it otherwise. Never reloads per reaction.
    func evaluate(appState: AppState) {
        let allowed = AdGate.adsAllowed(inputs(appState: appState))
        if allowed, !isBannerActive {
            isBannerActive = true
            reservedHeight = adapter.bannerHeight
            requestCount += 1
            adapter.load(adUnitID: configuration.bannerAdUnitID)
        } else if !allowed, isBannerActive {
            isBannerActive = false
            reservedHeight = 0
            adapter.destroy()
        }
    }
}

/// Minimal surface the SDK adapter implements. Habit data never crosses this boundary.
@MainActor
protocol BannerAdapting: AnyObject {
    var isConfigured: Bool { get }
    var bannerHeight: CGFloat { get }
    func load(adUnitID: String)
    func destroy()
}

@MainActor
final class MockBannerAdapter: BannerAdapting {
    var isConfigured = true
    var bannerHeight: CGFloat = 50
    private(set) var loads: [String] = []
    private(set) var destroys = 0

    init() {}

    func load(adUnitID: String) { loads.append(adUnitID) }
    func destroy() { destroys += 1 }
}
