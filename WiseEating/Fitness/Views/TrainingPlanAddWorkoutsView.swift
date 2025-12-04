// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Fitness/TrainingPlanAddWorkoutsView.swift ====
import SwiftUI
import SwiftData

struct TrainingPlanAddWorkoutsView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    let sourceTrainings: [Training]
    let onBack: () -> Void
    let onCancel: () -> Void
    let onNext: ([Training]) -> Void

    @State private var selectedTrainingIDs: Set<UUID>

    init(sourceTrainings: [Training], onBack: @escaping () -> Void, onCancel: @escaping () -> Void, onNext: @escaping ([Training]) -> Void) {
        self.sourceTrainings = sourceTrainings
        self.onBack = onBack
        self.onCancel = onCancel
        self.onNext = onNext
        _selectedTrainingIDs = State(initialValue: Set(sourceTrainings.map { $0.id }))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if sourceTrainings.isEmpty {
                ContentUnavailableView("No Workouts to Add", systemImage: "dumbbell.fill")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            } else {
                List {
                    ForEach(sourceTrainings) { training in
                        trainingRow(for: training)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.01),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 0.95)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Back", action: onBack)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

            Spacer()
            Text("Select Workouts to Add").font(.headline)
            Spacer()

            Button("Next") {
                let selected = sourceTrainings.filter { selectedTrainingIDs.contains($0.id) }
                onNext(selected)
            }
            .disabled(selectedTrainingIDs.isEmpty)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            .foregroundStyle(selectedTrainingIDs.isEmpty ? effectManager.currentGlobalAccentColor.opacity(0.5) : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }

    private func trainingRow(for training: Training) -> some View {
        Button(action: {
            if selectedTrainingIDs.contains(training.id) {
                selectedTrainingIDs.remove(training.id)
            } else {
                selectedTrainingIDs.insert(training.id)
            }
        }) {
            HStack {
                Image(systemName: selectedTrainingIDs.contains(training.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(training.name).font(.headline)
                    Text("\(training.exercises(using: modelContext).count) exercises")
                        .font(.caption).opacity(0.8)
                }
                Spacer()
            }
            .padding()
            .contentShape(Rectangle())
            .glassCardStyle(cornerRadius: 15)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .buttonStyle(.plain)
    }
}
