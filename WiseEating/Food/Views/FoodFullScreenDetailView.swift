import SwiftUI

struct FoodFullScreenDetailView: View {
    let item: FoodItem
    var onUse: (FoodItem) -> Void
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var effectManager = EffectManager.shared
    
    @State private var image: UIImage? = nil
    
    var body: some View {
        ZStack {
            // Фон (черен или темата)
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // Изображение
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding()
                        .shadow(color: effectManager.currentGlobalAccentColor.opacity(0.3), radius: 20)
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
                
                Spacer()
                
                // Име на продукта
                Text(item.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
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
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                    }
                    
                    // Use Button
                    Button(action: {
                        onUse(item)
                    }) {
                        Text("Use")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(effectManager.currentGlobalAccentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
        }
        .task {
            // ✅ ПРОМЯНА: Използваме "" вместо nil
            if let loaded = item.foodImage(variant: "1024") {
                withAnimation {
                    self.image = loaded
                }
            } else if let fallback = item.foodImage(variant: "144") {
                // Fallback към малката, ако няма голяма
                withAnimation {
                    self.image = fallback
                }
            }
        }
    }
}
