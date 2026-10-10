import NikuCueDomain
import SwiftUI

/// Purchase screen (docs/03 §5, docs/08 §5): one-time purchase, same features as the free version, explicit restore.
/// The price always comes from StoreKit through `PurchaseViewModel`; nothing here invents a price.
struct PurchaseView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        PurchaseContent(container: container)
    }
}

struct PurchaseContent: View {
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var vm: PurchaseViewModel

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: PurchaseViewModel(service: container.purchase) { _ in
            // Ownership changes flow through the purchase observer in AppContainer; re-evaluate the gate right away.
            container.reevaluateAdGate()
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizer.t("purchase.subtitle"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Label(localizer.t("purchase.sameFeatures"), systemImage: "pawprint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                purchaseButton

                Button {
                    Task { await vm.restore() }
                } label: {
                    Text(localizer.t("purchase.restore"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(vm.phase == .processing)

                if let key = vm.messageKey {
                    Text(localizer.t(key))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                Text(localizer.t("purchase.restoreHelp"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localizer.t("purchase.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    @ViewBuilder
    private var purchaseButton: some View {
        if vm.isOwned {
            Label(localizer.t("purchase.owned"), systemImage: "checkmark.seal")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            switch vm.phase {
            case .loading, .processing:
                Button {} label: {
                    Text(localizer.t(vm.phase == .processing ? "purchase.processing" : "purchase.loading"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
            case .unavailable:
                // Price could not be loaded: offer a reload, never a fixed fallback price (docs/03 §6).
                Button {
                    Task { await vm.load() }
                } label: {
                    Text(localizer.t("common.retry"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            case .ready(let product):
                Button {
                    Task { await vm.purchase() }
                } label: {
                    Text(localizer.t("purchase.button", ["price": product.displayPrice]))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canPurchase)
            }
        }
    }
}
