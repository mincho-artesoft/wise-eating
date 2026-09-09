import SwiftUI

// Мениджър за ротацията (Upgrade -> Ad -> Upgrade...).
@MainActor
final class BannerRotationManager: ObservableObject {
    static let shared = BannerRotationManager()

    enum BannerType {
        case upgrade
        case ad
    }

    private var nextType: BannerType = .upgrade

    func getAndCycle() -> BannerType {
        let typeToShow = nextType
        if nextType == .upgrade {
            nextType = .ad
        } else {
            nextType = .upgrade
        }
        return typeToShow
    }
}

struct UpdatePlanBanner: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var adsConsent = AdsConsentManager.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var currentBannerType: BannerRotationManager.BannerType = .upgrade
    @State private var isVisible: Bool = true
    @State private var isAdLoaded: Bool = true
    @State private var hasAppeared: Bool = false

    var body: some View {
        Group {
            if subscriptionManager.subscriptionStatus == .base && isVisible {
                Group {
                    switch currentBannerType {
                    case .upgrade:
                        upgradePlanContent
                    case .ad:
                        if AdsConfiguration.canRequestAds && isAdLoaded {
                            adBannerContent
                        } else {
                            upgradePlanContent
                        }
                    }
                }
                .padding(.top)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear {
                    if !hasAppeared {
                        refreshContent()
                        hasAppeared = true
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && hasAppeared {
                        refreshContent()
                    }
                }
            }
        }
        .onChange(of: adsConsent.canRequestAds) { _, ready in
            if ready { isAdLoaded = true }
        }
    }

    private func refreshContent() {
        withAnimation {
            isAdLoaded = true
            currentBannerType = AdsConfiguration.shouldShowAds
                ? BannerRotationManager.shared.getAndCycle()
                : .upgrade
            isVisible = true
        }
    }

    // MARK: - Original Upgrade Banner
    private var upgradePlanContent: some View {
        Button(action: {
            NotificationCenter.default.post(name: .openSubscriptionFlow, object: nil)
        }) {
            Text("Upgrade plan & Support Us")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 76.8, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            Rectangle()
                .fill(effectManager.isLightRowTextColor ? .white.opacity(0.2) : .black.opacity(0.2))
        }
        .glassCardStyle(cornerRadius: 20)
        .overlay(
            closeButton,
            alignment: .trailing
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Ad Banner
    private var adBannerContent: some View {
        HStack(spacing: 0) {
            BannerAdView(adsBool: $isAdLoaded, bucket: .small)
                .frame(width: 320, height: 50)
            closeButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, effectManager.appColorScheme)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Close Button
    private var closeButton: some View {
        Button(action: {
            withAnimation {
                isVisible = false
            }
        }) {
            Image(systemName: "xmark")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .padding(10)
                .background(effectManager.currentGlobalAccentColor.opacity(0.12), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss banner")
        .padding(.trailing, 8)
    }
}
