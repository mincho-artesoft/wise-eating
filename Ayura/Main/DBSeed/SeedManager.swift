import SwiftData
import Foundation

@MainActor
enum SeedManager {

    // MARK: – Public entry point
    static func seedIfNeeded(container: ModelContainer) async {
        AyuraLaunchProbe.event("seed-checks-begin")
        print("🚀 Starting database seed process if needed...")
        let ctx = GlobalState.modelContext!
        ctx.autosaveEnabled = false

        migrateExerciseDurationsIfNeeded(context: ctx)
        removeBundledExercisesIfNeeded(context: ctx)
        seedYogaIfNeeded(context: ctx)
        await seedBarcodesIfNeeded(context: ctx)
        await seedReferenceVitaminsIfNeeded(context: ctx)
        await seedReferenceMineralsIfNeeded(context: ctx)
        await seedFoodsIfNeeded(context: ctx)
        AyuraLaunchProbe.event("ayurveda-check-begin")
        let ayurvedaChangedSearchableFoods = await seedAyurvedaIfNeeded(context: ctx)
        AyuraLaunchProbe.event("ayurveda-check-end")

        do {
            if ctx.hasChanges {
                try ctx.save()
                print("💾 Final save of all seeded data successful.")
            }

            let projectedRecipeCount = try RecipeNutritionProjection.shared.load(context: ctx)
            print("   ✅ Loaded nutrition display data for \(projectedRecipeCount) recipes.")

            try SearchIndexStore.shared.rebuildIndexIfNeeded(
                context: ctx,
                force: ayurvedaChangedSearchableFoods
            )

        } catch {
            print("❌ Final save or indexing after seeding failed: \(error)")
        }

        ctx.autosaveEnabled = true
        print("✅ Seeding process completed.")
        AyuraLaunchProbe.event("seed-checks-end")
    }

    // MARK: – Yoga
    private static func migrateExerciseDurationsIfNeeded(context ctx: ModelContext) {
        do {
            try ExerciseDurationUnitMigrator.migrateIfNeeded(context: ctx)
        } catch {
            ctx.rollback()
            print("   ❌ Exercise duration unit migration failed: \(error)")
            assertionFailure("Exercise duration unit migration failed: \(error)")
        }
    }

    private static func seedYogaIfNeeded(context ctx: ModelContext) {
        print("-> Checking for Yoga data...")
        let versionKey = "yogaSeedVersion"
        do {
            let bundleVersion = try YogaSeeder.bundleSeedVersion()
            let installedVersion = UserDefaults.standard.integer(forKey: versionKey)
            let catalogueIsInstalled = try YogaSeeder.isInstalled(context: ctx)
            if installedVersion >= bundleVersion, catalogueIsInstalled {
                print("   Yoga seed version already applied, skipping.")
                return
            }
            if installedVersion == 0, catalogueIsInstalled {
                UserDefaults.standard.set(bundleVersion, forKey: versionKey)
                print(
                    "   ✅ Yoga v\(bundleVersion) preseed stamp verified; "
                        + "no inserts or updates."
                )
                return
            }

            let result = try YogaSeeder.run(context: ctx)
            UserDefaults.standard.set(bundleVersion, forKey: versionKey)
            print(
                "   Yoga seed v\(bundleVersion) installed: "
                    + "\(result.asanaCount) asanas, "
                    + "\(result.sequenceCount) sequences."
            )
        } catch {
            ctx.rollback()
            print("   ❌ Yoga seeding failed: \(error)")
            assertionFailure("Yoga seed gate failed: \(error)")
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
            assertionFailure("vocabulary.json not found"); return
        }

        do {
            let vocabData = try Data(contentsOf: vocabURL)
            let decodedVocab = try JSONDecoder().decode([VocabularySeedDTO].self, from: vocabData)
            for row in decodedVocab {
                let entry = VocabularyEntry(
                    id: row.id,
                    tokenIndex: row.tokenIndex,
                    word: row.word
                )
                ctx.insert(entry)
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
            let decodedBuckets = try JSONDecoder().decode([ProductBucketSeedDTO].self, from: bucketsData)

            for row in decodedBuckets {
                let bucket = ProductBucket(
                    id: row.id,
                    bucketKey: row.bucketKey,
                    compressedData: row.compressedData
                )
                ctx.insert(bucket)
            }
            print("   ✅ Seeded \(decodedBuckets.count) product buckets.")
        } catch {
            print("   ❌ Product bucket seeding failed: \(error)")
        }
    }

    // MARK: – Ayurveda
    private static func seedAyurvedaIfNeeded(context ctx: ModelContext) async -> Bool {
        print("-> Checking for Ayurveda data...")
        do {
            let seedVersion = try AyurvedaSeeder.bundleSeedVersion()
            guard UserDefaults.standard.integer(forKey: "ayurvedaSeedVersion") < seedVersion else {
                print("   Ayurveda seed version already applied, skipping.")
                return false
            }
            let result = try AyurvedaSeeder.run(context: ctx)
            if ctx.hasChanges {
                try ctx.save()
            }
            UserDefaults.standard.set(seedVersion, forKey: "ayurvedaSeedVersion")
            return result.requiresSearchIndexRebuild
        } catch {
            ctx.rollback()
            print("   ❌ Ayurveda seeding failed; continuing without Ayurveda data: \(error)")
            return false
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
            let raw = try Data(contentsOf: url)
            let dtos = try JSONDecoder().decode([FoodItemDTO].self, from: raw)

            var items: [FoodItem] = []
            items.reserveCapacity(dtos.count)

            for dto in dtos {
                let model = dto.model()
                model.isUserAdded = false
                model.isRecipe = false
                items.append(model)
            }

            try ctx.transaction {
                for item in items { ctx.insert(item) }
            }
            print("   ✅ Seeded \(items.count) foods.")
        } catch {
            print("   ❌ Food seeding failed: \(error)")
        }
    }

    // MARK: – Removed bundled exercise catalogue
    private static func removeBundledExercisesIfNeeded(context ctx: ModelContext) {
        do {
            let descriptor = FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.catalogNumber != nil }
            )
            let bundledExercises = try ctx.fetch(descriptor).filter {
                guard let catalogNumber = $0.catalogNumber else { return false }
                return catalogNumber < 800_000
            }
            guard !bundledExercises.isEmpty else { return }

            let bundledIDs = Set(bundledExercises.map(\.id))

            for link in try ctx.fetch(FetchDescriptor<ExerciseLink>()) {
                if let exerciseID = link.exercise?.id,
                   bundledIDs.contains(exerciseID) {
                    ctx.delete(link)
                }
            }

            for planExercise in try ctx.fetch(FetchDescriptor<TrainingPlanExercise>()) {
                if let exerciseID = planExercise.exercise?.id,
                   bundledIDs.contains(exerciseID) {
                    ctx.delete(planExercise)
                }
            }

            for exercise in bundledExercises {
                ctx.delete(exercise)
            }
            try ctx.save()
            print("🧹 Removed \(bundledExercises.count) bundled exercises.")
        } catch {
            ctx.rollback()
            print("❌ Failed to remove bundled exercises: \(error)")
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

private struct VocabularySeedDTO: Decodable {
    let id: UUID
    let tokenIndex: Int
    let word: String
}

private struct ProductBucketSeedDTO: Decodable {
    let id: UUID
    let bucketKey: String
    let compressedData: String
}
