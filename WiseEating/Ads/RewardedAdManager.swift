import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
final class RewardedAdManager: NSObject {

    static let shared = RewardedAdManager()
    private var isLoading = false

#if !targetEnvironment(macCatalyst)
    private var rewardedAd: RewardedAd?
    private var presentingAd: RewardedAd?
    var isReady: Bool {
        AdsConsentManager.shouldShowAds
            && AdsConsentManager.shared.canRequestAds
            && !FullScreenAdPresentation.isShowing
            && rewardedAd != nil
    }
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        return "ca-app-pub-3759868960530173/7620553844"
        #endif
    }

    func reset() {
        rewardedAd = nil
    }

    func loadAd() async {
        guard AdsConsentManager.shouldShowAds,
              AdsConsentManager.shared.canRequestAds else {
            rewardedAd = nil
            return
        }
        guard !isLoading, rewardedAd == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let ad = try await RewardedAd.load(with: adUnitID, request: Request())
            guard AdsConsentManager.shouldShowAds,
                  AdsConsentManager.shared.canRequestAds else { return }
            rewardedAd = ad
            rewardedAd?.fullScreenContentDelegate = self
        } catch {
            print("❌ [Rewarded] Error: \(error.localizedDescription)")
        }
    }

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        guard AdsConsentManager.shouldShowAds,
              AdsConsentManager.shared.canRequestAds,
              UIApplication.shared.applicationState == .active,
              let ad = rewardedAd,
              let root = keyWindowRootViewController(),
              FullScreenAdPresentation.begin() else {
            Task { await loadAd() }
            return
        }

        presentingAd = ad
        rewardedAd = nil
        let reward = ad.adReward
        ad.present(from: root) {
            onReward(reward.amount, reward.type)
        }
    }

#endif
}

#if !targetEnvironment(macCatalyst)
extension RewardedAdManager: FullScreenContentDelegate {
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        FullScreenAdPresentation.end()
        presentingAd = nil
        rewardedAd = nil
        Task { await loadAd() }
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        FullScreenAdPresentation.end()
        presentingAd = nil
        rewardedAd = nil
        Task { await loadAd() }
    }
}
#endif
