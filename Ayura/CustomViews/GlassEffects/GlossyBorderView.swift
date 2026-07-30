import SwiftUI

/// Creates a realistic, beveled glass border effect by mirroring the content adjacent to each edge.
struct GlossyBorderView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Configuration
    let cornerRadius: CGFloat
    
    // You can adjust these values to fine-tune the effect.
    let borderWidth: CGFloat      = 3.0 // The thickness of the beveled edge.
    let highlightOpacity: Double  = 0.5  // Opacity of the top-left white highlight.
    let shadowOpacity: Double     = 0.35 // Opacity of the bottom-right shadow.
    private let parallaxScale: CGFloat = 1.03 // How much the background moves for parallax.

    private enum PhysicalEdge {
        case top, bottom, left, right
    }

    var body: some View {
        GeometryReader { geo in
            let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            // MASK 1: The continuous, hollow shape for the border area.
            let borderMask = cardShape.stroke(style: StrokeStyle(lineWidth: borderWidth))
            
            ZStack {
                // 1. Composite view of the four flipped/refracted edges.
                // Each edge is now masked twice: once for the shape, and a second time to isolate its specific edge.
                ZStack {
                    // --- TOP BORDER ---
                    refractedEdge(for: .top, in: geo)
                        .mask(borderMask) // First, cut the border shape out of the transformed image.
                        .mask( // Second, use a gradient to keep only the TOP part of that border.
                            LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .center)
                        )

                    // --- BOTTOM BORDER ---
                    refractedEdge(for: .bottom, in: geo)
                        .mask(borderMask)
                        .mask( // Keep only the BOTTOM part.
                            LinearGradient(colors: [.black, .black, .clear], startPoint: .bottom, endPoint: .center)
                        )

                    // --- LEFT BORDER ---
                    refractedEdge(for: .left, in: geo)
                        .mask(borderMask)
                        .mask( // Keep only the LEFT part.
                            LinearGradient(colors: [.black, .black, .clear], startPoint: .leading, endPoint: .center)
                        )
                        
                    // --- RIGHT BORDER ---
                    refractedEdge(for: .right, in: geo)
                        .mask(borderMask)
                        .mask( // Keep only the RIGHT part.
                            LinearGradient(colors: [.black, .black, .clear], startPoint: .trailing, endPoint: .center)
                        )
                }
                .blur(radius: 1.0) // Blur the final composite of the four pieces.

                // 2. A specular highlight on the top and left edges to simulate light reflection.
                cardShape
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(highlightOpacity), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )

                // 3. A subtle inner shadow on the bottom and right edges to add depth.
                cardShape
                    .stroke(
                        LinearGradient(
                            colors: [.black.opacity(shadowOpacity), .clear],
                            startPoint: .bottomTrailing,
                            endPoint: .topLeading
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(cardShape)
            .allowsHitTesting(false)
        }
    }

    // This function and `refractedEdge` from the previous answer are correct.
    // No changes are needed below this line.
    
    /// Creates a view of the background snapshot prepared with the parallax effect.
    @ViewBuilder
    private func parallaxSourceView(for geo: GeometryProxy, additionalOffset: CGSize = .zero) -> some View {
        if let snapshot = effectManager.snapshot {
            let globalFrame = geo.frame(in: .global)
            let parallaxOffsetX = -globalFrame.midX + UIScreen.main.bounds.width / 2
            let parallaxOffsetY = -globalFrame.midY + UIScreen.main.bounds.height / 2
            
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .scaleEffect(
                    parallaxScale,
                    anchor: .init(
                        x: globalFrame.midX / UIScreen.main.bounds.width,
                        y: globalFrame.midY / UIScreen.main.bounds.height
                    )
                )
                .offset(
                    x: parallaxOffsetX + additionalOffset.width,
                    y: parallaxOffsetY + additionalOffset.height
                )
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    
    /// Generates a single refracted edge by fetching adjacent content and flipping it.
    @ViewBuilder
    private func refractedEdge(for edge: PhysicalEdge, in geo: GeometryProxy) -> some View {
        switch edge {
        case .top:
            parallaxSourceView(for: geo, additionalOffset: .init(width: 0, height: -borderWidth))
                .scaleEffect(y: -1, anchor: .top)
        case .bottom:
            parallaxSourceView(for: geo, additionalOffset: .init(width: 0, height: borderWidth))
                .scaleEffect(y: -1, anchor: .bottom)
        case .left:
            parallaxSourceView(for: geo, additionalOffset: .init(width: -borderWidth, height: 0))
                .scaleEffect(x: -1, anchor: .leading)
        case .right:
            parallaxSourceView(for: geo, additionalOffset: .init(width: borderWidth, height: 0))
                .scaleEffect(x: -1, anchor: .trailing)
        }
    }
}
