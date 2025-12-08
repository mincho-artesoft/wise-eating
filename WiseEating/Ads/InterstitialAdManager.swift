//
//  InterstitialAdManager.swift
//  WiseEating
//
//  Created by Aleksandar Svinarov on 8/12/25.
//


@preconcurrency import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {

    static let shared = InterstitialAdManager()

    private var interstitialAd: InterstitialAd?
    private var isLoading = false

    // MARK: - Test ad unit ID
    private let adUnitID = "ca-app-pub-3940256099942544/4411468910"

    // MARK: - Load

    func loadAd() async {
        guard !isLoading, interstitialAd == nil else {
            print("🟡 [Interstitial] Пропуск loadAd() – вече има/зарежда се.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        print("⬇️ [Interstitial] Зареждаме… \(adUnitID)")
        do {
            interstitialAd = try await InterstitialAd.load(
                with: adUnitID,
                request: Request()
            )
            interstitialAd?.fullScreenContentDelegate = self
            print("✅ [Interstitial] Успешно заредена")
        } catch {
            print("❌ [Interstitial] Грешка при зареждане: \(error.localizedDescription)")
            interstitialAd = nil
        }
    }

    // MARK: - Show

    func showIfAvailable() {
        print("🎬 [Interstitial] showIfAvailable()")

        guard let ad = interstitialAd else {
            print("ℹ️ [Interstitial] Няма готова реклама → опитваме да заредим.")
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
            print("⚠️ [Interstitial] Няма rootViewController.")
            return
        }

        do {
            try ad.canPresent(from: root)
        } catch {
            print("⚠️ [Interstitial] Не може да се покаже: \(error.localizedDescription)")
            interstitialAd = nil
            Task { await loadAd() }
            return
        }

        print("▶️ [Interstitial] Показваме…")
        ad.present(from: root)
    }

    // MARK: - FullScreenContentDelegate

    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("📺 [Interstitial] adWillPresentFullScreenContent")
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        print("❌ [Interstitial] didFailToPresent: \(error.localizedDescription)")
        interstitialAd = nil
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("🙋‍♂️ [Interstitial] adDidDismissFullScreenContent → чистим и презареждаме")
        interstitialAd = nil
        Task { await loadAd() }
    }
}
