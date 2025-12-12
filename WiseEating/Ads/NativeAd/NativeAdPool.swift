import SwiftUI
import GoogleMobileAds

@MainActor
final class NativeAdPool: NSObject, ObservableObject {
    static let shared = NativeAdPool()
    
    // 👇 ПРОМЯНА: Намаляваме от 5 на 3, за да облекчим WebKit процеса
    private let poolSize = 3
    private let adUnitID = "ca-app-pub-3759868960530173/3629337942"
    
    @Published var availableAds: [NativeAd] = []
    
    private var activeLoaders: Set<AdLoader> = []
    
    override private init() {
        super.init()
    }
    
    func refreshPool() {
        let needed = poolSize - (availableAds.count + activeLoaders.count)
        guard needed > 0 else { return }
        
        print("📥 [NativeAdPool] Need \(needed) more ads. Staggering loads...")
        
        // 👇 ПРОМЯНА: Увеличаваме паузата на 2.5 секунди между заявките
        for i in 0..<needed {
            let delay = Double(i) * 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.loadSingleAd()
            }
        }
    }
    
    private func loadSingleAd() {
        let currentCount = availableAds.count + activeLoaders.count
        if currentCount >= poolSize { return }
        
        // Важно: Проверка за активен контролер
        guard let rootVC = UIApplication.shared.topMostViewController else {
            print("⚠️ [NativeAdPool] No root VC found, skipping load.")
            return
        }
        
        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [NativeAdViewAdOptions()]
        )
        
        loader.delegate = self
        activeLoaders.insert(loader)
        
        print("📥 [NativeAdPool] Requesting single ad...")
        loader.load(Request())
    }
    
    func popAd() -> NativeAd? {
        // Зареждаме нови, само ако имаме поне една, за да не останем без.
        // Но с по-голямо закъснение (5 сек), за да не пречим на UI скролирането.
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.refreshPool()
            }
        }
        
        if !availableAds.isEmpty {
            let ad = availableAds.removeFirst()
            print("📤 [NativeAdPool] Ad popped. Remaining in pool: \(availableAds.count)")
            return ad
        } else {
            return nil
        }
    }
}

extension NativeAdPool: @preconcurrency NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("✅ [NativeAdPool] Ad received!")
        self.availableAds.append(nativeAd)
        self.activeLoaders.remove(adLoader)
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("❌ [NativeAdPool] Failed: \(error.localizedDescription)")
        self.activeLoaders.remove(adLoader)
        
        // При грешка чакаме много повече (15 сек), преди да пробваме пак
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.refreshPool()
        }
    }
}
