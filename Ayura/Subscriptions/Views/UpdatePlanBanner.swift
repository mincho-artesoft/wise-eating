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

    @Environment(\.scenePhase) private var scenePhase

    @State private var currentBannerType: BannerRotationManager.BannerType = .upgrade
    @State private var isVisible: Bool = true
    @State private var isAdLoaded: Bool = true
    @State private var hasAppeared: Bool = false

    var body: some View {
        VStack {
            // ✅ СЦЕНАРИЙ 1: ПРОМОЦИЯ (До 17 Януари)
            if subscriptionManager.isPromoActive {
                if subscriptionManager.subscriptionStatus == .removeAds && isVisible {
                    upgradePlanContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // ✅ СЦЕНАРИЙ 2: СТАНДАРТЕН РЕЖИМ (След 17 Януари)
            else if subscriptionManager.subscriptionStatus == .base && isVisible {
                Group {
                    switch currentBannerType {
                    case .upgrade:
                        upgradePlanContent
                    case .ad:
                        if AdsConfiguration.shouldShowAds {
                            adBannerContent
                        } else {
                            upgradePlanContent
                        }
                    }
                }
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
        .padding(.top)
    }

    private func refreshContent() {
        withAnimation {
            currentBannerType = AdsConfiguration.shouldShowAds
                ? BannerRotationManager.shared.getAndCycle()
                : .upgrade
            isVisible = true
        }
    }

    // MARK: - Original Upgrade Banner
    private var upgradePlanContent: some View {
        HStack {
            Spacer()

            Button(action: {
                NotificationCenter.default.post(name: .openSubscriptionFlow, object: nil)
            }) {
                Image("Sub_Icon")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 176.4, height: 61.6, alignment: .center)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Upgrade plan & Support Us")
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 88, alignment: .center)
        .padding(.vertical, 4)
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
        HStack {
            Spacer()
            BannerAdView(adsBool: $isAdLoaded, bucket: .small)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            closeButton
        }
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
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.18), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }
}
