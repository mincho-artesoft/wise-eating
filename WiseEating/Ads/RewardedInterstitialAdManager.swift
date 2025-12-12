@preconcurrency import GoogleMobileAds
import UIKit

@MainActor
final class RewardedInterstitialAdManager: NSObject, FullScreenContentDelegate {

    static let shared = RewardedInterstitialAdManager()

    // ✅ ДОБАВЕНО: Свойството isReady, което RootView търси
    var isReady: Bool {
        return rewardedInterstitial != nil
    }

    private var rewardedInterstitial: RewardedInterstitialAd?
    private var isLoading = false

    private let adUnitID = "ca-app-pub-2322123786875027/7743463842"

    // MARK: - Load

    func loadAd() async {
        guard !isLoading, rewardedInterstitial == nil else {
            print("🟡 [RewInt] Пропуск loadAd() – вече има/зарежда се.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        print("⬇️ [RewInt] Зареждаме… \(adUnitID)")
        do {
            rewardedInterstitial = try await RewardedInterstitialAd.load(
                with: adUnitID,
                request: Request()
            )
            rewardedInterstitial?.fullScreenContentDelegate = self
            print("✅ [RewInt] Успешно заредена")
        } catch {
            print("❌ [RewInt] Грешка при зареждане: \(error.localizedDescription)")
            rewardedInterstitial = nil
        }
    }

    // MARK: - Show

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        print("🎬 [RewInt] showIfAvailable()")

        guard let ad = rewardedInterstitial else {
            print("ℹ️ [RewInt] Няма готова реклама → опитваме да заредим.")
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
            print("⚠️ [RewInt] Няма rootViewController.")
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

        print("▶️ [RewInt] Показваме…")
        ad.present(from: root) { [weak self] in
            guard let self, let reward = self.rewardedInterstitial?.adReward else {
                print("ℹ️ [RewInt] Няма reward обект.")
                return
            }
            print("🏅 [RewInt] User earned reward: \(reward.amount) \(reward.type)")
            onReward(reward.amount, reward.type)
        }
    }

    // MARK: - FullScreenContentDelegate

    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("📺 [RewInt] adWillPresentFullScreenContent")
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        print("❌ [RewInt] didFailToPresent: \(error.localizedDescription)")
        rewardedInterstitial = nil
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("🙋‍♂️ [RewInt] adDidDismissFullScreenContent → чистим и презареждаме")
        rewardedInterstitial = nil
        Task { await loadAd() }
    }
}
