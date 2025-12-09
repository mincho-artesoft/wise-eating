// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Main/RootView/UpdatePlanBanner.swift ====
import SwiftUI

// Мениджър за ротацията (Upgrade -> Ad -> Upgrade...).
// Гарантира, че състоянието се помни глобално.
@MainActor
final class BannerRotationManager: ObservableObject {
    static let shared = BannerRotationManager()
    
    enum BannerType {
        case upgrade
        case ad
    }
    
    // Започваме с .upgrade според изискването
    private var nextType: BannerType = .upgrade
    
    /// Връща текущия тип, който трябва да се покаже, и веднага завърта
    /// състоянието за *следващото* извикване.
    func getAndCycle() -> BannerType {
        let typeToShow = nextType
        
        // Подготвяме следващия тип
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
    
    // Следим състоянието на приложението (Active/Background)
    @Environment(\.scenePhase) private var scenePhase
    
    // Локално състояние за текущия изглед
    @State private var currentBannerType: BannerRotationManager.BannerType = .upgrade
    @State private var isVisible: Bool = true
    
    // Състояние за BannerAdView
    @State private var isAdLoaded: Bool = true
    
    // Флаг за избягване на двойно извикване при старт (onAppear + scenePhase)
    @State private var hasAppeared: Bool = false
    
    var body: some View {
        // Показваме само ако е Base план и локално трябва да е видимо
        if subscriptionManager.subscriptionStatus == .base && isVisible {
            Group {
                switch currentBannerType {
                case .upgrade:
                    upgradePlanContent
                case .ad:
                    adBannerContent
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
                // "Следващо извикване" -> когато приложението стане активно отново
                if newPhase == .active && hasAppeared {
                    refreshContent()
                }
            }
        }
    }
    
    /// Изтегля следващия тип от мениджъра и прави банера видим
    private func refreshContent() {
        withAnimation {
            // Взимаме следващия подред (Plan -> Ad -> Plan...)
            currentBannerType = BannerRotationManager.shared.getAndCycle()
            // Винаги го правим видим при ново извикване/рестарт на view-то
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
    
    // MARK: - Ad Banner (Updated)
    private var adBannerContent: some View {
        HStack {
            Spacer()
            
            // Стандартна височина за банер (обикновено 50),
            // за да не става прекалено голям контейнера.
            BannerAdView(adsBool: $isAdLoaded, bucket: .small)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            
            closeButton
        }
        // Малък вертикален padding, за да пасне на височината на upgradePlanContent
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
        )

        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Shared Close Button
    private var closeButton: some View {
        Button(action: {
            withAnimation {
                // Само скриваме текущия.
                // Типът за следващия път вече е подготвен от getAndCycle() при показването.
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
