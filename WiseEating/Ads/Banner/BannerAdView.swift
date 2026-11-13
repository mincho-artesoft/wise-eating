import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Upgraded from low-CPM 320x50 BannerView to rich/video Native Advanced ad
/// (`SimpleNativeAdView`) while preserving the exact `BannerAdView` call-site signature.
struct BannerAdView: UIViewRepresentable {
    @Binding var adsBool: Bool
    let bucket: BannerBucket
    @ObservedObject private var adsConsent = AdsConsentManager.shared

    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return "ca-app-pub-3759868960530173/3629337942"
        #endif
    }

#if !targetEnvironment(macCatalyst)
    func makeUIView(context: Context) -> SimpleNativeAdView {
        let view = SimpleNativeAdView(frame: .zero)
        view.isHidden = true
        context.coordinator.attach(to: view, adUnitID: adUnitID)
        context.coordinator.loadIfAllowed()
        return view
    }

    func updateUIView(_ uiView: SimpleNativeAdView, context: Context) {
        context.coordinator.loadIfAllowed()
    }

    func makeCoordinator() -> Coordinator { Coordinator(adsBool: $adsBool) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency NativeAdLoaderDelegate {
        @Binding private var adsBool: Bool
        private weak var nativeView: SimpleNativeAdView?
        private var adLoader: AdLoader?
        private var adUnitID: String = ""
        private var hasRequested = false
        private var lastFailedAt: Date?

        init(adsBool: Binding<Bool>) {
            _adsBool = adsBool
        }

        func attach(to view: SimpleNativeAdView, adUnitID: String) {
            self.nativeView = view
            self.adUnitID = adUnitID
        }

        func loadIfAllowed() {
            let cooldownElapsed = lastFailedAt.map { Date().timeIntervalSince($0) >= 60 } ?? true
            guard !hasRequested,
                  cooldownElapsed,
                  AdsConsentManager.shared.canRequestAds,
                  AdsConsentManager.shouldShowAds,
                  !adUnitID.isEmpty else { return }
            hasRequested = true

            let mediaOptions = NativeAdMediaAdLoaderOptions()
            mediaOptions.mediaAspectRatio = .any

            let rootVC = UIApplication.shared.topMostViewController
            let loader = AdLoader(
                adUnitID: adUnitID,
                rootViewController: rootVC,
                adTypes: [.native],
                options: [mediaOptions]
            )
            loader.delegate = self
            self.adLoader = loader
            loader.load(Request())
        }

        func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
            guard AdsConsentManager.shared.canRequestAds,
                  AdsConsentManager.shouldShowAds,
                  let nativeView else { return }
            nativeAd.rootViewController = UIApplication.shared.topMostViewController
            nativeView.populate(with: nativeAd)
            nativeView.isHidden = false
            withAnimation {
                adsBool = true
            }
        }

        func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
            lastFailedAt = Date()
            hasRequested = false
            withAnimation {
                adsBool = false
            }
        }
    }
#else
    func makeUIView(context: Context) -> UIView {
        return UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
#endif
}
