import SwiftUI

struct TrapezoidBorderView<Source: View>: View {
    let source: Source
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let skewAmount: CGFloat

    // Tuned parameters for a better glass effect
    private let blurRadius: CGFloat = 1.0
    private let borderOpacity: Double = 0.7

    init(source: Source, cornerRadius: CGFloat, borderWidth: CGFloat = 1.0) {
        self.source = source
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.skewAmount = borderWidth
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let verticalOffset = (size.height - borderWidth) / 2
            let horizontalOffset = (size.width - borderWidth) / 2

            let borderEffect = ZStack {
                // Top Border
                source.frame(width: size.width, height: size.height).offset(y: verticalOffset)
                    .frame(height: borderWidth).clipped().scaleEffect(y: -1)
                    .clipShape(Trapezoid(type: .top, amount: skewAmount))
                    .frame(maxHeight: .infinity, alignment: .top)

                // Bottom Border
                source.frame(width: size.width, height: size.height).offset(y: -verticalOffset)
                    .frame(height: borderWidth).clipped().scaleEffect(y: -1)
                    .clipShape(Trapezoid(type: .bottom, amount: skewAmount))
                    .frame(maxHeight: .infinity, alignment: .bottom)

                // Left Border
                source.frame(width: size.width, height: size.height).offset(x: horizontalOffset)
                    .frame(width: borderWidth).clipped().scaleEffect(x: -1)
                    .clipShape(Trapezoid(type: .left, amount: skewAmount))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Right Border
                source.frame(width: size.width, height: size.height).offset(x: -horizontalOffset)
                    .frame(width: borderWidth).clipped().scaleEffect(x: -1)
                    .clipShape(Trapezoid(type: .right, amount: skewAmount))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .blur(radius: blurRadius)
            .opacity(borderOpacity)
            
            // ✅ SPECULAR HIGHLIGHT
            // This overlay adds the bright edge that sells the "glass" look.
//            let highlightOverlay = RoundedRectangle(cornerRadius: cornerRadius)
//                .stroke(
//                    LinearGradient(
//                        colors: [.white.opacity(0.8), .white.opacity(0.1), .clear],
//                        startPoint: .topLeading,
//                        endPoint: .bottomTrailing
//                    ),
//                    lineWidth: 2.5
//                )

            borderEffect
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
//                .overlay(highlightOverlay) // Apply the highlight
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.black.opacity(0.2), lineWidth: 1))
                .allowsHitTesting(false)
        }
    }
}
