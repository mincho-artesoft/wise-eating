import Foundation
import SwiftData

@MainActor
class TrainingPlanListVM: ObservableObject {
    
    // Енумерация за разделите
    enum PlanScope: String, CaseIterable, Identifiable {
        case myPlans = "My Plans"
        case templates = "Templates"
        var id: String { rawValue }
    }
    
    // Структура за визуализация (обединява TrainingPlan и TemplatePlan)
    struct DisplayPlan: Identifiable {
        let id: String
        let name: String
        let dayCount: Int
        let creationDate: Date? // nil за шаблони
        let isTemplate: Bool
        let minAgeMonths: Int
        let originalObject: Any // TrainingPlan или TemplatePlan
    }
    
    // MARK: - Published Properties
    @Published var displayPlans: [DisplayPlan] = []
    
    @Published var searchText: String = "" {
        didSet { filterPlans() }
    }
    
    @Published var selectedScope: PlanScope = .myPlans {
        didSet { fetchPlans() }
    }
    
    // MARK: - Internal State
    private var allFetchedPlans: [DisplayPlan] = []
    private let profile: Profile?
    private weak var modelContext: ModelContext?

    init(profile: Profile?) {
        self.profile = profile
    }

    func attach(context: ModelContext) {
        self.modelContext = context
        fetchPlans()
    }
    
    // MARK: - Fetching
    func fetchPlans() {
        guard let context = modelContext else { return }
        
        allFetchedPlans = []
        
        if selectedScope == .myPlans {
            // 1. Търсим плановете на потребителя
            let profileID = profile?.persistentModelID
            let descriptor = FetchDescriptor<TrainingPlan>(
                predicate: #Predicate { $0.profile?.persistentModelID == profileID },
                sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
            )
            
            if let userPlans = try? context.fetch(descriptor) {
                allFetchedPlans = userPlans.map { plan in
                    DisplayPlan(
                        id: plan.id.uuidString,
                        name: plan.name,
                        dayCount: plan.days.count,
                        creationDate: plan.creationDate,
                        isTemplate: false,
                        minAgeMonths: plan.minAgeMonths,
                        originalObject: plan
                    )
                }
            }
        } else {
            // 2. Търсим шаблони от templates.store
            let descriptor = FetchDescriptor<TemplatePlan>(sortBy: [SortDescriptor(\.name)])
            
            if let templates = try? context.fetch(descriptor) {
                allFetchedPlans = templates.map { template in
                    DisplayPlan(
                        id: template.id,
                        name: template.name,
                        dayCount: template.days.count,
                        creationDate: nil,
                        isTemplate: true,
                        minAgeMonths: 0,
                        originalObject: template
                    )
                }
            }
        }
        
        filterPlans()
    }
    
    private func filterPlans() {
        if searchText.isEmpty {
            displayPlans = allFetchedPlans
        } else {
            let term = searchText.lowercased()
            displayPlans = allFetchedPlans.filter { $0.name.lowercased().contains(term) }
        }
    }
    
    // MARK: - Helpers
    private func nextExerciseId() -> Int {
        guard let context = modelContext else { return Int.random(in: 100000...999999) }
        var desc = FetchDescriptor<ExerciseItem>()
        desc.sortBy = [SortDescriptor(\.id, order: .reverse)]
        desc.fetchLimit = 1
        let maxId = ((try? context.fetch(desc))?.first?.id) ?? 0
        return maxId + 1
    }
    
    // MARK: - Actions
    
    // Копиране от Шаблон към Моите Планове
    // ✅ ПРОМЯНА: Добавен параметър targetWorkoutName
    // MARK: - Actions
        
        // Копиране от Шаблон към Моите Планове
    @discardableResult
    func copyTemplateToMyPlans(_ displayPlan: DisplayPlan, targetWorkoutName: String? = nil) -> TrainingPlan? {
        guard let template = displayPlan.originalObject as? TemplatePlan,
              let context = modelContext,
              let profile = profile else { return nil }
        
        // 1. Създаваме нов план за профила
        let newPlan = TrainingPlan(name: template.name, profile: profile, minAgeMonths: 0)
        context.insert(newPlan)
        
        // 2. Копираме структурата
        for tDay in template.days {
            let newDay = TrainingPlanDay(dayIndex: tDay.dayIndex)
            newDay.plan = newPlan
            context.insert(newDay)
            newPlan.days.append(newDay)
            
            for tWorkout in tDay.workouts {
                // ✅ ИЗПОЛЗВАНЕ НА ЦЕЛЕВОТО ИМЕ
                let finalWorkoutName = targetWorkoutName ?? tWorkout.workoutName
                
                // А. Създаваме вътрешния обект за плана
                let newWorkout = TrainingPlanWorkout(workoutName: finalWorkoutName)
                newWorkout.day = newDay
                context.insert(newWorkout)
                newDay.workouts.append(newWorkout)
                
                // Б. Търсене или Създаване на реалния ExerciseItem (Workout)
                let uniqueWorkoutName = "\(newPlan.name) - Day \(tDay.dayIndex) - \(finalWorkoutName)"
                
                var workoutItem: ExerciseItem!
                var isNewWorkoutItem = false // Флаг, за да знаем дали да пълним ExerciseLinks
                
                // 🔎 ТЪРСЕНЕ: Проверяваме дали вече има тренировка с това име
                let predicate = #Predicate<ExerciseItem> {
                    $0.name == uniqueWorkoutName && $0.isWorkout == false
                }
                var descriptor = FetchDescriptor(predicate: predicate)
                descriptor.fetchLimit = 1
                
                if let existingItem = try? context.fetch(descriptor).first {
                    // ✅ НАМЕРЕНА: Ползваме съществуващата
                    workoutItem = existingItem
                    print("♻️ Reusing existing workout: \(uniqueWorkoutName)")
                } else {
                    // 🆕 НЯМА ТАКАВА: Създаваме нова
                    let newWorkoutItemID = nextExerciseId()
                    workoutItem = ExerciseItem(
                        id: newWorkoutItemID,
                        name: uniqueWorkoutName,
                        isUserAdded: true,
                        muscleGroups: [],
                        isWorkout: true
                    )
                    context.insert(workoutItem)
                    isNewWorkoutItem = true
                    print("✨ Creating new workout: \(uniqueWorkoutName)")
                }
                
                // В. Свързваме вътрешния обект с външния
                newWorkout.linkedWorkoutID = workoutItem.id
                
                var allMuscleGroups: Set<MuscleGroup> = []
                var allSports: Set<Sport> = []
                var totalDuration: Double = 0
                
                for tEx in tWorkout.exercises {
                    // 3. Търсим или създаваме единичното упражнение
                    let targetName = tEx.exerciseName
                    var exerciseItem: ExerciseItem?
                    
                    var desc = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.name == targetName })
                    desc.fetchLimit = 1
                    
                    if let found = (try? context.fetch(desc))?.first {
                        exerciseItem = found
                    } else {
                        // Fallback: Създаваме placeholder
                        let newItem = ExerciseItem(id: nextExerciseId(), name: targetName, muscleGroups: [])
                        newItem.isUserAdded = false
                        context.insert(newItem)
                        exerciseItem = newItem
                    }
                    
                    guard let validEx = exerciseItem else { continue }
                    
                    // --- Г. Събираме метаданни ---
                    allMuscleGroups.formUnion(validEx.muscleGroups)
                    if let s = validEx.sports { allSports.formUnion(s) }
                    totalDuration += tEx.durationMinutes
                    
                    // --- Д. Добавяме ExerciseLink към Workout Item-а ---
                    // ⚠️ ВАЖНО: Добавяме само ако тренировката е нова, за да не дублираме упражненията вътре
                    if isNewWorkoutItem {
                        let exerciseLink = ExerciseLink(
                            exercise: validEx,
                            durationMinutes: tEx.durationMinutes,
                            owner: workoutItem
                        )
                        context.insert(exerciseLink)
                        if workoutItem.exercises == nil { workoutItem.exercises = [] }
                        workoutItem.exercises?.append(exerciseLink)
                    }
                    
                    // --- Е. Добавяме TrainingPlanExercise към вътрешния план ---
                    // Това се прави ВИНАГИ, защото `newWorkout` (обектът от плана) е нов
                    let newLink = TrainingPlanExercise(exercise: validEx, durationMinutes: tEx.durationMinutes, workout: newWorkout)
                    context.insert(newLink)
                    newWorkout.exercises.append(newLink)
                    
                    for tSet in tEx.sets {
                        let unit = TimeUnit(rawValue: tSet.timeUnitString) ?? .seconds
                        let newSet = TrainingPlanSet(
                            reps: tSet.reps,
                            weight: nil,
                            isToFailure: tSet.isToFailure,
                            isTimeBased: tSet.isTimeBased,
                            timeUnit: unit,
                            orderIndex: tSet.orderIndex
                        )
                        newSet.exercise = newLink
                        context.insert(newSet)
                        newLink.sets.append(newSet)
                    }
                }
                
                // Ж. Ако е нова тренировка, записваме агрегираните данни
                if isNewWorkoutItem {
                    workoutItem.muscleGroups = Array(allMuscleGroups).sorted { $0.rawValue < $1.rawValue }
                    workoutItem.sports = Array(allSports).sorted { $0.rawValue < $1.rawValue }
                    workoutItem.durationMinutes = Int(totalDuration)
                }
            }
        }
        
        try? context.save()
        
        // Превключваме, за да види потребителят новия си план
        selectedScope = .myPlans
        
        // ✅ Връщаме новия план
        return newPlan
    }
    // Изтриване
    func delete(plan: TrainingPlan, alsoDeleteLinkedWorkouts: Bool) {
        guard let context = modelContext else { return }

        if alsoDeleteLinkedWorkouts {
            let linkedIDs = Set(
                plan.days
                    .flatMap { $0.workouts }
                    .compactMap { $0.linkedWorkoutID }
            )

            if !linkedIDs.isEmpty {
                do {
                    let descriptor = FetchDescriptor<ExerciseItem>(
                        predicate: #Predicate { $0.isWorkout == true }
                    )
                    let allWorkouts = try context.fetch(descriptor)
                    let toDelete = allWorkouts.filter { linkedIDs.contains($0.id) }

                    for w in toDelete {
                        context.delete(w)
                    }
                } catch {
                    print("❌ Failed to delete linked workouts: \(error)")
                }
            }
        }

        context.delete(plan)
        try? context.save()
        fetchPlans()
    }
}
