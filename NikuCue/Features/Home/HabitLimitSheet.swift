import NikuCueDomain
import SwiftUI

/// Explains the five-active-habit limit (docs/02 §2). There is no purchase link: extra slots are never sold.
struct HabitLimitSheet: View {
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "tray.full")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(localizer.t("habit.limit"))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(localizer.t("habit.limitHelp"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        dismiss()
                    } label: {
                        Text(localizer.t("common.close"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizer.t("common.close")) { dismiss() }
                }
            }
        }
    }
}
