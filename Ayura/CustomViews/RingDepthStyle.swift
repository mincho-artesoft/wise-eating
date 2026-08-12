import SwiftUI

/// Shared lighting for the circular progress indicators used across the app.
enum RingDepthRole: Equatable {
    case track
    case value
}

/// Draws a stroke as a rounded tube instead of a flat line. The two inset
/// ridges simulate the highlight and self-shadow across a donut cross-section.
struct TubularRingStroke<RingShape: Shape, RingStyle: ShapeStyle>: View {
    let shape: RingShape
    let style: RingStyle
    let strokeStyle: StrokeStyle
    var role: RingDepthRole = .value

    private var lineWidth: CGFloat { strokeStyle.lineWidth }

    private var ridgeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: lineWidth * 0.42,
            lineCap: strokeStyle.lineCap,
            lineJoin: strokeStyle.lineJoin,
            miterLimit: strokeStyle.miterLimit,
            dash: strokeStyle.dash,
            dashPhase: strokeStyle.dashPhase
        )
    }

    private var shadowRidgeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: lineWidth * 0.24,
            lineCap: strokeStyle.lineCap,
            lineJoin: strokeStyle.lineJoin,
            miterLimit: strokeStyle.miterLimit,
            dash: strokeStyle.dash,
            dashPhase: strokeStyle.dashPhase
        )
    }

    private var specularStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: max(0.7, lineWidth * 0.13),
            lineCap: strokeStyle.lineCap,
            lineJoin: strokeStyle.lineJoin,
            miterLimit: strokeStyle.miterLimit,
            dash: strokeStyle.dash,
            dashPhase: strokeStyle.dashPhase
        )
    }

    var body: some View {
        let lightOffset = max(0.8, lineWidth * 0.18)
        let darkOffset = max(0.95, lineWidth * 0.20)
        let ridgeBlur = max(0.35, lineWidth * 0.09)

        ZStack {
            shape.stroke(style, style: strokeStyle)

            // Broad light rolling over the upper-left side of the tube.
            ZStack {
                shape
                    .stroke(.white.opacity(0.78), style: ridgeStyle)
                    .blur(radius: ridgeBlur)
                    .offset(x: -lightOffset, y: -lightOffset)
            }
            .mask {
                shape.stroke(.white, style: strokeStyle)
            }
            .blendMode(.screen)

            // Thin glossy crest keeps the ring visibly rounded at small sizes.
            ZStack {
                shape
                    .stroke(.white.opacity(0.62), style: specularStyle)
                    .offset(x: -lightOffset * 1.12, y: -lightOffset * 1.12)
            }
            .mask {
                shape.stroke(.white, style: strokeStyle)
            }
            .blendMode(.screen)

            // Opposite ridge is the tube's self-shadow, not only a drop shadow.
            ZStack {
                shape
                    .stroke(.black.opacity(0.19), style: shadowRidgeStyle)
                    .blur(radius: ridgeBlur * 0.72)
                    .offset(x: darkOffset * 0.72, y: darkOffset * 0.72)
            }
            .mask {
                shape.stroke(.white, style: strokeStyle)
            }
            .blendMode(.multiply)
        }
        .compositingGroup()
        .shadow(
            color: .white.opacity(0.44),
            radius: max(0.6, lineWidth * 0.12),
            x: -lineWidth * 0.08,
            y: -lineWidth * 0.08
        )
        .shadow(
            color: .black.opacity(0.21),
            radius: max(1.0, lineWidth * 0.22),
            x: lineWidth * 0.16,
            y: lineWidth * 0.19
        )
    }
}

private struct RingDepthModifier: ViewModifier {
    let lineWidth: CGFloat
    let role: RingDepthRole

    private var highlightOpacity: Double {
        role == .track ? 0.82 : 0.60
    }

    private var shadowOpacity: Double {
        role == .track ? 0.24 : 0.32
    }

    func body(content: Content) -> some View {
        let lightOffset = max(0.45, lineWidth * 0.10)
        let darkOffset = max(0.75, lineWidth * 0.15)
        let lightRadius = max(0.55, lineWidth * 0.11)
        let darkRadius = max(0.85, lineWidth * 0.18)

        content
            .compositingGroup()
            // Raised upper-left edge.
            .shadow(
                color: .white.opacity(highlightOpacity),
                radius: lightRadius,
                x: -lightOffset,
                y: -lightOffset
            )
            // Soft lower-right falloff gives the stroke its depth.
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: darkRadius,
                x: darkOffset,
                y: darkOffset
            )
    }
}

/// Gives the values and symbols inside a ring a raised, embossed edge that
/// follows the same upper-left lighting direction as the tubular ring.
private struct RingCenterDepthModifier: ViewModifier {
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            // Crisp lower-right layers form a visible extruded edge.
            .shadow(
                color: .black.opacity(0.24),
                radius: 0,
                x: 0.65 * scale,
                y: 0.80 * scale
            )
            .shadow(
                color: .black.opacity(0.18),
                radius: 0.25 * scale,
                x: 1.25 * scale,
                y: 1.50 * scale
            )
            // Small bright rim and soft falloff make the content feel raised.
            .shadow(
                color: .white.opacity(0.92),
                radius: 0.35 * scale,
                x: -0.65 * scale,
                y: -0.75 * scale
            )
            .shadow(
                color: .black.opacity(0.16),
                radius: 1.20 * scale,
                x: 1.60 * scale,
                y: 1.90 * scale
            )
    }
}

extension View {
    func ringDepth(lineWidth: CGFloat, role: RingDepthRole = .value) -> some View {
        modifier(RingDepthModifier(lineWidth: lineWidth, role: role))
    }

    func ringCenterDepth(scale: CGFloat = 1) -> some View {
        modifier(RingCenterDepthModifier(scale: scale))
    }
}
