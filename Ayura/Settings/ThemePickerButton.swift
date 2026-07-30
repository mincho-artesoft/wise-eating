import SwiftUI

struct ThemePickerButton: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var backgroundManager = BackgroundManager.shared
    @ObservedObject private var effectManager = EffectManager.shared

    let theme: Theme
    @Binding var selectedTheme: Theme
    
    // ПРЕМАХНЕТЕ този изчисляем параметър от тук.
    // private var isSelected: Bool { ... }
    
    var body: some View {
        // ДЕКЛАРИРАЙТЕ isSelected като локална константа ВЪТРЕ в body.
        let isSelected = theme.id == selectedTheme.id && backgroundManager.selectedImage == nil

        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(theme.screenGradient)
                    .clipShape(
                        Path(CGRect(x: 0, y: 0, width: 60, height: 60))
                    )
            
                Circle()
                    .stroke(effectManager.currentGlobalAccentColor.opacity(0.1), lineWidth: 1)
            }
            .frame(width: 60, height: 60)
            .shadow(radius: 3, y: 2)
            .overlay(
                Group {
                    // Вече можете да използвате isSelected тук без проблеми.
                    if isSelected {
                        Circle()
                            .stroke(effectManager.currentGlobalAccentColor, lineWidth: 4)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
            )
            .frame(width: 68, height: 68)
            .scaleEffect(isSelected ? 1.1 : 1.0)

            Text(theme.name)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                // Тази логика премахва избраното фоново изображение,
                // когато потребителят избере цветова тема.
                backgroundManager.removeBackgroundImage()
                themeManager.setTheme(to: theme)
            }
        }
    }
}
