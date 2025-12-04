import SwiftUI
import SwiftData

struct DailyTrainingPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var aiManager = AIManager.shared

    // MARK: - Input
    let profile: Profile
    let planPreview: TrainingPlanDraft
    let sourceAIGenerationJobID: UUID?
    let onDismiss: () -> Void

    // MARK: - State
    @State private var day: TrainingPlanDayDraft
    @State private var selectedWorkoutID: UUID? = nil
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private enum TrainingAddMode { case append, overwrite }
    @State private var isShowingConfirmation = false
    
    @State private var targetDate: Date = Date()
    
    private static let palette: [Color] = [
        .cyan, .green, .indigo, .orange, .pink, .purple, .blue, .red
    ]
    
    // MARK: - Initializer
    init(
        profile: Profile,
        planPreview: TrainingPlanDraft,
        sourceAIGenerationJobID: UUID?,
        onDismiss: @escaping () -> Void
    ) {
        self.profile = profile
        self.planPreview = planPreview
        self.sourceAIGenerationJobID = sourceAIGenerationJobID
        self.onDismiss = onDismiss
        
        let firstPreviewDay = planPreview.days.first ?? TrainingPlanDayDraft(dayIndex: 1, trainings: [])
        _day = State(initialValue: firstPreviewDay)
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        daySection(for: day)
                    }
                    .padding()
                    
                    Spacer(minLength: 150)
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
            .blur(radius: isSaving ? 1.5 : 0)
            .disabled(isSaving)
            .alert("Error", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
            .onAppear {
                if selectedWorkoutID == nil, let firstWorkout = day.trainings.first {
                    selectedWorkoutID = firstWorkout.id
                }
            }
            .confirmationDialog("Add Workouts to Calendar", isPresented: $isShowingConfirmation, titleVisibility: .visible) {
                Button("Add to Existing Workouts") { processTrainingPlanAddition(mode: .append) }
                Button("Overwrite Existing Workouts", role: .destructive) { processTrainingPlanAddition(mode: .overwrite) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will add workouts for \(targetDate.formatted(date: .abbreviated, time: .omitted)). How should workouts for a specific time slot be handled?")
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            Spacer()
            Text("AI Daily Workout Plan").font(.headline)
            Spacer()
            Button("Add to Day") {
                isShowingConfirmation = true
            }
            .disabled(isSaving)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }
    
    private func daySection(for day: TrainingPlanDayDraft) -> some View {
        let colorMap = colorFor(day.trainings)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggested Workouts")
                    .font(.headline)
                Spacer()
                CustomDatePicker(
                    selection: $targetDate,
                    tintColor: UIColor(effectManager.currentGlobalAccentColor),
                    textColor: .label,
                    minimumDate: Date(),
                    maximumDate: Calendar.current.date(byAdding: .year, value: 1, to: Date())
                )
                .frame(height: 40)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(day.trainings.sorted { ($0.startTime) < ($1.startTime) }) { training in
                        workoutTabButton(for: training, colorMap: colorMap)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if let workoutID = selectedWorkoutID, let workout = day.trainings.first(where: { $0.id == workoutID }) {
                workoutContent(for: workout)
            }
        }
        .animation(.default, value: selectedWorkoutID)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    @ViewBuilder
    private func workoutTabButton(for training: Training, colorMap: [UUID: Color]) -> some View {
        let isSelected = selectedWorkoutID == training.id
        let baseColor = colorMap[training.id] ?? effectManager.currentGlobalAccentColor

        Button {
            withAnimation {
                selectedWorkoutID = training.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(training.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.3))
                    )
                    .glassCardStyle(cornerRadius: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(baseColor, lineWidth: isSelected ? 2 : 0)
                    )
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                let exerciseCount = training.exercises(using: modelContext).count
                if exerciseCount > 0 {
                    ZStack {
                        Circle().fill(baseColor)
                        Text("\(exerciseCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func workoutContent(for training: Training) -> some View {
        VStack {
            let exercises = training.exercises(using: modelContext)
            if !exercises.isEmpty {
                let sorted = exercises.keys.sorted { $0.name < $1.name }
                ForEach(sorted) { exercise in
                    ExerciseCalorieRowView(exercise: exercise, duration: exercises[exercise] ?? 0, profile: profile)
                }
            } else {
                Text("No exercises planned for this workout.")
                    .font(.caption)
                    .italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
    }

    private func colorFor(_ trainings: [Training]) -> [UUID: Color] {
        let sortedTemplates = profile.trainings.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let nameToColor = Dictionary(uniqueKeysWithValues: sortedTemplates.enumerated().map { (idx, template) in
            (template.name, Self.palette[idx % Self.palette.count])
        })
        
        var finalMap: [UUID: Color] = [:]
        for training in trainings {
            finalMap[training.id] = nameToColor[training.name] ?? .gray
        }
        return finalMap
    }
    
    private func processTrainingPlanAddition(mode: TrainingAddMode) {
        Task {
            isSaving = true
            
            let dateToAddTo = targetDate
            let existingTrainings = await CalendarViewModel.shared.trainings(forProfile: profile, on: dateToAddTo)

            for training in day.trainings {
                let template = profile.trainings.first { $0.name == training.name }
                let targetTraining = template?.detached(for: dateToAddTo) ?? training.detached(for: dateToAddTo)
                let existingEvent = existingTrainings.first { $0.name == targetTraining.name }

                var finalExercises = mode == .append ? (existingEvent?.exercises(using: modelContext) ?? [:]) : [:]
                finalExercises.merge(training.exercises(using: modelContext)) { (_, new) in new }

                if finalExercises.isEmpty {
                    if let id = existingEvent?.calendarEventID {
                        _ = await CalendarViewModel.shared.deleteEvent(withIdentifier: id)
                    }
                    continue
                }

                targetTraining.calendarEventID = existingEvent?.calendarEventID
                
                let tempTrainingForPayload = Training(name: "", startTime: Date(), endTime: Date())
                tempTrainingForPayload.updateNotes(exercises: finalExercises, detailedLog: nil)
                let payload = OptimizedInvisibleCoder.encode(from: tempTrainingForPayload.notes ?? "")

                _ = await CalendarViewModel.shared.createOrUpdateTrainingEvent(
                    forProfile: profile,
                    training: targetTraining,
                    exercisesPayload: payload
                )
            }

            if let jobID = sourceAIGenerationJobID {
                await aiManager.deleteJob(byID: jobID)
            }
            
            NotificationCenter.default.post(name: .forceCalendarReload, object: nil)
            
            isSaving = false
            onDismiss()
        }
    }
}
