import Combine
import Foundation
import SwiftData

@MainActor
final class FoodListVM: ObservableObject {
    
    // MARK: - Inputs & Outputs
    @Published var searchText: String = ""
    @Published var filter: FoodItemListView.Filter = .foods
    @Published private(set) var items: [FoodItem] = []
    @Published private(set) var hasMore: Bool = false
    
    // MARK: - Private State
    private var context: ModelContext!
    private var container: ModelContainer?
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 30
    @Published private(set) var isLoading: Bool = false
    private var currentTask: Task<Void, Never>?
    
    // Two-phase search
    private enum SearchPhase { case startsWith, contains, finished }
    private var searchPhase: SearchPhase = .startsWith
    private var startsWithOffset = 0
    private var containsOffset = 0
    
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
    
    /// Attaches the real `ModelContext` (called from the View).
    func attach(context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        self.container = context.container
    }
    
    // MARK: - Loading Logic
    
    func loadNextPage() {
        // Explicitly state this is not a reset, but loading the next page.
        loadPage(isReset: false)
    }
    
    func resetAndLoad() {
        // Cancel any ongoing task.
        currentTask?.cancel()
        currentTask = nil
        
        // Show the loading indicator, but DO NOT clear `items`.
        isLoading = true
        
        // Call loadPage with a flag to indicate a fresh load.
        loadPage(isReset: true)
    }
    
    /// Fetches a page of items. Can either reset the list or append to it.
    private func loadPage(isReset: Bool) {
        // If already loading and it's not a reset request, do nothing.
        if !isReset && isLoading { return }
        
        guard let container else {
            // If the context is not yet available, stop the indicator.
            if isReset { self.isLoading = false }
            return
        }
        
        isLoading = true
        
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let startsPredicate   = makePredicate(for: .startsWith, search: search)
        let containsPredicate = makePredicate(for: .contains,   search: search)
        
        // If it's a reset, start from the beginning. Otherwise, use current values.
        let startsOff   = isReset ? 0 : self.startsWithOffset
        let containsOff = isReset ? 0 : self.containsOffset
        let phase0      = isReset ? SearchPhase.startsWith : self.searchPhase
        let pageSize    = self.pageSize
        
        // Cancel the previous task to avoid race conditions.
        currentTask?.cancel()
        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            let bg = ModelContext(container)
            bg.autosaveEnabled = false
            
            var resultsIDs: [Int] = []
            var nextStarts   = startsOff
            var nextContains = containsOff
            var phase        = phase0
            
            if phase == .startsWith {
                var d = FetchDescriptor<FoodItem>(
                    predicate: startsPredicate,
                    sortBy: [SortDescriptor(\.name)]
                )
                d.fetchOffset = startsOff
                d.fetchLimit  = pageSize
                
                let page = (try? bg.fetch(d)) ?? []
                resultsIDs.append(contentsOf: page.map(\.id))
                nextStarts += page.count
                
                if search.isEmpty {
                    if page.count < pageSize { phase = .finished }
                } else {
                    if page.count < pageSize { phase = .contains }
                }
            }
            
            if !search.isEmpty, phase == .contains, resultsIDs.count < pageSize {
                let needed = pageSize - resultsIDs.count
                var d = FetchDescriptor<FoodItem>(
                    predicate: containsPredicate,
                    sortBy: [SortDescriptor(\.name)]
                )
                d.fetchOffset = containsOff
                d.fetchLimit  = needed
                
                let page = (try? bg.fetch(d)) ?? []
                resultsIDs.append(contentsOf: page.map(\.id))
                nextContains += page.count
                
                if page.count < needed { phase = .finished }
            }
            
            // Check if the task was cancelled before updating the UI.
            if Task.isCancelled {
                await MainActor.run { [weak self] in self?.isLoading = false }
                return
            }
            
            await MainActor.run { [weak self] in
                guard let self, let ctx = self.context else { return }
                
                var fetchedItems: [FoodItem] = []
                if !resultsIDs.isEmpty {
                    let idSet = Set(resultsIDs)
                    let d = FetchDescriptor<FoodItem>(predicate: #Predicate { idSet.contains($0.id) })
                    if let objs = try? ctx.fetch(d) {
                        var sorted = objs
                        sorted.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
                        fetchedItems = sorted
                    }
                }
                
                if isReset {
                    // For a reset, replace the entire array.
                    self.items = fetchedItems
                } else {
                    // For a next page, append to the existing array.
                    self.items.append(contentsOf: fetchedItems)
                }
                
                self.startsWithOffset = nextStarts
                self.containsOffset   = nextContains
                self.searchPhase      = phase
                self.hasMore          = (self.searchPhase != .finished)
                self.isLoading        = false
            }
        }
    }
    
    // MARK: - Predicate Builder
    private func makePredicate(for phase: SearchPhase, search: String) -> Predicate<FoodItem> {
        let normalizedSearch = search.lowercased()
        
        if search.isEmpty {
            switch filter {
            case .foods:     return #Predicate<FoodItem> { $0.isUserAdded && !$0.isRecipe && !$0.isMenu }
            case .recipes:   return #Predicate<FoodItem> { $0.isUserAdded && $0.isRecipe }
            case .menus:     return #Predicate<FoodItem> { $0.isUserAdded && $0.isMenu }
            case .favorites: return #Predicate<FoodItem> { $0.isFavorite }
            case .default:   return #Predicate<FoodItem> { !$0.isUserAdded }
            case .diets:     return #Predicate<FoodItem> { _ in false }
            case .plans:     return #Predicate<FoodItem> { _ in false }
            }
        }
        
        switch filter {
        case .foods:
            if phase == .startsWith {
                return #Predicate<FoodItem> { item in
                    item.nameNormalized.starts(with: normalizedSearch) &&
                    item.isUserAdded && !item.isRecipe && !item.isMenu
                }
            } else {
                return #Predicate<FoodItem> { item in
                    item.name.localizedStandardContains(search) &&
                    !item.nameNormalized.starts(with: normalizedSearch) &&
                    item.isUserAdded && !item.isRecipe && !item.isMenu
                }
            }
            
        case .recipes:
            if phase == .startsWith {
                return #Predicate<FoodItem> { item in
                    item.nameNormalized.starts(with: normalizedSearch) &&
                    item.isUserAdded && item.isRecipe
                }
            } else {
                return #Predicate<FoodItem> { item in
                    item.name.localizedStandardContains(search) &&
                    !item.nameNormalized.starts(with: normalizedSearch) &&
                    item.isUserAdded && item.isRecipe
                }
            }
            
        case .menus:
            if phase == .startsWith {
                return #Predicate<FoodItem> { item in
                    item.nameNormalized.starts(with: normalizedSearch) &&
                    item.isUserAdded && item.isMenu
                }
            } else {
                return #Predicate<FoodItem> { item in
                    item.name.localizedStandardContains(search) &&
                    !item.nameNormalized.starts(with: normalizedSearch) &&
                    item.isUserAdded && item.isMenu
                }
            }
            
        case .favorites:
            if phase == .startsWith {
                return #Predicate<FoodItem> { item in
                    item.nameNormalized.starts(with: normalizedSearch) && item.isFavorite
                }
            } else {
                return #Predicate<FoodItem> { item in
                    item.name.localizedStandardContains(search) &&
                    !item.nameNormalized.starts(with: normalizedSearch) &&
                    item.isFavorite
                }
            }
            
        case .default:
            if phase == .startsWith {
                return #Predicate<FoodItem> { item in
                    item.nameNormalized.starts(with: normalizedSearch) && !item.isUserAdded
                }
            } else {
                return #Predicate<FoodItem> { item in
                    item.name.localizedStandardContains(search) &&
                    !item.nameNormalized.starts(with: normalizedSearch) &&
                    !item.isUserAdded
                }
            }
            
        case .diets:
            return #Predicate<FoodItem> { _ in false }
            
        case .plans:
            return #Predicate<FoodItem> { _ in false }
        }
    }
    
    // MARK: - Delete Helpers
    
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
        
        // 1) Първо махаме реда от UI
        if let index = items.firstIndex(of: item) {
            items.remove(at: index)
        }
        
        // 2) Изчакваме, за да се обнови UI
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self,
                  let ctx = self.context,
                  let item = item
            else { return }
            
            if item.modelContext == nil { return }
            
            // --- логика за менюта ---
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
            
            // 3) Чистим RecentlyAddedFood / DismissedFoodID / ShoppingListItem
            self.cleanupShoppingMetadata(for: item)
            
            // 4) Чистим история (MealLogStorageLink / StorageTransaction)
            self.cleanupPantryHistory(for: item)
            
            // 5) (ПРЕМАХНАТО) Вече не викаме cleanupIndexes(for:), тъй като моделите са изтрити.
            
            // 6) Обновяваме In-Memory Search Cache (важно за търсачката)
            SearchIndexStore.shared.removeItem(id: foodID, context: ctx)

            // 7) Нулираме релациите (optional)
            item.macronutrients = nil
            item.lipids         = nil
            item.vitamins       = nil
            item.minerals       = nil
            item.other          = nil
            item.aminoAcids     = nil
            item.carbDetails    = nil
            item.sterols        = nil
            
            // 8) Трием FoodItem
            ctx.delete(item)
            
            do {
                try ctx.save()
            } catch {
                print("❌ Failed to save context after deleting food '\(item.name)': \(error)")
            }
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
