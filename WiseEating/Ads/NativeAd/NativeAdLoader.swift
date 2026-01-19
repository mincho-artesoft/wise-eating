// ==== FILE: /Ads/NativeAd/NativeAdLoader.swift ====
import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if !targetEnvironment(macCatalyst)
@MainActor
final class NativeAdLoader: NSObject, ObservableObject, GADNativeAdLoaderDelegate {
    @Published var nativeAd: GADNativeAd?
    private var adLoader: GADAdLoader?
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return "ca-app-pub-3759868960530173/3629337942"
        #endif
    }
    
    func loadAd() {
        // Проверка за абонамент преди заявка, за да не генерираме трафик напразно
        guard SubscriptionManager.shared.subscriptionStatus == .base else { return }

        let rootVC = UIApplication.shared.topMostViewController
        
        let multipleAdsOptions = GADMultipleAdsAdLoaderOptions()
        multipleAdsOptions.numberOfAds = 1 // ТЕГЛИМ САМО ЕДНА!
        
        adLoader = GADAdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [multipleAdsOptions]
        )
        adLoader?.delegate = self
        
        adLoader?.load(GADRequest())
    }
    
    func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        print("✅ [Native] Ad received directly.")
        withAnimation {
            self.nativeAd = nativeAd
        }
    }
    
    func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        print("❌ [Native] Failed to load: \(error.localizedDescription)")
    }
}
#else
// Mac Stub
class NativeAdLoader: ObservableObject {
    @Published var nativeAd: Any? = nil
    func loadAd() {}
}
#endif
