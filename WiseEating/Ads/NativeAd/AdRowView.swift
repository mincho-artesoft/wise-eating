import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct AdRowView: View {
    @StateObject private var loader = NativeAdLoader()
    @State private var hasLoaded = false
    
    var body: some View {
        VStack {
            #if !targetEnvironment(macCatalyst)
            // iOS логика
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
            #endif
        }
        .padding(.vertical, 4)
    }
}

#if !targetEnvironment(macCatalyst)
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
