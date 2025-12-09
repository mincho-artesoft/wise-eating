import SwiftUI
import GoogleMobileAds

// MARK: - Ad Row View
struct AdRowView: View {
    @State private var nativeAd: NativeAd?
    
    var body: some View {
        VStack {
            if let ad = nativeAd {
                // Използваме Wrapper за твоя SimpleNativeAdView
                NativeAdViewWrapper(nativeAd: ad)
                    .frame(height: 140) // Приблизителна височина за native ad
                    .glassCardStyle(cornerRadius: 20)
            } else {
                // Placeholder докато зарежда или ако няма реклама (скрит)
                Color.clear.frame(height: 1)
            }
        }
        .onAppear {
            // Взимаме реклама от пула само ако още нямаме
            if nativeAd == nil {
                nativeAd = NativeAdPool.shared.popAd()
            }
        }
    }
}

// Wrapper за твоя UIKit SimpleNativeAdView
struct NativeAdViewWrapper: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> SimpleNativeAdView {
        // Използваме твоя SimpleNativeAdView
        let view = SimpleNativeAdView(frame: .zero)
        view.populate(with: nativeAd)
        return view
    }
    
    func updateUIView(_ uiView: SimpleNativeAdView, context: Context) {
        // Няма нужда от update, рекламата е статична за клетката
    }
}

