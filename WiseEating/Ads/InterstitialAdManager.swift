@preconcurrency import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {

    static let shared = InterstitialAdManager()

    private var interstitialAd: InterstitialAd?
    private var isLoading = false
    
    // ✅ ВАЖНО: Тази променлива липсваше. Трябва да е тук, в началото на класа.
    private var onAdDismissed: (() -> Void)?

    // MARK: - Config
        private var adUnitID: String {
            #if DEBUG
            // Официален Google Test ID за Interstitial
            return "ca-app-pub-3940256099942544/4411468910"
            #else
            // Твоят реален ID
            return "ca-app-pub-3759868960530173/8136285513"
            #endif
        }
    // MARK: - Load
    func loadAd() async {
        guard !isLoading, interstitialAd == nil else { return }
        isLoading = true
        defer { isLoading = false }

        print("⬇️ [Interstitial] Зареждаме…")
        do {
            interstitialAd = try await InterstitialAd.load(with: adUnitID, request: Request())
            interstitialAd?.fullScreenContentDelegate = self
            print("✅ [Interstitial] Успешно заредена")
        } catch {
            print("❌ [Interstitial] Грешка: \(error.localizedDescription)")
            interstitialAd = nil
        }
    }
    
    // ✅ Helper property
    var isReady: Bool {
        return interstitialAd != nil
    }

    // MARK: - Show with Completion
    func showIfAvailable(onDismiss: @escaping () -> Void) {
        print("🎬 [Interstitial] Опит за показване...")

        guard let ad = interstitialAd else {
            print("ℹ️ [Interstitial] Няма реклама -> продължаваме.")
            onDismiss()
            Task { await loadAd() }
            return
        }

        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        else {
            onDismiss()
            return
        }

        // Запазваме действието за по-късно
        self.onAdDismissed = onDismiss
        
        ad.fullScreenContentDelegate = self
        ad.present(from: root)
    }

    // MARK: - Delegate Methods
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        print("❌ [Interstitial] Fail to show: \(error.localizedDescription)")
        interstitialAd = nil
        // Ако не успее да се покаже, веднага извикваме callback-а, за да не блокираме потребителя
        onAdDismissed?()
        onAdDismissed = nil
        Task { await loadAd() }
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("🙋‍♂️ [Interstitial] Рекламата е затворена.")
        interstitialAd = nil
        
        // Изпълняваме действието (генерирането на AI)
        onAdDismissed?()
        onAdDismissed = nil
        
        Task { await loadAd() }
    }
}
