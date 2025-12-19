import SwiftUI
import SwiftData

struct TemplatePlanExerciseDetailRow: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    // Input Data (Template)
    let exercise: TemplateExercise
    let profile: Profile

    // Resolved Real ExerciseItem (if found by name)
    @State private var resolvedExercise: ExerciseItem? = nil

    // Expand state
    @State private var isExpanded: Bool = false

    private var duration: Double { exercise.durationMinutes }

    private var caloriesBurned: Double {
        guard let ex = resolvedExercise, let met = ex.metValue else { return 0 }
        let cpm = (met * 3.5 * profile.weight) / 200.0
        return cpm * duration
    }

    var body: some View {
        VStack(spacing: 0) {

            // --- HEADER ROW (Clickable) ---
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    exerciseImage
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(resolvedExercise?.name ?? exercise.exerciseName)
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

                            Text("•")
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))

                            Text("\(exercise.sets.count) sets")
                                .font(.caption)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Text(String(format: "%.0f", duration))
                            .font(.subheadline)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)

                        Text("min")
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .padding(.leading, 4)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // --- EXPANDED SETS ---
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(effectManager.currentGlobalAccentColor.opacity(0.2))
                        .padding(.vertical, 8)

                    if exercise.sets.isEmpty {
                        Text("No sets detailed.")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                            .padding(.bottom, 4)
                    } else {
                        let sortedSets = exercise.sets.sorted { $0.orderIndex < $1.orderIndex }

                        ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                            // Extracted to helper function to fix compiler error
                            setRow(index: index, set: set)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .glassCardStyle(cornerRadius: 20)
        .task(id: exercise.exerciseName) {
            resolvedExercise = fetchExerciseItem(named: exercise.exerciseName)
        }
    }

    // MARK: - Extracted View Builder to reduce complexity
    @ViewBuilder
    private func setRow(index: Int, set: TemplateSet) -> some View {
        HStack {
            Text("Set \(index + 1)")
                .font(.subheadline.bold())
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))
                .frame(width: 50, alignment: .leading)

            Spacer()

            // REPS OR FAILURE OR TIME
            if set.isToFailure {
                HStack(spacing: 4) {
                    Text("To Failure")
                }
                .foregroundStyle(.orange)
            } else {
                if let val = set.reps {
                    let unitText: String = {
                        if set.isTimeBased {
                            // FIX: Compare with rawValue string because TemplateSet stores `timeUnitString`
                            return set.timeUnitString == TimeUnit.minutes.rawValue ? "min" : "sec"
                        }
                        return "reps"
                    }()

                    Text("\(val) \(unitText)")
                        .font(.subheadline)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.5))
                }
            }

            Spacer()

            // Weight Column
            // FIX: TemplateSet does NOT have a `weight` property.
            // Templates usually just define reps/schemes. We show a placeholder to keep alignment.
            Text("-")
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.5))
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            index % 2 == 0
            ? effectManager.currentGlobalAccentColor.opacity(0.05)
            : Color.clear
        )
        .cornerRadius(8)
    }

    private func fetchExerciseItem(named name: String) -> ExerciseItem? {
        do {
            let desc = FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.name == name }
            )
            return try modelContext.fetch(desc).first
        } catch {
            return nil
        }
    }

    @ViewBuilder
    private var exerciseImage: some View {
        if let data = resolvedExercise?.photo, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if let asset = resolvedExercise?.assetImageName, let uiImage = UIImage(named: asset) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Image(systemName: "dumbbell.fill")
                .resizable()
                .scaledToFit()
                .padding(12)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.6))
                .background(effectManager.currentGlobalAccentColor.opacity(0.1))
                .clipShape(Circle())
        }
    }
}
