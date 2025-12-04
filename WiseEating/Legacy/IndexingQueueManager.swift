//import Foundation
//import SwiftData
//
//@MainActor
//class IndexingQueueManager {
//    static let shared = IndexingQueueManager()
//    private var modelContainer: ModelContainer?
//    private var debounceTimer: Timer?
//
//    private init() {}
//
//    func setup(container: ModelContainer) {
//        self.modelContainer = container
//    }
//
//    /// Persistently queues a FoodItem for re-indexing.
//    func queueForIndexing(foodID: Int) {
//        guard let modelContext = modelContainer?.mainContext else { return }
//
//        // Prevent adding a duplicate job if one already exists for this foodID.
//        let descriptor = FetchDescriptor<IndexingJob>(predicate: #Predicate { $0.foodID == foodID })
//        if let existingCount = try? modelContext.fetchCount(descriptor), existingCount > 0 {
//            print("📦 [IndexingQueue] Job for foodID \(foodID) is already in the queue.")
//            return
//        }
//        
//        let newJob = IndexingJob(foodID: foodID)
//        modelContext.insert(newJob)
//        
//        // Save the job immediately to ensure it's persisted.
//        try? modelContext.save()
//        print("📦 [IndexingQueue] Queued job for foodID \(foodID).")
//
//        // Schedule the queue to be processed after a short delay.
//        debounceTimer?.invalidate()
//        debounceTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
//            self?.processQueue()
//        }
//    }
//
//    /// Fetches all pending jobs from SwiftData and processes them in the background.
//    func processQueue() {
//        guard let container = modelContainer else { return }
//        
//        Task { @MainActor in
//            let context = ModelContext(container)
//            let jobsToProcess = (try? context.fetch(FetchDescriptor<IndexingJob>())) ?? []
//            
//            guard !jobsToProcess.isEmpty else {
//                print("✅ [IndexingQueue] Queue is empty. Nothing to process.")
//                return
//            }
//
//            print("🚀 [IndexingQueue] Processing \(jobsToProcess.count) items in the background.")
//
//            // Pass only the Sendable container and IDs to the background task.
//            let foodIDs = jobsToProcess.map { $0.foodID }
//
//            Task.detached(priority: .background) {
//                let bgContext = ModelContext(container)
//                
//                for foodID in foodIDs {
//                    // Fetch the full FoodItem on the background thread.
//                    let foodDescriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == foodID })
//                    if let foodItem = try? bgContext.fetch(foodDescriptor).first {
//                        // Допълнителна защита
//                        guard foodItem.modelContext != nil else { continue }
//                        await self.updateIndexesInBackground(for: foodItem, context: bgContext)
//                    }
//
//                    // After processing, delete the job from the queue.
//                    let jobDescriptor = FetchDescriptor<IndexingJob>(predicate: #Predicate { $0.foodID == foodID })
//                    if let job = try? bgContext.fetch(jobDescriptor).first {
//                        bgContext.delete(job)
//                    }
//                }
//                
//                // Save the changes (deletions of jobs and updates to indexes).
//                if bgContext.hasChanges {
//                    do {
//                        try bgContext.save()
//                        await MainActor.run {
//                            print("✅ [IndexingQueue] Background indexing complete and saved.")
//                        }
//                    } catch {
//                        await MainActor.run {
//                            print("❌ [IndexingQueue] Failed to save background context: \(error)")
//                        }
//                    }
//                }
//            }
//        }
//    }
//
//    // This function is now non-isolated and safe to call from any thread.
//    nonisolated private func updateIndexesInBackground(for foodItem: FoodItem, context: ModelContext) async {
//        let allVitamins = (try? context.fetch(FetchDescriptor<Vitamin>())) ?? []
//        let allMinerals = (try? context.fetch(FetchDescriptor<Mineral>())) ?? []
//        let allNutrientIDs = allVitamins.map { "vit_\($0.id)" } + allMinerals.map { "min_\($0.id)" }
//        
//        let allIndexes = (try? context.fetch(FetchDescriptor<NutrientIndex>())) ?? []
//        let indexMap = Dictionary(uniqueKeysWithValues: allIndexes.map { ($0.nutrientID, $0) })
//
//        for nutrientID in allNutrientIDs {
//            let index = indexMap[nutrientID] ?? NutrientIndex(nutrientID: nutrientID, rankedFoods: [])
//            if index.modelContext == nil { context.insert(index) }
//
//            index.rankedFoods.removeAll { $0.foodID == foodItem.id }
//
//            guard let (value, unit) = foodItem.value(of: nutrientID), value > 0 else { continue }
//            let referenceWeight = foodItem.referenceWeightG
//            guard referenceWeight > 0 else { continue }
//
//            let valuePer100g = (value / referenceWeight) * 100.0
//            let valueInMg = Self.toMg(value: valuePer100g, unit: unit)
//            guard valueInMg > 0.00001 else { continue }
//            
//            let newRank = FoodRank(foodID: foodItem.id, value: valueInMg, nameKey: foodItem.nameNormalized)
//            
//            if let insertionIndex = index.rankedFoods.firstIndex(where: { $0.value < newRank.value }) {
//                index.rankedFoods.insert(newRank, at: insertionIndex)
//            } else {
//                index.rankedFoods.append(newRank)
//            }
//        }
//
//        let nameIndexDescriptor = FetchDescriptor<NameIndex>()
//        if let nameIndex = (try? context.fetch(nameIndexDescriptor))?.first {
//            nameIndex.entries.removeAll { $0.foodID == foodItem.id }
//            nameIndex.entries.append(NameEntry(foodID: foodItem.id, nameKey: foodItem.nameNormalized))
//        }
//    }
//
//    nonisolated private static func toMg(value: Double, unit: String) -> Double {
//        switch unit.lowercased() {
//        case "g": return value * 1_000
//        case "µg", "mcg": return value * 0.001
//        default: return value
//        }
//    }
//}
