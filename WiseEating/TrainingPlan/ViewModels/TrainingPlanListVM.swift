import Foundation
import SwiftData

@MainActor
class TrainingPlanListVM: ObservableObject {
    @Published var plans: [TrainingPlan] = []
    @Published var searchText: String = "" {
        didSet {
            filterPlans()
        }
    }
    
    private var allPlans: [TrainingPlan] = []
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
        
        let profileID = profile?.persistentModelID
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate { $0.profile?.persistentModelID == profileID },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        do {
            allPlans = try context.fetch(descriptor)
            filterPlans()
        } catch {
            print("Failed to fetch training plans: \(error)")
        }
    }
    
    private func filterPlans() {
        if searchText.isEmpty {
            plans = allPlans
        } else {
            let lowercasedSearch = searchText.lowercased()
            plans = allPlans.filter { $0.name.lowercased().contains(lowercasedSearch) }
        }
    }
    
    func delete(plan: TrainingPlan, alsoDeleteLinkedWorkouts: Bool) {
        guard let context = modelContext else { return }

        if alsoDeleteLinkedWorkouts {
            // 1) Събираме всички linkedWorkoutID от плана
            let linkedIDs = Set(
                plan.days
                    .flatMap { $0.workouts }
                    .compactMap { $0.linkedWorkoutID }
            )

            if !linkedIDs.isEmpty {
                do {
                    // 2) Вземаме всички Workout-и (ExerciseItem, isWorkout == true)
                    let descriptor = FetchDescriptor<ExerciseItem>(
                        predicate: #Predicate { $0.isWorkout == true }
                    )
                    let allWorkouts = try context.fetch(descriptor)

                    // 3) Филтрираме само тези, чиито id са в linkedIDs
                    let toDelete = allWorkouts.filter { linkedIDs.contains($0.id) }

                    if !toDelete.isEmpty {
                        print("🗑️ Deleting \(toDelete.count) linked workouts for training plan '\(plan.name)'")
                        for w in toDelete {
                            context.delete(w)
                        }
                    }
                } catch {
                    print("❌ Failed to fetch workouts for deletion: \(error)")
                }
            }
        }

        // 4) Трием самия план (каскадно ще изтрие дни, тренировки, TrainingPlanExercise)
        context.delete(plan)

        do {
            try context.save()
        } catch {
            print("❌ Failed to delete training plan: \(error)")
        }

        // 5) Презареждаме списъка
        fetchPlans()
    }

}
