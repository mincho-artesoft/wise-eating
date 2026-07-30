import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(GoogleMobileAds)
@MainActor
class AppOpenAdManager: NSObject {

    static let shared = AppOpenAdManager()
    private var isLoadingAd = false
    private var isShowingAd = false
    private var loadTime: Date?
    

    private var appOpenAd: AppOpenAd?
    
    func loadAd() async {
        guard AdsConfiguration.shouldShowAds else {
            appOpenAd = nil
            loadTime = nil
            return
        }
        guard let adUnitID = AdsConfiguration.adUnitID(for: .appOpen) else { return }
        guard !isLoadingAd && !isAdAvailable() else { return }

        isLoadingAd = true
        defer { isLoadingAd = false }

        do {
            appOpenAd = try await AppOpenAd.load(with: adUnitID, request: Request())
            appOpenAd?.fullScreenContentDelegate = self
            loadTime = Date()
        } catch {
            print("❌ [AppOpen] Error: \(error.localizedDescription)")
        }
    }
    
    private func isAdAvailable() -> Bool {
        guard let loadTime = loadTime else { return false }
        return appOpenAd != nil && Date().timeIntervalSince(loadTime) < (4 * 3600)
    }

    func showAdIfAvailable(forceShow: Bool = false) { // Параметърът forceShow вече не е нужен, но можем да го оставим за съвместимост
        guard AdsConfiguration.shouldShowAds else { return }
        if isShowingAd { return }
        
        if !isAdAvailable() {
            Task { await loadAd() }
            return
        }

        // Премахваме брояча и проверката за честота.
        // Рекламата се показва винаги, когато е налична.
        if let root = keyWindowRootViewController() {
            isShowingAd = true
            appOpenAd?.present(from: root)
        }
    }

}

extension AppOpenAdManager: FullScreenContentDelegate {
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }
}
#else
@MainActor
final class AppOpenAdManager: NSObject {
    static let shared = AppOpenAdManager()

    func loadAd() async {}
    func showAdIfAvailable(forceShow: Bool = false) {}
}
#endif
