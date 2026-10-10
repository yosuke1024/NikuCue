import Foundation

/// Ownership of the one non-consumable ad-removal product. Separate from purchase progress (docs/05 §1).
public enum EntitlementState: String, Sendable, Equatable {
    case unknown, owned, notOwned
}

/// Inputs of the banner display gate (docs/08 §3). Every flag must be true to request an ad.
public struct AdGateInputs: Equatable, Sendable {
    public var configValid: Bool
    public var entitlement: EntitlementState
    public var onboardingComplete: Bool
    public var firstRealSessionFinished: Bool
    public var homeVisible: Bool
    public var sceneActive: Bool
    public var canRequestAds: Bool
    public var sdkPrivacyConfigurationVerified: Bool

    public init(configValid: Bool, entitlement: EntitlementState, onboardingComplete: Bool,
                firstRealSessionFinished: Bool, homeVisible: Bool, sceneActive: Bool,
                canRequestAds: Bool, sdkPrivacyConfigurationVerified: Bool) {
        self.configValid = configValid
        self.entitlement = entitlement
        self.onboardingComplete = onboardingComplete
        self.firstRealSessionFinished = firstRealSessionFinished
        self.homeVisible = homeVisible
        self.sceneActive = sceneActive
        self.canRequestAds = canRequestAds
        self.sdkPrivacyConfigurationVerified = sdkPrivacyConfigurationVerified
    }
}

public enum AdGate {
    /// `unknown` ownership and unresolved consent both block ads: mis-serving is worse than lost revenue.
    public static func adsAllowed(_ i: AdGateInputs) -> Bool {
        i.configValid
            && i.entitlement == .notOwned
            && i.onboardingComplete
            && i.firstRealSessionFinished
            && i.homeVisible
            && i.sceneActive
            && i.canRequestAds
            && i.sdkPrivacyConfigurationVerified
    }
}
