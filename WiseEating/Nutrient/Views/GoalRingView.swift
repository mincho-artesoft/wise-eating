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
            Circle()
                .stroke(effectManager.currentGlobalAccentColor.opacity(0.2), lineWidth: 6)

            // прогрес
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, // <-- Използваме новото свойство тук
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            // текст “x / y”
            Text("\(achieved) / \(total)")
                .font(.caption.monospacedDigit())
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: diameter, height: diameter)
    }
}
