import SwiftUI
import SwiftData

struct TemplatePlanDetailView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext

    // MARK: - Inputs
    let planWrapper: TrainingPlanListVM.DisplayPlan
    let profile: Profile
    let onDismiss: () -> Void
    let onGet: () -> Void

    // MARK: - State (selection)
    @State private var selectedDayKey: String? = nil
    @State private var selectedWorkoutKey: String? = nil

    // MARK: - Overlay (View Exercise Details like TrainingPlanDetailView)
    @State private var exerciseItemToView: ExerciseItem? = nil

    // MARK: - Real object
    private var templatePlan: TemplatePlan? {
        planWrapper.originalObject as? TemplatePlan
    }

    // MARK: - Computed
    private var sortedDays: [TemplateDay] {
        (templatePlan?.days ?? []).sorted { $0.dayIndex < $1.dayIndex }
    }

    private static let palette: [Color] = [
        .cyan, .green, .indigo, .orange, .pink, .purple, .blue, .red
    ]

    private func colorFor(workoutName: String) -> Color {
        let hash = abs(workoutName.hashValue)
        return Self.palette[hash % Self.palette.count]
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Text(planWrapper.name)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(effectManager.currentGlobalAccentColor)

                        ForEach(Array(sortedDays.enumerated()), id: \.offset) { index, day in
                            daySection(for: day, dayIndex: index + 1)
                        }
                    }
                    .padding()

                    Color.clear.frame(height: 150)
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
            // like TrainingPlanDetailView
            .blur(radius: exerciseItemToView != nil ? 1.5 : 0)

            // Overlay ExerciseItemDetailView (1:1)
            if let exerciseToView = exerciseItemToView {
                ExerciseItemDetailView(
                    item: exerciseToView,
                    profile: profile,
                    onDismiss: {
                        withAnimation(.easeInOut) {
                            exerciseItemToView = nil
                        }
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing),
                                        removal: .move(edge: .leading)))
                .zIndex(20)
            }
        }
        .onAppear {
            // Auto select first day/workout like TrainingPlanDetailView
            if selectedDayKey == nil, let firstDay = sortedDays.first {
                selectedDayKey = dayKey(for: firstDay)
                if let firstWorkout = firstDay.workouts.first {
                    selectedWorkoutKey = workoutKey(for: firstWorkout, day: firstDay)
                }
            }
        }
    }

    // MARK: - Toolbar (same style, but has GET)
    private var toolbar: some View {
        HStack {
            Button("Back", action: onDismiss)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

            Spacer()

            Button("GET", action: onGet)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.horizontal)
    }

    // MARK: - Day section (same structure)
    private func daySection(for day: TemplateDay, dayIndex: Int) -> some View {
        let dKey = dayKey(for: day)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Day \(dayIndex)")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                Spacer()
            }

            // Tabs for workouts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let sortedWorkouts = day.workouts.sorted {
                        $0.workoutName.localizedCaseInsensitiveCompare($1.workoutName) == .orderedAscending
                    }

                    ForEach(sortedWorkouts) { workout in
                        workoutTabButton(for: workout, in: day)
                    }
                }
                .padding(.vertical, 4)
            }

            // Selected workout content
            if selectedDayKey == dKey,
               let wKey = selectedWorkoutKey,
               let workout = day.workouts.first(where: { workoutKey(for: $0, day: day) == wKey }) {
                workoutContent(for: workout)
            } else if selectedDayKey == dKey {
                Text("No workout selected.")
                    .font(.caption).italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.default, value: selectedWorkoutKey)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    // MARK: - Workout tab (same style)
    @ViewBuilder
    private func workoutTabButton(for workout: TemplateWorkout, in day: TemplateDay) -> some View {
        let dKey = dayKey(for: day)
        let wKey = workoutKey(for: workout, day: day)
        let isSelected = (selectedWorkoutKey == wKey && selectedDayKey == dKey)
        let baseColor = colorFor(workoutName: workout.workoutName)

        Button {
            withAnimation {
                selectedDayKey = dKey
                selectedWorkoutKey = wKey
            }
        } label: {
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

                // Badge count (same)
                ZStack {
                    Circle().fill(baseColor)
                    Text("\(workout.exercises.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                }
                .frame(width: 16, height: 16)
                .offset(x: 6, y: -6)
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Workout content (uses the 1:1 row)
    @ViewBuilder
    private func workoutContent(for workout: TemplateWorkout) -> some View {
        VStack {
            if !workout.exercises.isEmpty {
                let sortedExercises = workout.exercises.sorted {
                    $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
                }

                ForEach(sortedExercises) { ex in
                    TemplatePlanExerciseDetailRow(
                        exercise: ex,
                        profile: profile
                    )
                    .contextMenu {
                        // Same as TrainingPlanDetailView: View Details overlay (if we can resolve ExerciseItem)
                        if let real = findExerciseItem(named: ex.exerciseName) {
                            Button {
                                withAnimation(.easeInOut) {
                                    exerciseItemToView = real
                                }
                            } label: {
                                Label("View Details", systemImage: "info.circle")
                            }
                        }
                    }
                }
            } else {
                Text("No exercises planned for this workout.")
                    .font(.caption).italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Keys (stable selection)
    private func dayKey(for day: TemplateDay) -> String {
        "day-\(day.dayIndex)"
    }

    private func workoutKey(for workout: TemplateWorkout, day: TemplateDay) -> String {
        "day-\(day.dayIndex)-workout-\(workout.workoutName)"
    }

    // MARK: - SwiftData resolve by name
    private func findExerciseItem(named name: String) -> ExerciseItem? {
        do {
            let desc = FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.name == name }
            )
            return try modelContext.fetch(desc).first
        } catch {
            return nil
        }
    }
}
