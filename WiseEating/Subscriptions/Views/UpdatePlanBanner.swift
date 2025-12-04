import SwiftUI

struct UpdatePlanBanner: View {
    // Компонентът сам си следи мениджърите
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var effectManager = EffectManager.shared
    
    var body: some View {
        // Логиката за проверка: показваме само ако е base план И ако не е затворен
        if subscriptionManager.subscriptionStatus == .base && !subscriptionManager.isPlanBannerDismissed {
            HStack {
                Spacer() // 1. Избутва бутона към центъра (отляво)
                
                Button(action: {
                    // Изпраща сигнал към RootView да отвори абонаментите
                    NotificationCenter.default.post(name: .openSubscriptionFlow, object: nil)
                }) {
                    HStack(spacing: 6) {
                        Image("Sub_Icon")
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                        
                        Text("Update Plan")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(.white.opacity(0.25))
                    // Запазваме оригиналния стъклен стил на бутона
                    .glassCardStyle(cornerRadius: 15)
                }
                .buttonStyle(.plain)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer() // 1. Избутва бутона към центъра (отдясно)
            }
            // Настройки на контейнера (фонът зад бутона)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        effectManager.isLightRowTextColor ? Color.yellow.opacity(0.5) : Color.green.opacity(0.5)
                    )
            )
            // --- БУТОН ЗА ЗАТВАРЯНЕ (X) ---
            .overlay(
                Button(action: {
                    withAnimation {
                        // Това ще скрие банера навсякъде в приложението до рестарт
                        subscriptionManager.isPlanBannerDismissed = true
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.headline) // 1. По-голям размер (беше .caption)
                        .fontWeight(.bold)
                        .foregroundColor(effectManager.currentGlobalAccentColor) // 2. Плътен цвят (без opacity)
                        .padding(10) // Увеличена зона за натискане
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8), // Отстояние от десния ръб
                alignment: .trailing
            )
            // -----------------------------
            
            // Външни отстояния
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
