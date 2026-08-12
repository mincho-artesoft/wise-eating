import SwiftUI

/// Кръг, който показва колко от зададените нутриентни цели са изпълнени.
/// – progress = achieved / total
/// – в центъра: “x / y”
struct GoalRingView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let achieved: Int
    let total: Int
    var diameter: CGFloat = 60         // смени размера по вкус

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(achieved) / Double(total)
    }

    // НОВО: Изчисляемо свойство за цвета на прогреса
    private var progressColor: Color {
        if progress < 1.0 {
            return .red // Червен, когато не е пълен
        } else {
            return .green // Целевият цвят, когато е пълен
        }
    }

    var body: some View {
        ZStack {
            // фонов трак
            TubularRingStroke(
                shape: Circle(),
                style: effectManager.currentGlobalAccentColor.opacity(0.2),
                strokeStyle: StrokeStyle(lineWidth: 6),
                role: .track
            )

            // прогрес
            TubularRingStroke(
                shape: Circle().trim(from: 0, to: progress),
                style: progressColor,
                strokeStyle: StrokeStyle(lineWidth: 6, lineCap: .butt)
            )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            // текст “x / y”
            Text("\(achieved) / \(total)")
                .font(.caption.monospacedDigit())
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .ringCenterDepth()
        }
        .frame(width: diameter, height: diameter)
    }
}
