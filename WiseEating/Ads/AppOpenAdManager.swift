@preconcurrency import GoogleMobileAds
import UIKit

@MainActor
class AppOpenAdManager: NSObject, FullScreenContentDelegate {

    static let shared = AppOpenAdManager()

    private var appOpenAd: AppOpenAd?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var loadTime: Date?
    
    /// Флаг, който определя дали следващото налично показване трябва да се случи.
    /// true = показвай, false = пропускай (за логиката "през път").
    /// Започваме с true, за да се покаже при първа възможност.
    private var shouldShowNextAd = true

    // MARK: - Ad Unit ID
    private let adUnitID = "ca-app-pub-3940256099942544/5575463023"

    // MARK: - Load

    func loadAd() async {
        // 1. Проверка на абонамент: Зареждаме САМО ако е Base план
        guard SubscriptionManager.shared.subscriptionStatus == .base else {
            // Ако потребителят е платил, чистим рекламата да не заема памет
            appOpenAd = nil
            return
        }

        guard !isLoadingAd else { return }
        guard !isAdAvailable() else { return }

        isLoadingAd = true
        print("⬇️ [AppOpenAd] Започваме зареждане…")

        defer { isLoadingAd = false }

        do {
            appOpenAd = try await AppOpenAd.load(
                with: adUnitID,
                request: Request()
            )
            appOpenAd?.fullScreenContentDelegate = self
            loadTime = Date()
            print("✅ [AppOpenAd] Успешно заредена реклама")
        } catch {
            print("❌ [AppOpenAd] Грешка при зареждане: \(error.localizedDescription)")
        }
    }

    // MARK: - Show

    func showAdIfAvailable() {
        print("🎬 [AppOpenAd] Опит за показване...")

        // 1. Проверка на абонамент
        guard SubscriptionManager.shared.subscriptionStatus == .base else {
            print("💎 [AppOpenAd] Premium потребител - не показваме реклама.")
            return
        }

        // 2. Ако вече се показва, излизаме
        if isShowingAd { return }

        // 3. Проверка дали има готова реклама
        guard isAdAvailable() else {
            print("ℹ️ [AppOpenAd] Няма готова реклама. Опитваме зареждане за следващия път.")
            // ВАЖНО: Не променяме shouldShowNextAd. Ако сега не успеем,
            // искаме да се покаже веднага щом е налична (при следващото отваряне).
            Task { await loadAd() }
            return
        }

        // 4. Логика "През път"
        // Тук влизаме само ако ИМА готова реклама.
        if shouldShowNextAd {
            // Показваме рекламата
            if let root = getRootViewController() {
                print("▶️ [AppOpenAd] Показваме реклама.")
                isShowingAd = true
                appOpenAd?.present(from: root)
                
                // Следващият път трябва да пропуснем
                shouldShowNextAd = false
            }
        } else {
            // Пропускаме рекламата (логика "през път")
            print("⏭️ [AppOpenAd] Пропускаме този път (логика 'през път').")
            
            // Следващият път трябва да покажем
            shouldShowNextAd = true
            
            // Тъй като не я изгорихме, тя си стои заредена за следващия път,
            // освен ако не изтече (4 часа).
        }
    }

    // MARK: - FullScreenContentDelegate

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        print("❌ [AppOpenAd] Fail: \(error.localizedDescription)")
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("🙋‍♂️ [AppOpenAd] Рекламата е затворена.")
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }

    // MARK: - Helpers

    private func isAdAvailable() -> Bool {
        guard let loadTime = loadTime else { return false }
        let age = Date().timeIntervalSince(loadTime)
        return appOpenAd != nil && age < (4 * 3600) // Валидна 4 часа
    }
    
    private func getRootViewController() -> UIViewController? {
        return UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }
}
