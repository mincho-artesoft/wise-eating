import SwiftUI

/// Shared by both launch phases so database preparation has one familiar UI.
struct DatabaseLoadingView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var backgroundManager = BackgroundManager.shared

    private var foreground: Color {
        EffectManager.foregroundColor(
            theme: themeManager.currentTheme,
            background: backgroundManager.selectedImage
        )
    }

    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()

            VStack(spacing: 28) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    .accessibilityHidden(true)

                VStack(spacing: 18) {
                    ProgressView()
                        .tint(foreground)
                        .scaleEffect(1.5)

                    Text("Preparing database…")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(foreground)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                .frame(minWidth: 240)
                .glassCardStyle(cornerRadius: 20, useSnapShot: 0)
            }
            .padding(24)
            .accessibilityIdentifier("database-loading-screen")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(foreground.isLight() ? .dark : .light)
    }
}
