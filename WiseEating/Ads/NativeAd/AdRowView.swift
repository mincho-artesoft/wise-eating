import SwiftUI
import GoogleMobileAds

struct AdRowView: View {
    @State private var nativeAd: NativeAd?
    @State private var hasAttemptedLoad: Bool = false
    
    var body: some View {
        VStack {
            if let ad = nativeAd {
                NativeAdViewWrapper(nativeAd: ad)
                    .frame(height: 140)
                    .glassCardStyle(cornerRadius: 20)
                    .transition(.opacity) // Плавен преход при поява
            } else {
                // Placeholder, докато зареди или ако няма реклама
                Color.clear.frame(height: 1)
            }
        }
        .onAppear {
            loadAdIfNeeded()
        }
    }
    
    private func loadAdIfNeeded() {
        // Ако вече имаме реклама, не правим нищо (запазваме я стабилна при скрол)
        if nativeAd != nil { return }
        
        // Опитваме да изтеглим реклама от пула
        if let ad = NativeAdPool.shared.popAd() {
            withAnimation {
                self.nativeAd = ad
            }
        } else {
            // Ако пулът е празен, опитваме пак след кратък интервал (retry logic)
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

