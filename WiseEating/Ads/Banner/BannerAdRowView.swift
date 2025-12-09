// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Ads/Banner/BannerAdRowView.swift ====
import SwiftUI

struct BannerAdRowView: View {
    @State private var isAdLoaded: Bool = true
    
    // Уникално ID за този конкретен ред.
    // Това кара SwiftUI да създаде нов Coordinator и да изтегли нов банер от пула.
    private let id = UUID()

    var body: some View {
        BannerAdView(adsBool: $isAdLoaded, bucket: .large)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .opacity(isAdLoaded ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isAdLoaded)
            .id(id) // 👈 Важно: Това гарантира уникалност
    }
}
