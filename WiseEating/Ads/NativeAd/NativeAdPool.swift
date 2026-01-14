import SwiftUI
import UIKit

// Зареждаме SDK само ако не сме на Mac
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// MARK: - 1. iOS IMPLEMENTATION (Real Logic)
#if !targetEnvironment(macCatalyst)

@MainActor
final class NativeAdPool: NSObject, ObservableObject {
    static let shared = NativeAdPool()
    
    // Намаляваме Pool-a, за да пестим памет.
    private let poolSize = 2
    
    @Published var availableAds: [NativeAd] = []
    
    private var currentLoader: AdLoader?
    private var isLoading = false
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511" // Test ID
        #else
        return "ca-app-pub-3759868960530173/3629337942" // Real ID
        #endif
    }
    
    override private init() {
        super.init()
    }
    
    /// Публичен метод: Извиква се при старт или когато се консумира реклама
    func refreshPool() {
        guard !isLoading else { return }
        guard availableAds.count < poolSize else { return }
        
        startLoadingOne()
    }
    
    private func startLoadingOne() {
        // UIApplication.shared.topMostViewController е твоят extension
        guard let rootVC = UIApplication.shared.topMostViewController else {
            print("⚠️ [NativeAdPool] No root VC found.")
            retryLoad(after: 2.0)
            return
        }
        
        print("📥 [NativeAdPool] Requesting single ad... (Pool: \(availableAds.count)/\(poolSize))")
        isLoading = true
        
        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [NativeAdViewAdOptions()]
        )
        loader.delegate = self
        self.currentLoader = loader
        
        loader.load(Request())
    }
    
    func popAd() -> NativeAd? {
        if !availableAds.isEmpty {
            let ad = availableAds.removeFirst()
            print("📤 [NativeAdPool] Ad popped. Remaining: \(availableAds.count)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refreshPool()
            }
            return ad
        }
        
        refreshPool()
        return nil
    }
    
    private func retryLoad(after seconds: Double) {
        self.isLoading = false
        self.currentLoader = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.refreshPool()
        }
    }
}

// MARK: - Delegate (iOS Only)
extension NativeAdPool: @MainActor AdLoaderDelegate, @MainActor NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("✅ [NativeAdPool] Ad received!")
        self.availableAds.append(nativeAd)
        
        self.currentLoader = nil
        self.isLoading = false
        
        // Рекурсия за зареждане на следващата, ако има нужда
        self.refreshPool()
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        let nsError = error as NSError
        print("❌ [NativeAdPool] Failed: \(error.localizedDescription) (Code: \(nsError.code))")
        
        var delayTime = 5.0
        
        // Проверяваме дали грешката е от Google Ads
        if nsError.domain == GADErrorDomain {
            // Mapping GADError codes (safe logic using raw values)
            switch nsError.code {
            case 1: // No Fill
                delayTime = 30.0
            case 2: // Network Error
                delayTime = 10.0
            case 13: // Too many requests (Limit Exceeded)
                delayTime = 60.0
            default:
                delayTime = 10.0
            }
        }
        
        print("⏳ [NativeAdPool] Waiting \(Int(delayTime))s before retry...")
        
        self.currentLoader = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) { [weak self] in
            self?.isLoading = false
            self?.refreshPool()
        }
    }
}

#else

// MARK: - 2. MAC CATALYST STUB (Placeholder)
// Този код се изпълнява само на Mac. Създаваме фалшиви типове, за да не гърми компилаторът.

// 1. Дефинираме фалшив NativeAd, защото GoogleMobileAds липсва
class NativeAd {}

@MainActor
final class NativeAdPool: NSObject, ObservableObject {
    static let shared = NativeAdPool()
    
    // Празен масив с фалшивия тип
    @Published var availableAds: [NativeAd] = []
    
    override private init() { super.init() }
    
    // Празни методи, които не правят нищо
    func refreshPool() {
        print("🖥️ [NativeAdPool] Mac Catalyst: Refresh ignored (Using AdSense).")
    }
    
    func popAd() -> NativeAd? {
        return nil // На Mac никога нямаме native ads в пула
    }
}

#endif
