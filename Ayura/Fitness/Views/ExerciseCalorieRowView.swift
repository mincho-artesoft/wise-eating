import SwiftUI

struct ExerciseCalorieRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: - Input
    let exercise: ExerciseItem
    let duration: Double
    let profile: Profile

    // MARK: - Computed Properties
    private var caloriesBurned: Double {
        guard let met = exercise.metValue else { return 0 }
        let cpm = (met * 3.5 * profile.weight) / 200.0 // Calories per minute
        return cpm * (duration / 60)
    }

    // MARK: - Body
    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnailView(
                item: exercise,
                size: 60,
                cornerRadius: 30
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("\(caloriesBurned, specifier: "%.0f") kcal")
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(String(format: "%.0f", duration))
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)

                Text("sec")
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
    }
}
