import NikuCueDomain
import SwiftUI

/// Placeholder purchase screen (docs/03 §5): one-time purchase, same features as the free version,
/// restore purchases. P09 replaces this view with one driven by `PurchaseViewModel` (StoreKit 2):
/// the price then comes from StoreKit, the buy button becomes `purchase.button {price}` and restore works.
/// Nothing here talks to StoreKit; no price is invented (docs/03 §6).
struct PurchaseView: View {
    @EnvironmentObject private var localizer: Localizer

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

                // P09: enabled once the product loads; label becomes purchase.button with the StoreKit price.
                Button {
                } label: {
                    Text(localizer.t("purchase.loading"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)

                // P09: explicit restore → AppStore.sync() → entitlement re-evaluation.
                Button {
                } label: {
                    Text(localizer.t("purchase.restore"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(true)

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
    }
}
