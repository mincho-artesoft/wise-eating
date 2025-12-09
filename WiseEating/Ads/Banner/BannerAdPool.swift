import UIKit
import GoogleMobileAds

/// Хелпър за rootViewController (може и като private func в класа)
func keyWindowRootViewController() -> UIViewController? {
    UIApplication
        .shared
        .connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap   { $0.windows }
        .first     { $0.isKeyWindow }?
        .rootViewController
}

/// Пул за банери – поддържа по 3 предварително заредени за всеки размер
final class BannerAdPool: NSObject, BannerViewDelegate {
    nonisolated(unsafe) static let shared = BannerAdPool()
    
    // MARK: - Config
    private let adUnitID = "ca-app-pub-3759868960530173/9640938872" // тестов
    private let targetPreloadedCount = 3
    
    // MARK: - State
    private var readySmall: [BannerView] = []
    private var readyLarge: [BannerView] = []
    
    /// Кои банери в момента се зареждат и към кой bucket принадлежат
    private var loading: [ObjectIdentifier: BannerBucket] = [:]
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Добре е да се извика още при старта на app-а (напр. в App / AppDelegate)
    func warmUp() {
        ensurePoolFilled(for: .small)
        ensurePoolFilled(for: .large)
    }
    
    /// Взимаме банер за даден bucket.
    /// - Ако има предварително зареден: връщаме него.
    /// - Ако няма: създаваме нов и го зареждаме (без да чакаме).
    func dequeueBanner(
            for bucket: BannerBucket,
            rootViewController: UIViewController?,
            delegate: BannerViewDelegate?
        ) -> BannerView {
            
            // 1. Стартираме зареждане на нови банери, за да запълним дупката, която ще направим
            defer { ensurePoolFilled(for: bucket) }
            
            let banner: BannerView
            
            switch bucket {
            case .small:
                if !readySmall.isEmpty {
                    // ВАЖНО: removeFirst() гарантира, че този банер вече не е в пула
                    // и следващото извикване ще вземе следващия (различен) банер.
                    banner = readySmall.removeFirst()
                    print("📤 [BannerPool] Dequeued SMALL banner. Remaining: \(readySmall.count)")
                } else {
                    banner = makeAndLoadFreshBanner(for: bucket)
                }
            case .large:
                if !readyLarge.isEmpty {
                    banner = readyLarge.removeFirst()
                    print("📤 [BannerPool] Dequeued LARGE banner. Remaining: \(readyLarge.count)")
                } else {
                    banner = makeAndLoadFreshBanner(for: bucket)
                }
            }
            
            banner.rootViewController = rootViewController
            banner.delegate = delegate
            
            return banner
        }
    
    // MARK: - Internal helpers
    
    /// Уверяваме се, че за даден bucket има targetPreloadedCount банера (ready + loading)
    private func ensurePoolFilled(for bucket: BannerBucket) {
        let readyCount: Int
        switch bucket {
        case .small: readyCount = readySmall.count
        case .large: readyCount = readyLarge.count
        }
        
        let loadingCount = loading.values.filter { $0 == bucket }.count
        let total = readyCount + loadingCount
        
        guard total < targetPreloadedCount else { return }
        
        let missing = targetPreloadedCount - total
        for _ in 0..<missing {
            _ = makeAndLoadHiddenBanner(for: bucket)
        }
    }
    
    /// Създава банер, който няма да се показва веднага, а само ще попълни пула.
    @discardableResult
    private func makeAndLoadHiddenBanner(for bucket: BannerBucket) -> BannerView {
        let width  = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = keyWindowRootViewController()
        banner.delegate = self
        
        let id = ObjectIdentifier(banner)
        loading[id] = bucket
        
        print("⬇️ [BannerAdPool] Start loading hidden banner for \(bucket)")
        banner.load(Request())
        
        return banner
    }
    
    /// Създава банер за директно използване (ако пулът е празен)
    private func makeAndLoadFreshBanner(for bucket: BannerBucket) -> BannerView {
        let width  = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = keyWindowRootViewController()
        
        // В този случай вече координаторът на конкретния BannerAdView ще стане delegate,
        // така че тук не записваме в loading и не следим този банер в пула.
        
        print("⬇️ [BannerAdPool] Fresh banner for UI (bucket: \(bucket))")
        banner.load(Request())
        return banner
    }
    
    // MARK: - BannerViewDelegate (за hidden банерите)
    
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        let id = ObjectIdentifier(bannerView)
        guard let bucket = loading.removeValue(forKey: id) else {
            // Този банер не е от пула (fresh), игнорираме
            return
        }
        
        switch bucket {
        case .small:
            readySmall.append(bannerView)
        case .large:
            readyLarge.append(bannerView)
        }
        
        print("✅ [BannerAdPool] Hidden banner loaded for \(bucket). ReadySmall=\(readySmall.count), ReadyLarge=\(readyLarge.count)")
        
        // След като един се е заредил, може пак да допълним ако трябва
        ensurePoolFilled(for: bucket)
    }
    
    func bannerView(
        _ bannerView: BannerView,
        didFailToReceiveAdWithError error: Error
    ) {
        let id = ObjectIdentifier(bannerView)
        let bucket = loading.removeValue(forKey: id)
        
        print("❌ [BannerAdPool] Hidden banner failed (\(bucket.map { "\($0)" } ?? "nil")): \(error.localizedDescription)")
        
        // Опитваме да допълним пула отново (може да добавиш backoff ако искаш)
        if let bucket {
            ensurePoolFilled(for: bucket)
        }
    }
}
