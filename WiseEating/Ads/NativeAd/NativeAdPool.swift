// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Ads/NativeAd/NativeAdPool.swift ====
import SwiftUI
import GoogleMobileAds

@MainActor
final class NativeAdPool: NSObject, ObservableObject {
    static let shared = NativeAdPool()
    
    // Увеличаваме размера на пула, за да имаме резерв при бързо скролване
    private let poolSize = 5
    private let adUnitID = "ca-app-pub-3759868960530173/3629337942"
    
    // Кеш с готови реклами
    @Published var availableAds: [NativeAd] = []
    
    // Лоудъри (множество, за да не се блокираме взаимно)
    private var activeLoaders: Set<AdLoader> = []
    
    override private init() {
        super.init()
        // Първоначално зареждане
        refreshPool()
    }
    
    /// Основен метод за пълнене на басейна
    func refreshPool() {
        // Колко реклами ни трябват още?
        let needed = poolSize - (availableAds.count + activeLoaders.count)
        
        guard needed > 0 else { return }
        
        print("📥 [NativeAdPool] Need \(needed) more ads. Starting loading batch...")
        
        for _ in 0..<needed {
            loadSingleAd()
        }
    }
    
    private func loadSingleAd() {
        let rootVC = UIApplication.shared.topMostViewController
        
        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [NativeAdViewAdOptions()]
        )
        
        loader.delegate = self
        
        // Запазваме референция към лоудъра, за да не бъде deallocated
        activeLoaders.insert(loader)
        
        loader.load(Request())
    }
    
    // Взимане на реклама за показване
    func popAd() -> NativeAd? {
        // Винаги проверяваме дали имаме нужда от още реклами
        defer { refreshPool() }
        
        if !availableAds.isEmpty {
            let ad = availableAds.removeFirst()
            print("📤 [NativeAdPool] Ad popped. Remaining in pool: \(availableAds.count)")
            return ad
        } else {
            print("⚠️ [NativeAdPool] Pool is empty! Returns nil, waiting for loaders.")
            return nil
        }
    }
}

// Делегат за зареждането
extension NativeAdPool: @preconcurrency NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("✅ [NativeAdPool] Ad received!")
        self.availableAds.append(nativeAd)
        self.activeLoaders.remove(adLoader) // Освобождаваме лоудъра
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("❌ [NativeAdPool] Failed: \(error.localizedDescription)")
        self.activeLoaders.remove(adLoader) // Освобождаваме лоудъра
        
        // Опитваме отново след малко закъснение, за да не "удавим" AdMob
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.refreshPool()
        }
    }
}
