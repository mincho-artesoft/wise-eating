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
                    // Проверка дали приложението работи на Mac Catalyst
                    #if targetEnvironment(macCatalyst)
                    // На Mac Catalyst винаги показваме само upgrade съдържанието
                    upgradePlanContent
                    #else
                    // На iOS продължаваме със старата логика за редуване
                    switch currentBannerType {
                    case .upgrade:
                        upgradePlanContent
                    case .ad:
                        adBannerContent
                    }
                    #endif
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
            // Проверка и тук, за да сме сигурни, че на Catalyst типът никога не се сменя на .ad
            #if targetEnvironment(macCatalyst)
            currentBannerType = .upgrade
            #else
            currentBannerType = BannerRotationManager.shared.getAndCycle()
            #endif
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
                HStack(spacing: 6) {
                    Image("Sub_Icon")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)

                    Text("Upgrade plan & Support Us")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.white.opacity(0.25))
                .glassCardStyle(cornerRadius: 15)
            }
            .buttonStyle(.plain)
            .foregroundColor(effectManager.currentGlobalAccentColor)

            Spacer()
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    effectManager.isLightRowTextColor ? Color.yellow.opacity(0.5) : Color.green.opacity(0.5)
                )
        )
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
                .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
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
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }
}
