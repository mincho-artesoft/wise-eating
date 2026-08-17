import SwiftData
import Foundation

@MainActor
enum SeedManager {

    // MARK: – Public entry point
    static func seedIfNeeded(container: ModelContainer) async {
        AyurvedaAsanaYogaLaunchProbe.event("seed-checks-begin")
        print("🚀 Starting database seed process if needed...")
        let ctx = GlobalState.modelContext!
        ctx.autosaveEnabled = false

        migrateExerciseDurationsIfNeeded(context: ctx)
        removeBundledExercisesIfNeeded(context: ctx)
        seedYogaIfNeeded(context: ctx)
        seedPracticesIfNeeded(context: ctx)
        await seedBarcodesIfNeeded(context: ctx)
        await seedReferenceVitaminsIfNeeded(context: ctx)
        await seedReferenceMineralsIfNeeded(context: ctx)
        await seedFoodsIfNeeded(context: ctx)
        AyurvedaAsanaYogaLaunchProbe.event("ayurveda-check-begin")
        let ayurvedaChangedSearchableFoods = await seedAyurvedaIfNeeded(context: ctx)
        AyurvedaAsanaYogaLaunchProbe.event("ayurveda-check-end")

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
        AyurvedaAsanaYogaLaunchProbe.event("seed-checks-end")
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

    // MARK: - Practices
    private static func seedPracticesIfNeeded(context ctx: ModelContext) {
        print("-> Checking for Practices data...")
        let versionKey = "practiceSeedVersion"
        do {
            let bundleVersion = try PracticeSeeder.bundleSeedVersion()
            let installedVersion = UserDefaults.standard.integer(forKey: versionKey)
            let catalogueIsInstalled = try PracticeSeeder.isInstalled(context: ctx)
            if installedVersion >= bundleVersion, catalogueIsInstalled {
                print("   Practices seed version already applied, skipping.")
                return
            }

            let result = try PracticeSeeder.run(context: ctx)
            UserDefaults.standard.set(bundleVersion, forKey: versionKey)
            print(
                "   Practices seed v\(bundleVersion) installed: "
                    + "\(result.practiceCount) practices, "
                    + "\(result.cueCount) cues, "
                    + "timing=\(result.timingMode), "
                    + "unresolved seats=\(result.unresolvedSeatReferences)."
            )
        } catch {
            ctx.rollback()
            print("   ❌ Practices seeding failed: \(error)")
            assertionFailure("Practice seed gate failed: \(error)")
        }
    }

    // MARK: - Barcodes
    private static func seedBarcodesIfNeeded(context ctx: ModelContext) async {
        print("-> Checking for Barcodes (Vocabulary & Buckets)...")
        let versionKey = "barcodeCatalogVersion"
        guard let metadataURL = Bundle.main.url(
            forResource: "barcode_catalog_metadata",
            withExtension: "json"
        ) else {
            assertionFailure("barcode_catalog_metadata.json not found")
            return
        }

        do {
            let metadataData = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(
                BarcodeCatalogMetadata.self,
                from: metadataData
            )
            guard metadata.schemaVersion == 1 else {
                throw BarcodeCatalogSeedError.unsupportedSchema(
                    metadata.schemaVersion
                )
            }
            let vocabularyCount = try ctx.fetchCount(
                FetchDescriptor<VocabularyEntry>()
            )
            let bucketCount = try ctx.fetchCount(
                FetchDescriptor<ProductBucket>()
            )
            let catalogueIsInstalled =
                vocabularyCount == metadata.vocabularyCount
                && bucketCount == metadata.bucketCount

            if catalogueIsInstalled {
                if UserDefaults.standard.integer(forKey: versionKey)
                    < metadata.catalogVersion {
                    UserDefaults.standard.set(
                        metadata.catalogVersion,
                        forKey: versionKey
                    )
                }
                print(
                    "   Barcode catalogue v\(metadata.catalogVersion) verified: "
                        + "\(metadata.productCount) products."
                )
                return
            }

            guard let vocabURL = Bundle.main.url(
                forResource: "vocabulary",
                withExtension: "json"
            ), let bucketsURL = Bundle.main.url(
                forResource: "product_buckets",
                withExtension: "json"
            ) else {
                assertionFailure("barcode seed resources not found")
                return
            }

            print(
                "   Updating barcode catalogue to v\(metadata.catalogVersion) "
                    + "(\(metadata.productCount) products)..."
            )
            try deleteAll(entity: ProductBucket.self, context: ctx)
            try deleteAll(entity: VocabularyEntry.self, context: ctx)

            print("   Seeding Vocabulary from vocabulary.json...")
            let vocabData = try Data(contentsOf: vocabURL)
            let decodedVocab = try JSONDecoder().decode([VocabularySeedDTO].self, from: vocabData)
            for (index, row) in decodedVocab.enumerated() {
                let entry = VocabularyEntry(
                    id: row.id,
                    tokenIndex: row.tokenIndex,
                    word: row.word
                )
                ctx.insert(entry)
                if (index + 1).isMultiple(of: 10_000) {
                    try ctx.save()
                }
            }
            if ctx.hasChanges { try ctx.save() }
            print("   ✅ Seeded \(decodedVocab.count) vocabulary entries.")

            print("   Seeding Product Buckets from product_buckets.json...")
            let bucketsData = try Data(contentsOf: bucketsURL)
            let decodedBuckets = try JSONDecoder().decode([ProductBucketSeedDTO].self, from: bucketsData)

            for (index, row) in decodedBuckets.enumerated() {
                let bucket = ProductBucket(
                    id: row.id,
                    bucketKey: row.bucketKey,
                    compressedData: row.compressedData
                )
                ctx.insert(bucket)
                if (index + 1).isMultiple(of: 1_000) {
                    try ctx.save()
                }
            }
            if ctx.hasChanges { try ctx.save() }

            let installedVocabularyCount = try ctx.fetchCount(
                FetchDescriptor<VocabularyEntry>()
            )
            let installedBucketCount = try ctx.fetchCount(
                FetchDescriptor<ProductBucket>()
            )
            guard installedVocabularyCount == metadata.vocabularyCount,
                  installedBucketCount == metadata.bucketCount else {
                throw BarcodeCatalogSeedError.countMismatch(
                    vocabulary: installedVocabularyCount,
                    buckets: installedBucketCount
                )
            }
            UserDefaults.standard.set(
                metadata.catalogVersion,
                forKey: versionKey
            )
            ProductDataManager.shared.resetCatalogCache()
            print("   ✅ Seeded \(decodedBuckets.count) product buckets.")
        } catch {
            ctx.rollback()
            print("   ❌ Barcode catalogue update failed: \(error)")
            assertionFailure("Barcode catalogue update failed: \(error)")
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

    private static func deleteAll<T: PersistentModel>(
        entity: T.Type,
        context ctx: ModelContext
    ) throws {
        while true {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchLimit = 10_000
            let rows = try ctx.fetch(descriptor)
            guard !rows.isEmpty else { return }
            for row in rows { ctx.delete(row) }
            try ctx.save()
        }
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

private struct BarcodeCatalogMetadata: Decodable {
    let schemaVersion: Int
    let catalogVersion: Int
    let productCount: Int
    let vocabularyCount: Int
    let bucketCount: Int
}

private enum BarcodeCatalogSeedError: Error {
    case unsupportedSchema(Int)
    case countMismatch(vocabulary: Int, buckets: Int)
}
