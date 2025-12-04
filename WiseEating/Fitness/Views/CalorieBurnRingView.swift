import SwiftUI

struct CalorieBurnRingView: View {
    // MARK: - Environment & Managers
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Input Properties
    let value: Double
    let target: Double?
    let color: Color
    
    // MARK: - Computed Properties
    private var progress: Double {
        if let targetValue = target, targetValue > 0 {
            return value / targetValue
        }
        return value > 0 ? 1.0 : 0.0
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 6)
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.2))

            Circle()
                .trim(from: 0.0, to: min(progress, 1.0))
                .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear(duration: 0.5), value: progress)
                
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundColor(color)

                Text(String(format: "%.0f", value))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                Text("kcal")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                
            }
        }
    }
}
