import Foundation

/// Central switch for the entire advertising subsystem.
///
/// Keep this disabled until new AdMob identifiers are configured.
enum AdsConfiguration {
    static let shouldShowAds = false

    enum Unit: String {
        case appOpen = "AyuraAdMobAppOpenAdUnitID"
        case banner = "AyuraAdMobBannerAdUnitID"
        case interstitial = "AyuraAdMobInterstitialAdUnitID"
        case native = "AyuraAdMobNativeAdUnitID"
        case rewarded = "AyuraAdMobRewardedAdUnitID"
    }

    static func adUnitID(for unit: Unit) -> String? {
        guard
            shouldShowAds,
            let value = Bundle.main.object(forInfoDictionaryKey: unit.rawValue) as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return value
    }
}
