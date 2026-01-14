import SwiftUI
import UIKit

// Зареждаме GoogleMobileAds само ако не сме на Mac Catalyst
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// MARK: - 1. NativeAdLoader (Multi-platform)

#if !targetEnvironment(macCatalyst)
// 📱 === iOS ВЕРСИЯ (Оригинална логика) ===

@MainActor
final class NativeAdLoader: NSObject,
                            ObservableObject,
                            @MainActor AdLoaderDelegate,
                            @MainActor NativeAdLoaderDelegate {

    @Published private(set) var nativeAd: NativeAd?
    private var adLoader: AdLoader?

    private var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return "ca-app-pub-3759868960530173/3629337942"
        #endif
    }

    func loadAd() {
        let options: [GADAdLoaderOptions] = [NativeAdViewAdOptions()]

        let rootVC = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap   { $0.windows }
            .first     { $0.isKeyWindow }?
            .rootViewController

        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: options
        )
        adLoader?.delegate = self

        print("⬇️ [Native] Зареждаме native ad…")
        adLoader?.load(Request())
    }

    // MARK: - Delegates
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
        print("❌ [Native] Грешка при зареждане: \(error.localizedDescription)")
        nativeAd = nil
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("✅ [Native] Получихме NativeAd")
        self.nativeAd = nativeAd
    }
}

#else
// 🖥️ === MAC CATALYST ВЕРСИЯ (Dummy Class) ===
// Този клас съществува само за да не гърми кодът, който се опитва да го създаде.

@MainActor
final class NativeAdLoader: NSObject, ObservableObject {
    // Използваме Any, защото NativeAd типът липсва на Mac
    @Published private(set) var nativeAd: Any? = nil
    
    func loadAd() {
        // На Mac не зареждаме нищо, защото ползваме WebView (AdSense)
        print("🖥️ [Native] Mac Catalyst detected - Native Ads skipped (using AdSense).")
    }
}
#endif


// MARK: - 2. NativeAdContainerView (Wrapper)

struct NativeAdContainerView: View {
    @ObservedObject var loader: NativeAdLoader

    var body: some View {
        #if targetEnvironment(macCatalyst)
        // 🖥️ НА MAC: Показваме HTML AdSense банер
        // Използваме AdSenseBannerView, който създадохме в предишната стъпка.
        // Слагаме му рамка и фон, за да прилича на "карта".
        AdSenseBannerView()
            .frame(height: 140) // Височината на Native рекламата ти
            .background(Color.black.opacity(0.1))
            .cornerRadius(12)
        #else
        // 📱 НА iOS: Показваме истинската Native реклама
        NativeAdContainerView_iOS(loader: loader)
        #endif
    }
}

// MARK: - 3. Implementation Details (iOS Only)

#if !targetEnvironment(macCatalyst)
/// Истинската имплементация, която работи само на iOS с Google SDK
struct NativeAdContainerView_iOS: UIViewRepresentable {
    @ObservedObject var loader: NativeAdLoader

    func makeUIView(context: Context) -> SimpleNativeAdView {
        // Използваме твоя SimpleNativeAdView
        return SimpleNativeAdView(frame: .zero)
    }

    func updateUIView(_ uiView: SimpleNativeAdView, context: Context) {
        if let nativeAd = loader.nativeAd {
            uiView.populate(with: nativeAd)
        }
    }
}
#endif
