import SwiftUI
import GoogleMobileAds
import UIKit

@MainActor
final class NativeAdLoader: NSObject,
                            ObservableObject,
                            @preconcurrency AdLoaderDelegate,
                            @preconcurrency NativeAdLoaderDelegate {

    @Published private(set) var nativeAd: NativeAd?

    private var adLoader: AdLoader?
    private let adUnitID = "ca-app-pub-2322123786875027/7272690555"

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

    // MARK: - NativeAdLoaderDelegate / AdLoaderDelegate

    func adLoader(
        _ adLoader: AdLoader,
        didFailToReceiveAdWithError error: any Error
    ) {
        print("❌ [Native] Грешка при зареждане: \(error.localizedDescription)")
        nativeAd = nil
    }

    func adLoader(
        _ adLoader: AdLoader,
        didReceive nativeAd: NativeAd
    ) {
        print("✅ [Native] Получихме NativeAd")
        self.nativeAd = nativeAd
    }
}

// MARK: - SwiftUI контейнер

struct NativeAdContainerView: UIViewRepresentable {
    @ObservedObject var loader: NativeAdLoader

    func makeUIView(context: Context) -> SimpleNativeAdView {
        // ✅ ПРОМЯНА: Директна инстанциация, без XIB/NIB
        return SimpleNativeAdView(frame: .zero)
    }

    func updateUIView(_ uiView: SimpleNativeAdView, context: Context) {
        if let nativeAd = loader.nativeAd {
            uiView.populate(with: nativeAd)
        }
    }
}
