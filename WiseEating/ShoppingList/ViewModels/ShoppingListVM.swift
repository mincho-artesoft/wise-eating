import SwiftUI
import SwiftData
import Combine

@MainActor
class ShoppingListViewModel: ObservableObject {
    @Published var lists: [ShoppingListModel] = []
    
    @Published var isDataLoaded: Bool = false
    
    @Published var suggestedItems: [StorageItem] = []
    @Published var recentFoodItems: [FoodItem] = []
    
    @Published var isLoadingSuggestions = false

    private static let lastOpenedKey = "LastOpenedShoppingListID"

    var lastOpenedListID: UUID? {
        didSet {
            let key = Self.lastOpenedKey + "_\(dataOwnerKeySuffix)"
            if let id = lastOpenedListID {
                UserDefaults.standard.set(id.uuidString, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    
    let profile: Profile
    private var modelContext: ModelContext?
    
    private var dataOwnerProfileID: PersistentIdentifier? {
        profile.hasSeparateStorage ? profile.persistentModelID : nil
    }
    
    private var dataOwnerProfile: Profile? {
        profile.hasSeparateStorage ? profile : nil
    }
    
    private var dataOwnerKeySuffix: String {
        if let profileID = dataOwnerProfileID {
            if let encodedData = try? JSONEncoder().encode(profileID),
               let encodedString = String(data: encodedData, encoding: .utf8) {
                return encodedString.filter { $0.isLetter || $0.isNumber }
            }
        }
        return "global"
    }
    
    init(profile: Profile) {
        self.profile = profile
        let key = Self.lastOpenedKey + "_\(dataOwnerKeySuffix)"
        if let saved = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: saved) {
            self.lastOpenedListID = uuid
        }
    }
    
    func setup(context: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = context
        fetchAllData()
    }
    
    func recordLastOpened(_ list: ShoppingListModel) {
        lastOpenedListID = list.id
    }
    
    func fetchAllData() {
        fetchLists()
        fetchLowStockSuggestions()
        fetchRecentFoodSuggestions()
    }
    
    func fetchLists() {
        guard let modelContext = modelContext else { return }
        let ownerID = dataOwnerProfileID
        
        let descriptor = FetchDescriptor<ShoppingListModel>(
            predicate: #Predicate { $0.profile?.persistentModelID == ownerID },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        do {
            lists = try modelContext.fetch(descriptor)
            if !isDataLoaded {
                isDataLoaded = true
            }
        } catch {
            print("SHOPPING VM: ❗️❗️ Грешка при fetch на списъци: \(error)")
        }
    }
    
    func deleteAllLists() {
        guard let modelContext = modelContext else { return }
        for list in lists {
            if let notificationID = list.notificationID {
                NotificationManager.shared.cancelNotification(id: notificationID)
            }
            if let eventID = list.calendarEventID {
                Task { await CalendarViewModel.shared.deleteEvent(withIdentifier: eventID) }
            }
            modelContext.delete(list)
        }
        saveAndReload()
    }
    
    func deleteList(at offsets: IndexSet) {
        guard let modelContext = modelContext else { return }
        for index in offsets {
            let listToDelete = lists[index]
            if let notificationID = listToDelete.notificationID {
                NotificationManager.shared.cancelNotification(id: notificationID)
            }
            if let eventID = listToDelete.calendarEventID {
                Task { await CalendarViewModel.shared.deleteEvent(withIdentifier: eventID) }
            }
            modelContext.delete(listToDelete)
        }
        saveAndReload()
    }
    
    func delete(list: ShoppingListModel) {
        guard let modelContext = modelContext else { return }
        if let notificationID = list.notificationID {
            NotificationManager.shared.cancelNotification(id: notificationID)
        }
        if let eventID = list.calendarEventID {
            Task { await CalendarViewModel.shared.deleteEvent(withIdentifier: eventID) }
        }
        modelContext.delete(list)
        saveAndReload()
    }
    
    @discardableResult
    func duplicate(list original: ShoppingListModel) -> ShoppingListModel {
        let ownerProfile = self.profile.hasSeparateStorage ? self.profile : nil
        
        let copy = ShoppingListModel(
            profile: ownerProfile,
            name: original.name,
            reminderMinutes: original.reminderMinutes
        )
        copy.creationDate = Date()

        original.dismissedSuggestions.forEach { dismissedOriginal in
            let newDismissed = DismissedFoodID(foodID: dismissedOriginal.foodID)
            copy.dismissedSuggestions.append(newDismissed)
        }

        original.items.forEach { item in
            let newItem = ShoppingListItem(
                name:     item.name,
                quantity: item.quantity,
                price:    item.price,
                isBought: false,
                foodItem: item.foodItem
            )
            copy.items.append(newItem)
        }
        
        modelContext?.insert(copy)

        Task { @MainActor in
            guard let context = self.modelContext else { return }
            
            // --- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 ---
            let newEventID = await CalendarViewModel.shared.createOrUpdateShoppingListEvent(
                for: copy,
                context: context
            )
            // --- 👆 КРАЙ НА ПРОМЯНАТА 👆 ---

            copy.calendarEventID = newEventID
            try? context.save()
        }
        
        return copy
    }
    
    private func unpackIngredients(from item: FoodItem) -> [FoodItem] {
        guard item.isRecipe || item.isMenu else { return [item] }
        var ingredients: [FoodItem] = []
        for link in item.ingredients ?? [] {
            if let food = link.food {
                ingredients.append(contentsOf: unpackIngredients(from: food))
            }
        }
        return ingredients
    }

    func fetchLowStockSuggestions() {
        guard let modelContext = modelContext else { return }
        isLoadingSuggestions = true
        
        let ownerID = dataOwnerProfileID
        
        do {
            let allDescriptor = FetchDescriptor<StorageItem>(predicate: #Predicate { $0.owner?.persistentModelID == ownerID })
            let allItems = try modelContext.fetch(allDescriptor)

            let lowStockItemsAndRecipes = allItems.filter { $0.totalQuantity >= 0 && $0.totalQuantity <= 200 }
            
            var lowStockBaseProducts: [StorageItem] = []
            for storageItem in lowStockItemsAndRecipes {
                guard let foodItem = storageItem.food else { continue }
                if !foodItem.isRecipe && !foodItem.isMenu {
                    lowStockBaseProducts.append(storageItem)
                } else {
                    let baseIngredients = unpackIngredients(from: foodItem)
                    let baseIngredientIDs = Set(baseIngredients.map { $0.id })
                    let ingredientStorageItems = allItems.filter {
                        guard let id = $0.food?.id else { return false }
                        return baseIngredientIDs.contains(id) && $0.totalQuantity <= 200
                    }
                    lowStockBaseProducts.append(contentsOf: ingredientStorageItems)
                }
            }
            
            let inListPredicate = #Predicate<ShoppingListItem> {
                $0.list?.profile?.persistentModelID == ownerID && $0.foodItem != nil
            }
            let listDescriptor = FetchDescriptor(predicate: inListPredicate)
            let listItems = try modelContext.fetch(listDescriptor)
            let existingFoodItemPersistentIDs = Set(listItems.compactMap { $0.foodItem?.persistentModelID })
            
            let finalSuggestions = lowStockBaseProducts.filter { storageItem in
                guard let foodPersistentID = storageItem.food?.persistentModelID else { return false }
                return !existingFoodItemPersistentIDs.contains(foodPersistentID)
            }
            
            var uniqueSuggestions: [StorageItem] = []
            var seenIDs = Set<Int>()
            for item in finalSuggestions {
                if let food = item.food, !seenIDs.contains(food.id) {
                    uniqueSuggestions.append(item)
                    seenIDs.insert(food.id)
                }
            }
            self.suggestedItems = uniqueSuggestions
        } catch {
            print("Failed to fetch low stock suggestions: \(error)")
        }
        isLoadingSuggestions = false
    }
    
    func fetchRecentFoodSuggestions() {
        guard let modelContext = modelContext else { return }
        do {
            let predicate: Predicate<RecentlyAddedFood>
            if profile.hasSeparateStorage {
                let profileID = profile.persistentModelID
                predicate = #Predicate<RecentlyAddedFood> { $0.profile?.persistentModelID == profileID }
            } else {
                predicate = #Predicate<RecentlyAddedFood> { $0.profile == nil }
            }
            
            let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
            let entries = try modelContext.fetch(descriptor)
            let recentComplexItems = entries.compactMap { $0.food }
            let recentBaseProducts = recentComplexItems.flatMap { unpackIngredients(from: $0) }
            
            var uniqueRecentFoods: [FoodItem] = []
            var seenIDs = Set<Int>()
            for item in recentBaseProducts {
                if !seenIDs.contains(item.id) {
                    uniqueRecentFoods.append(item)
                    seenIDs.insert(item.id)
                }
            }
            self.recentFoodItems = uniqueRecentFoods
        } catch {
            print("Failed to fetch recent food suggestions: \(error)")
            self.recentFoodItems = []
        }
    }
    
    func processCompletedItems(for list: ShoppingListModel, initiallyBoughtIDs: Set<UUID>) throws {
        guard let modelContext = modelContext else {
            print("ModelContext not available.")
            return
        }

        let newlyBoughtItems = list.items.filter {
            $0.isBought && !initiallyBoughtIDs.contains($0.id) && $0.foodItem != nil
        }
        
        guard !newlyBoughtItems.isEmpty else { return }

        let ownerID = dataOwnerProfileID
        let foodItemIDs = newlyBoughtItems.compactMap { $0.foodItem?.persistentModelID }
        
        let predicate = #Predicate<StorageItem> {
            $0.owner?.persistentModelID == ownerID
        }

        let storageDescriptor = FetchDescriptor<StorageItem>(predicate: predicate)
        
        let allUserStorageItems = try modelContext.fetch(storageDescriptor)
        let existingStorageItems = allUserStorageItems.filter { storageItem in
            guard let foodID = storageItem.food?.persistentModelID else { return false }
            return foodItemIDs.contains(foodID)
        }

        var storageItemsMap: [PersistentIdentifier: StorageItem] = [:]
        for storage in existingStorageItems {
            if let foodID = storage.food?.persistentModelID {
                storageItemsMap[foodID] = storage
            }
        }

        for item in newlyBoughtItems {
            guard let foodItem = item.foodItem else { continue }
            let foodID = foodItem.persistentModelID

            if let storageToUpdate = storageItemsMap[foodID] {
                storageToUpdate.batches.append(Batch(quantity: item.quantity))
            } else {
                let newStorage = StorageItem(owner: dataOwnerProfile, food: foodItem, batches: [Batch(quantity: item.quantity)])
                modelContext.insert(newStorage)
            }
            
            let tx = StorageTransaction(
                date: Date(),
                type: .shoppingAddition,
                quantityChange: item.quantity,
                profile: dataOwnerProfile,
                food: foodItem
            )
            modelContext.insert(tx)
        }
    }
    
    private func saveAndReload(inserting newObject: (any PersistentModel)? = nil) {
        guard let modelContext = modelContext else { return }
        if let newObject = newObject { modelContext.insert(newObject) }
        do {
            try modelContext.save()
            fetchLists()
        } catch {
            print("Failed to save model context: \(error)")
        }
    }
}
