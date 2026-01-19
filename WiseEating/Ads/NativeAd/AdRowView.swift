// ==== FILE: /WiseEating/Ads/NativeAd/AdRowView.swift ====
import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct AdRowView: View {
    @StateObject private var loader = NativeAdLoader()
    @State private var hasLoaded = false
    
    var body: some View {
        VStack {
            #if targetEnvironment(macCatalyst)
            AdSenseBannerView()
                .frame(height: 140)
                .background(Color.black.opacity(0.1))
                .cornerRadius(12)
            #else
            
            if let nativeAd = loader.nativeAd {
                // ✅ FIX: Използваме Wrapper-а (дефиниран по-долу)
                NativeAdViewWrapper(nativeAd: nativeAd)
                    .frame(height: 140)
                    .glassCardStyle(cornerRadius: 20)
                    .transition(.opacity) // ✅ FIX: Добавен transition
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
            #endif
        }
        .padding(.vertical, 4)
    }
}

// ✅ FIX: Добавяме Wrapper-а тук, за да е видим за AdRowView
#if !targetEnvironment(macCatalyst)
struct NativeAdViewWrapper: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> SimpleNativeAdView {
        // Използваме твоя къстъм клас SimpleNativeAdView (от SimpleNativeAdView.swift)
        return SimpleNativeAdView(frame: .zero)
    }
    
    func updateUIView(_ uiView: SimpleNativeAdView, context: Context) {
        uiView.populate(with: nativeAd)
    }
}
#endif
