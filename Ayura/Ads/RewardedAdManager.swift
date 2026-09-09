import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(GoogleMobileAds)
@MainActor
final class RewardedAdManager: NSObject {

    static let shared = RewardedAdManager()
    private var isLoading = false

    private var rewardedAd: RewardedAd?
    private var presentingAd: RewardedAd?
    var isReady: Bool {
        AdsConfiguration.canRequestAds && !FullScreenAdPresentation.isShowing && rewardedAd != nil
    }

    func reset() {
        rewardedAd = nil
    }

    func loadAd() async {
        guard AdsConfiguration.canRequestAds else {
            rewardedAd = nil
            return
        }
        guard let adUnitID = AdsConfiguration.adUnitID(for: .rewarded) else { return }
        guard !isLoading, rewardedAd == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let ad = try await RewardedAd.load(with: adUnitID, request: Request())
            guard AdsConfiguration.canRequestAds else { return }
            rewardedAd = ad
            print("[Ads] Rewarded loaded.")
            rewardedAd?.fullScreenContentDelegate = self
        } catch {
            AdDiagnostics.failure("Rewarded load", error)
        }
    }

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        guard AdsConfiguration.canRequestAds else { return }
        guard UIApplication.shared.applicationState == .active,
              let ad = rewardedAd, let root = UIApplication.shared.topMostViewController,
              FullScreenAdPresentation.begin() else {
            Task { await loadAd() }
            return
        }
        
        presentingAd = ad
        rewardedAd = nil
        let reward = ad.adReward
        print("[Ads] Rewarded presenting.")
        ad.present(from: root) {
            onReward(reward.amount, reward.type)
        }
    }

}

extension RewardedAdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[Ads] Rewarded will present.")
    }
    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        print("[Ads] Rewarded impression recorded.")
    }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        AdDiagnostics.failure("Rewarded presentation", error)
        FullScreenAdPresentation.end()
        presentingAd = nil
        rewardedAd = nil
        Task { await loadAd() }
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[Ads] Rewarded dismissed.")
        FullScreenAdPresentation.end()
        presentingAd = nil
        rewardedAd = nil
        Task { await loadAd() }
    }
}
#else
@MainActor
final class RewardedAdManager: NSObject {
    static let shared = RewardedAdManager()

    var isReady: Bool { false }

    func reset() {}
    func loadAd() async {}

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {}
}
#endif
