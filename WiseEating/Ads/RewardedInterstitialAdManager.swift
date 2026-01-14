import UIKit

// Зареждаме GoogleMobileAds само ако не сме на Mac
#if canImport(GoogleMobileAds)
@preconcurrency import GoogleMobileAds
#endif

@MainActor
final class RewardedInterstitialAdManager: NSObject {

    static let shared = RewardedInterstitialAdManager()
    
    // Флаг за зареждане (общ)
    private var isLoading = false
    
    // MARK: - Config
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/6978759866"
        #else
        return "ca-app-pub-3759868960530173/8933635514"
        #endif
    }

// MARK: - 📱 iOS IMPLEMENTATION
#if !targetEnvironment(macCatalyst)

    // Свойството isReady, което RootView търси
    var isReady: Bool {
        return rewardedInterstitial != nil
    }

    private var rewardedInterstitial: RewardedInterstitialAd?

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

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        print("🎬 [RewInt] showIfAvailable()")

        guard let ad = rewardedInterstitial else {
            print("ℹ️ [RewInt] Няма готова реклама → опитваме да заредим.")
            Task { await loadAd() }
            return
        }

        // Helper function to get root VC (defined in other files or here locally if needed)
        guard let root = UIApplication.shared.connectedScenes
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

#else

// MARK: - 🖥️ MAC CATALYST IMPLEMENTATION

    // На Mac винаги сме "готови", защото зареждаме HTML в реално време
    var isReady: Bool {
        return true
    }

    // No-op на Mac
    func loadAd() async {
        // Може да заредиш WebView предварително тук ако искаш, но не е задължително
    }

    func showIfAvailable(onReward: @escaping (_ amount: NSDecimalNumber, _ type: String) -> Void) {
        print("🎬 [RewInt] Mac Catalyst Show Request")
        
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        else { return }
        
        // Използваме контролера от AdSenseSupport.swift
        let macAdVC = MacFullScreenAdViewController()
        macAdVC.modalPresentationStyle = .overFullScreen
        
        // Когато потребителят затвори рекламата, даваме наградата
        macAdVC.onDismiss = {
            print("🏅 [RewInt] Mac User earned reward (Simulated)")
            onReward(1, "Coins")
        }
        
        root.present(macAdVC, animated: true)
    }

#endif
}

// MARK: - Delegate Extension (iOS Only)
#if !targetEnvironment(macCatalyst)
extension RewardedInterstitialAdManager: FullScreenContentDelegate {

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
#endif
