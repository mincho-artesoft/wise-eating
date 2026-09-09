import SwiftUI
#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
import GoogleMobileAds
import UserMessagingPlatform
#endif

/// Owns consent and SDK startup. No ad request may run before this is ready.
@MainActor
final class AdsConsentManager: ObservableObject {
    static let shared = AdsConsentManager()

    @Published private(set) var canRequestAds = false
    @Published private(set) var isPrivacyOptionsRequired = false
    @Published private(set) var isPreparing = false
    @Published var privacyError: String?

    private var didGatherConsent = false
    private var didStartSDK = false

    private init() {}

    func prepareAds() async {
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        guard AdsConfiguration.shouldShowAds,
              UIApplication.shared.applicationState == .active,
              !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        print("[Ads] Preparing ads for Base plan.")

        if !didGatherConsent {
            do {
                try await ConsentInformation.shared.requestConsentInfoUpdate(
                    with: RequestParameters()
                )
                try await ConsentForm.loadAndPresentIfRequired(from: nil)
                didGatherConsent = true
            } catch {
                // UMP may still allow ads using consent from a previous launch.
                print("[Ads] Consent update failed: \(error.localizedDescription)")
            }
        }

        await startAdsIfAllowed()
        #endif
    }

    func subscriptionDidChange() async {
        if AdsConfiguration.shouldShowAds {
            await prepareAds()
        } else {
            canRequestAds = false
            discardLoadedAds()
        }
    }

    func presentPrivacyOptions() async {
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        guard isPrivacyOptionsRequired, !isPreparing else { return }
        isPreparing = true
        canRequestAds = false
        discardLoadedAds()
        defer { isPreparing = false }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        } catch {
            privacyError = error.localizedDescription
        }
        await startAdsIfAllowed()
        #endif
    }

    private func discardLoadedAds() {
        AppOpenAdManager.shared.reset()
        InterstitialAdManager.shared.reset()
        RewardedAdManager.shared.reset()
    }

    #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
    private func startAdsIfAllowed() async {
        isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard AdsConfiguration.shouldShowAds,
              ConsentInformation.shared.canRequestAds else {
            canRequestAds = false
            return
        }

        if !didStartSDK {
            print("[Ads] Starting Google Mobile Ads SDK.")
            await MobileAds.shared.start()
            didStartSDK = true
        }
        canRequestAds = AdsConfiguration.shouldShowAds
            && ConsentInformation.shared.canRequestAds
        guard canRequestAds else { return }
        print("[Ads] SDK ready. Loading ad formats.")
        // A slow/no-fill App Open request must not delay the other formats.
        Task { await AppOpenAdManager.shared.loadAd() }
        Task { await InterstitialAdManager.shared.loadAd() }
        Task { await RewardedAdManager.shared.loadAd() }
    }
    #endif
}
