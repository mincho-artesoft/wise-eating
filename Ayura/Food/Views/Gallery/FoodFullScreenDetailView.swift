import SwiftUI

struct FoodFullScreenDetailView: View {
    let item: FoodItem
    var onUse: (FoodItem) -> Void
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var effectManager = EffectManager.shared
    
    @State private var image: UIImage? = nil
    
    var body: some View {
        ZStack {
            // 1. Използваме глобалната тема за фон
            ThemeBackgroundView().ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // Изображение
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                        .padding(.horizontal)
                        // Сянката вече използва акцентния цвят за по-добра интеграция с темата
                        .shadow(color: effectManager.currentGlobalAccentColor.opacity(0.4), radius: 25, y: 10)
                } else {
                    ZStack {
                        // Placeholder, ако няма снимка
                        Circle()
                            .fill(effectManager.currentGlobalAccentColor.opacity(0.1))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "fork.knife")
                            .font(.system(size: 50))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                        
                        ProgressView()
                            .tint(effectManager.currentGlobalAccentColor)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                    }
                }
                
                Spacer()
                
                // Долен панел с информация и бутони (Glass Effect)
                VStack(spacing: 24) {
                    // Име на продукта
                    Text(item.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Бутони
                    HStack(spacing: 20) {
                        // Cancel Button
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                        .glassCardStyle(cornerRadius: 20)
                        
                        // Use Button (Primary)
                        Button(action: {
                            onUse(item)
                        }) {
                            Text("Use")
                                .font(.headline.weight(.bold))
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                // Добавяме лек фон за акцент на Primary бутона
                                .background(effectManager.currentGlobalAccentColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(effectManager.currentGlobalAccentColor.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(24)
                .glassCardStyle(cornerRadius: 30) // Глас ефект за целия долен панел
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .task {
            // Логика за зареждане на снимката
            if let loaded = item.foodImage(variant: "1024") {
                withAnimation(.easeOut(duration: 0.5)) {
                    self.image = loaded
                }
            } else if let fallback = item.foodImage(variant: "144") {
                withAnimation(.easeOut(duration: 0.5)) {
                    self.image = fallback
                }
            }
        }
    }
}
