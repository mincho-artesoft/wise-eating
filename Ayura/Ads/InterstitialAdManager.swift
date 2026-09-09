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
    // Keep the consumed ad alive until its presentation delegate finishes.
    private var presentingAd: InterstitialAd?

    var isReady: Bool {
        AdsConfiguration.canRequestAds && !FullScreenAdPresentation.isShowing && interstitialAd != nil
    }

    func reset() {
        interstitialAd = nil
    }

    func loadAd() async {
        guard AdsConfiguration.canRequestAds else {
            interstitialAd = nil
            return
        }
        guard let adUnitID = AdsConfiguration.adUnitID(for: .interstitial) else { return }
        guard !isLoading, interstitialAd == nil else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let ad = try await InterstitialAd.load(with: adUnitID, request: Request())
            guard AdsConfiguration.canRequestAds else { return }
            interstitialAd = ad
            print("[Ads] Interstitial loaded.")
            interstitialAd?.fullScreenContentDelegate = self
        } catch {
            AdDiagnostics.failure("Interstitial load", error)
            interstitialAd = nil
        }
    }

    func showIfAvailable(onDismiss: @escaping () -> Void) {
        guard AdsConfiguration.canRequestAds else {
            print("[Ads] Interstitial skipped: subscription or consent blocks ads.")
            onDismiss()
            return
        }
        guard UIApplication.shared.applicationState == .active,
              let ad = interstitialAd, let root = UIApplication.shared.topMostViewController,
              FullScreenAdPresentation.begin() else {
            print("[Ads] Interstitial skipped: active=\(UIApplication.shared.applicationState == .active), loaded=\(interstitialAd != nil), anotherAd=\(FullScreenAdPresentation.isShowing).")
            onDismiss()
            Task { await loadAd() }
            return
        }
        presentingAd = ad
        interstitialAd = nil
        self.onAdDismissed = onDismiss
        print("[Ads] Interstitial presenting.")
        ad.present(from: root)
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[Ads] Interstitial will present.")
    }
    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        print("[Ads] Interstitial impression recorded.")
    }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        AdDiagnostics.failure("Interstitial presentation", error)
        FullScreenAdPresentation.end()
        presentingAd = nil
        interstitialAd = nil
        onAdDismissed?()
        onAdDismissed = nil
        Task { await loadAd() }
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[Ads] Interstitial dismissed.")
        FullScreenAdPresentation.end()
        presentingAd = nil
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

    func reset() {}
    func loadAd() async {}

    func showIfAvailable(onDismiss: @escaping () -> Void) {
        onDismiss()
    }
}
#endif
