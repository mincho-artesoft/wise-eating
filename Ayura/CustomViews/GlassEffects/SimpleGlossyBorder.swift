import SwiftUI

/// A lightweight, performant glossy border for small elements that doesn't require a snapshot.
/// It uses simple gradients to simulate an inner shadow and a top-left highlight.
struct SimpleGlossyBorder: View {
    let cornerRadius: CGFloat
    let borderWidth: CGFloat = 1.0 // A thin border is usually best for small chips.
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        ZStack {
            // Inner shadow for depth (bottom-right)
            shape
                .stroke(
                    LinearGradient(
                        colors: [.black.opacity(0.4), .clear],
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    ),
                    lineWidth: borderWidth
                )

            // Main highlight for the "glass" look (top-left)
            shape
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.7), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: borderWidth
                )
        }
        .clipShape(shape) // Clip the gradients to the shape
        .allowsHitTesting(false)
    }
}
