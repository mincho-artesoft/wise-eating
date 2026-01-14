import SwiftUI

struct BannerAdRowView: View {
    @State private var isAdLoaded: Bool = true
    private let id = UUID()

    var body: some View {
        BannerAdView(adsBool: $isAdLoaded, bucket: .large)
            .frame(maxWidth: .infinity)
            .frame(height: 120) // Височината за банера
            .opacity(isAdLoaded ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isAdLoaded)
            .id(id)
    }
}
