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
    
    // Този property липсваше и предизвикваше грешката в Picker-а
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
            
            // Важно: Тук SwiftData автоматично ще търси в правилния ModelConfiguration,
            // ако типовете са настроени правилно в DatabaseSetup.
            if let templates = try? context.fetch(descriptor) {
                allFetchedPlans = templates.map { template in
                    DisplayPlan(
                        id: template.id,
                        name: template.name,
                        dayCount: template.days.count,
                        creationDate: nil,
                        isTemplate: true,
                        minAgeMonths: 0, // Шаблоните може да нямат възраст засега
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
    
    // MARK: - Actions
    
    // Копиране от Шаблон към Моите Планове
    func copyTemplateToMyPlans(_ displayPlan: DisplayPlan) {
        guard let template = displayPlan.originalObject as? TemplatePlan,
              let context = modelContext,
              let profile = profile else { return }
        
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
                let newWorkout = TrainingPlanWorkout(workoutName: tWorkout.workoutName)
                newWorkout.day = newDay
                context.insert(newWorkout)
                newDay.workouts.append(newWorkout)
                
                for tEx in tWorkout.exercises {
                    // 3. Търсим или създаваме упражнението
                    let targetName = tEx.exerciseName
                    var exerciseItem: ExerciseItem?
                    
                    var desc = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.name == targetName })
                    desc.fetchLimit = 1
                    
                    if let found = (try? context.fetch(desc))?.first {
                        exerciseItem = found
                    } else {
                        // Fallback: Създаваме placeholder, ако няма такова упражнение
                        let newItem = ExerciseItem(id: Int.random(in: 900000...999999), name: targetName, muscleGroups: [])
                        newItem.isUserAdded = false
                        context.insert(newItem)
                        exerciseItem = newItem
                    }
                    
                    guard let validEx = exerciseItem else { continue }
                    
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
            }
        }
        
        try? context.save()
        
        // Превключваме, за да види потребителят новия си план
        selectedScope = .myPlans
    }
    
    // Изтриване (Това оправя грешката 'has no dynamic member delete')
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
