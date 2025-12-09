@preconcurrency import GoogleMobileAds
import UIKit

@MainActor
final class RewardedAdManager: NSObject, FullScreenContentDelegate {

    var isReady: Bool {
           return rewardedAd != nil
       }
    
    static let shared = RewardedAdManager()

    private var rewardedAd: RewardedAd?
    private var isLoading = false

    private let adUnitID = "ca-app-pub-3759868960530173/7620553844"

    // MARK: - Load

    func loadAd() async {
        guard !isLoading, rewardedAd == nil else {
            print("🟡 [Rewarded] Пропуск loadAd() – вече има/зарежда се.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        print("⬇️ [Rewarded] Зареждаме… \(adUnitID)")
        do {
            rewardedAd = try await RewardedAd.load(
                with: adUnitID,
                request: Request()
            )
            rewardedAd?.fullScreenContentDelegate = self
            print("✅ [Rewarded] Успешно заредена")
        } catch {
            print("❌ [Rewarded] Грешка при зареждане: \(error.localizedDescription)")
            rewardedAd = nil
        }
    }

    // MARK: - Show

    /// `onReward` – тук кредитираш потребителя (coins, premium действие и т.н.)
    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        print("🎬 [Rewarded] showIfAvailable()")

        guard let ad = rewardedAd else {
            print("ℹ️ [Rewarded] Няма готова реклама → опитваме да заредим.")
            Task { await loadAd() }
            return
        }

        guard let root = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        else {
            print("⚠️ [Rewarded] Няма rootViewController.")
            return
        }

        do {
            try ad.canPresent(from: root)
        } catch {
            print("⚠️ [Rewarded] Не може да се покаже: \(error.localizedDescription)")
            rewardedAd = nil
            Task { await loadAd() }
            return
        }

        print("▶️ [Rewarded] Показваме…")
        ad.present(from: root) { [weak self] in
            guard let self, let reward = self.rewardedAd?.adReward else {
                print("ℹ️ [Rewarded] Няма reward обект.")
                return
            }
            print("🏅 [Rewarded] User earned reward: \(reward.amount) \(reward.type)")
            onReward(reward.amount, reward.type)
        }
    }

    // MARK: - FullScreenContentDelegate

    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("📺 [Rewarded] adWillPresentFullScreenContent")
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        print("❌ [Rewarded] didFailToPresent: \(error.localizedDescription)")
        rewardedAd = nil
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("🙋‍♂️ [Rewarded] adDidDismissFullScreenContent → чистим и презареждаме")
        rewardedAd = nil
        Task { await loadAd() }
    }
}
