import SwiftUI
import GoogleMobileAds

@MainActor
final class NativeAdPool: NSObject, ObservableObject {
    static let shared = NativeAdPool()
    
    // Намаляваме Pool-a, за да пестим памет. 2 е напълно достатъчно за скролване.
    private let poolSize = 2
    
    @Published var availableAds: [NativeAd] = []
    
    // ПАЗИ СИЛНА РЕФЕРЕНЦИЯ към текущия лоудър, но само един!
    private var currentLoader: AdLoader?
    
    // Флаг, за да не се викат няколко зареждания едновременно
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
        // Ако вече зареждаме нещо, не правим нищо. Чакаме то да свърши.
        guard !isLoading else { return }
        
        // Ако имаме достатъчно реклами, спираме.
        guard availableAds.count < poolSize else { return }
        
        startLoadingOne()
    }
    
    private func startLoadingOne() {
        guard let rootVC = UIApplication.shared.topMostViewController else {
            print("⚠️ [NativeAdPool] No root VC found.")
            // Пробваме пак след малко, ако няма VC
            retryLoad(after: 2.0)
            return
        }
        
        print("📥 [NativeAdPool] Requesting single ad... (Pool: \(availableAds.count)/\(poolSize))")
        isLoading = true
        
        // Създаваме нов лоудър за тази конкретна заявка
        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [NativeAdViewAdOptions()]
        )
        loader.delegate = self
        self.currentLoader = loader // Важно: Retain на лоудъра
        
        loader.load(Request())
    }
    
    func popAd() -> NativeAd? {
        if !availableAds.isEmpty {
            let ad = availableAds.removeFirst()
            print("📤 [NativeAdPool] Ad popped. Remaining: \(availableAds.count)")
            
            // След като вземем реклама, проверяваме дали трябва да заредим нова
            // С малко закъснение, за да не натоварваме UI thread-a веднага
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refreshPool()
            }
            return ad
        }
        
        // Ако нямаме реклама, форсираме опит за зареждане
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

extension NativeAdPool: @preconcurrency NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("✅ [NativeAdPool] Ad received!")
        self.availableAds.append(nativeAd)
        
        // Освобождаваме текущия лоудър и флага
        self.currentLoader = nil
        self.isLoading = false
        
        // Веднага проверяваме дали трябва още една (рекурсия чрез refreshPool)
        // Това гарантира последователност: Зареди 1 -> Успех -> Провери за 2 -> Зареди 2...
        self.refreshPool()
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
            let nsError = error as NSError
            print("❌ [NativeAdPool] Failed: \(error.localizedDescription) (Code: \(nsError.code))")
            
            // Умно управление на грешките
            var delayTime = 5.0
            
            // Проверяваме дали грешката е от Google Ads домейна
            if nsError.domain == GADErrorDomain {
                // В Swift GADErrorCode е заменено с GADError
                switch nsError.code {
                case RequestError.noFill.rawValue:
                    delayTime = 30.0 // Няма реклами, няма смисъл да спамим
                case RequestError.networkError.rawValue:
                    delayTime = 10.0 // Проблем с мрежата
                // 13 често е свързано с лимити, но не винаги е в enum-а, затова го оставяме като magic number или използваме default
                case 13:
                    delayTime = 60.0 // Наказани сме (Too many requests), чакаме дълго
                default:
                    delayTime = 10.0
                }
            }
            
            print("⏳ [NativeAdPool] Waiting \(Int(delayTime))s before retry...")
            
            // Нулираме флаговете ЧАК след изтичане на наказанието
            self.currentLoader = nil
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) { [weak self] in
                self?.isLoading = false
                self?.refreshPool()
            }
        }
}
