import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct BannerAdView: UIViewRepresentable {
    @Binding var adsBool: Bool
    let bucket: BannerBucket
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return "ca-app-pub-3759868960530173/9640938872"
        #endif
    }

#if !targetEnvironment(macCatalyst)
    // --- iOS VERSION ---
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
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
#endif
}
