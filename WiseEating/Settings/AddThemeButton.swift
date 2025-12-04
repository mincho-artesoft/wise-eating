import SwiftUI

struct AddThemeButton: View {
    // Вместо binding, използваме closure за действие. Това прави бутона по-универсален.
    var action: () -> Void
    
    @ObservedObject private var effectManager = EffectManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Фон на кръга
                Circle()
                    .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                
                // Иконата е променена на "plus"
                Image(systemName: "plus")
                    .font(.title2)
                    .fontWeight(.semibold) // Малко по-плътен, за да изпъква
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                // Рамка на кръга
                Circle()
                    .stroke(effectManager.currentGlobalAccentColor.opacity(0.1), lineWidth: 1)
            }
            .frame(width: 60, height: 60)
            .shadow(radius: 3, y: 2)
            .frame(width: 68, height: 68) // Рамка, която дава място на сянката

            // Текстът е променен на "Add Theme"
            Text("Add Theme")
                .font(.caption)
                .fontWeight(.medium)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                // Изпълнява действието, което е подадено отвън
                action()
            }
        }
    }
}
