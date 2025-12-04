import SwiftUI
import SwiftData

struct TrainingPlanAddDestinationView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    @Bindable var targetPlan: TrainingPlan
    let selectedTrainings: [Training]
    let profile: Profile
    let onBack: () -> Void
    let onComplete: () -> Void

    @State private var isReplacing = false
    @State private var selectedWorkoutIDByDay: [TrainingPlanDay.ID: TrainingPlanWorkout.ID?] = [:]

    private static let palette: [Color] = [
        .cyan, .green, .indigo, .orange, .pink, .purple, .blue, .red
    ]

    private var colorFor: [String: Color] {
        let sortedTemplates = profile.trainings.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let n = Self.palette.count
        return Dictionary(uniqueKeysWithValues:
            sortedTemplates.enumerated().map { idx, template in
                (template.name, Self.palette[idx % n])
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    Button(action: addAsNewDay) {
                        Label("Add as New Day", systemImage: "plus.square.on.square")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .padding().glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                    Button(action: { withAnimation { isReplacing.toggle() } }) {
                        Label("Replace an Existing Day", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .padding().glassCardStyle(cornerRadius: 20)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                    if isReplacing {
                        VStack(spacing: 16) {
                            ForEach(Array(targetPlan.days.sorted { $0.dayIndex < $1.dayIndex }.enumerated()), id: \.element.id) { index, day in
                                dayReplacementCard(for: day, dayIndex: index + 1)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
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
            Spacer()
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Back", action: onBack)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            Spacer()
            Text("Choose Destination").font(.headline)
            Spacer()
            Button("Back", action: {}).hidden()
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }

    private func dayReplacementCard(for day: TrainingPlanDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // --- ПРОМЯНА: Проверяваме isRestDay и променяме текста ---
                Text(day.isRestDay ? "Day \(dayIndex): Rest Day" : "Day \(dayIndex)")
                    .font(.headline)
                
                Spacer()
                
                Button("Replace This Day") { replace(day: day) }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 15)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)

            // --- ПРОМЯНА: Показваме съдържанието само ако НЕ е ден за почивка ---
            if !day.isRestDay {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let sortedWorkouts = day.workouts.sorted { w1, w2 in
                            let t1 = profile.trainings.first { $0.name == w1.workoutName }?.startTime ?? .distantFuture
                            let t2 = profile.trainings.first { $0.name == w2.workoutName }?.startTime ?? .distantFuture
                            return t1 < t2
                        }
                        ForEach(sortedWorkouts) { workout in
                            workoutTabButton(for: workout, in: day)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let workoutID = selectedWorkoutIDByDay[day.id],
                   let workout = day.workouts.first(where: { $0.id == workoutID }) {
                    workoutContent(for: workout)
                }
            }
        }
        .padding().glassCardStyle(cornerRadius: 20)
        .animation(.default, value: selectedWorkoutIDByDay[day.id])
    }

    @ViewBuilder
    private func workoutTabButton(for workout: TrainingPlanWorkout, in day: TrainingPlanDay) -> some View {
        let isSelected = selectedWorkoutIDByDay[day.id] == workout.id
        let baseColor = colorFor[workout.workoutName] ?? effectManager.currentGlobalAccentColor

        Button(action: {
            withAnimation {
                if selectedWorkoutIDByDay[day.id] == workout.id {
                    selectedWorkoutIDByDay[day.id] = nil
                } else {
                    selectedWorkoutIDByDay[day.id] = workout.id
                }
            }
        }) {
            // --- НАЧАЛО НА ПРОМЯНАТА: Копираме ZStack логиката от Meal-версията ---
            ZStack(alignment: .topTrailing) {
                Text(workout.workoutName)
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

                if !workout.exercises.isEmpty {
                    ZStack {
                        Circle().fill(baseColor)
                        Text("\(workout.exercises.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                } else {
                    ZStack {
                        Circle().fill(baseColor)
                        Text("0")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
        .buttonStyle(.plain)
    }

    // --- НАЧАЛО НА ПРОМЯНАТА (2/2): Добавяме ново View за съдържанието на тренировката ---
    @ViewBuilder
    private func workoutContent(for workout: TrainingPlanWorkout) -> some View {
        VStack {
            if !workout.exercises.isEmpty {
                let sortedExercises = workout.exercises.sorted { ($0.exercise?.name ?? "") < ($1.exercise?.name ?? "") }
                ForEach(sortedExercises) { entry in
                    if let exercise = entry.exercise {
                        ExerciseCalorieRowView(exercise: exercise, duration: entry.durationMinutes, profile: profile)
                    }
                }
            } else {
                Text("No exercises planned for this workout.")
                    .font(.caption)
                    .italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
        .contentShape(Rectangle())
    }
    // --- КРАЙ НА ПРОМЯНАТА (2/2) ---

    private func addAsNewDay() {
        let newIndex = (targetPlan.days.map { $0.dayIndex }.max() ?? 0) + 1
        let newDay = TrainingPlanDay(dayIndex: newIndex)
        
        for training in selectedTrainings {
            let newWorkout = TrainingPlanWorkout(workoutName: training.name)
            let exercises = training.exercises(using: modelContext)
            for (exerciseItem, duration) in exercises {
                let newExercise = TrainingPlanExercise(exercise: exerciseItem, durationMinutes: duration, workout: newWorkout)
                newWorkout.exercises.append(newExercise)
            }
            newWorkout.day = newDay
            newDay.workouts.append(newWorkout)
        }
        
        newDay.plan = targetPlan
        targetPlan.days.append(newDay)
        saveAndDismiss()
    }
    
    private func replace(day: TrainingPlanDay) {
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        // Ако денят е бил ден за почивка, маркираме го, че вече не е.
        if day.isRestDay {
            day.isRestDay = false
        }
        // --- КРАЙ НА ПРОМЯНАТА ---
        
        let workoutNamesToReplace = Set(selectedTrainings.map { $0.name })
        let workoutsToDelete = day.workouts.filter { workoutNamesToReplace.contains($0.workoutName) }
        
        for workout in workoutsToDelete {
            workout.exercises.forEach { modelContext.delete($0) }
            modelContext.delete(workout)
        }
        day.workouts.removeAll { workoutNamesToReplace.contains($0.workoutName) }

        for training in selectedTrainings {
            let newWorkout = TrainingPlanWorkout(workoutName: training.name)
            let exercises = training.exercises(using: modelContext)
            for (exerciseItem, duration) in exercises {
                let newExercise = TrainingPlanExercise(exercise: exerciseItem, durationMinutes: duration, workout: newWorkout)
                newWorkout.exercises.append(newExercise)
            }
            newWorkout.day = day
            day.workouts.append(newWorkout)
        }
        saveAndDismiss()
    }
    
    private func saveAndDismiss() {
        do { try modelContext.save() } catch { print("Error saving training plan: \(error)") }
        onComplete()
    }
}
