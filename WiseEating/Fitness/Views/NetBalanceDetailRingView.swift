// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth/WiseEating/Fitness/Views/NetBalanceDetailRingView.swift
import SwiftUI
import SwiftData

struct NetBalanceDetailRingView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    let totalConsumed: Double
    let totalBurned: Double
    let netBalance: Double
    let dailyTrainings: [Training]
    let onDismiss: () -> Void
    let profile: Profile

    private var allExercisesOfTheDay: [(exercise: ExerciseItem, duration: Double)] {
        dailyTrainings
            .flatMap { training in
                training.exercises(using: modelContext)
            }
            .map { (exercise: $0.key, duration: $0.value) }
            .sorted { $0.exercise.name < $1.exercise.name }
    }
    
    init(totalConsumed: Double, totalBurned: Double, netBalance: Double, dailyTrainings: [Training], onDismiss: @escaping () -> Void, profile: Profile) {
        self.totalConsumed = totalConsumed
        self.totalBurned = totalBurned
        self.netBalance = netBalance
        self.dailyTrainings = dailyTrainings
        self.onDismiss = onDismiss
        self.profile = profile
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Close", action: onDismiss)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                Spacer()
                Text("Net Calorie Balance").font(.headline)
                Spacer()
                Button("Close") {}.hidden().padding(.horizontal, 10).padding(.vertical, 5)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()

            VStack(spacing: 16) {
                summaryCard
                
                listHeader
            }
            .padding(.horizontal)
            // Main content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // --- START OF MODIFICATION: Replaced training list with exercise list ---
                    if allExercisesOfTheDay.isEmpty {
                        ContentUnavailableView("No Exercises Logged", systemImage: "dumbbell")
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .padding(.vertical, 40)
                            .glassCardStyle(cornerRadius: 15)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(allExercisesOfTheDay, id: \.exercise.id) { item in
                                ExerciseCalorieRowView(
                                    exercise: item.exercise,
                                    duration: item.duration,
                                    profile: profile
                                )
                            }
                        }
                    }
                    // --- END OF MODIFICATION ---
                    Spacer(minLength: 150)
                }
                .padding()
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: effectManager.currentGlobalAccentColor, location: 0.01),
                        .init(color: effectManager.currentGlobalAccentColor, location: 0.9),
                        .init(color: .clear, location: 0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        Spacer()
    }
    
    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack { Text("Calories Consumed:"); Spacer(); Text("\(totalConsumed, specifier: "%.0f") kcal") }
            HStack { Text("Calories Burned:"); Spacer(); Text("-\(totalBurned, specifier: "%.0f") kcal") }
            Divider()
            HStack {
                Text("Net Balance:").fontWeight(.bold)
                Spacer()
                Text("\(netBalance, specifier: "%+.0f") kcal").fontWeight(.bold)
            }
        }
        .font(.headline)
        .padding()
        .glassCardStyle(cornerRadius: 15)
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }

    private var listHeader: some View {
        // --- START OF MODIFICATION: Changed header text ---
        Text("Exercises Today")
            .font(.headline)
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
        // --- END OF MODIFICATION ---
    }

    // This computed property is no longer used by the body.
    private var trainingsWithCalories: [(training: Training, calories: Double)] {
        dailyTrainings.map { training in
            let exercises = training.exercises(using: modelContext)
            let calories = exercises.reduce(0.0) { acc, pair in
                let (ex, dur) = pair
                guard let met = ex.metValue, met > 0, dur > 0 else { return acc }
                let cpm = (met * 3.5 * profile.weight) / 200.0
                return acc + cpm * dur
            }
            return (training, calories)
        }
        .filter { $0.calories > 0 }
        .sorted { $0.calories > $1.calories }
    }
    
    // This private view is no longer used by the body.
    private struct TrainingSummaryRow: View {
        @ObservedObject private var effectManager = EffectManager.shared
    
        let training: Training
        let calories: Double
    
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                    .background(effectManager.currentGlobalAccentColor.opacity(0.1))
                    .clipShape(Circle())
                    .frame(width: 60, height: 60)
    
                VStack(alignment: .leading, spacing: 2) {
                    Text(training.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
    
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(calories, specifier: "%.0f") kcal burned")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .glassCardStyle(cornerRadius: 20)
        }
    }
}
