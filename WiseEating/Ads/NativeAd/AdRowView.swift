// ==== FILE: /Ads/NativeAd/AdRowView.swift ====
import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct AdRowView: View {
    // Използваме StateObject - loader-ът живее само докато този ред е на екрана (или в паметта на List-а)
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
            
            // Ако имаме заредена реклама -> показваме я
            if let nativeAd = loader.nativeAd {
                NativeAdViewWrapper(nativeAd: nativeAd)
                    .frame(height: 140)
                    .glassCardStyle(cornerRadius: 20)
                    .transition(.opacity)
            }
            // Ако няма, но пробваме да зареждаме -> празно място (или нищо)
            else {
                Color.clear
                    .frame(height: 1) // Минимална височина докато зареди
                    .onAppear {
                        // ТОВА Е КЛЮЧЪТ ЗА ADMOB POLICY:
                        // Зареждаме само когато View-то се появи на екрана.
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
