import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    /// A single source of truth that SwiftUI can react to
    @Binding var adsBool: Bool
    
    /// Кой bucket искаме – 50 или 120
    let bucket: BannerBucket
    
    // MARK: - UIViewRepresentable
    func makeUIView(context: Context) -> BannerView {
        let rootVC = keyWindowRootViewController()
        
        // Взимаме банер от пула (или fresh, ако няма готов)
        let banner = BannerAdPool.shared.dequeueBanner(
            for: bucket,
            rootViewController: rootVC,
            delegate: context.coordinator
        )
        
        print("⬇️ [BannerAdView] Using banner from pool for \(bucket)")
        return banner
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {
        // Нищо специално – банерът вече е зареден или ще се зареди.
    }
    
    // MARK: - Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(adsBool: $adsBool)
    }
    
    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var adsBool: Bool
        init(adsBool: Binding<Bool>) { _adsBool = adsBool }
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("✅ [BannerAd] Banner received (UI)")
            adsBool = true
        }
        
        func bannerView(
            _ bannerView: BannerView,
            didFailToReceiveAdWithError error: Error
        ) {
            adsBool = false
            print("❌ [BannerAd] Banner failed (UI): \(error.localizedDescription)")
        }
        
        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            print("👀 [BannerAd] Impression recorded")
        }
        
        func bannerViewWillPresentScreen(_ bannerView: BannerView) {
            print("📺 [BannerAd] Will present full screen content")
        }
        
        func bannerViewWillDismissScreen(_ bannerView: BannerView) {
            print("🙋‍♂️ [BannerAd] Will dismiss full screen content")
        }
        
        func bannerViewDidDismissScreen(_ bannerView: BannerView) {
            print("🚪 [BannerAd] Did dismiss full screen content")
        }
    }
}
