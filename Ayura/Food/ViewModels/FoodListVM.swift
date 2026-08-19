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
    private var userContext: ModelContext?
    private var userContainer: ModelContainer?
    private var container: ModelContainer?
    private var cancellables = Set<AnyCancellable>()
    
    // Smart Search Engine
    private var searchEngine: SmartFoodSearch3?
    
    // Pagination (Only used when searchText is empty)
    private let pageSize = 50
    private var currentOffset = 0
    private var currentTask: Task<Void, Never>?
    private var recentUserWrites: [UUID: FoodItem] = [:]
    private var recentUserWriteContexts: [UUID: ModelContext] = [:]
    
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
        self.userContext = try? CombinedStoreFactory.makeUserWriteContext(
            from: context.container
        )
        self.userContainer = self.userContext?.container
        try? CatalogPreferenceStore.shared.load(context: context)
        
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

    /// Applies a food saved by the dedicated user-store writer immediately.
    /// The combined read context can retain an older registered instance after
    /// another container updates the same SQLite row, so refetching alone may
    /// briefly redisplay stale values until the next launch.
    func applyUserStoreWrite(_ item: FoodItem) {
        // Retain the exact context that owns the successfully saved object.
        // Otherwise the editor's local context can be released on dismissal,
        // leaving `item.modelContext == nil`; FoodItemRowView deliberately
        // hides such detached objects even though the row is already in SQLite.
        let displayItem: FoodItem
        if let savedContext = item.modelContext {
            userContext = savedContext
            recentUserWriteContexts[item.id] = savedContext
            displayItem = item
        } else if let userContainer {
            let freshContext = ModelContext(userContainer)
            freshContext.autosaveEnabled = false
            userContext = freshContext
            let itemID = item.id
            var descriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            descriptor.fetchLimit = 1
            displayItem = (try? freshContext.fetch(descriptor).first) ?? item
            recentUserWriteContexts[item.id] = freshContext
        } else {
            displayItem = item
        }

        recentUserWrites[displayItem.id] = displayItem
        print(
            "USER_FOOD_LIST_WRITE|name=\(displayItem.name)|filter=\(filter.rawValue)"
        )
        items.removeAll { $0.id == displayItem.id }
        if shouldDisplay(displayItem, for: filter) {
            items.append(displayItem)
            items.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
        }
        currentOffset = items.count
        isLoading = false
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
                case .foods, .default, .plans:
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
                    case .plans:
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
                // User-created foods, recipes and menus are read through the
                // same unambiguous user-only container used by their editors.
                // Catalogue/default browsing continues through the combined
                // read context.
                let browseContext: ModelContext
                switch currentFilter {
                case .foods, .recipes, .menus:
                    if let userContainer {
                        let freshContext = ModelContext(userContainer)
                        freshContext.autosaveEnabled = false
                        userContext = freshContext
                        browseContext = freshContext
                    } else {
                        browseContext = userContext ?? mainCtx
                    }
                case .default, .favorites, .plans:
                    browseContext = mainCtx
                }
                var displayItems = try browseContext.fetch(descriptor)

                // A reset can finish after an editor's immediate list update.
                // Reconcile recent successful writes so that late pagination
                // results cannot hide the newly saved or edited object.
                if isReset {
                    for item in recentUserWrites.values {
                        displayItems.removeAll { $0.id == item.id }
                        if shouldDisplay(item, for: currentFilter) {
                            displayItems.append(item)
                        }
                    }
                    displayItems.sort {
                        $0.name.localizedCaseInsensitiveCompare($1.name)
                            == .orderedAscending
                    }
                    print(
                        "USER_FOOD_LIST_FETCH|filter=\(currentFilter.rawValue)"
                            + "|count=\(displayItems.count)"
                            + "|recent=\(recentUserWrites.count)"
                    )
                }
                
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
        let catalogFavoriteIDs = CatalogPreferenceStore.shared.favoriteIDs(
            kind: "food"
        )
        switch filter {
        case .foods:     return #Predicate<FoodItem> { $0.isEdible && $0.isUserAdded && !$0.isRecipe && !$0.isMenu }
        case .recipes:   return #Predicate<FoodItem> { $0.isEdible && $0.isUserAdded && $0.isRecipe }
        case .menus:     return #Predicate<FoodItem> { $0.isEdible && $0.isUserAdded && $0.isMenu }
        case .favorites: return #Predicate<FoodItem> {
            $0.isEdible
                && ($0.isFavorite || catalogFavoriteIDs.contains($0.id))
        }
        case .default:   return #Predicate<FoodItem> { $0.isEdible && !$0.isUserAdded }
        case .plans:     return #Predicate<FoodItem> { _ in false }
        }
    }

    private func shouldDisplay(
        _ item: FoodItem,
        for filter: FoodItemListView.Filter
    ) -> Bool {
        switch filter {
        case .foods:
            return item.isEdible && item.isUserAdded
                && !item.isRecipe && !item.isMenu
        case .recipes:
            return item.isEdible && item.isUserAdded && item.isRecipe
        case .menus:
            return item.isEdible && item.isUserAdded && item.isMenu
        case .favorites:
            return item.isEdible && (
                item.isFavorite
                    || CatalogPreferenceStore.shared.isFavorite(
                        kind: "food",
                        itemID: item.id,
                        fallback: false
                    )
            )
        case .default:
            return item.isEdible && !item.isUserAdded
        case .plans:
            return false
        }
    }
    
    // MARK: - Delete Helpers (Kept Intact)
    
    func ingredientUsageCount(for item: FoodItem) -> Int {
        guard let ctx = context else { return 0 }
        let targetID = item.id
        let descriptor = FetchDescriptor<IngredientLink>(
            predicate: #Predicate<IngredientLink> { link in
                link.persistedFood?.id == targetID
                    || link.catalogFoodID == targetID
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
                    link.persistedFood?.id == targetID
                        || link.catalogFoodID == targetID
                }
            )
            let ingredientCount = try ctx.fetch(ingredientDesc).count
            
            let mealEntryDesc = FetchDescriptor<MealPlanEntry>(
                predicate: #Predicate<MealPlanEntry> { entry in
                    entry.persistedFood?.id == targetID
                        || entry.catalogFoodID == targetID
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
        guard let ctx = userContext else { return }
        let targetID = item.id
        
        do {
            let ingredientDesc = FetchDescriptor<IngredientLink>(
                predicate: #Predicate<IngredientLink> { link in
                    link.persistedFood?.id == targetID
                        || link.catalogFoodID == targetID
                }
            )
            let ingredientLinks = try ctx.fetch(ingredientDesc)
            if !ingredientLinks.isEmpty {
                print("🧹 Removing \(ingredientLinks.count) ingredient links for food '\(item.name)'")
                ingredientLinks.forEach { ctx.delete($0) }
            }
            
            let mealEntryDesc = FetchDescriptor<MealPlanEntry>(
                predicate: #Predicate<MealPlanEntry> { entry in
                    entry.persistedFood?.id == targetID
                        || entry.catalogFoodID == targetID
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
        guard item.isUserAdded, let ctx = userContext else { return }
        let foodID = item.id

        do {
            guard let storedItem = try CatalogReferenceResolver.userFood(
                id: foodID,
                context: ctx
            ) else {
                throw CatalogReferenceError.missingUserFood(foodID)
            }
            let itemName = storedItem.name

            // All models mutated below are user-owned. Fetching and deleting
            // them in the single-store context prevents a combined read
            // context from merely dropping the visible row while the SQLite
            // record survives (or from routing a fault to the catalogue).
            if storedItem.isMenu {
                print("🗑️ Deleting a menu item: \(itemName). Checking for linked meal plans...")
                let menuIDToDelete = foodID
                let descriptor = FetchDescriptor<MealPlanMeal>(
                    predicate: #Predicate { $0.linkedMenuID == menuIDToDelete }
                )
                let linkedMeals = try ctx.fetch(descriptor)
                for meal in linkedMeals {
                    for entry in meal.entries {
                        ctx.delete(entry)
                    }
                    meal.entries.removeAll()
                    meal.linkedMenuID = nil
                }
            }

            cleanupShoppingMetadata(forID: foodID, in: ctx)
            cleanupPantryHistory(forID: foodID, in: ctx)
            SearchIndexStore.shared.removeItem(id: foodID, context: ctx)
            AyurvedaUserProfileStore.remove(foodId: foodID, context: ctx)

            storedItem.macronutrients = nil
            storedItem.lipids         = nil
            storedItem.vitamins       = nil
            storedItem.minerals       = nil
            storedItem.other          = nil
            storedItem.aminoAcids     = nil
            storedItem.carbDetails    = nil
            storedItem.sterols        = nil
            ctx.delete(storedItem)
            try ctx.save()

            items.removeAll { $0.id == foodID }
            recentUserWrites.removeValue(forKey: foodID)
            recentUserWriteContexts.removeValue(forKey: foodID)
        } catch {
            print("❌ Failed to delete food '\(item.name)': \(error)")
        }
    }

    func pruneFavoritesAfterToggle() {
        guard filter == .favorites else { return }
        items.removeAll { !$0.effectiveIsFavorite }
    }
    
    // MARK: - Pantry / History cleanup

    private func cleanupPantryHistory(
        forID targetID: UUID,
        in ctx: ModelContext
    ) {
        do {
            let linksDesc = FetchDescriptor<MealLogStorageLink>(
                predicate: #Predicate<MealLogStorageLink> {
                    $0.persistedFood?.id == targetID
                        || $0.catalogFoodID == targetID
                }
            )
            let links = try ctx.fetch(linksDesc)
            links.forEach { ctx.delete($0) }
            
            let transactionsDesc = FetchDescriptor<StorageTransaction>(
                predicate: #Predicate<StorageTransaction> {
                    $0.persistedFood?.id == targetID
                        || $0.catalogFoodID == targetID
                }
            )
            let transactions = try ctx.fetch(transactionsDesc)
            transactions.forEach { ctx.delete($0) }
            
        } catch {
            print("❌ Failed to cleanup pantry history for food \(targetID): \(error)")
        }
    }

    // MARK: - Shopping / Suggestions cleanup

    private func cleanupShoppingMetadata(
        forID targetID: UUID,
        in ctx: ModelContext
    ) {
        do {
            let recentDesc = FetchDescriptor<RecentlyAddedFood>(
                predicate: #Predicate<RecentlyAddedFood> { entry in
                    entry.persistedFood?.id == targetID
                        || entry.catalogFoodID == targetID
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
                    sli.persistedFoodItem?.id == targetID
                        || sli.catalogFoodID == targetID
                }
            )
            let shoppingItems = try ctx.fetch(shoppingItemsDesc)
            if !shoppingItems.isEmpty {
                shoppingItems.forEach { ctx.delete($0) }
            }
            
        } catch {
            print("❌ Failed to cleanup shopping metadata for food \(targetID): \(error)")
        }
    }
}
