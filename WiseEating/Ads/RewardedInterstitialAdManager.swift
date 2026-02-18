import UIKit

#if canImport(GoogleMobileAds)
@preconcurrency import GoogleMobileAds
#endif

@MainActor
final class RewardedInterstitialAdManager: NSObject {

    static let shared = RewardedInterstitialAdManager()
    private var isLoading = false
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/6978759866"
        #else
        return "ca-app-pub-3759868960530173/8933635514"
        #endif
    }

// MARK: - 📱 iOS IMPLEMENTATION
#if !targetEnvironment(macCatalyst)

    var isReady: Bool { return rewardedInterstitial != nil }
    private var rewardedInterstitial: RewardedInterstitialAd?

    func loadAd() async {
        guard !isLoading, rewardedInterstitial == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            rewardedInterstitial = try await RewardedInterstitialAd.load(
                with: adUnitID,
                request: Request()
            )
            rewardedInterstitial?.fullScreenContentDelegate = self
        } catch {
            print("❌ [RewInt] Грешка при зареждане: \(error.localizedDescription)")
            rewardedInterstitial = nil
        }
    }

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        guard let ad = rewardedInterstitial, let root = keyWindowRootViewController() else {
            Task { await loadAd() }
            return
        }

        do {
            try ad.canPresent(from: root)
        } catch {
            print("⚠️ [RewInt] Не може да се покаже: \(error.localizedDescription)")
            rewardedInterstitial = nil
            Task { await loadAd() }
            return
        }

        ad.present(from: root) { [weak self] in
            guard let self, let reward = self.rewardedInterstitial?.adReward else { return }
            onReward(reward.amount, reward.type)
        }
    }
#endif
}

#if !targetEnvironment(macCatalyst)
extension RewardedInterstitialAdManager: FullScreenContentDelegate {
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        rewardedInterstitial = nil
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        rewardedInterstitial = nil
        Task { await loadAd() }
    }
}
#endif
