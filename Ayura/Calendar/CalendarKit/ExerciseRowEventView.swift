import SwiftUI
import UIKit

struct ExerciseRowEventView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let exercise: ExerciseItem
    let duration: Double
    let profile: Profile

    private var caloriesBurned: Double {
        guard let met = exercise.metValue else { return 0 }
        let cpm = (met * 3.5 * profile.weight) / 200.0 // Калории в минуту
        return cpm * duration
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ExerciseThumbnailView(
                item: exercise,
                size: 40,
                cornerRadius: 20
            )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exercise.name)
                        .font(.system(size: 10, weight: .bold)).lineLimit(1)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    Spacer()
                    Text("\(Int(duration)) min")
                        .font(.caption2)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(caloriesBurned, specifier: "%.0f") kcal burned")
                        .font(.caption2)
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
            }
            .layoutPriority(1)
        }
    }
}
