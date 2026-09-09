import SwiftUI

struct BannerAdRowView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var adsConsent = AdsConsentManager.shared
    @State private var isAdLoaded: Bool = true
    private let id = UUID()

    var body: some View {
        if subscriptionManager.subscriptionStatus == .base && adsConsent.canRequestAds {
            BannerAdView(adsBool: $isAdLoaded, bucket: .large)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .opacity(isAdLoaded ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isAdLoaded)
                .id(id)
        }
    }
}
