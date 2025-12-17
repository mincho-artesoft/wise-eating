import SwiftUI
import SwiftData

struct TrainingPlanDetailView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @State private var isBannerAdLoaded: Bool = false

    // MARK: - Input
    let plan: TrainingPlan
    let profile: Profile
    let onDismiss: () -> Void
    @Binding var navBarIsHiden: Bool

    // MARK: - State
    @State private var selectedDayID: TrainingPlanDay.ID? = nil
    @State private var selectedWorkoutID: TrainingPlanWorkout.ID? = nil
    
    // 👇 1. НОВО: Състояние за избраното упражнение за преглед
    @State private var exerciseItemToView: ExerciseItem? = nil
    
    // MARK: - Computed
    private var sortedDays: [TrainingPlanDay] {
        plan.days.sorted { $0.dayIndex < $1.dayIndex }
    }
    
    private var colorFor: [String: Color] {
        let sortedTemplates = profile.trainings.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let palette: [Color] = [.cyan, .green, .indigo, .orange, .pink, .purple, .blue, .red]
        let n = palette.count

        return Dictionary(uniqueKeysWithValues:
            sortedTemplates.enumerated().map { idx, workoutTemplate in
                (workoutTemplate.name, palette[idx % n])
            })
    }

    // MARK: - Body
    var body: some View {
        // 👇 2. НОВО: Обвиваме всичко в ZStack, за да може ExerciseItemDetailView да се покаже отгоре
        ZStack {
            ThemeBackgroundView().ignoresSafeArea()
            
            VStack(spacing: 0) {
                toolbar
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Text(plan.name)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(effectManager.currentGlobalAccentColor)

                        if plan.minAgeMonths > 0 {
                            HStack {
                                Text("Minimum Age:")
                                    .font(.headline)
                                Spacer()
                                Text("\(plan.minAgeMonths) months")
                                    .font(.headline.weight(.semibold))
                            }
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                            .padding()
                            .glassCardStyle(cornerRadius: 20)
                        }
                        
                        bannerAdSection
                            .frame(height: isBannerAdLoaded ? 120 : 0)
                        
                        ForEach(Array(sortedDays.enumerated()), id: \.element.id) { index, day in
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
            // Добавяме малко blur на задния фон, ако е отворен детайлът (по желание, както е в Editor-а)
            .blur(radius: exerciseItemToView != nil ? 1.5 : 0)
            
            // 👇 3. НОВО: Показваме ExerciseItemDetailView, ако има избрано упражнение
            if let exerciseToView = exerciseItemToView {
                ExerciseItemDetailView(
                    item: exerciseToView,
                    profile: profile,
                    onDismiss: {
                        withAnimation(.easeInOut) {
                            exerciseItemToView = nil
                            // Възстановяваме състоянието на навигацията, ако е нужно
                            // Тъй като DetailView по подразбиране крие навигацията, тук може да не е нужно да се пипа navBarIsHiden,
                            // но за консистенция с Editor-а:
                        }
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                .zIndex(20)
            }
        }
        .onAppear {
            navBarIsHiden = true
            if selectedDayID == nil, let firstDay = sortedDays.first {
                selectedDayID = firstDay.id
                if let firstWorkout = firstDay.workouts.first {
                    selectedWorkoutID = firstWorkout.id
                }
            }
        }
        .onDisappear { navBarIsHiden = false }
    }

    private var toolbar: some View {
        HStack {
            Button("Back", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()

            Button("Back") {}.hidden()
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.horizontal)
    }
    
    private func daySection(for day: TrainingPlanDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            
            HStack {
                Text(day.isRestDay ? "Day \(dayIndex): Rest Day" : "Day \(dayIndex)")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer()
            }
            
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
                    Text("No workout selected.")
                        .font(.caption).italic()
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.default, value: selectedWorkoutID)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
    private func workoutTabButton(for workout: TrainingPlanWorkout, in day: TrainingPlanDay) -> some View {
        let isSelected = selectedWorkoutID == workout.id && selectedDayID == day.id
        let baseColor = colorFor[workout.workoutName] ?? effectManager.currentGlobalAccentColor

        Button {
            withAnimation {
                selectedDayID = day.id
                selectedWorkoutID = workout.id
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
                let sortedExercises = workout.exercises.sorted {
                    ($0.exercise?.name ?? "") < ($1.exercise?.name ?? "")
                }
                
                ForEach(sortedExercises) { entry in
                    if entry.exercise != nil {
                        TrainingPlanExerciseDetailRow(
                            link: entry,
                            profile: profile
                        )
                        // 👇 4. НОВО: Добавяме контекстно меню
                        .contextMenu {
                            if let exercise = entry.exercise {
                                Button {
                                    withAnimation(.easeInOut) {
                                        exerciseItemToView = exercise
                                        // Тук не скриваме навбара изрично, защото той вече е скрит в този View,
                                        // но ако имате друга логика, можете да сложите navBarIsHiden = true
                                    }
                                } label: {
                                    Label("View Details", systemImage: "info.circle")
                                }
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
    
    @ViewBuilder
    private var bannerAdSection: some View {
        if SubscriptionManager.shared.subscriptionStatus == .base {
            BannerAdView(adsBool: $isBannerAdLoaded, bucket: .large)
                .frame(height: 120)
                .opacity(isBannerAdLoaded ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isBannerAdLoaded)
                .padding(.horizontal)
        }
    }
}
