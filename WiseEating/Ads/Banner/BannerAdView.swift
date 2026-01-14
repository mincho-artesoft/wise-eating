import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct BannerAdView: UIViewRepresentable {
    @Binding var adsBool: Bool
    let bucket: BannerBucket
    
    // MARK: - UIViewRepresentable
    
#if !targetEnvironment(macCatalyst)
    // --- iOS VERSION ---
    func makeUIView(context: Context) -> BannerView {
        let rootVC = keyWindowRootViewController()
        let banner = BannerAdPool.shared.dequeueBanner(
            for: bucket,
            rootViewController: rootVC,
            delegate: context.coordinator
        )
        return banner
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(adsBool: $adsBool) }
    
    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var adsBool: Bool
        init(adsBool: Binding<Bool>) { _adsBool = adsBool }
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) { adsBool = true }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) { adsBool = false }
    }

#else
    // --- MAC CATALYST VERSION ---
    // Използваме helper-а от AdSenseSupport.swift
    func makeUIView(context: Context) -> some UIView {
        let controller = UIHostingController(rootView: AdSenseBannerView())
        controller.view.backgroundColor = .clear
        return controller.view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {}
    
    func makeCoordinator() -> () { }
#endif
}
