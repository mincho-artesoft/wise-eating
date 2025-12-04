// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Fitness/Views/TrainingPlanPreviewView.swift ====
import SwiftUI
import SwiftData

struct TrainingPlanPreviewView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Input
    let plan: TrainingPlan
    let profile: Profile
    let onDismiss: () -> Void
    let onAdd: ([TrainingPlanDay]) -> Void

    // MARK: - State for UI
    // --- НАЧАЛО НА ПРОМЯНАТА (1/5): Добавяме състояние за управление на списъка ---
    @State private var days: [TrainingPlanDay]
    @State private var selectedDayIDs: Set<TrainingPlanDay.ID>
    @State private var editMode: EditMode = .inactive
    // --- КРАЙ НА ПРОМЯНАТА (1/5) ---

    // State for internal tab selection remains
    @State private var selectedDayID: TrainingPlanDay.ID? = nil
    @State private var selectedWorkoutID: TrainingPlanWorkout.ID? = nil

    // MARK: - Initializer
    // --- НАЧАЛО НА ПРОМЯНАТА (2/5): Актуализираме init, за да заредим състоянията ---
    init(plan: TrainingPlan, profile: Profile, onDismiss: @escaping () -> Void, onAdd: @escaping ([TrainingPlanDay]) -> Void) {
        self.plan = plan
        self.profile = profile
        self.onDismiss = onDismiss
        self.onAdd = onAdd
        
        // Създаваме локално, редактируемо копие на дните от плана, сортирано по индекс
        let sortedInitialDays = plan.days.sorted { $0.dayIndex < $1.dayIndex }
        _days = State(initialValue: sortedInitialDays)
        // По подразбиране всички дни са избрани
        _selectedDayIDs = State(initialValue: Set(sortedInitialDays.map { $0.id }))
    }
    // --- КРАЙ НА ПРОМЯНАТА (2/5) ---

    // MARK: - Computed Properties
    // --- НАЧАЛО НА ПРОМЯНАТА (3/5): Добавяме изчисляеми свойства за сортиране ---
    private var sortedDaysForDisplay: [TrainingPlanDay] {
        let selected = days.filter { selectedDayIDs.contains($0.id) }.sorted { $0.dayIndex < $1.dayIndex }
        let deselected = days.filter { !selectedDayIDs.contains($0.id) }.sorted { $0.dayIndex < $1.dayIndex }
        return selected + deselected
    }

    private var selectedDays: [TrainingPlanDay] {
        sortedDaysForDisplay.filter { selectedDayIDs.contains($0.id) }
    }
    // --- КРАЙ НА ПРОМЯНАТА (3/5) ---
    
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

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            
            // --- НАЧАЛО НА ПРОМЯНАТА (4/5): Заменяме ScrollView с List ---
            List {
                ForEach(Array(sortedDaysForDisplay.enumerated()), id: \.element.id) { visualIndex, day in
                    let isDraggable = selectedDayIDs.contains(day.id)
                    
                    daySection(for: day, dayIndex: visualIndex + 1)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .moveDisabled(!isDraggable)
                        .opacity(editMode.isEditing && !isDraggable ? 0.6 : 1.0)
                }
                .onMove(perform: moveDay)
                
                Color.clear
                    .frame(height: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
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
            // --- КРАЙ НА ПРОМЯНАТА (4/5) ---
        }
        .onAppear {
            if selectedDayID == nil, let firstDay = sortedDaysForDisplay.first {
                selectedDayID = firstDay.id
                if let firstWorkout = firstDay.workouts.first {
                    selectedWorkoutID = firstWorkout.id
                }
            }
        }
    }
    
    // MARK: - Subviews
    private var toolbar: some View {
        HStack {
            Button("Back", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            // --- НАЧАЛО НА ПРОМЯНАТА (5/5): Актуализираме toolbar-а с Edit бутон ---
            if editMode.isEditing {
                EditButton()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
            } else {
                Button("Add to Training") { onAdd(selectedDays) } // Използваме избраните дни
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                    .transition(.opacity.combined(with: .scale))
            }
            // --- КРАЙ НА ПРОМЯНАТА (5/5) ---
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
        .animation(.default, value: editMode)
    }
    
    private func daySection(for day: TrainingPlanDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // --- ПРОМЯНА: Показваме "Rest Day" в заглавието, ако денят е такъв ---
                Text(day.isRestDay ? "Day \(dayIndex): Rest Day" : "Day \(dayIndex)")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer()

                // Бутон за избор на ден
                Button(action: {
                    withAnimation {
                        toggleSelection(for: day)
                    }
                }) {
                    Image(systemName: selectedDayIDs.contains(day.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
            }
            
            // --- ПРОМЯНА: Показваме тренировките само ако денят НЕ е за почивка ---
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
                
                if let workoutID = selectedWorkoutID, let workout = day.workouts.first(where: { $0.id == workoutID }) {
                    workoutContent(for: workout)
                } else if selectedDayID == day.id {
                     Text("No workout selected.").font(.caption).italic().opacity(0.7)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                }
            }
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .animation(.default, value: selectedWorkoutID)
        .padding().glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
    private func workoutTabButton(for workout: TrainingPlanWorkout, in day: TrainingPlanDay) -> some View {
        let isSelected = selectedWorkoutID == workout.id && selectedDayID == day.id
        let baseColor = colorFor[workout.workoutName] ?? .gray

        Button {
            withAnimation {
                selectedDayID = day.id
                selectedWorkoutID = workout.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(workout.workoutName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 20).fill(isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.3))
                    )
                    .glassCardStyle(cornerRadius: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20).stroke(baseColor, lineWidth: isSelected ? 2 : 0)
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
        }
        .buttonStyle(.plain)
    }

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
                Text("No exercises planned for this workout.").font(.caption).italic().opacity(0.7)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
    }

    // --- НОВО: Функции за управление на списъка ---
    private func toggleSelection(for day: TrainingPlanDay) {
        if selectedDayIDs.contains(day.id) {
            selectedDayIDs.remove(day.id)
        } else {
            let maxIndex = days
                .filter { selectedDayIDs.contains($0.id) }
                .map { $0.dayIndex }
                .max() ?? 0
            
            if let dayToUpdate = days.first(where: { $0.id == day.id }) {
                dayToUpdate.dayIndex = maxIndex + 1
            }
            
            selectedDayIDs.insert(day.id)
        }
    }
    
    private func moveDay(from source: IndexSet, to destination: Int) {
        var selected = self.selectedDays
        selected.move(fromOffsets: source, toOffset: destination)

        for (index, day) in selected.enumerated() {
            if let dayInState = days.first(where: { $0.id == day.id }) {
                dayInState.dayIndex = index + 1
            }
        }
    }
}
