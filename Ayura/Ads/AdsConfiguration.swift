import Foundation

/// Subscription eligibility is separate from consent/SDK readiness so existing
/// save and generation flows keep their Base-plan behavior while ads load.
@MainActor
enum AdsConfiguration {
    static var shouldShowAds: Bool {
        #if canImport(GoogleMobileAds)
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("-aiGenerationSmokeTest")
            && !arguments.contains("-catalogSeparationSmokeTest")
            && SubscriptionManager.shared.subscriptionStatus == .base
        #else
        return false
        #endif
    }

    static var canRequestAds: Bool {
        shouldShowAds && AdsConsentManager.shared.canRequestAds
    }

    enum Unit: String {
        case appOpen = "AyurvedaAsanaYogaAdMobAppOpenAdUnitID"
        case banner = "AyurvedaAsanaYogaAdMobBannerAdUnitID"
        case interstitial = "AyurvedaAsanaYogaAdMobInterstitialAdUnitID"
        case native = "AyurvedaAsanaYogaAdMobNativeAdUnitID"
        case rewarded = "AyurvedaAsanaYogaAdMobRewardedAdUnitID"
    }

    static func adUnitID(for unit: Unit) -> String? {
        guard shouldShowAds else { return nil }
        #if DEBUG
        // Google's demo inventory keeps development traffic off the live units.
        switch unit {
        case .appOpen: return "ca-app-pub-3940256099942544/5575463023"
        case .banner: return "ca-app-pub-3940256099942544/2934735716"
        case .interstitial: return "ca-app-pub-3940256099942544/4411468910"
        case .native: return "ca-app-pub-3940256099942544/3986624511"
        case .rewarded: return "ca-app-pub-3940256099942544/1712485313"
        }
        #else
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: unit.rawValue) as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
        #endif
    }
}
