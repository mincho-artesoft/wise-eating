import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
final class InterstitialAdManager: NSObject {

    static let shared = InterstitialAdManager()
    
    private var onAdDismissed: (() -> Void)?
    private var isLoading = false

#if !targetEnvironment(macCatalyst)
    private var interstitialAd: InterstitialAd?
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return "ca-app-pub-3759868960530173/8136285513"
        #endif
    }

    var isReady: Bool { return interstitialAd != nil }

    func loadAd() async {
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
        guard let ad = interstitialAd, let root = keyWindowRootViewController() else {
            onDismiss()
            Task { await loadAd() }
            return
        }
        self.onAdDismissed = onDismiss
        ad.present(from: root)
    }
#endif
}

#if !targetEnvironment(macCatalyst)
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
#endif
