@preconcurrency import GoogleMobileAds
import UIKit

@MainActor
class AppOpenAdManager: NSObject, FullScreenContentDelegate {

    static let shared = AppOpenAdManager()

    private var appOpenAd: AppOpenAd?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var loadTime: Date?
    
    // ✅ НАСТРОЙКИ ЗА ЧЕСТОТА
    // На всеки колко пъти да се показва при връщане от background (10)
    private let adFrequency = 10
    
    // Запазваме брояча в UserDefaults, за да се помни между сесиите
    private var presentationCounter: Int {
        get { UserDefaults.standard.integer(forKey: "app_open_ad_count") }
        set { UserDefaults.standard.set(newValue, forKey: "app_open_ad_count") }
    }

    // MARK: - Ad Unit ID
    private let adUnitID = "ca-app-pub-3759868960530173/2316256277"

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

    /// forceShow: Ако е true, рекламата се показва задължително (за студен старт).
    /// Ако е false, се проверява брояча (на всеки 10-ти път).
    func showAdIfAvailable(forceShow: Bool = false) {
        print("🎬 [AppOpenAd] Опит за показване (Force: \(forceShow))...")

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
            Task { await loadAd() }
            return
        }

        // 4. Логика за честота
        // Увеличаваме брояча при всяко потенциално показване (влизане в app-a)
        presentationCounter += 1
        print("🔢 [AppOpenAd] Брояч на влизания: \(presentationCounter). Честота: \(adFrequency)")

        // Условие: ИЛИ е насилствено показване (Cold Start), ИЛИ броячът се дели на 10
        if forceShow || (presentationCounter % adFrequency == 0) {
            
            if let root = getRootViewController() {
                print("▶️ [AppOpenAd] Показваме реклама (Force: \(forceShow) или Брояч % 10 == 0).")
                isShowingAd = true
                appOpenAd?.present(from: root)
            }
        } else {
            // Пропускаме рекламата
            print("⏭️ [AppOpenAd] Пропускаме този път (Остават \(adFrequency - (presentationCounter % adFrequency)) до следващата реклама от background).")
            // Тъй като не я изгорихме, тя си стои заредена за следващия път.
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
