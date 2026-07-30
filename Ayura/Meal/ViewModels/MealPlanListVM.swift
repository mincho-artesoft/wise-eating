import Foundation
import SwiftData

@MainActor
class MealPlanListVM: ObservableObject {
    @Published var plans: [MealPlan] = []
    @Published var searchText: String = "" {
        didSet {
            filterPlans()
        }
    }
    
    private var allPlans: [MealPlan] = []
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
        let descriptor = FetchDescriptor<MealPlan>(
            predicate: #Predicate { $0.profile?.persistentModelID == profileID },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        do {
            allPlans = try context.fetch(descriptor)
            filterPlans()
        } catch {
            print("Failed to fetch meal plans: \(error)")
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
    
    func delete(plan: MealPlan, alsoDeleteMenus: Bool) {
        guard let context = modelContext else { return }

        if alsoDeleteMenus {
            // Collect all linked menu IDs from the plan's meals
            let menuIDs = plan.days
                .flatMap { $0.meals }
                .compactMap { $0.linkedMenuID }

            if !menuIDs.isEmpty {
                let idSet = Set(menuIDs)

                let descriptor = FetchDescriptor<FoodItem>(
                    predicate: #Predicate<FoodItem> { item in
                        item.isMenu && idSet.contains(item.id)
                    }
                )

                do {
                    let menus = try context.fetch(descriptor)
                    if !menus.isEmpty {
                        print("🗑️ Deleting \(menus.count) menus linked to meal plan '\(plan.name)'")
                        for menu in menus {
                            context.delete(menu)
                        }
                    }
                } catch {
                    print("❌ Failed to delete menus linked to meal plan: \(error)")
                }
            }
        }

        // Delete the plan itself
        context.delete(plan)

        do {
            try context.save()
        } catch {
            print("❌ Failed to delete meal plan: \(error)")
        }

        // Refresh list
        fetchPlans()
    }

}
