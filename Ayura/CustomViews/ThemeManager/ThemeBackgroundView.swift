import SwiftUI

struct ThemeBackgroundView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var backgroundManager = BackgroundManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let gradient = themeManager.currentTheme.screenGradient
                
                gradient
                    .animation(.easeIn(duration: 0.5), value: colorScheme)
                    .animation(.easeIn(duration: 0.5), value: themeManager.currentTheme)

                // Използвайте selectedImage вместо backgroundImage
                if let image = backgroundManager.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeIn(duration: 0.4)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Използвайте selectedImage за анимацията
            .animation(.easeIn(duration: 0.4), value: backgroundManager.selectedImage)
        }
        .ignoresSafeArea()
    }
}
