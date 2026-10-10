import Foundation

/// Identifiers and URLs the owner must confirm before release (RELEASE_BLOCKERS R05–R09).
///
/// Values are explicit placeholders; nothing here is guessed. Debug builds run with mocks
/// regardless, and `scripts/check_release_config.sh` fails a Release build while any placeholder remains.
struct AppConfiguration: Sendable, Equatable {
    static let placeholderMarker = "REPLACE_WITH_"

    /// Non-consumable ad-removal product (docs/08 §1). The pack's provisional string is kept verbatim.
    var removeAdsProductID: String
    var adMobApplicationID: String
    var bannerAdUnitID: String
    var privacyPolicyURL: String
    var supportURL: String
    var supportEmail: String

    static let development = AppConfiguration(
        removeAdsProductID: "REPLACE_WITH_CONFIRMED_BUNDLE_ID.remove_ads",
        adMobApplicationID: "REPLACE_WITH_ADMOB_APP_ID",
        bannerAdUnitID: "REPLACE_WITH_BANNER_AD_UNIT_ID",
        privacyPolicyURL: "REPLACE_WITH_PRIVACY_POLICY_URL",
        supportURL: "REPLACE_WITH_SUPPORT_URL",
        supportEmail: "REPLACE_WITH_SUPPORT_EMAIL"
    )

    /// The one place the owner edits. Keep Debug on mocks even after real values exist.
    static var current: AppConfiguration { .development }

    var placeholders: [String] {
        var out: [String] = []
        if removeAdsProductID.contains(Self.placeholderMarker) { out.append("removeAdsProductID") }
        if adMobApplicationID.contains(Self.placeholderMarker) { out.append("adMobApplicationID") }
        if bannerAdUnitID.contains(Self.placeholderMarker) { out.append("bannerAdUnitID") }
        if privacyPolicyURL.contains(Self.placeholderMarker) { out.append("privacyPolicyURL") }
        if supportURL.contains(Self.placeholderMarker) { out.append("supportURL") }
        if supportEmail.contains(Self.placeholderMarker) { out.append("supportEmail") }
        return out
    }

    var isReleaseReady: Bool { placeholders.isEmpty }

    var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "" }
    var isPlaceholderBundleIdentifier: Bool { bundleIdentifier.lowercased().contains("placeholder") }

    var marketingVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif
}
