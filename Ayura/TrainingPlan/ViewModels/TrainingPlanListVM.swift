import Foundation
import SwiftData

@MainActor
final class TrainingPlanListVM: ObservableObject {

    enum PlanScope: String, CaseIterable, Identifiable {
        case myPlans = "My Plans"
        case templates = "Templates"
        var id: String { rawValue }
    }

    struct DisplayPlan: Identifiable {
        let id: String
        let name: String
        let dayCount: Int
        let creationDate: Date?
        let isTemplate: Bool
        let minAgeMonths: Int
        let originalObject: Any
    }

    @Published var displayPlans: [DisplayPlan] = []

    @Published var searchText: String = "" {
        didSet { filterPlans() }
    }

    @Published var selectedScope: PlanScope = .myPlans {
        didSet { fetchPlans() }
    }

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

    func fetchPlans() {
        guard let context = modelContext else { return }

        allFetchedPlans = []

        if selectedScope == .myPlans {
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

    private func nextExerciseId() -> Int {
        guard let context = modelContext else { return Int.random(in: 100000...999999) }
        var desc = FetchDescriptor<ExerciseItem>()
        desc.sortBy = [SortDescriptor(\.id, order: .reverse)]
        desc.fetchLimit = 1
        let maxId = ((try? context.fetch(desc))?.first?.id) ?? 0
        return maxId + 1
    }

    // MARK: - Actions

    @discardableResult
    func copyTemplateToMyPlans(_ displayPlan: DisplayPlan, targetWorkoutName: String? = nil) -> TrainingPlan? {
        guard let template = displayPlan.originalObject as? TemplatePlan,
              let context = modelContext,
              let profile = profile else { return nil }

        let newPlan = TrainingPlan(name: template.name, profile: profile, minAgeMonths: 0)
        context.insert(newPlan)

        for tDay in template.days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
            let newDay = TrainingPlanDay(dayIndex: tDay.dayIndex, isRestDay: tDay.isRestDay, plan: newPlan)
            context.insert(newDay)
            newPlan.days.append(newDay)

            if tDay.isRestDay { continue }

            for tWorkout in tDay.workouts {
                let finalWorkoutName = targetWorkoutName ?? tWorkout.workoutName
                let newWorkout = TrainingPlanWorkout(workoutName: finalWorkoutName, day: newDay)
                context.insert(newWorkout)
                newDay.workouts.append(newWorkout)

                let uniqueWorkoutName = "\(newPlan.name) - Day \(tDay.dayIndex) - \(finalWorkoutName)"

                var workoutItem: ExerciseItem!
                var isNewWorkoutItem = false

                let predicate = #Predicate<ExerciseItem> {
                    $0.name == uniqueWorkoutName && $0.isWorkout == false
                }
                var descriptor = FetchDescriptor(predicate: predicate)
                descriptor.fetchLimit = 1

                if let existingItem = try? context.fetch(descriptor).first {
                    workoutItem = existingItem
                } else {
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
                }

                newWorkout.linkedWorkoutID = workoutItem.id

                var allMuscleGroups: Set<MuscleGroup> = []
                var totalDuration: Double = 0

                for tEx in tWorkout.exercises {
                    let targetName = tEx.exerciseName
                    var exerciseItem: ExerciseItem?

                    var exDesc = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.name == targetName })
                    exDesc.fetchLimit = 1

                    if let found = (try? context.fetch(exDesc))?.first {
                        exerciseItem = found
                    } else {
                        let newItem = ExerciseItem(id: nextExerciseId(), name: targetName, muscleGroups: [])
                        newItem.isUserAdded = false
                        context.insert(newItem)
                        exerciseItem = newItem
                    }

                    guard let validEx = exerciseItem else { continue }

                    allMuscleGroups.formUnion(validEx.muscleGroups)
                    totalDuration += tEx.durationMinutes

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

                if isNewWorkoutItem {
                    workoutItem.muscleGroups = Array(allMuscleGroups).sorted { $0.rawValue < $1.rawValue }
                    workoutItem.durationMinutes = Int(totalDuration)
                }
            }
        }

        try? context.save()
        selectedScope = .myPlans
        return newPlan
    }

    /// ✅ Безопасно изтриване по UUID (без да държим TrainingPlan reference в UI state)
    func deletePlan(planID: UUID, alsoDeleteLinkedWorkouts: Bool) {
        guard let context = modelContext else { return }

        do {
            var desc = FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == planID })
            desc.fetchLimit = 1

            guard let plan = try context.fetch(desc).first else {
                // вече е изтрит или не съществува
                fetchPlans()
                return
            }

            if alsoDeleteLinkedWorkouts {
                let linkedIDs = Set(
                    plan.days
                        .flatMap { $0.workouts }
                        .compactMap { $0.linkedWorkoutID }
                )

                if !linkedIDs.isEmpty {
                    let wDesc = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.isWorkout == true })
                    let allWorkouts = try context.fetch(wDesc)

                    for w in allWorkouts where linkedIDs.contains(w.id) {
                        context.delete(w)
                    }
                }
            }

            context.delete(plan)
            try context.save()
            fetchPlans()
        } catch {
            print("❌ Failed to delete plan: \(error)")
        }
    }
}
