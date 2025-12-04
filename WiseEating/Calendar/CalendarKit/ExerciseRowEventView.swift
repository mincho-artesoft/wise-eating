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

    private var image: Image {
        if let photoData = exercise.photo, let uiImage = UIImage(data: photoData) {
            return Image(uiImage: uiImage)
        } else if let assetName = exercise.assetImageName, let uiImage = UIImage(named: assetName) {
            return Image(uiImage: uiImage)
        } else {
            return Image(systemName: "dumbbell.fill")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                .padding(4)
                .background(effectManager.currentGlobalAccentColor.opacity(0.1))
                .clipShape(Circle())
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
