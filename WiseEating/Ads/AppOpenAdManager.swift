import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
class AppOpenAdManager: NSObject {

    static let shared = AppOpenAdManager()
    private var isLoadingAd = false
    private var isShowingAd = false
    private var loadTime: Date?
    

#if !targetEnvironment(macCatalyst)
    private var appOpenAd: AppOpenAd?
    private var adUnitID: String {
          #if DEBUG
          return "ca-app-pub-3940256099942544/5575463023"
          #else
          return "ca-app-pub-3759868960530173/2316256277"
          #endif
    }
    
    func reset() {
        appOpenAd = nil
        loadTime = nil
    }

    func loadAd() async {
        guard AdsConsentManager.shouldShowAds,
              AdsConsentManager.shared.canRequestAds else {
            reset()
            return
        }
        guard !isLoadingAd && !isAdAvailable() else { return }

        isLoadingAd = true
        defer { isLoadingAd = false }

        do {
            let ad = try await AppOpenAd.load(with: adUnitID, request: Request())
            guard AdsConsentManager.shouldShowAds,
                  AdsConsentManager.shared.canRequestAds else { return }
            appOpenAd = ad
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
        guard AdsConsentManager.shouldShowAds,
              AdsConsentManager.shared.canRequestAds,
              !ReviewManager.shouldPauseAppOpenAds,
              UIApplication.shared.applicationState == .active else { return }
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
            appOpenAd?.present(from: root)
        }
    }

#endif
}

#if !targetEnvironment(macCatalyst)
extension AppOpenAdManager: FullScreenContentDelegate {
    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        FullScreenAdPresentation.end()
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        FullScreenAdPresentation.end()
        appOpenAd = nil
        isShowingAd = false
        Task { await loadAd() }
    }
}
#endif
