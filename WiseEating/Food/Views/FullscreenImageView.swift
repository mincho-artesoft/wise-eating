import SwiftUI

struct FullscreenImageView: View {
    let image: UIImage
    let onClose: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var effectManager = EffectManager.shared
    
    var body: some View {
        ZStack {
            // 1. Използваме глобалната тема за фон
            ThemeBackgroundView().ignoresSafeArea()
            
            // 2. Изображението
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .glassCardStyle(cornerRadius: 0)
                .padding(2)
            
            // 3. Бутон за затваряне
            VStack {
                HStack {
                    Spacer()
                    
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .padding(10)
                    }
                    // Прилагаме стъкления стил
                    .glassCardStyle(cornerRadius: 50)
                    .padding(.top, 30)
                    .padding(.trailing, 30)
                }
                Spacer()
            }
        }
    }
}
