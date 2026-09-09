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
    
    func reset() {
        appOpenAd = nil
    }

    func loadAd() async {
        guard AdsConfiguration.canRequestAds else {
            appOpenAd = nil
            loadTime = nil
            return
        }
        guard let adUnitID = AdsConfiguration.adUnitID(for: .appOpen) else { return }
        guard !isLoadingAd && !isAdAvailable() else { return }

        isLoadingAd = true
        defer { isLoadingAd = false }

        do {
            let ad = try await AppOpenAd.load(with: adUnitID, request: Request())
            guard AdsConfiguration.canRequestAds else { return }
            appOpenAd = ad
            print("[Ads] App Open loaded.")
            appOpenAd?.fullScreenContentDelegate = self
            loadTime = Date()
        } catch {
            AdDiagnostics.failure("App Open load", error)
        }
    }
    
    private func isAdAvailable() -> Bool {
        guard let loadTime = loadTime else { return false }
        return appOpenAd != nil && Date().timeIntervalSince(loadTime) < (4 * 3600)
    }

    func showAdIfAvailable(forceShow: Bool = false) { // Параметърът forceShow вече не е нужен, но можем да го оставим за съвместимост
        guard AdsConfiguration.canRequestAds else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        if isShowingAd { return }
        
        if !isAdAvailable() {
            Task { await loadAd() }
            return
        }

        // Премахваме брояча и проверката за честота.
        // Рекламата се показва винаги, когато е налична.
        if let root = keyWindowRootViewController(), root.presentedViewController == nil,
           FullScreenAdPresentation.begin() {
            isShowingAd = true
            print("[Ads] App Open presenting.")
            appOpenAd?.present(from: root)
        }
    }

}

extension AppOpenAdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[Ads] App Open will present.")
    }
    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        print("[Ads] App Open impression recorded.")
    }
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        AdDiagnostics.failure("App Open presentation", error)
        FullScreenAdPresentation.end()
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        print("[Ads] App Open dismissed.")
        FullScreenAdPresentation.end()
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }
}
#else
@MainActor
final class AppOpenAdManager: NSObject {
    static let shared = AppOpenAdManager()

    func reset() {}
    func loadAd() async {}
    func showAdIfAvailable(forceShow: Bool = false) {}
}
#endif
