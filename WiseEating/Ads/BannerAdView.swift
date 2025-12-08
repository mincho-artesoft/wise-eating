import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    /// A single source of truth that SwiftUI can react to
    @Binding var adsBool: Bool

    // MARK: - Ad Unit ID (test vs production)
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"

    // MARK: - UIViewRepresentable
    func makeUIView(context: Context) -> BannerView {
        let width  = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)

        let banner = BannerView(adSize: adSize)
        banner.adUnitID           = adUnitID
        banner.delegate           = context.coordinator
        banner.rootViewController = UIApplication
            .shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap   { $0.windows }
            .first     { $0.isKeyWindow }?
            .rootViewController

        print("⬇️ [BannerAd] Зареждаме банер… (adUnitID = \(adUnitID))")
        banner.load(Request())     // start loading the ad
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    // MARK: - Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(adsBool: $adsBool)
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var adsBool: Bool
        init(adsBool: Binding<Bool>) { _adsBool = adsBool }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("✅ [BannerAd] Banner received")
            adsBool = true
        }

        func bannerView(
            _ bannerView: BannerView,
            didFailToReceiveAdWithError error: Error
        ) {
            adsBool = false
            print("❌ [BannerAd] Banner failed: \(error.localizedDescription)")
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            print("👀 [BannerAd] Impression recorded")
        }

        func bannerViewWillPresentScreen(_ bannerView: BannerView) {
            print("📺 [BannerAd] Will present full screen content")
        }

        func bannerViewWillDismissScreen(_ bannerView: BannerView) {
            print("🙋‍♂️ [BannerAd] Will dismiss full screen content")
        }

        func bannerViewDidDismissScreen(_ bannerView: BannerView) {
            print("🚪 [BannerAd] Did dismiss full screen content")
        }
    }
}
