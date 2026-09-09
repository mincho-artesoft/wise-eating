import SwiftUI

/// Shared lighting for horizontal data bars and scales. It rounds the visual
/// cross-section without changing the bar's layout or any surrounding labels.
private struct TubularBarDepthModifier: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.78), location: 0),
                        .init(color: .white.opacity(0.26), location: 0.30),
                        .init(color: .clear, location: 0.52),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask { content }
                .blendMode(.screen)
                .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.12), location: 0.72),
                        .init(color: .black.opacity(0.30), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask { content }
                .blendMode(.multiply)
                .allowsHitTesting(false)
            }
            .compositingGroup()
            .shadow(
                color: .white.opacity(0.50),
                radius: max(0.45, height * 0.09),
                x: 0,
                y: -max(0.35, height * 0.06)
            )
            .shadow(
                color: .black.opacity(0.22),
                radius: max(0.75, height * 0.15),
                x: 0,
                y: max(0.70, height * 0.13)
            )
    }
}

extension View {
    func tubularBarDepth(height: CGFloat) -> some View {
        modifier(TubularBarDepthModifier(height: height))
    }
}
