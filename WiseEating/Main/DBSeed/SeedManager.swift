// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Main/DBSeed/SeedManager.swift ====
import SwiftData
import Foundation
import UIKit

@MainActor
enum SeedManager {

    // MARK: – Public entry point
    static func seedIfNeeded(container: ModelContainer) async {
        print("🚀 Starting database seed check...")
        let ctx = GlobalState.modelContext!
        
        // 1. Проверка: Имаме ли успешно заредена Read-Only (Reference) база?
        // Името "Reference" идва от DatabaseSetup.swift -> ModelConfiguration("Reference", ...)
        let hasReferenceStore = container.configurations.contains { $0.name == "Reference" }
        
        if hasReferenceStore {
            print("✨ SeedManager: 'Reference' store detected. Skipping data injection to avoid duplication.")
            
            // В този сценарий данните (Храни, Витамини и т.н.) идват от read-only файла.
            // НЕ ги вкарваме (insert) отново, за да не напълним default.store с дубликати.
            
            // НО! Трябва да се уверим, че индексът за търсене е наличен.
            // Той се записва в потребителската (writable) база.
            await buildIndexOnly(context: ctx)
            return
        }

        // ========================================================================
        // FALLBACK / LEGACY MODE
        // Ако сме тук, значи или сме нов потребител без preseed, или preseed-ът е гръмнал
        // и сме се върнали към старата логика (само default.store).
        // Трябва да налеем данните ръчно, както преди.
        // ========================================================================
        
        print("⚠️ SeedManager: No reference store found (Legacy/Fallback mode). Checking if seeding is needed...")
        
        ctx.autosaveEnabled = false

        // 1. Извикване на методите за зареждане
        await seedBarcodesIfNeeded(context: ctx)
        await seedReferenceVitaminsIfNeeded(context: ctx)
        await seedReferenceMineralsIfNeeded(context: ctx)
        await seedReferenceDietsIfNeeded(context: ctx)
        await seedFoodsIfNeeded(context: ctx)
        await seedExercisesIfNeeded(context: ctx)

        // 2. Финален запис на всички данни
        do {
            if ctx.hasChanges {
                try ctx.save()
                print("💾 Final save of all seeded data successful.")
            }
            
            // 3. Генериране на индекса
            try SearchIndexStore.shared.rebuildIndexIfNeeded(context: ctx)
            
        } catch {
            print("❌ Final save or indexing after seeding failed: \(error)")
        }

        ctx.autosaveEnabled = true
        print("✅ Seeding process completed (Legacy Mode).")
    }
    
    // MARK: - Helper for Reference Mode
    private static func buildIndexOnly(context ctx: ModelContext) async {
        print("🔎 SeedManager: Building/Verifying Search Index from Reference store...")
        do {
            // Това ще прочете данните от Reference store-а (чрез контекста)
            // и ще запише индекса в Writable store-а (където е SearchIndexCache).
            try SearchIndexStore.shared.rebuildIndexIfNeeded(context: ctx)
            print("✅ Search Index ready.")
        } catch {
            print("❌ Failed to build search index in Reference mode: \(error)")
        }
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
            // Не спираме с fatal error, за да не крашва в production, ако файлът липсва случайно
            print("⚠️ vocabulary.json not found"); return
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
            print("⚠️ product_buckets.json not found"); return
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
            print("⚠️ foods.json not found"); return
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
            print("⚠️ sports.json not found"); return
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
