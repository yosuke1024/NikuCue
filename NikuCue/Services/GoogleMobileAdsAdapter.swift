import Foundation
import NikuCueDomain
import SwiftUI
import UIKit

// Real Google Mobile Ads / UMP integration (docs/08, P10).
//
// This file compiles to nothing until the owner adds the GoogleMobileAds Swift package to the app target with a
// pinned stable version (RELEASE_BLOCKERS R07/R08; the version must be read from the current official
// documentation and recorded in Package.resolved — it is intentionally not guessed here). Until then the app
// runs with MockAdConsentService / MockBannerAdapter and shows no ads.
//
// Owner checklist when enabling:
//   1. Add the package, set GADApplicationIdentifier (INFOPLIST_KEY) from AppConfiguration.adMobApplicationID.
//   2. Confirm the SDK's privacy manifest and update PrivacyInfo.xcprivacy / App Store disclosures.
//   3. Keep publisher first-party ID disabled and request only non-personalized ads (docs/08 §4).
//   4. Test only with official test ad unit IDs / registered test devices.
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class UMPConsentService: AdConsentServicing {
    private(set) var status: ConsentStatus = .unknown
    private var observers: [() -> Void] = []

    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }
    var privacyOptionsRequired: Bool { ConsentInformation.shared.privacyOptionsRequirementStatus == .required }

    func gatherConsent() async {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
               let root = scene.windows.first?.rootViewController {
                try await ConsentForm.loadAndPresentIfRequired(from: root)
            }
            status = ConsentInformation.shared.consentStatus == .required ? .required
                : (ConsentInformation.shared.consentStatus == .notRequired ? .notRequired : .obtained)
        } catch {
            status = .unknown
        }
        observers.forEach { $0() }
    }

    func presentPrivacyOptions() async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first?.rootViewController else { return }
        try? await ConsentForm.presentPrivacyOptionsForm(from: root)
        observers.forEach { $0() }
    }

    func addObserver(_ observer: @escaping () -> Void) { observers.append(observer) }
}

@MainActor
final class GoogleBannerAdapter: BannerAdapting {
    private(set) var bannerView: BannerView?
    private var started = false
    var isConfigured: Bool { true }
    var bannerHeight: CGFloat { 50 } // anchored adaptive banner height is taken from the loaded ad size

    func load(adUnitID: String) {
        if !started {
            started = true
            MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
            MobileAds.shared.start()
        }
        let view = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: UIScreen.main.bounds.width))
        view.adUnitID = adUnitID
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"] // non-personalized only (docs/08 §4)
        request.register(extras)
        view.load(request)
        bannerView = view
    }

    func destroy() {
        bannerView?.removeFromSuperview()
        bannerView = nil
    }
}
#endif
