import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct AdRowView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var adsConsent = AdsConsentManager.shared
    @StateObject private var loader = NativeAdLoader()
    @State private var hasLoaded = false
    
    var body: some View {
    #if canImport(GoogleMobileAds)
        if subscriptionManager.subscriptionStatus == .base && adsConsent.canRequestAds {
            VStack {
                if let nativeAd = loader.nativeAd {
                    NativeAdViewWrapper(nativeAd: nativeAd)
                        .frame(height: 140)
                        .glassCardStyle(cornerRadius: 20)
                        .transition(.opacity)
                }
                else {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            if !hasLoaded {
                                loader.loadAd()
                                hasLoaded = true
                            }
                        }
                }
            }
            .padding(.vertical, 4)
            .onDisappear {
                loader.nativeAd = nil
                hasLoaded = false
            }
        }
    #endif
    }
}

#if canImport(GoogleMobileAds)
struct NativeAdViewWrapper: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> SimpleNativeAdView {
        return SimpleNativeAdView(frame: .zero)
    }
    
    func updateUIView(_ uiView: SimpleNativeAdView, context: Context) {
        uiView.populate(with: nativeAd)
    }
}
#endif
