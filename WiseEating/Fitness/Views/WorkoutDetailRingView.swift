import SwiftUI
import SwiftData

struct WorkoutDetailRingView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    // --- START OF MODIFICATION: Inputs are changed ---
    @Bindable var training: Training
    let onDismiss: () -> Void
    let profile: Profile
    let onSaveChanges: () -> Void

    @State private var detailedLog: [ExerciseLog] = []
    @State private var expandedExerciseIDs = Set<Int>()
    
    typealias FocusField = ExerciseLogEntryView.FocusField
    
    @FocusState private var focusedSetField: FocusField?

    private var exercises: [ExerciseItem: Double] {
        training.exercises(using: modelContext)
    }

    private var sortedExercises: [ExerciseItem] {
        exercises.keys.sorted { $0.name < $1.name }
    }
    
    private var caloriesBurned: Double {
        exercises.reduce(0.0) { acc, pair in
            let (ex, dur) = pair
            guard let met = ex.metValue, met > 0, dur > 0 else { return acc }
            let cpm = (met * 3.5 * profile.weight) / 200.0
            return acc + cpm * dur
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            mainContent
        }
        .onAppear(perform: loadDetailedLog)
        .onChange(of: detailedLog) { _, _ in saveChanges() }
    }
    
    // --- START OF CORRECTION 2/3: The toolbar is extracted. ---
    private var toolbar: some View {
        HStack {
            Button("Close", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            Spacer()
            Text("Workout Log").font(.headline)
            Spacer()
            Button("Close") {}.hidden().padding(.horizontal, 10).padding(.vertical, 5)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }
    
    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    summaryCard
                    listHeader
                    
                    if sortedExercises.isEmpty {
                        ContentUnavailableView("No Exercises", systemImage: "dumbbell")
                            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                            .padding(.vertical, 40)
                            .glassCardStyle(cornerRadius: 15)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedExercises) { exercise in
                                ExerciseLogEntryView(
                                    exercise: exercise,
                                    profile: profile,
                                    onExpand: { // <-- PASS THE CALLBACK
                                        // Small delay to allow layout to begin update
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            withAnimation {
                                                proxy.scrollTo(exercise.id, anchor: .top)
                                            }
                                        }
                                    },
                                    exerciseLog: logBinding(for: exercise),
                                    isExpanded: expansionBinding(for: exercise.id),
                                    focusedField: $focusedSetField
                                )
                                .id(exercise.id)
                            }
                        }
                    }
                    Spacer(minLength: 150)
                }
                .padding()
            }
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
    
    private var summaryCard: some View {
        HStack {
            Text("Total Burned:")
            Spacer()
            Text("\(caloriesBurned, specifier: "%.0f") kcal")
        }
        .font(.headline)
        .padding()
        .glassCardStyle(cornerRadius: 15)
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }
    
    private var listHeader: some View {
        Text("Logged Exercises")
            .font(.headline)
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadDetailedLog() {
        self.detailedLog = training.detailedLog(using: modelContext)?.logs ?? []
    }

    private func logBinding(for exercise: ExerciseItem) -> Binding<ExerciseLog> {
        Binding<ExerciseLog>(
            get: {
                if let existingLog = detailedLog.first(where: { $0.exerciseID == exercise.id }) {
                    return existingLog
                }
                return ExerciseLog(exerciseID: exercise.id, sets: [])
            },
            set: { newLog in
                if let index = detailedLog.firstIndex(where: { $0.exerciseID == exercise.id }) {
                    detailedLog[index] = newLog
                } else if !newLog.sets.isEmpty {
                    detailedLog.append(newLog)
                }
            }
        )
    }

    private func expansionBinding(for exerciseID: Int) -> Binding<Bool> {
        Binding<Bool>(
            get: { self.expandedExerciseIDs.contains(exerciseID) },
            set: { isExpanding in
                if isExpanding {
                    self.expandedExerciseIDs.insert(exerciseID)
                } else {
                    self.expandedExerciseIDs.remove(exerciseID)
                }
            }
        )
    }

    private func saveChanges() {
        let currentExercises = training.exercises(using: modelContext)
        let logToSave = DetailedTrainingLog(logs: detailedLog)
        
        training.updateNotes(exercises: currentExercises, detailedLog: logToSave)
        
        onSaveChanges()
    }
}
