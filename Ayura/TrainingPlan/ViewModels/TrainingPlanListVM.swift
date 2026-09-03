import Foundation
import SwiftData

@MainActor
final class TrainingPlanListVM: ObservableObject {

    struct DisplayPlan: Identifiable {
        let id: UUID
        let name: String
        let dayCount: Int
        let creationDate: Date
        let minAgeMonths: Int
        let plan: TrainingPlan
    }

    @Published var displayPlans: [DisplayPlan] = []

    @Published var searchText: String = "" {
        didSet { filterPlans() }
    }

    private var allFetchedPlans: [DisplayPlan] = []
    private let profile: Profile?
    private var combinedContainer: ModelContainer?
    private var userContext: ModelContext?

    init(profile: Profile?) {
        self.profile = profile
    }

    func attach(context: ModelContext) {
        combinedContainer = context.container
        fetchPlans()
    }

    func fetchPlans() {
        guard let combinedContainer,
              let context = try? CombinedStoreFactory.makeUserWriteContext(
                from: combinedContainer
              ) else { return }
        userContext = context

        allFetchedPlans = []

        let profileID = profile?.id
        let descriptor = FetchDescriptor<TrainingPlan>(
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )

        if let userPlans = try? context.fetch(descriptor) {
            allFetchedPlans = userPlans
                .filter { $0.profile?.id == profileID }
                .map { plan in
                DisplayPlan(
                    id: plan.id,
                    name: plan.name,
                    dayCount: plan.days.count,
                    creationDate: plan.creationDate,
                    minAgeMonths: plan.minAgeMonths,
                    plan: plan
                )
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

    /// ✅ Безопасно изтриване по UUID (без да държим TrainingPlan reference в UI state)
    func deletePlan(planID: UUID, alsoDeleteLinkedWorkouts: Bool) {
        guard let context = userContext else { return }

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
