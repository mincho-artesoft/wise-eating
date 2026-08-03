import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class FoodListVM: ObservableObject {
    
    // MARK: - Inputs & Outputs
    @Published var searchText: String = ""
    @Published var filter: FoodItemListView.Filter = .foods
    @Published private(set) var items: [FoodItem] = []
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var isLoading: Bool = false
    
    // MARK: - Private State
    private var context: ModelContext!
    private var container: ModelContainer?
    private var cancellables = Set<AnyCancellable>()
    
    // Smart Search Engine
    private var searchEngine: SmartFoodSearch3?
    
    // Pagination (Only used when searchText is empty)
    private let pageSize = 50
    private var currentOffset = 0
    private var currentTask: Task<Void, Never>?
    
    // MARK: - Init
    init() {
        Publishers.CombineLatest(
            $searchText.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.removeDuplicates(),
            $filter.removeDuplicates()
        )
        .dropFirst()
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.resetAndLoad()
        }
        .store(in: &cancellables)
    }
    
    /// Attaches the real `ModelContext` and initializes the Search Engine.
    func attach(context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        self.container = context.container
        
        // Initialize the Smart Search Engine with the container
        if let container = self.container {
            self.searchEngine = SmartFoodSearch3(container: container)
            
            // Pre-load data in background so search is snappy later
            Task {
                await self.searchEngine?.loadData()
            }
        }
    }
    
    // MARK: - Loading Logic
    
    func loadNextPage() {
        // If we are performing a Smart Search (text is not empty),
        // we essentially return all relevant ranked results in one go (top 100-200),
        // so we disable infinite scroll to avoid complexity with ranking vs offsetting.
        if !searchText.isEmpty { return }
        
        loadPage(isReset: false)
    }
    
    func resetAndLoad() {
        // Cancel any ongoing task.
        currentTask?.cancel()
        currentTask = nil
        
        isLoading = true
        
        loadPage(isReset: true)
    }
    
    /// Fetches items. Delegates to SmartSearch if query exists, otherwise uses standard DB fetch.
    private func loadPage(isReset: Bool) {
          if !isReset && isLoading { return }
          
          guard let container, let searchEngine, let mainCtx = self.context else {
              if isReset { self.isLoading = false }
              return
          }
          
          // Refresh search engine index
          searchEngine.refreshData()
          
          isLoading = true
          
          let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
          let currentFilter = self.filter
        
        // --- 1. SMART SEARCH MODE (Query exists) ---
        if !query.isEmpty {
            currentTask = Task {
                // Determine engine constraints based on current UI filter
                var isRecipes = false
                var isMenus = false
                var isFavorites = false
                
                switch currentFilter {
                case .recipes:   isRecipes = true
                case .menus:     isMenus = true
                case .favorites: isFavorites = true
                case .foods, .default, .diets, .plans:
                    break
                }
                
                // Perform the search using the engine
                let results = await searchEngine.searchResults(
                    query: query,
                    activeFilters: [],
                    isFavoritesOnly: isFavorites,
                    isRecipesOnly: isRecipes,
                    isMenusOnly: isMenus,
                    limit: 200
                )
                
                if Task.isCancelled {
                    await MainActor.run { self.isLoading = false }
                    return
                }
                
                // Post-process results based on specific list filters
                let filteredResults = results.filter { item in
                    switch currentFilter {
                    case .foods:
                        return !item.isRecipe && !item.isMenu && item.isUserAdded
                    case .default:
                        return !item.isUserAdded
                    case .diets, .plans:
                        return false
                    case .recipes:
                        return item.isUserAdded && item.isRecipe
                    case .menus:
                        return item.isUserAdded && item.isMenu
                    case .favorites:
                        return true
                    }
                }
                
                await MainActor.run {
                    self.items = filteredResults
                    self.hasMore = false
                    self.isLoading = false
                }
            }
            return
        }
        
        // --- 2. BROWSE MODE (Empty Query) ---
        // ✅ FIX: Използваме директно mainCtx, за да избегнем проблеми със синхронизацията
        // между нишките при бързо изтриване/добавяне.
        
        let offset = isReset ? 0 : self.currentOffset
        let limit = self.pageSize
        
        // Не използваме Task.detached тук, за да гарантираме работа с Main Context
        // Въпреки че сме в Task, ние сме на @MainActor, така че кодът е безопасен.
        currentTask = Task {
            let predicate = makeEmptyStatePredicate(filter: currentFilter)
            var descriptor = FetchDescriptor<FoodItem>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit
            
            do {
                // Директен fetch от главния контекст
                let displayItems = try mainCtx.fetch(descriptor)
                
                if Task.isCancelled {
                    self.isLoading = false
                    return
                }
                
                if isReset {
                    self.items = displayItems
                } else {
                    self.items.append(contentsOf: displayItems)
                }
                
                self.currentOffset = offset + displayItems.count
                self.hasMore = displayItems.count == limit
                self.isLoading = false
                
            } catch {
                print("❌ Browse fetch failed: \(error)")
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Predicate Builder (Empty State Only)
    
    private func makeEmptyStatePredicate(filter: FoodItemListView.Filter) -> Predicate<FoodItem> {
        switch filter {
        case .foods:     return #Predicate<FoodItem> { $0.isEdible && $0.isUserAdded && !$0.isRecipe && !$0.isMenu }
        case .recipes:   return #Predicate<FoodItem> { $0.isEdible && $0.isUserAdded && $0.isRecipe }
        case .menus:     return #Predicate<FoodItem> { $0.isEdible && $0.isUserAdded && $0.isMenu }
        case .favorites: return #Predicate<FoodItem> { $0.isEdible && $0.isFavorite }
        case .default:   return #Predicate<FoodItem> { $0.isEdible && !$0.isUserAdded }
        case .diets:     return #Predicate<FoodItem> { _ in false }
        case .plans:     return #Predicate<FoodItem> { _ in false }
        }
    }
    
    // MARK: - Delete Helpers (Kept Intact)
    
    func ingredientUsageCount(for item: FoodItem) -> Int {
        guard let ctx = context else { return 0 }
        let targetID = item.id
        let descriptor = FetchDescriptor<IngredientLink>(
            predicate: #Predicate<IngredientLink> { link in
                link.food?.id == targetID
            }
        )
        do {
            let links = try ctx.fetch(descriptor)
            return links.count
        } catch {
            print("❌ Failed to fetch ingredient usage count: \(error)")
            return 0
        }
    }
    
    func foodUsageCount(_ item: FoodItem) -> Int {
        guard let ctx = context else { return 0 }
        let targetID = item.id
        
        do {
            let ingredientDesc = FetchDescriptor<IngredientLink>(
                predicate: #Predicate<IngredientLink> { link in
                    link.food?.id == targetID
                }
            )
            let ingredientCount = try ctx.fetch(ingredientDesc).count
            
            let mealEntryDesc = FetchDescriptor<MealPlanEntry>(
                predicate: #Predicate<MealPlanEntry> { entry in
                    entry.food?.id == targetID
                }
            )
            let mealEntryCount = try ctx.fetch(mealEntryDesc).count
            
            return ingredientCount + mealEntryCount
        } catch {
            print("❌ Failed to fetch food usage count: \(error)")
            return 0
        }
    }

    func deleteDetachingFromRecipesAndMealPlans(_ item: FoodItem) {
        guard let ctx = context else { return }
        let targetID = item.id
        
        do {
            let ingredientDesc = FetchDescriptor<IngredientLink>(
                predicate: #Predicate<IngredientLink> { link in
                    link.food?.id == targetID
                }
            )
            let ingredientLinks = try ctx.fetch(ingredientDesc)
            if !ingredientLinks.isEmpty {
                print("🧹 Removing \(ingredientLinks.count) ingredient links for food '\(item.name)'")
                ingredientLinks.forEach { ctx.delete($0) }
            }
            
            let mealEntryDesc = FetchDescriptor<MealPlanEntry>(
                predicate: #Predicate<MealPlanEntry> { entry in
                    entry.food?.id == targetID
                }
            )
            let mealEntries = try ctx.fetch(mealEntryDesc)
            if !mealEntries.isEmpty {
                print("🧹 Removing \(mealEntries.count) meal plan entries for food '\(item.name)'")
                mealEntries.forEach { ctx.delete($0) }
            }
        } catch {
            print("❌ Failed to detach food from recipes/meal plans before delete: \(error)")
        }
        
        delete(item)
    }

    func delete(_ item: FoodItem) {
        guard item.isUserAdded, let ctx = context else { return }
        
        let foodID = item.id
        
        // 1) Remove row from UI immediately
        if let index = items.firstIndex(of: item) {
            items.remove(at: index)
        }
        
        // 2) Delete logic directly on MainActor to ensure consistency
        // --- Logic for menus ---
        if item.isMenu {
            print("🗑️ Deleting a menu item: \(item.name). Checking for linked meal plans...")
            let menuIDToDelete = item.id
            let descriptor = FetchDescriptor<MealPlanMeal>(
                predicate: #Predicate { $0.linkedMenuID == menuIDToDelete }
            )
            do {
                let linkedMeals = try ctx.fetch(descriptor)
                if !linkedMeals.isEmpty {
                    for meal in linkedMeals {
                        for entry in meal.entries {
                            ctx.delete(entry)
                        }
                        meal.entries.removeAll()
                        meal.linkedMenuID = nil
                    }
                }
            } catch {
                print("   - ❌ Failed to fetch linked meal plan meals: \(error)")
            }
        }
        
        // 3) Cleanup Metadata
        self.cleanupShoppingMetadata(for: item)
        self.cleanupPantryHistory(for: item)
        
        // 4) Update Search Index (Remove from In-Memory Cache)
        SearchIndexStore.shared.removeItem(id: foodID, context: ctx)

        // 5) Nullify relations
        item.macronutrients = nil
        item.lipids         = nil
        item.vitamins       = nil
        item.minerals       = nil
        item.other          = nil
        item.aminoAcids     = nil
        item.carbDetails    = nil
        item.sterols        = nil
        
        // 6) Delete
        ctx.delete(item)
        
        do {
            try ctx.save()
        } catch {
            print("❌ Failed to save context after deleting food '\(item.name)': \(error)")
        }
    }
    
    func pruneFavoritesAfterToggle() {
        guard filter == .favorites else { return }
        items.removeAll { !$0.isFavorite }
    }
    
    // MARK: - Pantry / History cleanup

    private func cleanupPantryHistory(for item: FoodItem) {
        guard let ctx = context else { return }
        let targetPID = item.persistentModelID
        
        do {
            let linksDesc = FetchDescriptor<MealLogStorageLink>(
                predicate: #Predicate<MealLogStorageLink> {
                    $0.food?.persistentModelID == targetPID
                }
            )
            let links = try ctx.fetch(linksDesc)
            links.forEach { ctx.delete($0) }
            
            let transactionsDesc = FetchDescriptor<StorageTransaction>(
                predicate: #Predicate<StorageTransaction> {
                    $0.food?.persistentModelID == targetPID
                }
            )
            let transactions = try ctx.fetch(transactionsDesc)
            transactions.forEach { ctx.delete($0) }
            
        } catch {
            print("❌ Failed to cleanup pantry history for food '\(item.name)': \(error)")
        }
    }

    // MARK: - Shopping / Suggestions cleanup

    private func cleanupShoppingMetadata(for item: FoodItem) {
        guard let ctx = context else { return }
        let targetID  = item.id
        let targetPID = item.persistentModelID
        
        do {
            let recentDesc = FetchDescriptor<RecentlyAddedFood>(
                predicate: #Predicate<RecentlyAddedFood> { entry in
                    entry.food?.id == targetID
                }
            )
            let recentEntries = try ctx.fetch(recentDesc)
            if !recentEntries.isEmpty {
                recentEntries.forEach { ctx.delete($0) }
            }
            
            let dismissedDesc = FetchDescriptor<DismissedFoodID>(
                predicate: #Predicate<DismissedFoodID> { dismissed in
                    dismissed.foodID == targetID
                }
            )
            let dismissedEntries = try ctx.fetch(dismissedDesc)
            if !dismissedEntries.isEmpty {
                dismissedEntries.forEach { ctx.delete($0) }
            }
            
            let shoppingItemsDesc = FetchDescriptor<ShoppingListItem>(
                predicate: #Predicate<ShoppingListItem> { sli in
                    sli.foodItem?.persistentModelID == targetPID
                }
            )
            let shoppingItems = try ctx.fetch(shoppingItemsDesc)
            if !shoppingItems.isEmpty {
                shoppingItems.forEach { ctx.delete($0) }
            }
            
        } catch {
            print("❌ Failed to cleanup shopping metadata for food '\(item.name)': \(error)")
        }
    }
}
