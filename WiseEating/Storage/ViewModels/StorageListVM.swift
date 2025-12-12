import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class StorageListVM: ObservableObject {

    // MARK: - Inputs & Outputs
    @Published var searchText: String = ""
    @Published private(set) var filteredItems: [StorageItem] = []
    
    /// Quick check if the database has any items for this profile (to show/hide empty states).
    var hasItems: Bool {
        guard let modelContext = GlobalState.modelContext else { return false }
        let ownerID = dataOwnerProfileID
        let descriptor = FetchDescriptor<StorageItem>(predicate: #Predicate { $0.owner?.persistentModelID == ownerID })
        if let count = try? modelContext.fetchCount(descriptor) {
            return count > 0
        }
        return false
    }

    // MARK: - Private State
    private let profile: Profile
    private weak var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    // Smart Search Engine
    private var searchEngine: SmartFoodSearch3?
    private var currentSearchTask: Task<Void, Never>?
    
    // Loading State
    @Published private(set) var isLoading = false
    
    // Derived Profile Properties
    private var dataOwnerProfileID: PersistentIdentifier? {
        profile.hasSeparateStorage ? profile.persistentModelID : nil
    }
    
    private var dataOwnerProfile: Profile? {
        profile.hasSeparateStorage ? profile : nil
    }

    // MARK: - Init
    init(profile: Profile) {
        self.profile = profile
        
        // 1. Get Context from GlobalState
        guard let modelContext = GlobalState.modelContext else {
            fatalError("ModelContext not available. It must be set at app launch.")
        }
        self.modelContext = modelContext
        
        // 2. Initialize Smart Search Engine
        // FIX: modelContext.container is NOT optional, so we access it directly.
        let container = modelContext.container
        self.searchEngine = SmartFoodSearch3(container: container)
        
        // Pre-load data in background
        Task {
            await self.searchEngine?.loadData()
        }
        
        // Initial Load
        loadAllAndSortByDate()
        
        // Search Listener
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadData()
            }
            .store(in: &cancellables)
    }

    func reloadData() {
        // Cancel previous search task
        currentSearchTask?.cancel()
        currentSearchTask = nil
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if query.isEmpty {
            loadAllAndSortByDate()
        } else {
            performSmartSearch(query: query)
        }
    }
    
    func loadNextPage() {
        // Pagination logic is handled by the search engine batching or
        // full-load for pantry items. No action needed here for now.
    }
    
    // MARK: - Loading Logic
    
    /// Default behavior: Fetch all items owned by profile, sorted by Expiration Date.
    private func loadAllAndSortByDate() {
        guard let modelContext else { return }
        isLoading = true
        
        let ownerID = dataOwnerProfileID
        let descriptor = FetchDescriptor<StorageItem>(
            predicate: #Predicate { $0.owner?.persistentModelID == ownerID }
        )
        
        do {
            var items = try modelContext.fetch(descriptor)
            
            // In-memory sort: Earliest expiration first. If equal, alphabetical by food name.
            items.sort { lhs, rhs in
                let lhsDate = lhs.firstExpirationDate ?? .distantFuture
                let rhsDate = rhs.firstExpirationDate ?? .distantFuture
                if lhsDate == rhsDate {
                    return (lhs.food?.name ?? "") < (rhs.food?.name ?? "")
                }
                return lhsDate < rhsDate
            }
            
            self.filteredItems = items
        } catch {
            print("Failed to fetch and sort all storage items: \(error)")
        }
        isLoading = false
    }
    
    /// Smart Search behavior: Delegate to Engine, find matching Foods, then find StorageItems.
    private func performSmartSearch(query: String) {
        guard let searchEngine, let modelContext else {
            isLoading = false
            return
        }
        
        isLoading = true
        let ownerID = dataOwnerProfileID
        
        currentSearchTask = Task {
            // 1. Get ranked FoodItems from the engine
            let matchedFoods = await searchEngine.searchResults(
                query: query,
                limit: 200
            )
            
            if Task.isCancelled { return }
            
            let matchedFoodIDs = Set(matchedFoods.map { $0.persistentModelID })
            
            if matchedFoodIDs.isEmpty {
                await MainActor.run {
                    self.filteredItems = []
                    self.isLoading = false
                }
                return
            }
            
            // 2. Fetch StorageItems and filter
            do {
                let descriptor = FetchDescriptor<StorageItem>(
                    predicate: #Predicate { $0.owner?.persistentModelID == ownerID }
                )
                let userPantryItems = try modelContext.fetch(descriptor)
                
                // 3. Filter: Keep only items whose food matches the search results
                let filteredPantry = userPantryItems.filter { item in
                    guard let foodID = item.food?.persistentModelID else { return false }
                    return matchedFoodIDs.contains(foodID)
                }
                
                // 4. Re-rank: Sort the storage items to match the order returned by the Search Engine
                let rankLookup = matchedFoods.enumerated().reduce(into: [PersistentIdentifier: Int]()) { dict, pair in
                    dict[pair.element.persistentModelID] = pair.offset
                }
                
                let sortedPantry = filteredPantry.sorted { lhs, rhs in
                    // FIX: Safely unwrap optional PersistentIdentifier.
                    // If food is nil, we treat it as max rank (end of list).
                    let id1 = lhs.food?.persistentModelID
                    let id2 = rhs.food?.persistentModelID
                    
                    let index1 = (id1 != nil) ? (rankLookup[id1!] ?? Int.max) : Int.max
                    let index2 = (id2 != nil) ? (rankLookup[id2!] ?? Int.max) : Int.max
                    
                    return index1 < index2
                }
                
                await MainActor.run {
                    self.filteredItems = sortedPantry
                    self.isLoading = false
                }
                
            } catch {
                print("Smart search fetch failed: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }

    // MARK: - CRUD Operations

    func deleteAllItems() {
        guard let modelContext else { return }
        
        let ownerID = dataOwnerProfileID
        let descriptor = FetchDescriptor<StorageItem>(
            predicate: #Predicate { $0.owner?.persistentModelID == ownerID }
        )
        guard let itemsToDelete = try? modelContext.fetch(descriptor) else { return }

        // 1) Cleanup history for unique foods
        let uniqueFoods = Set(itemsToDelete.compactMap { $0.food })
        for food in uniqueFoods {
            cleanupPantryHistory(for: food)
        }

        // 2) Delete items
        for item in itemsToDelete {
            modelContext.delete(item)
        }

        filteredItems.removeAll()
        saveContext()
    }
    
    func deleteStorageItem(with id: StorageItem.ID) {
        guard let modelContext else { return }
        
        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            let itemToDelete = filteredItems[index]
            let food = itemToDelete.food
            // 1) Чистим всички MealLogStorageLink и StorageTransaction за тази храна + профил

            cleanupPantryHistory(for: food)

            // 2) (По желание) ако въпреки това искаш финална транзакция "fullDeletion", я сложи ТУК
            //    ако не искаш НИКАКВИ StorageTransaction за тази храна, просто махни този блок.
            /*
            if itemToDelete.totalQuantity > 0 {
                let transaction = StorageTransaction(
                    date: Date(),
                    type: .fullDeletion,
                    quantityChange: -itemToDelete.totalQuantity,
                    profile: dataOwnerProfile,
                    food: food
                )
                modelContext.insert(transaction)
            }
            */

            // 3) Трием самия StorageItem

            
            // 2) Delete item
            modelContext.delete(itemToDelete)
            filteredItems.remove(at: index)
            saveContext()
        }
    }
    
    func consume(quantity: Double, from item: StorageItem) {
        guard let modelContext, quantity > 0 else { return }
        var remaining = quantity
        
        // Sort batches by date to consume oldest first (FIFO)
        let sortedBatches = item.batches.sorted {
            ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture)
        }
        
        for batch in sortedBatches {
            guard remaining > 0 else { break }
            
            if batch.quantity > remaining {
                batch.quantity -= remaining
                remaining = 0
            } else {
                remaining -= batch.quantity
                item.batches.removeAll { $0.id == batch.id }
                modelContext.delete(batch)
            }
        }
        
        // Log transaction
        let transaction = StorageTransaction(
            date: Date(), type: .consumption, quantityChange: -quantity,
            profile: dataOwnerProfile, food: item.food
        )
        modelContext.insert(transaction)
        
        objectWillChange.send()
        saveContext()
    }
    
    // MARK: - Transaction Consolidation Logic
    
    func triggerConsolidationIfNeeded() {
        guard let modelContext else { return }
        
        let ownerIDString = profile.hasSeparateStorage ? encodedString(for: profile.persistentModelID) : "global_storage"
        let userDefaultsKey = "lastTransactionConsolidationDate_\(ownerIDString)"
        
        let lastConsolidationDate = UserDefaults.standard.object(forKey: userDefaultsKey) as? Date
        
        let ownerID = dataOwnerProfileID
        let predicate: Predicate<StorageTransaction>
        if let lastDate = lastConsolidationDate {
            predicate = #Predicate<StorageTransaction> {
                $0.profile?.persistentModelID == ownerID && $0.date > lastDate
            }
        } else {
            predicate = #Predicate<StorageTransaction> {
                $0.profile?.persistentModelID == ownerID
            }
        }
        
        let descriptor = FetchDescriptor(predicate: predicate)
        
        do {
            let newTransactionsCount = try modelContext.fetchCount(descriptor)
            
            if newTransactionsCount > 0 {
                Task(priority: .background) {
                    await consolidateTransactions()
                    UserDefaults.standard.set(Date(), forKey: userDefaultsKey)
                }
            }
        } catch {
            print("Failed to check for new transactions: \(error)")
        }
    }
    
    private func consolidateTransactions() async {
        guard let modelContext else { return }

        let ownerID = dataOwnerProfileID
        let descriptor = FetchDescriptor<StorageTransaction>(
            predicate: #Predicate { $0.profile?.persistentModelID == ownerID },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        
        guard let allTransactions = try? modelContext.fetch(descriptor), !allTransactions.isEmpty else {
            return
        }
        
        // Group by Food + Transaction Type
        let groupedByFoodAndType = Dictionary(grouping: allTransactions) {
            "\(encodedString(for: $0.food?.persistentModelID))_\($0.type.rawValue)"
        }
        
        for (_, group) in groupedByFoodAndType {
            guard group.count > 1 else { continue }
            
            var transactionsToDelete: [StorageTransaction] = []
            var i = 0
            
            while i < group.count {
                var consolidatedQuantity = group[i].quantityChange
                var consolidatedEndDate = group[i].date
                var lastIndexInSequence = i
                
                // Merge transactions occurring within 60 seconds
                for j in (i + 1)..<group.count {
                    let timeDifference = group[j].date.timeIntervalSince(consolidatedEndDate)
                    
                    if timeDifference <= 60 {
                        consolidatedQuantity += group[j].quantityChange
                        consolidatedEndDate = group[j].date
                        lastIndexInSequence = j
                    } else {
                        break
                    }
                }
                
                if lastIndexInSequence > i {
                    // Create merged transaction
                    let newConsolidatedTransaction = StorageTransaction(
                        date: group[i].date, type: group[i].type, quantityChange: consolidatedQuantity,
                        profile: dataOwnerProfile, food: group[i].food
                    )
                    modelContext.insert(newConsolidatedTransaction)
                    
                    // Mark old ones for deletion
                    for k in i...lastIndexInSequence {
                        transactionsToDelete.append(group[k])
                    }
                }
                
                i = lastIndexInSequence + 1
            }
            
            transactionsToDelete.forEach { modelContext.delete($0) }
        }
        
        do {
            try modelContext.save()
            print("Transactions consolidated successfully.")
        } catch {
            print("Failed to save consolidated transactions: \(error)")
        }
    }

    private func encodedString(for id: PersistentIdentifier?) -> String {
        guard let id = id else { return "nil" }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(id) else { return "error" }
        return data.base64EncodedString()
    }
    
    private func saveContext() {
        guard let modelContext else { return }
        do { try modelContext.save() }
        catch { print("Failed to save context: \(error)") }
    }
    
    // MARK: - History cleanup for a given food

    private func cleanupPantryHistory(for food: FoodItem?) {
        guard let modelContext, let food else { return }

        let foodID  = food.persistentModelID
        let ownerID = dataOwnerProfileID

        do {
            // 1) MealLogStorageLink
            let linksDescriptor = FetchDescriptor<MealLogStorageLink>(
                predicate: #Predicate {
                    $0.food?.persistentModelID == foodID &&
                    $0.profile?.persistentModelID == ownerID
                }
            )
            let links = try modelContext.fetch(linksDescriptor)
            links.forEach { modelContext.delete($0) }

            // 2) StorageTransaction
            let transactionsDescriptor = FetchDescriptor<StorageTransaction>(
                predicate: #Predicate {
                    $0.food?.persistentModelID == foodID &&
                    $0.profile?.persistentModelID == ownerID
                }
            )
            let transactions = try modelContext.fetch(transactionsDescriptor)
            transactions.forEach { modelContext.delete($0) }

        } catch {
            print("❌ Failed to cleanup pantry history for food '\(food.name)': \(error)")
        }
    }
}
