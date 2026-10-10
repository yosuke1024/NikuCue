import Combine
import Foundation
import NikuCueDomain

/// Purchase screen state (docs/08 §5): verified success stops ads immediately, cancel is silent, pending shows
/// a waiting message, unverified never unlocks, restore is explicit. Double purchase starts are blocked.
@MainActor
final class PurchaseViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready(ProductInfo)
        case unavailable
        case processing
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var entitlement: EntitlementState
    /// Localization key for the status line (purchase.success / pending / unverified / error / noneFound).
    @Published private(set) var messageKey: String?

    private let service: any PurchaseServicing
    private let onEntitlementChange: (EntitlementState) -> Void

    init(service: any PurchaseServicing, onEntitlementChange: @escaping (EntitlementState) -> Void) {
        self.service = service
        self.onEntitlementChange = onEntitlementChange
        self.entitlement = service.entitlement
    }

    var isOwned: Bool { entitlement == .owned }
    var canPurchase: Bool {
        if case .ready = phase { return !isOwned }
        return false
    }

    func load() async {
        entitlement = service.entitlement
        if let info = await service.loadProduct() {
            phase = .ready(info)
        } else {
            phase = .unavailable // price field offers reload; never a made-up fixed price (docs/03 §6)
        }
    }

    func purchase() async {
        guard canPurchase, case .ready(let info) = phase else { return }
        phase = .processing
        messageKey = nil
        let outcome = await service.purchase()
        entitlement = service.entitlement
        switch outcome {
        case .owned:
            messageKey = "purchase.success"
            onEntitlementChange(.owned)
        case .cancelled:
            messageKey = nil
        case .pending:
            messageKey = "purchase.pending"
        case .unverified:
            messageKey = "purchase.unverified"
        case .failed:
            messageKey = "purchase.error"
        }
        phase = .ready(info)
    }

    func restore() async {
        guard phase != .processing else { return }
        let previous = phase
        phase = .processing
        messageKey = nil
        let state = await service.restore()
        entitlement = state
        onEntitlementChange(state)
        messageKey = state == .owned ? "purchase.success" : "purchase.noneFound"
        phase = previous == .processing ? .loading : previous
        if case .loading = phase { await load() }
    }
}
