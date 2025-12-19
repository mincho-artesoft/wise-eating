import SwiftData
import Foundation
import UIKit

@MainActor
enum SeedManager {

    // MARK: – Public entry point
    static func seedIfNeeded(container: ModelContainer) async {
        print("🚀 Starting database seed process if needed...")
        let ctx = GlobalState.modelContext!
        ctx.autosaveEnabled = false

        // 1. Извикване на методите за зареждане
        await seedBarcodesIfNeeded(context: ctx)
        await seedReferenceVitaminsIfNeeded(context: ctx)
        await seedReferenceMineralsIfNeeded(context: ctx)
        await seedReferenceDietsIfNeeded(context: ctx)
        await seedFoodsIfNeeded(context: ctx)
        await seedExercisesIfNeeded(context: ctx)
        await seedTrainingPlansIfNeeded(context: ctx)
        // 2. Финален запис на всички данни
        do {
            if ctx.hasChanges {
                try ctx.save()
                print("💾 Final save of all seeded data successful.")
            }
            
            // 3. ⚠️ ГЕНЕРИРАНЕ НА ИНДЕКСА
            // След като всичко е записано, форсираме изграждането на search cache.
            // Това ще създаде SearchIndexCache в базата.
            try SearchIndexStore.shared.rebuildIndexIfNeeded(context: ctx)
            
        } catch {
            print("❌ Final save or indexing after seeding failed: \(error)")
        }

        // ✅ Върни autosave за нормалната работа на UI след сеенето
        ctx.autosaveEnabled = true

        print("✅ Seeding process completed.")
    }

    // MARK: - Barcodes
    private static func seedBarcodesIfNeeded(context ctx: ModelContext) async {
        print("-> Checking for Barcodes (Vocabulary & Buckets)...")
        guard databaseIsEmpty(entity: ProductBucket.self, context: ctx),
              databaseIsEmpty(entity: VocabularyEntry.self, context: ctx) else {
            print("   Barcodes already seeded, skipping.")
            return
        }

        print("   Seeding Vocabulary from vocabulary.json...")
        guard let vocabURL = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
            assertionFailure("vocabulary.json not found"); return
        }
        
        do {
            let vocabData = try Data(contentsOf: vocabURL)
            let decodedVocab = try JSONDecoder().decode([String: String].self, from: vocabData)
            for (idString, word) in decodedVocab {
                if let id = Int(idString) {
                    let entry = VocabularyEntry(id: id, word: word)
                    ctx.insert(entry)
                }
            }
            print("   ✅ Seeded vocabulary entries.")
        } catch {
            print("   ❌ Vocabulary seeding failed: \(error)")
            return
        }

        print("   Seeding Product Buckets from product_buckets.json...")
        guard let bucketsURL = Bundle.main.url(forResource: "product_buckets", withExtension: "json") else {
            assertionFailure("product_buckets.json not found"); return
        }

        do {
            let bucketsData = try Data(contentsOf: bucketsURL)
            let decodedBuckets = try JSONDecoder().decode([String: String].self, from: bucketsData)
            
            for (key, data) in decodedBuckets {
                if let keyAsInt = Int64(key) {
                    let bucket = ProductBucket(bucketKey: keyAsInt, compressedData: data)
                    ctx.insert(bucket)
                }
            }
            print("   ✅ Seeded \(decodedBuckets.count) product buckets.")
        } catch {
            print("   ❌ Product bucket seeding failed: \(error)")
        }
    }


    // MARK: – Foods
    private static func seedFoodsIfNeeded(context ctx: ModelContext) async {
        print("-> Checking for Foods...")
        guard databaseIsEmpty(entity: FoodItem.self, context: ctx) else {
            print("   Foods already seeded, skipping.")
            return
        }

        print("   Seeding Foods from foods.json...")
        guard let url = Bundle.main.url(forResource: "foods", withExtension: "json") else {
            assertionFailure("foods.json not found"); return
        }

        do {
            let persistedDiets = try ctx.fetch(FetchDescriptor<Diet>())
            let dietMap: [String: Diet] = Dictionary(
                uniqueKeysWithValues: persistedDiets.map {
                    ($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0)
                }
            )

            let raw = try Data(contentsOf: url)
            let dtos = try JSONDecoder().decode([FoodItemDTO].self, from: raw)

            var items: [FoodItem] = []
            items.reserveCapacity(dtos.count)

            for dto in dtos {
                let model = dto.model(dietMap: dietMap)
                model.isUserAdded = false
                model.isRecipe = false
                items.append(model)
            }

            try ctx.transaction {
                for item in items { ctx.insert(item) }
            }
            print("   ✅ Seeded \(items.count) foods with their diet relationships.")
        } catch {
            print("   ❌ Food seeding failed: \(error)")
        }
    }
    
    // MARK: – Exercises
    private static func seedExercisesIfNeeded(context ctx: ModelContext) async {
        print("-> Checking for Exercises...")
        guard databaseIsEmpty(entity: ExerciseItem.self, context: ctx) else {
            print("   Exercises already seeded, skipping.")
            return
        }

        print("   Seeding Exercises from sports.json...")
        guard let url = Bundle.main.url(forResource: "sports", withExtension: "json") else {
            assertionFailure("sports.json not found"); return
        }

        do {
            let raw = try Data(contentsOf: url)
            let dtos = try JSONDecoder().decode([ExerciseItemDTO].self, from: raw)

            try ctx.transaction {
                for dto in dtos {
                    let exercise = dto.model()
                    ctx.insert(exercise)
                }
            }
            print("   ✅ Seeded \(dtos.count) exercises from sports.json")
        } catch {
            print("   ❌ Exercise seeding failed: \(error)")
        }
    }

    // MARK: – Reference Vitamins
    private static func seedReferenceVitaminsIfNeeded(context ctx: ModelContext) async {
        guard databaseIsEmpty(entity: Vitamin.self, context: ctx) else { return }
        do {
            try ctx.transaction {
                for vitamin in defaultVitaminsList { ctx.insert(vitamin) }
            }
            print("   ✅ Seeded \(defaultVitaminsList.count) vitamins.")
        } catch {
            print("   ❌ Vitamin seeding failed: \(error)")
        }
    }

    // MARK: – Reference Minerals
    private static func seedReferenceMineralsIfNeeded(context ctx: ModelContext) async {
        guard databaseIsEmpty(entity: Mineral.self, context: ctx) else { return }
        do {
            try ctx.transaction {
                for mineral in defaultMineralsList { ctx.insert(mineral) }
            }
            print("   ✅ Seeded \(defaultMineralsList.count) minerals.")
        } catch {
            print("   ❌ Mineral seeding failed: \(error)")
        }
    }

    // MARK: – Reference Diets
    private static func seedReferenceDietsIfNeeded(context ctx: ModelContext) async {
        guard databaseIsEmpty(entity: Diet.self, context: ctx) else { return }
        do {
            try ctx.transaction {
                for diet in defaultDietsList { ctx.insert(diet) }
            }
            print("   ✅ Seeded \(defaultDietsList.count) diets.")
        } catch {
            print("   ❌ Diet seeding failed: \(error)")
        }
    }

    // В SeedManager.swift
    private static func seedTrainingPlansIfNeeded(context ctx: ModelContext) async {
        // Проверка дали има шаблони
        let descriptor = FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.profile == nil })
        if (try? ctx.fetchCount(descriptor)) ?? 0 > 0 {
            return // Вече са импортирани
        }
        
        print("   Seeding Training Plans from workouts.json...")
        guard let url = Bundle.main.url(forResource: "workouts", withExtension: "json") else {
            print("   ⚠️ workouts.json not found.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            try await TrainingPlanImporter.shared.importTemplates(jsonData: data, context: ctx)
        } catch {
            print("   ❌ Failed to import training plans: \(error)")
        }
    }
    

    // MARK: – Helpers
    private static func databaseIsEmpty<T: PersistentModel>(
        entity: T.Type,
        context ctx: ModelContext
    ) -> Bool {
        ((try? ctx.fetchCount(FetchDescriptor<T>())) ?? 0) == 0
    }

    private static func toMg(value: Double, unit: String) -> Double {
        switch unit.lowercased() {
        case "g":            return value * 1_000
        case "µg", "mcg":    return value * 0.001
        default:             return value
        }
    }
}
