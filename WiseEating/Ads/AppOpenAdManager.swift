@preconcurrency import GoogleMobileAds
import UIKit

@MainActor
class AppOpenAdManager: NSObject, FullScreenContentDelegate {

    static let shared = AppOpenAdManager()

    private var appOpenAd: AppOpenAd?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var loadTime: Date?

    // MARK: - Ad Unit ID – тестов App-Open
    private let adUnitID = "ca-app-pub-3940256099942544/5575463023"

    // MARK: - Public API

    /// Зарежда нов спот (ако няма или е експирал).
    func loadAd() async {
        guard !isLoadingAd else {
            print("🟡 [AppOpenAd] loadAd() пропуснато – вече зареждаме…")
            return
        }
        guard !isAdAvailable() else {
            print("🟡 [AppOpenAd] loadAd() пропуснато – има свежа реклама.")
            return
        }

        isLoadingAd = true
        print("⬇️ [AppOpenAd] Започваме зареждане… (adUnitID = \(adUnitID))")

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

    /// Опитва да покаже реклама, ако има готова.
    func showAdIfAvailable() {
        print("🎬 [AppOpenAd] showAdIfAvailable()")

        // 1. Ако вече показваме реклама → излизаме.
        guard !isShowingAd else {
            print("🟡 [AppOpenAd] Вече показваме реклама → abort")
            return
        }

        // 2. Ако още няма готова реклама → зареждаме и се връщаме.
        guard isAdAvailable() else {
            print("ℹ️ [AppOpenAd] Няма налична реклама → ще опитаме да заредим една…")
            Task { await loadAd() }
            return
        }

        // 3. Имаме спот → търсим root UIViewController, за да го презентираме.
        guard let ad = appOpenAd,
              let root = UIApplication.shared
                .connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        else {
            print("⚠️ [AppOpenAd] Не успях да намеря rootViewController → няма да покажа реклама.")
            return
        }

        // 4. Показваме рекламата.
        isShowingAd = true
        print("▶️ [AppOpenAd] Показваме App-Open реклама…")
        ad.present(from: root)
    }

    // MARK: - FullScreenContentDelegate

    /// Новият “will present” callback – `adDidPresentFullScreenContent` е unavailable.
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("📺 [AppOpenAd] adWillPresentFullScreenContent")
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        print("❌ [AppOpenAd] didFailToPresent: \(error.localizedDescription)")
        appOpenAd = nil
        isShowingAd = false
    }

    func adWillDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("🚪 [AppOpenAd] adWillDismissFullScreenContent")
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("🙋‍♂️ [AppOpenAd] adDidDismissFullScreenContent → чистим и презареждаме")
        appOpenAd = nil
        isShowingAd = false

        Task { await loadAd() }
    }

    // MARK: - Helpers

    private func isAdAvailable() -> Bool {
        guard let loadTime else {
            print("🔍 [AppOpenAd] isAdAvailable? → false (няма loadTime)")
            return false
        }
        let age = Date().timeIntervalSince(loadTime)
        let fresh = age < 4 * 3600
        print("🔍 [AppOpenAd] isAdAvailable? appOpenAd=\(appOpenAd != nil), age=\(Int(age))s, fresh=\(fresh)")
        return appOpenAd != nil && fresh
    }
}
