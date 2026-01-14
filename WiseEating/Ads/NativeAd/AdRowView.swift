import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct AdRowView: View {
    // Декларираме състоянието само ако сме на iOS, защото NativeAd типът не съществува на Mac
    #if !targetEnvironment(macCatalyst)
    @State private var nativeAd: NativeAd?
    #endif
    
    @State private var hasAttemptedLoad: Bool = false
    
    var body: some View {
        VStack {
            #if targetEnvironment(macCatalyst)
            // 🖥️ MAC CATALYST ВЕРСИЯ
            // Тъй като няма "Native Ads" за уеб, показваме AdSense банер
            // в рамка, която имитира размера на native рекламата.
            AdSenseBannerView()
                .frame(height: 140) // Височината, която искаш
                .background(Color.black.opacity(0.2)) // Лека подложка
                .cornerRadius(20)
            
            #else
            // 📱 iOS ВЕРСИЯ (Оригиналната ти логика)
            if let ad = nativeAd {
                NativeAdViewWrapper(nativeAd: ad)
                    .frame(height: 140)
                    .glassCardStyle(cornerRadius: 20) // Предполагам, че имаш този modifier
                    .transition(.opacity)
            } else {
                // Placeholder, докато зареди
                Color.clear.frame(height: 1)
            }
            #endif
        }
        .onAppear {
            #if !targetEnvironment(macCatalyst)
            loadAdIfNeeded()
            #endif
        }
    }
    
    // Тази функция съществува само за iOS
    #if !targetEnvironment(macCatalyst)
    private func loadAdIfNeeded() {
        if nativeAd != nil { return }
        
        // Опитваме да изтеглим реклама от пула
        if let ad = NativeAdPool.shared.popAd() {
            withAnimation {
                self.nativeAd = ad
            }
        } else {
            // Retry logic
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.nativeAd == nil {
                     if let retryAd = NativeAdPool.shared.popAd() {
                         withAnimation {
                             self.nativeAd = retryAd
                         }
                     }
                }
            }
        }
    }
    #endif
}

// ⚠️ ВАЖНО: Този Wrapper и SimpleNativeAdView не трябва да се компилират за Mac,
// защото ползват GADNativeAd, който липсва.
#if !targetEnvironment(macCatalyst)
struct NativeAdViewWrapper: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> SimpleNativeAdView {
        let view = SimpleNativeAdView(frame: .zero)
        view.populate(with: nativeAd)
        return view
    }
    
    func updateUIView(_ uiView: SimpleNativeAdView, context: Context) {
        // Няма нужда от update
    }
}
#endif
