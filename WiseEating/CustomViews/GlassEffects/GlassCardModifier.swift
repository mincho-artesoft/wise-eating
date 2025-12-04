import SwiftUI

// MARK: – Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    @ObservedObject private var effectManager = EffectManager.shared
    var cornerRadius: CGFloat
    
    // The 'useSpanShot' parameter is kept for compatibility with existing calls.
    var useSpanShot: Int

    /// A private helper view that encapsulates the logic for creating the main glass background.
    @ViewBuilder
    private func glassBackground(for globalFrame: CGRect) -> some View {
        if useSpanShot == 1, let snapshotImage = effectManager.snapshot {
            
            ZStack {
                // 1. The crisp, non-blurred parallax background for the card content.
                ParallaxBackgroundView(
                    snapshotImage: snapshotImage,
                    globalFrame: globalFrame
                )
                .saturation(effectManager.config.saturation)
                .brightness(effectManager.config.brightness)
                .brightness(effectManager.isLightRowTextColor ? -0.1 : 0.1)

                // 2. The overlay materials for the glass effect.
                if effectManager.config.useAppleMaterial {
                    Rectangle()
                        .fill(.clear)
                        .background {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
                        }
                } else {
                    Color.black.opacity(effectManager.config.customGlassOpacity)
                }
                
                // 3. Optional contrast scrim to improve text readability.
                if effectManager.config.useScrim {
                    LinearGradient(colors: [.black.opacity(0.0001), .black.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                }
            }
        } else {
            // Fallback for when no snapshot is available or effect is disabled.
            Rectangle().fill(.gray.opacity(0.2))
        }
    }

    func body(content: Content) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        content
            .background {
                GeometryReader { geo in
                    let globalFrame = geo.frame(in: .global)
                    
                    glassBackground(for: globalFrame)
                        .allowsHitTesting(false)
                        .clipShape(cardShape)
                }
            }
            .overlay {
                // Use the new, self-contained GlossyBorderView for the beveled effect.
                GlossyBorderView(cornerRadius: cornerRadius)
            }
            .clipShape(cardShape)
    }
}

/// A helper view to encapsulate the parallax background logic.
private struct ParallaxBackgroundView: View {
    let snapshotImage: UIImage
    let globalFrame: CGRect
    
    private let parallaxScale: CGFloat = 1.1

    var body: some View {
        let screenSize = UIScreen.main.bounds.size
        let anchorPoint = UnitPoint(
            x: globalFrame.midX / screenSize.width,
            y: globalFrame.midY / screenSize.height
        )

        Image(uiImage: snapshotImage)
            .resizable()
            .scaledToFill()
            .frame(width: screenSize.width, height: screenSize.height)
            .scaleEffect(parallaxScale, anchor: anchorPoint)
            .offset(x: -globalFrame.minX, y: -globalFrame.minY)
    }
}

// MARK: – Intelligent Contrast Modifier
struct IntelligentContrastModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var effectManager = EffectManager.shared

    private var contrastShader: Shader {
        Shader(
            function: .init(library: .default, name: "intelligentContrastColor"),
            arguments: [ .float(colorScheme == .dark ? 0.65 : 0.35) ]
        )
    }
    
    @ViewBuilder
    private var processedSnapshotImageView: some View {
        if let unwrappedSnapshot = effectManager.snapshot {
            Image(uiImage: unwrappedSnapshot)
                .resizable()
                .scaledToFill()
                .grayscale(1.0)
                .blur(radius: 5)
        } else {
            Color.clear
        }
    }
    
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let globalFrame = proxy.frame(in: .global)
            
            content
                .foregroundColor(.clear)
                .background(alignment: .topLeading) {
                    processedSnapshotImageView
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .colorEffect(contrastShader)
                        .offset(x: -globalFrame.minX, y: -globalFrame.minY)
                }
                .mask(content)
        }
    }
}
