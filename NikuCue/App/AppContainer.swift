import Combine
import Foundation
import NikuCueDomain
import SpriteKit
import SwiftData
import SwiftUI
import UserNotifications

/// Composition root. Builds the clock, repository, services, localizer and the single cat scene.
/// Views never touch the repository or a ModelContext directly (docs/06 §5).
@MainActor
final class AppContainer: ObservableObject {
    enum StoreMode {
        case persistent
        case inMemory
    }

    let configuration: AppConfiguration
    let clock: any Clock
    let repository: any HabitRepository
    let habitService: HabitService
    let localizer: Localizer
    let appState: AppState
    let notifications: any NotificationScheduling
    let notificationDelegate = NotificationDelegate()
    let haptics: HapticsService
    let purchase: any PurchaseServicing
    let adConsent: any AdConsentServicing
    let banner: BannerService
    let reactionCatalog: ReactionCatalog
    let rigSpec: RigSpec
    let artPaths: ArtPaths
    let animationSpec: AnimationSpec
    let artProvider: VectorArtProvider
    let rig: CatRig
    let scene: CatScene
    let catCoordinator: CatCoordinator
    let modelContainer: ModelContainer?
    /// Set when the on-device store could not be opened. The store is never deleted; the UI offers retry (docs/03 §6).
    let databaseError: String?
    /// Problems found while validating the bundled contracts at start-up (shown in Debug only).
    let contractProblems: [String]

    init(configuration: AppConfiguration = .current, storeMode: StoreMode = .persistent,
         repository overrideRepository: (any HabitRepository)? = nil, clock: any Clock = SystemClock(),
         notifications: (any NotificationScheduling)? = nil) throws {
        self.configuration = configuration
        self.clock = clock

        var dbError: String?
        var container: ModelContainer?
        let repo: any HabitRepository
        if let overrideRepository {
            repo = overrideRepository
        } else {
            do {
                let built = try NikuCueStore.makeContainer(inMemory: storeMode == .inMemory)
                container = built
                repo = SwiftDataHabitRepository(modelContainer: built)
            } catch {
                dbError = String(describing: error)
                repo = InMemoryHabitRepository()
            }
        }
        modelContainer = container
        databaseError = dbError
        self.repository = repo
        habitService = HabitService(repository: repo, clock: clock)
        localizer = Localizer(catalog: try Localizer.loadBundled())
        self.notifications = notifications ?? (AppConfiguration.isDebugBuild && overrideRepository != nil ? MockNotificationScheduler() : LocalNotificationService())
        haptics = HapticsService()

        // Monetization: StoreKit 2 for the one ad-removal product; the local .storekit configuration serves Debug.
        // Ads stay on mocks (no requests) until the owner links the Google Mobile Ads package (GoogleMobileAdsAdapter.swift).
        if overrideRepository != nil {
            purchase = MockPurchaseService()
        } else {
            purchase = StoreKitPurchaseService(productID: configuration.removeAdsProductID)
        }
        #if canImport(GoogleMobileAds)
        let consentService: any AdConsentServicing = UMPConsentService()
        let bannerAdapter: any BannerAdapting = GoogleBannerAdapter()
        #else
        let consentService: any AdConsentServicing = MockAdConsentService()
        let bannerAdapter: any BannerAdapting = MockBannerAdapter()
        #endif
        adConsent = consentService
        // Verified only once the SDK's privacy manifest has been reviewed against PrivacyInfo.xcprivacy (R08).
        banner = BannerService(configuration: configuration, consent: consentService, adapter: bannerAdapter, sdkPrivacyConfigurationVerified: false)

        reactionCatalog = try ReactionCatalog.load(from: try BundledResources.data(named: "reactions", extension: "json", subdirectory: "Reactions"))
        rigSpec = try RigSpec.load(from: try BundledResources.data(named: "character_spec", extension: "json", subdirectory: "Character"))
        artPaths = try ArtPaths.load(from: try BundledResources.data(named: "mali_paths", extension: "json", subdirectory: "Character"))
        animationSpec = try AnimationSpec.load(from: try BundledResources.data(named: "animations", extension: "json", subdirectory: "Character"))

        var problems = rigSpec.validate()
        problems += animationSpec.validate(against: rigSpec)
        problems += reactionCatalog.validate(knownMessageKeys: Set(localizer.catalog.tables["en"]?.keys.map { $0 } ?? []))
        contractProblems = problems

        artProvider = VectorArtProvider(paths: artPaths)
        // Textures are rendered for a ≈300 pt room at the device scale; the rig is scaled as a whole.
        let unitsPerPoint = rigSpec.canvas.height / 300
        let pixelsPerUnit = CGFloat(1 / unitsPerPoint) * UIScreen.main.scale
        rig = CatRig(spec: rigSpec, art: artProvider, pixelsPerUnit: pixelsPerUnit)
        let library = AnimationLibrary(spec: animationSpec)
        scene = CatScene(size: CGSize(width: 390, height: 260), rig: rig, library: library, seed: UInt64.random(in: 0...UInt64.max))
        appState = AppState(habitService: habitService, localizer: localizer)
        catCoordinator = CatCoordinator(scene: scene, habitService: habitService, catalog: reactionCatalog, clock: clock)

        // Entitlement flows into app state; the ad gate is re-evaluated whenever its inputs change (docs/06 §6).
        purchase.addObserver { [weak self] state in
            guard let self else { return }
            self.appState.entitlement = state
            self.banner.evaluate(appState: self.appState)
        }
        purchase.start()
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    /// Call when Home visibility, scene activity, consent or preferences change.
    func reevaluateAdGate() {
        banner.evaluate(appState: appState)
    }

    /// Free users only, after the first real session: update consent info (shows the UMP form if required).
    func gatherConsentIfNeeded() async {
        guard appState.entitlement == .notOwned, appState.preferences.hasFinishedFirstSession else { return }
        appState.isModalPresented = true
        scene.controller.setPaused(true)
        await adConsent.gatherConsent()
        appState.isModalPresented = false
        scene.controller.setPaused(false)
        reevaluateAdGate()
    }

    /// Demo path (onboarding "meet the cat", gallery): no statistics, no milestone tokens.
    func dispatchDemo(kind: CatEventKind, category: HabitCategory? = nil) {
        catCoordinator.dispatchDemo(kind: kind, category: category)
    }

    var currentTimeOfDay: TimeOfDay {
        TimeOfDay(hour: CalendarService(clock: clock).hour(of: clock.now))
    }

    var backupService: BackupService {
        BackupService(habitService: habitService, appVersion: "\(configuration.marketingVersion) (\(configuration.buildNumber))")
    }
}
