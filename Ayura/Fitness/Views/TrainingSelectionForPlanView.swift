import SwiftUI
import SwiftData

struct TrainingSelectionForPlanView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    let trainings: [Training]
    let onBack: () -> Void
    let onCancel: () -> Void
    let onCreatePlan: ([Training], String) -> Void

    @State private var selectedTrainingIDs: Set<UUID>

    init(trainings: [Training], onBack: @escaping () -> Void, onCancel: @escaping () -> Void, onCreatePlan: @escaping ([Training], String) -> Void) {
        self.trainings = trainings
        self.onBack = onBack
        self.onCancel = onCancel
        self.onCreatePlan = onCreatePlan
        _selectedTrainingIDs = State(initialValue: Set(trainings.map { $0.id }))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if trainings.isEmpty {
                ContentUnavailableView("No Workouts to Copy", systemImage: "dumbbell.fill")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            } else {
                List {
                    ForEach(trainings) { training in
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
            Text("Select Workouts").font(.headline)
            Spacer()

            Button("Create") { handleCreateAction() }
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

    private func handleCreateAction() {
        guard !selectedTrainingIDs.isEmpty else { return }
        let dateString = Date().formatted(date: .abbreviated, time: .omitted)
        let defaultPlanName = "Training Plan \(dateString)"
        let selected = trainings.filter { selectedTrainingIDs.contains($0.id) }
        onCreatePlan(selected, defaultPlanName)
    }
}
