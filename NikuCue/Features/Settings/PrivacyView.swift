import NikuCueDomain
import SwiftUI

/// Privacy explanation (docs/08 §6): where habits live, what uses the network, where backups go.
/// The policy link appears only once the owner replaced the placeholder URL (CLAUDE.md: never guess URLs).
struct PrivacyView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paragraph("privacy.summary", systemImage: "iphone")
                paragraph("privacy.backup", systemImage: "externaldrive")
                paragraph("privacy.ads", systemImage: "megaphone")
                if let url = privacyPolicyURL {
                    Link(destination: url) {
                        Label(localizer.t("settings.privacy"), systemImage: "link")
                            .frame(minHeight: 44)
                    }
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localizer.t("settings.privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paragraph(_ key: String, systemImage: String) -> some View {
        Label {
            Text(localizer.t(key))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var privacyPolicyURL: URL? {
        SettingsViewModel.configuredURL(container.configuration.privacyPolicyURL)
    }
}
