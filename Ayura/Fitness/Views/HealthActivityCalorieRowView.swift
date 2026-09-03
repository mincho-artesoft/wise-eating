import SwiftUI

struct HealthActivityCalorieRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let activity: HealthActivitySummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(8)
                .foregroundStyle(.green)
                .background(Color.green.opacity(0.12))
                .clipShape(Circle())
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Activity Total")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Image(systemName: "shoeprints.fill")
                        .font(.caption)
                    Text("\(activity.stepCount.formatted()) steps")
                        .font(.caption)
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))

                Text("HealthKit active energy")
                    .font(.caption2)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("\(activity.activeEnergyKilocalories, specifier: "%.0f") kcal")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
    }
}

struct HealthWorkoutActivityRowView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    let activity: HealthWorkoutActivity

    private var durationText: String {
        let totalMinutes = max(1, Int((activity.duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(minutes) min"
    }

    private var timingText: String {
        let startTime = activity.startDate.formatted(date: .omitted, time: .shortened)
        return "\(startTime) • \(durationText)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.symbolName)
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.orange)
                .background(Color.orange.opacity(0.12))
                .clipShape(Circle())
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)

                Text(timingText)
                    .font(.caption)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))

                Text(activity.sourceName)
                    .font(.caption2)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("\(activity.activeEnergyKilocalories, specifier: "%.0f") kcal")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
    }
}
