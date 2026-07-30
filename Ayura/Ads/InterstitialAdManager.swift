import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(GoogleMobileAds)
@MainActor
final class InterstitialAdManager: NSObject {

    static let shared = InterstitialAdManager()
    
    private var onAdDismissed: (() -> Void)?
    private var isLoading = false

    private var interstitialAd: InterstitialAd?

    var isReady: Bool {
        AdsConfiguration.shouldShowAds && interstitialAd != nil
    }

    func loadAd() async {
        guard AdsConfiguration.shouldShowAds else {
            interstitialAd = nil
            return
        }
        guard let adUnitID = AdsConfiguration.adUnitID(for: .interstitial) else { return }
        guard !isLoading, interstitialAd == nil else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            interstitialAd = try await InterstitialAd.load(with: adUnitID, request: Request())
            interstitialAd?.fullScreenContentDelegate = self
        } catch {
            print("❌ [Interstitial] Error: \(error.localizedDescription)")
            interstitialAd = nil
        }
    }

    func showIfAvailable(onDismiss: @escaping () -> Void) {
        guard AdsConfiguration.shouldShowAds else {
            onDismiss()
            return
        }
        guard let ad = interstitialAd, let root = keyWindowRootViewController() else {
            onDismiss()
            Task { await loadAd() }
            return
        }
        self.onAdDismissed = onDismiss
        ad.present(from: root)
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        interstitialAd = nil
        onAdDismissed?()
        onAdDismissed = nil
        Task { await loadAd() }
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        interstitialAd = nil
        onAdDismissed?()
        onAdDismissed = nil
        Task { await loadAd() }
    }
}
#else
@MainActor
final class InterstitialAdManager: NSObject {
    static let shared = InterstitialAdManager()

    var isReady: Bool { false }

    func loadAd() async {}

    func showIfAvailable(onDismiss: @escaping () -> Void) {
        onDismiss()
    }
}
#endif
