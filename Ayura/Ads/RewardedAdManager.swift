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
    var isReady: Bool {
        AdsConfiguration.shouldShowAds && rewardedAd != nil
    }

    func loadAd() async {
        guard AdsConfiguration.shouldShowAds else {
            rewardedAd = nil
            return
        }
        guard let adUnitID = AdsConfiguration.adUnitID(for: .rewarded) else { return }
        guard !isLoading, rewardedAd == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            rewardedAd = try await RewardedAd.load(with: adUnitID, request: Request())
            rewardedAd?.fullScreenContentDelegate = self
        } catch {
            print("❌ [Rewarded] Error: \(error.localizedDescription)")
        }
    }

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        guard AdsConfiguration.shouldShowAds else { return }
        guard let ad = rewardedAd, let root = keyWindowRootViewController() else {
            Task { await loadAd() }
            return
        }
        
        ad.present(from: root) { [weak self] in
            guard let reward = self?.rewardedAd?.adReward else { return }
            onReward(reward.amount, reward.type)
        }
    }

#endif
}

#if !targetEnvironment(macCatalyst)
extension RewardedAdManager: FullScreenContentDelegate {
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        rewardedAd = nil
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        rewardedAd = nil
        Task { await loadAd() }
    }
}
#endif
