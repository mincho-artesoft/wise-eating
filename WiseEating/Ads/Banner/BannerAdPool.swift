import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Хелпър за rootViewController
func keyWindowRootViewController() -> UIViewController? {
    UIApplication
        .shared
        .connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap   { $0.windows }
        .first     { $0.isKeyWindow }?
        .rootViewController
}

#if !targetEnvironment(macCatalyst)
/// ИСТИНСКИЯТ ПУЛ (САМО ЗА iOS)
final class BannerAdPool: NSObject, BannerViewDelegate {
    nonisolated(unsafe) static let shared = BannerAdPool()
    
    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return "ca-app-pub-3759868960530173/9640938872"
        #endif
    }
    private let targetPreloadedCount = 3
    
    private var readySmall: [BannerView] = []
    private var readyLarge: [BannerView] = []
    private var loading: [ObjectIdentifier: BannerBucket] = [:]
    
    private override init() { super.init() }
    
    func warmUp() {
        ensurePoolFilled(for: .small)
        ensurePoolFilled(for: .large)
    }
    
    func dequeueBanner(for bucket: BannerBucket, rootViewController: UIViewController?, delegate: BannerViewDelegate?) -> BannerView {
        defer { ensurePoolFilled(for: bucket) }
        let banner: BannerView
        
        switch bucket {
        case .small:
            if !readySmall.isEmpty {
                banner = readySmall.removeFirst()
            } else {
                banner = makeAndLoadFreshBanner(for: bucket)
            }
        case .large:
            if !readyLarge.isEmpty {
                banner = readyLarge.removeFirst()
            } else {
                banner = makeAndLoadFreshBanner(for: bucket)
            }
        }
        
        banner.rootViewController = rootViewController
        banner.delegate = delegate
        return banner
    }
    
    private func ensurePoolFilled(for bucket: BannerBucket) {
        let readyCount = (bucket == .small) ? readySmall.count : readyLarge.count
        let loadingCount = loading.values.filter { $0 == bucket }.count
        let total = readyCount + loadingCount
        
        guard total < targetPreloadedCount else { return }
        for _ in 0..<(targetPreloadedCount - total) {
            _ = makeAndLoadHiddenBanner(for: bucket)
        }
    }
    
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
        banner.load(Request())
        return banner
    }
    
    private func makeAndLoadFreshBanner(for bucket: BannerBucket) -> BannerView {
        let width  = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = keyWindowRootViewController()
        banner.load(Request())
        return banner
    }
    
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        let id = ObjectIdentifier(bannerView)
        guard let bucket = loading.removeValue(forKey: id) else { return }
        
        switch bucket {
        case .small: readySmall.append(bannerView)
        case .large: readyLarge.append(bannerView)
        }
        ensurePoolFilled(for: bucket)
    }
    
    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        let id = ObjectIdentifier(bannerView)
        let bucket = loading.removeValue(forKey: id)
        if let bucket { ensurePoolFilled(for: bucket) }
    }
}

#else
// MARK: - MAC CATALYST STUB
// На Mac пулът не прави нищо, защото WebViews се зареждат на момента.
final class BannerAdPool: NSObject {
    @MainActor static let shared = BannerAdPool()
    func warmUp() {}
}
#endif
