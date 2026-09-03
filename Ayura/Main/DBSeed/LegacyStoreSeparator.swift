import Foundation
import SwiftData

@MainActor
enum LegacyStoreSeparator {
    static let separationVersion = 1

    struct Result {
        let performedMigration: Bool
        let migratedFoodReferences: Int
        let migratedExerciseReferences: Int
        let preservedPreferences: Int
        let removedCatalogObjects: Int
    }

    static func prepareUserStore(
        at userStoreURL: URL,
        catalogStoreURL: URL,
        manifest: CatalogManifest,
        hadLegacyStore: Bool
    ) throws -> Result {
        if hadLegacyStore {
            try createRecoveryBackupIfNeeded(for: userStoreURL)
        }

        let userConfiguration = ModelConfiguration(
            DatabaseSchema.userConfigurationName,
            schema: DatabaseSchema.user,
            url: userStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let emptyCatalogConfiguration = ModelConfiguration(
            DatabaseSchema.catalogConfigurationName,
            schema: DatabaseSchema.catalog,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let userContainer = try ModelContainer(
            for: DatabaseSchema.combined,
            configurations: [emptyCatalogConfiguration, userConfiguration]
        )
        let userContext = userContainer.mainContext
        userContext.autosaveEnabled = false

        // Run the legacy units migration while only the writable store is
        // attached. This updates user workouts/plans without ever attempting
        // to modify the replacement catalogue.
        if hadLegacyStore {
            try ExerciseDurationUnitMigrator.migrateIfNeeded(
                context: userContext
            )
        }

        if let state = try userContext.fetch(
            FetchDescriptor<CatalogMigrationState>(
                predicate: #Predicate { $0.key == "catalog-separation" }
            )
        ).first, state.separationVersion >= separationVersion {
            if state.catalogVersion != manifest.catalogVersion
                || state.contentRevision != manifest.contentRevision {
                try deleteUserSearchCaches(context: userContext)
                state.catalogVersion = manifest.catalogVersion
                state.contentRevision = manifest.contentRevision
                state.completedAt = Date()
                try userContext.save()
            }
            return Result(
                performedMigration: false,
                migratedFoodReferences: 0,
                migratedExerciseReferences: 0,
                preservedPreferences: 0,
                removedCatalogObjects: 0
            )
        }

        guard hadLegacyStore else {
            userContext.insert(
                CatalogMigrationState(
                    separationVersion: separationVersion,
                    catalogVersion: manifest.catalogVersion,
                    contentRevision: manifest.contentRevision
                )
            )
            try userContext.save()
            return Result(
                performedMigration: true,
                migratedFoodReferences: 0,
                migratedExerciseReferences: 0,
                preservedPreferences: 0,
                removedCatalogObjects: 0
            )
        }

        let catalogConfiguration = ModelConfiguration(
            DatabaseSchema.catalogConfigurationName,
            schema: DatabaseSchema.catalog,
            url: catalogStoreURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let emptyUserConfiguration = ModelConfiguration(
            DatabaseSchema.userConfigurationName,
            schema: DatabaseSchema.user,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let catalogContainer = try ModelContainer(
            for: DatabaseSchema.combined,
            configurations: [catalogConfiguration, emptyUserConfiguration]
        )
        let catalogContext = catalogContainer.mainContext

        let catalogFoodIDs = Set(
            try catalogContext.fetch(FetchDescriptor<FoodItem>()).map(\.id)
        )
        let catalogExerciseIDs = Set(
            try catalogContext.fetch(FetchDescriptor<ExerciseItem>()).map(\.id)
        )
        let catalogVitaminIDs = Set(
            try catalogContext.fetch(FetchDescriptor<Vitamin>()).map(\.id)
        )
        let catalogMineralIDs = Set(
            try catalogContext.fetch(FetchDescriptor<Mineral>()).map(\.id)
        )
        let catalogPracticeIDs = Set(
            try catalogContext.fetch(FetchDescriptor<Practice>()).map(\.id)
        )
        // A user-owned object that happens to retain a former catalog UUID is
        // re-keyed before catalog rows are removed. All object relationships
        // remain attached to that object, so authored content is preserved.
        for food in try userContext.fetch(FetchDescriptor<FoodItem>())
        where catalogFoodIDs.contains(food.id) && food.isUserAdded {
            food.id = UUID()
            food.catalogNumber = nil
        }
        for exercise in try userContext.fetch(FetchDescriptor<ExerciseItem>())
        where catalogExerciseIDs.contains(exercise.id) && exercise.isUserAdded {
            exercise.id = UUID()
            exercise.catalogNumber = nil
        }

        var foodReferences = 0
        var exerciseReferences = 0

        func migrateFood(
            _ stored: inout FoodItem?,
            catalogID: inout UUID?
        ) {
            guard let food = stored, catalogFoodIDs.contains(food.id) else { return }
            catalogID = food.id
            stored = nil
            foodReferences += 1
        }

        func migrateExercise(
            _ stored: inout ExerciseItem?,
            catalogID: inout UUID?
        ) {
            guard let exercise = stored,
                  catalogExerciseIDs.contains(exercise.id) else { return }
            catalogID = exercise.id
            stored = nil
            exerciseReferences += 1
        }

        for link in try userContext.fetch(FetchDescriptor<IngredientLink>()) {
            migrateFood(&link.persistedFood, catalogID: &link.catalogFoodID)
        }
        for entry in try userContext.fetch(FetchDescriptor<MealPlanEntry>()) {
            migrateFood(&entry.persistedFood, catalogID: &entry.catalogFoodID)
        }
        for item in try userContext.fetch(FetchDescriptor<ShoppingListItem>()) {
            migrateFood(&item.persistedFoodItem, catalogID: &item.catalogFoodID)
        }
        for item in try userContext.fetch(FetchDescriptor<RecentlyAddedFood>()) {
            migrateFood(&item.persistedFood, catalogID: &item.catalogFoodID)
        }
        for item in try userContext.fetch(FetchDescriptor<StorageItem>()) {
            migrateFood(&item.persistedFood, catalogID: &item.catalogFoodID)
        }
        for item in try userContext.fetch(FetchDescriptor<StorageTransaction>()) {
            migrateFood(&item.persistedFood, catalogID: &item.catalogFoodID)
        }
        for item in try userContext.fetch(FetchDescriptor<MealLogStorageLink>()) {
            migrateFood(&item.persistedFood, catalogID: &item.catalogFoodID)
        }
        for link in try userContext.fetch(FetchDescriptor<ExerciseLink>()) {
            migrateExercise(
                &link.persistedExercise,
                catalogID: &link.catalogExerciseID
            )
        }
        for link in try userContext.fetch(FetchDescriptor<TrainingPlanExercise>()) {
            migrateExercise(
                &link.persistedExercise,
                catalogID: &link.catalogExerciseID
            )
        }

        for node in try userContext.fetch(FetchDescriptor<Node>()) {
            let foodSplit = (node.persistedFoods ?? []).reduce(
                into: (stored: [FoodItem](), ids: [UUID]())
            ) { result, food in
                if catalogFoodIDs.contains(food.id) {
                    result.ids.append(food.id)
                    foodReferences += 1
                } else {
                    result.stored.append(food)
                }
            }
            node.persistedFoods = foodSplit.stored
            node.catalogFoodIDs = foodSplit.ids

            let exerciseSplit = (node.persistedExercises ?? []).reduce(
                into: (stored: [ExerciseItem](), ids: [UUID]())
            ) { result, exercise in
                if catalogExerciseIDs.contains(exercise.id) {
                    result.ids.append(exercise.id)
                    exerciseReferences += 1
                } else {
                    result.stored.append(exercise)
                }
            }
            node.persistedExercises = exerciseSplit.stored
            node.catalogExerciseIDs = exerciseSplit.ids
        }

        for profile in try userContext.fetch(FetchDescriptor<Profile>()) {
            let vitamins = profile.persistedPriorityVitamins
            profile.priorityVitaminIDs = vitamins
                .filter { catalogVitaminIDs.contains($0.id) }
                .map(\.id)
            profile.persistedPriorityVitamins = vitamins.filter {
                !catalogVitaminIDs.contains($0.id)
            }

            let minerals = profile.persistedPriorityMinerals
            profile.priorityMineralIDs = minerals
                .filter { catalogMineralIDs.contains($0.id) }
                .map(\.id)
            profile.persistedPriorityMinerals = minerals.filter {
                !catalogMineralIDs.contains($0.id)
            }
        }

        var preferenceCount = 0
        for food in try userContext.fetch(FetchDescriptor<FoodItem>())
        where catalogFoodIDs.contains(food.id) && food.isFavorite {
            try upsertPreference(
                kind: "food",
                itemID: food.id,
                context: userContext
            )
            preferenceCount += 1
        }
        for exercise in try userContext.fetch(FetchDescriptor<ExerciseItem>())
        where catalogExerciseIDs.contains(exercise.id) && exercise.isFavorite {
            try upsertPreference(
                kind: "exercise",
                itemID: exercise.id,
                context: userContext
            )
            preferenceCount += 1
        }
        for practice in try userContext.fetch(FetchDescriptor<Practice>())
        where catalogPracticeIDs.contains(practice.id) && practice.isFavorite {
            try upsertPreference(
                kind: "practice",
                itemID: practice.id,
                context: userContext
            )
            preferenceCount += 1
        }

        // Persist detached user references before cascading catalog deletes.
        if userContext.hasChanges { try userContext.save() }

        var removed = 0
        let catalogueFoodPredicate = #Predicate<FoodItem> { !$0.isUserAdded }
        removed += try userContext.fetchCount(
            FetchDescriptor(predicate: catalogueFoodPredicate)
        )
        try userContext.delete(
            model: FoodItem.self,
            where: catalogueFoodPredicate
        )

        let catalogueExercisePredicate = #Predicate<ExerciseItem> {
            !$0.isUserAdded
        }
        removed += try userContext.fetchCount(
            FetchDescriptor(predicate: catalogueExercisePredicate)
        )
        try userContext.delete(
            model: ExerciseItem.self,
            where: catalogueExercisePredicate
        )

        removed += try userContext.fetchCount(FetchDescriptor<Practice>())
        removed += try userContext.fetchCount(FetchDescriptor<YogaSequence>())
        removed += try userContext.fetchCount(FetchDescriptor<Vitamin>())
        removed += try userContext.fetchCount(FetchDescriptor<Mineral>())
        try userContext.delete(model: Practice.self)
        try userContext.delete(model: YogaSequence.self)
        try userContext.delete(model: Vitamin.self)
        try userContext.delete(model: Mineral.self)

        let catalogueAyurvedaPredicate = #Predicate<AyurvedaProfile> {
            $0.kind != "user"
        }
        removed += try userContext.fetchCount(
            FetchDescriptor(predicate: catalogueAyurvedaPredicate)
        )
        try userContext.delete(
            model: AyurvedaProfile.self,
            where: catalogueAyurvedaPredicate
        )

        removed += try userContext.fetchCount(FetchDescriptor<AyurvedaLink>())
        try userContext.delete(model: AyurvedaLink.self)

        let productBucketCount = try userContext.fetchCount(
            FetchDescriptor<ProductBucket>()
        )
        let vocabularyCount = try userContext.fetchCount(
            FetchDescriptor<VocabularyEntry>()
        )
        try userContext.delete(model: ProductBucket.self)
        try userContext.delete(model: VocabularyEntry.self)
        removed += productBucketCount + vocabularyCount
        try deleteUserSearchCaches(context: userContext)

        userContext.insert(
            CatalogMigrationState(
                separationVersion: separationVersion,
                catalogVersion: manifest.catalogVersion,
                contentRevision: manifest.contentRevision
            )
        )
        try userContext.save()

        return Result(
            performedMigration: true,
            migratedFoodReferences: foodReferences,
            migratedExerciseReferences: exerciseReferences,
            preservedPreferences: preferenceCount,
            removedCatalogObjects: removed
        )
    }

    private static func upsertPreference(
        kind: String,
        itemID: UUID,
        context: ModelContext
    ) throws {
        let key = "\(kind):\(itemID.uuidString.lowercased())"
        let descriptor = FetchDescriptor<CatalogPreference>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.isFavorite = true
            existing.updatedAt = Date()
        } else {
            context.insert(
                CatalogPreference(kind: kind, itemID: itemID, isFavorite: true)
            )
        }
    }

    private static func deleteUserSearchCaches(context: ModelContext) throws {
        try context.delete(model: SearchIndexCache.self)
    }

    private static func createRecoveryBackupIfNeeded(for storeURL: URL) throws {
        let fileManager = FileManager.default
        let backupDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent("PreCatalogSeparationBackup", isDirectory: true)
        let backupStore = backupDirectory.appendingPathComponent(
            storeURL.lastPathComponent
        )
        guard !fileManager.fileExists(atPath: backupStore.path) else { return }

        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            let destination = URL(fileURLWithPath: backupStore.path + suffix)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
    }
}
