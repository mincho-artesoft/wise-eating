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
    
    func loadAd() async {
        guard SubscriptionManager.shared.subscriptionStatus == .base else { return }
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
        guard SubscriptionManager.shared.subscriptionStatus == .base else { return }
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

#endif
}

#if !targetEnvironment(macCatalyst)
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
#endif
