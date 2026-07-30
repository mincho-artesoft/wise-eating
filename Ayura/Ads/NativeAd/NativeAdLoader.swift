// ==== FILE: /Ayura/Ads/NativeAd/NativeAdLoader.swift ====
import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if !targetEnvironment(macCatalyst)

// ✅ FIX: Помощна структура за прехвърляне на non-Sendable обекти към MainActor
private struct UnsafeSendableAd: @unchecked Sendable {
    let ad: NativeAd
}

@MainActor
final class NativeAdLoader: NSObject, ObservableObject, AdLoaderDelegate, NativeAdLoaderDelegate {
    @Published var nativeAd: NativeAd?
    private var adLoader: AdLoader?
    
    func loadAd() {
        guard
            AdsConfiguration.shouldShowAds,
            let adUnitID = AdsConfiguration.adUnitID(for: .native)
        else {
            nativeAd = nil
            return
        }

        guard let rootVC = UIApplication.shared.topMostViewController else { return }
        
        let multipleAdsOptions = MultipleAdsAdLoaderOptions()
        multipleAdsOptions.numberOfAds = 1
        
        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [multipleAdsOptions]
        )
        adLoader?.delegate = self
        
        adLoader?.load(Request())
    }
    
    // MARK: - Delegates
    
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        // ✅ FIX: Опаковаме рекламата в Sendable кутия
        let safeAd = UnsafeSendableAd(ad: nativeAd)
        
        Task { @MainActor in
            print("✅ [Native] Ad received directly.")
            withAnimation {
                // Разопаковаме я на главната нишка
                self.nativeAd = safeAd.ad
            }
        }
    }
    
    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in
            print("❌ [Native] Failed to load: \(error.localizedDescription)")
        }
    }
}
#else
// Mac Stub
class NativeAdLoader: ObservableObject {
    @Published var nativeAd: Any? = nil
    func loadAd() {}
}
#endif
