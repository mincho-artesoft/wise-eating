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
        
        let profileID = profile?.id
        let descriptor = FetchDescriptor<MealPlan>(
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        do {
            allPlans = try context.fetch(descriptor).filter {
                $0.profile?.id == profileID
            }
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
        guard let context = userContext else { return }

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
