import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct BannerAdView: UIViewRepresentable {
    @Binding var adsBool: Bool
    let bucket: BannerBucket

#if canImport(GoogleMobileAds)
    // MARK: - iOS IMPLEMENTATION
    
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        guard
            AdsConfiguration.shouldShowAds,
            let adUnitID = AdsConfiguration.adUnitID(for: .banner)
        else {
            adsBool = false
            return banner
        }
        banner.adUnitID = adUnitID
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            banner.rootViewController = root
        }
        
        banner.delegate = context.coordinator
        banner.load(Request())
        
        return banner
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, BannerViewDelegate {
        let parent: BannerAdView
        init(_ parent: BannerAdView) { self.parent = parent }
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            withAnimation {
                parent.adsBool = true
            }
        }
        
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            withAnimation {
                parent.adsBool = false
            }
        }
    }

#else
    // MARK: - ADS SDK DISABLED STUB
    
    func makeUIView(context: Context) -> UIView {
        adsBool = false
        return UIView()
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
#endif
}
