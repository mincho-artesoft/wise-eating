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
    var isReady: Bool { return rewardedAd != nil }
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        return "ca-app-pub-3759868960530173/7620553844"
        #endif
    }

    func loadAd() async {
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
