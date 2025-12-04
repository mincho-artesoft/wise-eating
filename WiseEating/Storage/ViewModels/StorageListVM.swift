// StorageListVM.swift (пълна версия с промените)

import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class StorageListVM: ObservableObject {

    @Published var searchText: String = ""
    @Published private(set) var filteredItems: [StorageItem] = []
    
    // --- KEY CHANGE: This now performs a quick DB count instead of checking a large array. ---
    var hasItems: Bool {
        guard let modelContext else { return false }
        let ownerID = dataOwnerProfileID
        let descriptor = FetchDescriptor<StorageItem>(predicate: #Predicate { $0.owner?.persistentModelID == ownerID })
        if let count = try? modelContext.fetchCount(descriptor) {
            return count > 0
        }
        return false
    }

    private let profile: Profile
    private weak var modelContext: ModelContext?
    
    private var dataOwnerProfileID: PersistentIdentifier? {
        profile.hasSeparateStorage ? profile.persistentModelID : nil
    }
    
    private var dataOwnerProfile: Profile? {
        profile.hasSeparateStorage ? profile : nil
    }

    private var cancellables  = Set<AnyCancellable>()
    
    // --- KEY CHANGE: State management for two-phase paginated search ---
    private let pageSize = 30
    private var isLoading = false
    private enum SearchPhase {
        case startsWith
        case contains
        case finished
    }
    private var searchPhase: SearchPhase = .startsWith
    private var startsWithOffset = 0
    private var containsOffset = 0

    init(profile: Profile) {
        self.profile = profile
        
        guard let modelContext = GlobalState.modelContext else {
            fatalError("ModelContext not available. It must be set at app launch.")
        }
        self.modelContext = modelContext
        
        resetAndLoad()
        
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.resetAndLoad()
            }
            .store(in: &cancellables)
    }

    func reloadData() {
        resetAndLoad()
    }
    
    // --- KEY CHANGE: New public function for the View to call on scroll. ---
    func loadNextPage() {
        guard !isLoading, hasItems, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loadPaginated()
    }
    
    // --- KEY CHANGE: New core loading logic ---
    
    /// Resets the search state and triggers the first load.
    private func resetAndLoad() {
        filteredItems = []
        searchPhase = .startsWith
        startsWithOffset = 0
        containsOffset = 0
        isLoading = false
        load()
    }
    
    /// The main router that decides which search strategy to use.
    private func load() {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty {
            loadAllAndSortByDate()
        } else {
            loadPaginated()
        }
    }
    
    /// Replicates the original behavior for when the search bar is empty.
    /// Fetches all items and sorts them by expiration date in memory.
    private func loadAllAndSortByDate() {
        guard let modelContext else { return }
        
        let ownerID = dataOwnerProfileID
        let descriptor = FetchDescriptor<StorageItem>(
            predicate: #Predicate { $0.owner?.persistentModelID == ownerID }
        )
        do {
            var items = try modelContext.fetch(descriptor)
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
    }
    
    /// Performs the paginated, two-phase search when a search query is active.
    private func loadPaginated() {
        guard let modelContext, !isLoading, searchPhase != .finished else { return }
        isLoading = true
        
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSearch = search.lowercased()
        let ownerID = dataOwnerProfileID
        
        var resultsThisLoad: [StorageItem] = []
        
        // --- Phase 1: 'startsWith' Search ---
        if searchPhase == .startsWith {
            let predicate = #Predicate<StorageItem> {
                $0.owner?.persistentModelID == ownerID &&
                $0.food?.nameNormalized.starts(with: normalizedSearch) == true
            }
            var desc = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.food?.name)])
            desc.fetchOffset = startsWithOffset
            desc.fetchLimit = pageSize
            
            do {
                let page = try modelContext.fetch(desc)
                resultsThisLoad.append(contentsOf: page)
                startsWithOffset += page.count
                if page.count < pageSize { searchPhase = .contains }
            } catch {
                print("StorageListVM 'startsWith' error: \(error)"); searchPhase = .finished
            }
        }
        
        // --- Phase 2: 'contains' Search ---
        if searchPhase == .contains && resultsThisLoad.count < pageSize {
            let needed = pageSize - resultsThisLoad.count
            let predicate = #Predicate<StorageItem> {
                $0.owner?.persistentModelID == ownerID &&
                $0.food?.name.localizedStandardContains(search) == true &&
                $0.food?.nameNormalized.starts(with: normalizedSearch) == false
            }
            var desc = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.food?.name)])
            desc.fetchOffset = containsOffset
            desc.fetchLimit = needed
            
            do {
                let page = try modelContext.fetch(desc)
                resultsThisLoad.append(contentsOf: page)
                containsOffset += page.count
                if page.count < needed { searchPhase = .finished }
            } catch {
                print("StorageListVM 'contains' error: \(error)"); searchPhase = .finished
            }
        }
        
        // --- Finalize and Update State ---
        if !resultsThisLoad.isEmpty {
            filteredItems.append(contentsOf: resultsThisLoad)
        }
        isLoading = false
    }
    
    // MARK: - Modified CRUD Operations

    func deleteAllItems() {
        guard let modelContext else { return }
        
        let ownerID = dataOwnerProfileID
        let descriptor = FetchDescriptor<StorageItem>(
            predicate: #Predicate { $0.owner?.persistentModelID == ownerID }
        )
        guard let itemsToDelete = try? modelContext.fetch(descriptor) else { return }

        // 1) Събираме уникалните храни и чистим историята им
        let uniqueFoods = Set(itemsToDelete.compactMap { $0.food })
        for food in uniqueFoods {
            cleanupPantryHistory(for: food)
        }

        // 2) (по желание) – ако НЕ искаш нови fullDeletion транзакции, махни този блок
        /*
        for item in itemsToDelete {
            if item.totalQuantity > 0 {
                let transaction = StorageTransaction(
                    date: Date(),
                    type: .fullDeletion,
                    quantityChange: -item.totalQuantity,
                    profile: dataOwnerProfile,
                    food: item.food
                )
                modelContext.insert(transaction)
            }
            modelContext.delete(item)
        }
        */

        // 2a) Ако не искаш никакви допълнителни транзакции – просто трием:
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
            let food = itemToDelete.food  // запазваме референцията към храната

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
            modelContext.delete(itemToDelete)
            filteredItems.remove(at: index)
            saveContext()
        }
    }

    
    // No changes needed for consume, consolidation, or saveContext
    
    func consume(quantity: Double, from item: StorageItem) {
        guard let modelContext, quantity > 0 else { return }
        var remaining = quantity
        
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
        
        let transaction = StorageTransaction(
            date: Date(), type: .consumption, quantityChange: -quantity,
            profile: dataOwnerProfile, food: item.food
        )
        modelContext.insert(transaction)
        
        objectWillChange.send()
        saveContext()
    }
    
    // ... (rest of the functions: triggerConsolidationIfNeeded, consolidateTransactions, encodedString, saveContext)
    // --- NO CHANGES ARE NEEDED FOR THE FUNCTIONS BELOW THIS LINE ---
    
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
                
                for j in (i + 1)..<group.count {
                    let timeDifference = group[j].date.timeIntervalSince(consolidatedEndDate)
                    
                    if timeDifference <= 60 { // 1-минутен прозорец
                        consolidatedQuantity += group[j].quantityChange
                        consolidatedEndDate = group[j].date
                        lastIndexInSequence = j
                    } else {
                        break
                    }
                }
                
                if lastIndexInSequence > i {
                    let newConsolidatedTransaction = StorageTransaction(
                        date: group[i].date, type: group[i].type, quantityChange: consolidatedQuantity,
                        profile: dataOwnerProfile, food: group[i].food
                    )
                    modelContext.insert(newConsolidatedTransaction)
                    
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
        let ownerID = dataOwnerProfileID  // текущият профил / глобален storage

        do {
            // 1) MealLogStorageLink за тази храна и този профил
            let linksDescriptor = FetchDescriptor<MealLogStorageLink>(
                predicate: #Predicate {
                    $0.food?.persistentModelID == foodID &&
                    $0.profile?.persistentModelID == ownerID
                }
            )
            let links = try modelContext.fetch(linksDescriptor)
            links.forEach { modelContext.delete($0) }

            // 2) StorageTransaction за тази храна и този профил
            let transactionsDescriptor = FetchDescriptor<StorageTransaction>(
                predicate: #Predicate {
                    $0.food?.persistentModelID == foodID &&
                    $0.profile?.persistentModelID == ownerID
                }
            )
            let transactions = try modelContext.fetch(transactionsDescriptor)
            transactions.forEach { modelContext.delete($0) }

            print("🧹 Removed \(links.count) MealLogStorageLink and \(transactions.count) StorageTransaction for food '\(food.name)'")

        } catch {
            print("❌ Failed to cleanup pantry history for food '\(food.name)': \(error)")
        }
    }

}
