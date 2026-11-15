import SwiftUI
#if !targetEnvironment(macCatalyst) && canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
import GoogleMobileAds
import UserMessagingPlatform
#endif

/// Owns UMP consent and Google Mobile Ads SDK startup (non-tracking mode matching App Privacy).
@MainActor
final class AdsConsentManager: ObservableObject {
    static let shared = AdsConsentManager()

    @Published private(set) var canRequestAds = false
    @Published private(set) var isPrivacyOptionsRequired = false
    @Published private(set) var isPreparing = false

    private var didGatherConsent = false
    private var didStartSDK = false

    private init() {}

    static var shouldShowAds: Bool {
        #if !targetEnvironment(macCatalyst) && canImport(GoogleMobileAds)
        SubscriptionManager.shared.subscriptionStatus == .base
        #else
        false
        #endif
    }

    func prepareAds() async {
        #if !targetEnvironment(macCatalyst) && canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        guard Self.shouldShowAds,
              UIApplication.shared.applicationState == .active else { return }
        if isPreparing {
            while isPreparing {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return
        }
        isPreparing = true
        defer { isPreparing = false }

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
        if Self.shouldShowAds {
            await prepareAds()
        } else {
            canRequestAds = false
            discardLoadedAds()
        }
    }

    private func discardLoadedAds() {
        #if !targetEnvironment(macCatalyst)
        AppOpenAdManager.shared.reset()
        InterstitialAdManager.shared.reset()
        RewardedAdManager.shared.reset()
        #endif
    }

    #if !targetEnvironment(macCatalyst) && canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
    private func startAdsIfAllowed() async {
        isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard Self.shouldShowAds,
              ConsentInformation.shared.canRequestAds else {
            canRequestAds = false
            return
        }

        if !didStartSDK {
            await MobileAds.shared.start()
            didStartSDK = true
        }
        canRequestAds = Self.shouldShowAds && ConsentInformation.shared.canRequestAds
        guard canRequestAds else { return }

        Task { await AppOpenAdManager.shared.loadAd() }
        Task { await InterstitialAdManager.shared.loadAd() }
        Task { await RewardedAdManager.shared.loadAd() }
    }
    #endif
}
