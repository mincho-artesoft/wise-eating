//
//  NativeAdPool.swift
//  WiseEating
//
//  Created by Aleksandar Svinarov on 8/12/25.
//


import SwiftUI
import GoogleMobileAds

@MainActor
final class NativeAdPool: NSObject, ObservableObject {
    static let shared = NativeAdPool()
    
    // Настройки
    private let poolSize = 3
    private let adUnitID = "ca-app-pub-3759868960530173/3629337942" // Тестов ID, сменете с вашия
    
    // Кеш с готови реклами
    @Published var availableAds: [NativeAd] = []
    
    // Лоудър
    private var adLoader: AdLoader?
    private var isLoading = false
    
    override private init() {
        super.init()
        // Стартираме зареждане веднага
        preloadAds()
    }
    
    func preloadAds() {
        // Ако имаме достатъчно или вече зареждаме, спираме
        guard availableAds.count < poolSize, !isLoading else { return }
        
        isLoading = true
        print("📥 [AdPool] Preloading ad... (Current pool: \(availableAds.count))")
        
        let rootVC = UIApplication.shared.topMostViewController
        
        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [NativeAdViewAdOptions()]
        )
        adLoader?.delegate = self
        adLoader?.load(Request())
    }
    
    // Взимане на реклама за показване
    func popAd() -> NativeAd? {
        guard !availableAds.isEmpty else {
            preloadAds() // Ако сме празни, поискай спешно
            return nil
        }
        
        let ad = availableAds.removeFirst()
        print("📤 [AdPool] Ad popped. Remaining: \(availableAds.count)")
        
        // Веднага зареждаме нова, за да запълним дупката
        preloadAds()
        
        return ad
    }
}

// Делегат за зареждането
extension NativeAdPool: @preconcurrency NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("✅ [AdPool] Ad received!")
        self.availableAds.append(nativeAd)
        self.isLoading = false
        
        // Ако все още нямаме достатъчно, зареди още една
        if availableAds.count < poolSize {
            preloadAds()
        }
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("❌ [AdPool] Failed: \(error.localizedDescription)")
        self.isLoading = false
        // Може да сложим retry logic тук след малко време
    }
}
