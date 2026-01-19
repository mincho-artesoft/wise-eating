// ==== FILE: /Ads/Banner/BannerAdView.swift ====
import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct BannerAdView: UIViewRepresentable {
    @Binding var adsBool: Bool
    let bucket: BannerBucket
    
    // ID-тата от твоя код
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return "ca-app-pub-3759868960530173/9640938872"
        #endif
    }

#if !targetEnvironment(macCatalyst)
    // --- iOS VERSION ---
    func makeUIView(context: Context) -> GADBannerView {
        // 1. Създаваме стандартен банер
        let banner = GADBannerView(adSize: GADAdSizeBanner) // или GADCurrentOrientationAnchoredAdaptiveBanner
        banner.adUnitID = adUnitID
        
        // 2. Намираме root controller
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            banner.rootViewController = root
        }
        
        banner.delegate = context.coordinator
        
        // 3. Зареждаме веднага (Lazy load - само когато това View се създаде от SwiftUI)
        banner.load(GADRequest())
        
        return banner
    }
    
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, GADBannerViewDelegate {
        let parent: BannerAdView
        init(_ parent: BannerAdView) { self.parent = parent }
        
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            print("✅ Banner loaded")
            withAnimation {
                parent.adsBool = true
            }
        }
        
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("❌ Banner failed: \(error.localizedDescription)")
            withAnimation {
                parent.adsBool = false
            }
        }
    }

#else
    // --- MAC CATALYST VERSION ---
    func makeUIView(context: Context) -> some UIView {
        let controller = UIHostingController(rootView: AdSenseBannerView())
        controller.view.backgroundColor = .clear
        return controller.view
    }
    func updateUIView(_ uiView: UIViewType, context: Context) {}
    func makeCoordinator() -> () {}
#endif
}
