import NikuCueDomain
import XCTest
@testable import NikuCue

/// Purchase outcomes and the banner gate with mocks (QA Q24–Q28, Q30). No App Store or ad SDK involved.
@MainActor
final class MonetizationTests: XCTestCase {
    func makeState() throws -> (AppContainer, AppState) {
        let container = try AppContainer(repository: InMemoryHabitRepository(), clock: ManualClock(now: Date(), timeZone: TimeZone(identifier: "Asia/Bangkok")!))
        return (container, container.appState)
    }

    func testVerifiedPurchaseRemovesAdsImmediately() async throws { // Q24
        let service = MockPurchaseService(entitlement: .notOwned)
        var observed: [EntitlementState] = []
        let vm = PurchaseViewModel(service: service) { observed.append($0) }
        await vm.load()
        XCTAssertTrue(vm.canPurchase)
        await vm.purchase()
        XCTAssertEqual(vm.entitlement, .owned)
        XCTAssertEqual(vm.messageKey, "purchase.success")
        XCTAssertEqual(observed, [.owned])
        XCTAssertFalse(vm.canPurchase, "no second purchase of a non-consumable")
        XCTAssertEqual(service.purchaseCalls, 1)
    }

    func testCancelPendingUnverifiedAndFailureNeverUnlock() async throws { // Q25
        for (script, expectedKey) in [(MockPurchaseService.Script.cancelled, nil), (.pending, "purchase.pending"), (.unverified, "purchase.unverified"), (.failed, "purchase.error")] {
            let service = MockPurchaseService(entitlement: .notOwned)
            service.script = script
            var changes = 0
            let vm = PurchaseViewModel(service: service) { _ in changes += 1 }
            await vm.load()
            await vm.purchase()
            XCTAssertEqual(vm.entitlement, .notOwned, "\(script)")
            XCTAssertEqual(vm.messageKey, expectedKey, "\(script)")
            XCTAssertEqual(changes, 0, "\(script)")
            XCTAssertTrue(vm.canPurchase, "app stays usable and retry is possible, never forced")
        }
    }

    func testRestoreIsExplicitAndReportsResult() async throws { // Q27
        let service = MockPurchaseService(entitlement: .notOwned)
        service.restoreResult = .owned
        let vm = PurchaseViewModel(service: service) { _ in }
        await vm.load()
        await vm.restore()
        XCTAssertEqual(service.restoreCalls, 1)
        XCTAssertEqual(vm.entitlement, .owned)
        XCTAssertEqual(vm.messageKey, "purchase.success")
        let none = MockPurchaseService(entitlement: .notOwned)
        let vm2 = PurchaseViewModel(service: none) { _ in }
        await vm2.load()
        await vm2.restore()
        XCTAssertEqual(vm2.messageKey, "purchase.noneFound")
    }

    func testUnavailableProductOffersReloadNotFixedPrice() async throws {
        let service = MockPurchaseService(entitlement: .notOwned)
        service.productInfo = nil
        let vm = PurchaseViewModel(service: service) { _ in }
        await vm.load()
        XCTAssertEqual(vm.phase, .unavailable)
        XCTAssertFalse(vm.canPurchase)
    }

    func testBannerGateNeverRequestsWhenOwnedUnknownOrWithoutConsent() async throws { // Q28, Q30
        let consent = MockAdConsentService()
        let adapter = MockBannerAdapter()
        var config = AppConfiguration.development
        config.bannerAdUnitID = "test-unit"
        let banner = BannerService(configuration: config, consent: consent, adapter: adapter, sdkPrivacyConfigurationVerified: true)
        let (_, state) = try makeState()
        try await state.updatePreferences { $0.onboardingStep = .finished; $0.hasFinishedFirstSession = true }
        state.isHomeVisible = true
        state.isSceneActive = true

        state.entitlement = .unknown
        banner.evaluate(appState: state)
        XCTAssertFalse(banner.isBannerActive)
        XCTAssertEqual(adapter.loads.count, 0)

        state.entitlement = .notOwned
        banner.evaluate(appState: state)
        XCTAssertFalse(banner.isBannerActive, "consent not gathered yet")

        await consent.gatherConsent()
        banner.evaluate(appState: state)
        XCTAssertTrue(banner.isBannerActive)
        XCTAssertEqual(adapter.loads, ["test-unit"])
        XCTAssertEqual(banner.reservedHeight, 50)
        banner.evaluate(appState: state)
        XCTAssertEqual(adapter.loads.count, 1, "no reload while nothing changed")

        state.isSceneActive = false // backgrounded
        banner.evaluate(appState: state)
        XCTAssertFalse(banner.isBannerActive)
        XCTAssertEqual(adapter.destroys, 1)

        state.isSceneActive = true
        banner.evaluate(appState: state)
        XCTAssertTrue(banner.isBannerActive)
        consent.simulateWithdrawal()
        banner.evaluate(appState: state)
        XCTAssertFalse(banner.isBannerActive, "withdrawn consent stops requests")

        await consent.gatherConsent()
        state.entitlement = .owned
        banner.evaluate(appState: state)
        XCTAssertFalse(banner.isBannerActive, "owned users never see ads")
        XCTAssertEqual(adapter.loads.count, 2)
    }

    func testPlaceholderConfigurationBlocksAds() async throws { // Q36
        let consent = MockAdConsentService()
        await consent.gatherConsent()
        let banner = BannerService(configuration: .development, consent: consent, adapter: MockBannerAdapter(), sdkPrivacyConfigurationVerified: true)
        let (_, state) = try makeState()
        try await state.updatePreferences { $0.onboardingStep = .finished; $0.hasFinishedFirstSession = true }
        state.entitlement = .notOwned
        state.isHomeVisible = true
        banner.evaluate(appState: state)
        XCTAssertFalse(banner.isBannerActive, "REPLACE_WITH_ ad unit never requests")
    }

    func testFirstRealSessionFinishesOnlyAfterHomeAndBackground() async throws {
        let (_, state) = try makeState()
        await state.markFirstSessionFinishedIfNeeded()
        XCTAssertFalse(state.preferences.hasFinishedFirstSession, "onboarding not finished")
        try await state.updatePreferences { $0.onboardingStep = .finished }
        await state.markFirstSessionFinishedIfNeeded()
        XCTAssertFalse(state.preferences.hasFinishedFirstSession, "Home not shown yet")
        state.isHomeVisible = true
        await state.markFirstSessionFinishedIfNeeded()
        XCTAssertTrue(state.preferences.hasFinishedFirstSession)
    }
}
