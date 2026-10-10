import Foundation
import NikuCueDomain
import StoreKit

/// Localized product information for the purchase screen; the price is never a constant in the UI (docs/08 §1).
struct ProductInfo: Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
}

enum PurchaseOutcome: Equatable, Sendable {
    case owned          // verified and finished
    case cancelled      // user cancelled: return quietly
    case pending        // awaiting approval (Ask to Buy)
    case unverified     // signed data failed verification: no entitlement
    case failed(String) // other error
}

/// Boundary for the single non-consumable ad-removal product (docs/08 §5).
@MainActor
protocol PurchaseServicing: AnyObject {
    var entitlement: EntitlementState { get }
    /// Observers are called on the main actor whenever ownership changes (and once immediately).
    func addObserver(_ observer: @escaping (EntitlementState) -> Void)
    /// Begins the entitlement check and transaction listener. Safe to call once at launch.
    func start()
    func loadProduct() async -> ProductInfo?
    func purchase() async -> PurchaseOutcome
    /// Explicit "Restore purchases" only: AppStore.sync() then re-evaluate (never on every launch).
    func restore() async -> EntitlementState
}

/// StoreKit 2 implementation. Only `.verified` transactions for the configured product count; revoked or
/// absent entitlements mean `notOwned`. No server, no RevenueCat, no UserDefaults-only unlock.
@MainActor
final class StoreKitPurchaseService: PurchaseServicing {
    private let productID: String
    private(set) var entitlement: EntitlementState = .unknown {
        didSet { if entitlement != oldValue { observers.forEach { $0(entitlement) } } }
    }
    private var observers: [(EntitlementState) -> Void] = []
    private var updatesTask: Task<Void, Never>?
    private var product: Product?
    private var purchaseInProgress = false

    init(productID: String) {
        self.productID = productID
    }

    func addObserver(_ observer: @escaping (EntitlementState) -> Void) {
        observers.append(observer)
        observer(entitlement)
    }

    func start() {
        guard updatesTask == nil else { return }
        Task { await refreshEntitlement() }
        updatesTask = Task { [weak self] in
            // Transaction.updates delivers purchases made outside the app, Ask-to-Buy approvals and revocations.
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
    }

    /// `Transaction.currentEntitlements` reads the device's signed transaction cache, so it also works offline.
    /// A completed query with no matching entitlement is `notOwned`; the state stays `unknown` only until the query finishes.
    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID, transaction.revocationDate == nil {
                owned = true
            }
        }
        entitlement = owned ? .owned : .notOwned
    }

    func loadProduct() async -> ProductInfo? {
        if let product { return ProductInfo(id: product.id, displayName: product.displayName, displayPrice: product.displayPrice) }
        guard let fetched = try? await Product.products(for: [productID]).first else { return nil }
        product = fetched
        return ProductInfo(id: fetched.id, displayName: fetched.displayName, displayPrice: fetched.displayPrice)
    }

    func purchase() async -> PurchaseOutcome {
        guard !purchaseInProgress else { return .failed("inProgress") }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        if product == nil { _ = await loadProduct() }
        guard let product else { return .failed("productUnavailable") }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    entitlement = transaction.revocationDate == nil ? .owned : .notOwned
                    return entitlement == .owned ? .owned : .unverified
                case .unverified:
                    return .unverified
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("unknownResult")
            }
        } catch {
            return .failed(String(describing: error))
        }
    }

    func restore() async -> EntitlementState {
        do {
            try await AppStore.sync()
        } catch {
            // A failed sync is not "not owned": keep whatever the device knows.
        }
        await refreshEntitlement()
        return entitlement
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, transaction.productID == productID else { return }
        entitlement = transaction.revocationDate != nil ? .notOwned : .owned
        await transaction.finish()
    }
}

/// Scripted implementation for Debug, previews and tests (QA Q24–Q27 without the App Store).
@MainActor
final class MockPurchaseService: PurchaseServicing {
    enum Script: Equatable { case owned, cancelled, pending, unverified, failed }

    private(set) var entitlement: EntitlementState
    var script: Script = .owned
    var productInfo: ProductInfo? = ProductInfo(id: "mock.remove_ads", displayName: "Remove Ads (mock)", displayPrice: "¥0 (mock)")
    var restoreResult: EntitlementState = .notOwned
    private var observers: [(EntitlementState) -> Void] = []
    private(set) var purchaseCalls = 0
    private(set) var restoreCalls = 0

    init(entitlement: EntitlementState = .notOwned) {
        self.entitlement = entitlement
    }

    func addObserver(_ observer: @escaping (EntitlementState) -> Void) {
        observers.append(observer)
        observer(entitlement)
    }

    func start() {}

    func loadProduct() async -> ProductInfo? { productInfo }

    func purchase() async -> PurchaseOutcome {
        purchaseCalls += 1
        switch script {
        case .owned: set(.owned); return .owned
        case .cancelled: return .cancelled
        case .pending: return .pending
        case .unverified: return .unverified
        case .failed: return .failed("mock")
        }
    }

    func restore() async -> EntitlementState {
        restoreCalls += 1
        set(restoreResult)
        return entitlement
    }

    func simulateExternalUpdate(_ state: EntitlementState) { set(state) }

    private func set(_ state: EntitlementState) {
        guard state != entitlement else { return }
        entitlement = state
        observers.forEach { $0(state) }
    }
}
