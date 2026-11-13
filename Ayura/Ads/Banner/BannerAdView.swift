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

#if canImport(GoogleMobileAds)
    func makeUIView(context: Context) -> SimpleNativeAdView {
        let view = SimpleNativeAdView(frame: .zero)
        view.isHidden = true
        context.coordinator.attach(to: view)
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
        private var hasRequested = false
        private var lastFailedAt: Date?

        init(adsBool: Binding<Bool>) {
            _adsBool = adsBool
        }

        func attach(to view: SimpleNativeAdView) {
            self.nativeView = view
        }

        func loadIfAllowed() {
            let cooldownElapsed = lastFailedAt.map { Date().timeIntervalSince($0) >= 60 } ?? true
            guard !hasRequested,
                  cooldownElapsed,
                  AdsConfiguration.canRequestAds,
                  let adUnitID = AdsConfiguration.adUnitID(for: .native) else {
                return
            }
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
            guard AdsConfiguration.canRequestAds, let nativeView else { return }
            nativeAd.rootViewController = UIApplication.shared.topMostViewController
            nativeView.populate(with: nativeAd)
            nativeView.isHidden = false
            print("[Ads] Native placement loaded.")
            withAnimation {
                adsBool = true
            }
        }

        func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
            AdDiagnostics.failure("Native placement load", error)
            lastFailedAt = Date()
            hasRequested = false
            withAnimation {
                adsBool = false
            }
        }
    }

#else
    func makeUIView(context: Context) -> UIView {
        adsBool = false
        return UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
#endif
}
