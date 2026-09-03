#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CatalogSeparationSmokeTestRunner {
    private enum SmokeError: Error, LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            }
        }
    }

    private struct IDs {
        static let catalogFood = UUID(
            uuidString: "41b89485-6608-4d7e-90bc-657467dde001"
        )!
        static let catalogExercise = UUID(
            uuidString: "41b89485-6608-4d7e-90bc-657467dde002"
        )!
        static let catalogPractice = UUID(
            uuidString: "41b89485-6608-4d7e-90bc-657467dde003"
        )!
        static let catalogSequence = UUID(
            uuidString: "41b89485-6608-4d7e-90bc-657467dde004"
        )!
    }

    private struct Snapshot: Equatable {
        let profileCount: Int
        let profileName: String
        let userFoodNames: [String]
        let userExerciseNames: [String]
        let mealEntryGrams: Double
        let mealEntryFoodName: String
        let recipeIngredientName: String
        let storageQuantity: Double
        let shoppingQuantity: Double
        let trainingDuration: Double
        let trainingExerciseName: String
        let workoutExerciseName: String
        let nodeFoodName: String
        let nodeExerciseName: String
        let practiceSessionCount: Int
        let priorityVitaminName: String
        let priorityMineralName: String
        let favoriteKeys: [String]
    }

    static func run(realContext: ModelContext) async {
        let originalContext = GlobalState.modelContext
        let originalCatalogIdentifier = CatalogReferenceResolver
            .catalogStoreIdentifier
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "catalog-separation-smoke-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            defer {
                GlobalState.modelContext = originalContext
                if let originalCatalogIdentifier {
                    CatalogReferenceResolver.configure(
                        catalogStoreIdentifier: originalCatalogIdentifier
                    )
                }
                try? CatalogPreferenceStore.shared.load(context: realContext)
                try? fileManager.removeItem(at: root)
            }

            let userStoreURL = root.appendingPathComponent("legacy-user.store")
            let catalogStoreURL = root.appendingPathComponent("catalog.store")

            CatalogReferenceResolver.configure(
                catalogStoreIdentifier: "fixture-build-has-no-catalog"
            )
            try createFixtureStore(
                at: catalogStoreURL,
                schema: DatabaseSchema.catalog,
                configurationName: DatabaseSchema.catalogConfigurationName,
                includesUserRecords: false,
                catalogLabel: "Replacement",
                catalogFavorites: false
            )
            try CatalogStoreManager.finalizeForCombinedMount(
                at: catalogStoreURL
            )
            try createFixtureStore(
                at: userStoreURL,
                schema: DatabaseSchema.user,
                configurationName: DatabaseSchema.userConfigurationName,
                includesUserRecords: true,
                catalogLabel: "Legacy",
                catalogFavorites: true
            )

            let catalogIdentifier = try CatalogStoreManager.storeIdentifier(
                at: catalogStoreURL
            )
            CatalogReferenceResolver.configure(
                catalogStoreIdentifier: catalogIdentifier
            )

            let firstManifest = manifest(version: 1, revision: "smoke-v1")
            let migration = try LegacyStoreSeparator.prepareUserStore(
                at: userStoreURL,
                catalogStoreURL: catalogStoreURL,
                manifest: firstManifest,
                hadLegacyStore: true
            )
            try require(migration.performedMigration, "first separation did not run")
            try require(
                migration.migratedFoodReferences >= 5,
                "food references were not detached"
            )
            try require(
                migration.migratedExerciseReferences >= 3,
                "exercise references were not detached"
            )
            try require(
                migration.preservedPreferences == 3,
                "food/exercise/practice favorites were not preserved"
            )

            let firstSnapshot = try readAndValidateCombinedStore(
                userStoreURL: userStoreURL,
                catalogStoreURL: catalogStoreURL
            )

            let updateStart = ProcessInfo.processInfo.systemUptime
            let update = try LegacyStoreSeparator.prepareUserStore(
                at: userStoreURL,
                catalogStoreURL: catalogStoreURL,
                manifest: manifest(version: 2, revision: "smoke-v2"),
                hadLegacyStore: true
            )
            let updateElapsed = ProcessInfo.processInfo.systemUptime - updateStart

            try require(!update.performedMigration, "normal update repeated separation")
            try require(
                update.removedCatalogObjects == 0,
                "normal update performed row-by-row catalogue deletion"
            )

            let secondSnapshot = try readAndValidateCombinedStore(
                userStoreURL: userStoreURL,
                catalogStoreURL: catalogStoreURL
            )
            try require(
                firstSnapshot == secondSnapshot,
                "user records changed during normal catalogue update"
            )
            try require(
                updateElapsed < 5,
                "normal update path was unexpectedly slow (\(updateElapsed)s)"
            )

            print(
                "CATALOG_SEPARATION_SMOKE|PASS|"
                    + "foodRefs=\(migration.migratedFoodReferences)|"
                    + "exerciseRefs=\(migration.migratedExerciseReferences)|"
                    + "preferences=\(migration.preservedPreferences)|"
                    + "normalUpdateSeconds="
                    + String(format: "%.4f", updateElapsed)
                    + "|normalUpdateReseeded=false"
            )
        } catch {
            print("CATALOG_SEPARATION_SMOKE|FAIL|\(error.localizedDescription)")
        }
    }

    private static func createFixtureStore(
        at url: URL,
        schema: Schema,
        configurationName: String,
        includesUserRecords: Bool,
        catalogLabel: String,
        catalogFavorites: Bool
    ) throws {
        let configuration = ModelConfiguration(
            configurationName,
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = container.mainContext
        context.autosaveEnabled = false

        let fixtures = makeCatalogFixtures(
            label: catalogLabel,
            favorites: catalogFavorites
        )
        context.insert(fixtures.food)
        context.insert(fixtures.exercise)
        context.insert(fixtures.practice)
        context.insert(fixtures.sequence)
        context.insert(fixtures.vitamin)
        context.insert(fixtures.mineral)

        if includesUserRecords {
            try insertUserRecords(fixtures: fixtures, context: context)
        }
        try context.save()
        withExtendedLifetime(container) {}
    }

    private static func makeCatalogFixtures(
        label: String,
        favorites: Bool
    ) -> (
        food: FoodItem,
        exercise: ExerciseItem,
        practice: Practice,
        sequence: YogaSequence,
        vitamin: Vitamin,
        mineral: Mineral
    ) {
        let food = FoodItem(
            id: IDs.catalogFood,
            catalogNumber: 910_001,
            name: "Catalog Food \(label)",
            isUserAdded: false
        )
        food.isFavorite = favorites

        let exercise = ExerciseItem(
            id: IDs.catalogExercise,
            catalogNumber: 810_001,
            name: "Catalog Exercise \(label)",
            isUserAdded: false,
            muscleGroups: [.abs],
            durationSeconds: 60
        )
        exercise.isFavorite = favorites

        let practice = Practice(
            id: IDs.catalogPractice,
            catalogNumber: 920_001,
            slug: "smoke-practice",
            kind: "breathwork",
            title: "Catalog Practice \(label)",
            sanskrit: nil,
            practiceDescription: "Smoke fixture",
            technique: "Breathe",
            sourceTradition: "Test",
            seatAsanaID: IDs.catalogExercise,
            seatFlexible: true,
            posture: "seated",
            eyes: "closed",
            durationSeconds: 60,
            durationOptions: [60],
            goals: ["test"],
            themes: ["test"],
            level: 1,
            minimalAgeMonths: 0,
            contraindications: [],
            isFavorite: favorites,
            doshaVata: 0,
            doshaPitta: 0,
            doshaKapha: 0,
            doshaProvenance: "test",
            guna: "sattva",
            timeOfDay: ["morning"],
            season: ["all"],
            agni: "neutral",
            sceneImageName: nil,
            narrationAudioAssetName: nil,
            ttsVoiceHint: "default",
            wordsPerMinute: 120,
            ambienceTrackID: "none",
            ambienceLoops: false,
            ambienceVolume: 0,
            timingMode: "authored"
        )

        let sequence = YogaSequence(
            id: IDs.catalogSequence,
            catalogNumber: 930_001,
            title: "Catalog Sequence \(label)",
            intent: "test",
            level: 1,
            durationSeconds: 900,
            season: "all",
            school: "test",
            sequenceNote: nil,
            doshaEffect: YogaDoshaEffect(vata: 0, pitta: 0, kapha: 0),
            doshaProvenance: "test",
            estimatedSeconds: 900,
            posesData: Data("[]".utf8)
        )

        return (
            food,
            exercise,
            practice,
            sequence,
            Vitamin(
                id: "vitC",
                name: "Smoke Vitamin \(label)",
                unit: "mg",
                abbreviation: "SV",
                colorHex: "#ffffff",
                requirements: smokeRequirements()
            ),
            Mineral(
                id: "calcium",
                name: "Smoke Mineral \(label)",
                unit: "mg",
                symbol: "SM",
                colorHex: "#ffffff",
                requirements: smokeRequirements()
            )
        )
    }

    private static func smokeRequirements() -> [Requirement] {
        (0..<13).map {
            Requirement(demographic: "smoke-\($0)", dailyNeed: 0)
        }
    }

    private static func insertUserRecords(
        fixtures: (
            food: FoodItem,
            exercise: ExerciseItem,
            practice: Practice,
            sequence: YogaSequence,
            vitamin: Vitamin,
            mineral: Mineral
        ),
        context: ModelContext
    ) throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = Meal(
            name: "Migration Meal",
            startTime: start,
            endTime: start.addingTimeInterval(1_800)
        )
        let training = Training(
            name: "Migration Training",
            startTime: start,
            endTime: start.addingTimeInterval(1_800)
        )
        let profile = Profile(
            name: "Migration User",
            birthday: Date(timeIntervalSince1970: 0),
            gender: "male",
            weight: 72,
            height: 178,
            meals: [meal],
            trainings: [training],
            priorityVitamins: [fixtures.vitamin],
            priorityMinerals: [fixtures.mineral]
        )
        context.insert(profile)

        let userFood = FoodItem(name: "User Food", isUserAdded: true)
        let recipe = FoodItem(
            name: "User Recipe",
            isRecipe: true,
            isUserAdded: true
        )
        let ingredient = IngredientLink(
            food: fixtures.food,
            grams: 42,
            owner: recipe
        )
        recipe.ingredients = [ingredient]
        context.insert(userFood)
        context.insert(recipe)

        let mealPlan = MealPlan(name: "User Meal Plan", profile: profile)
        let mealPlanMeal = MealPlanMeal(mealName: "Lunch")
        let mealEntry = MealPlanEntry(
            food: fixtures.food,
            grams: 123,
            meal: mealPlanMeal
        )
        mealPlanMeal.entries = [mealEntry]
        mealPlanMeal.day = mealPlan.days[0]
        mealPlan.days[0].meals = [mealPlanMeal]
        profile.mealPlans = [mealPlan]

        let storage = StorageItem(
            owner: profile,
            food: fixtures.food,
            batches: [Batch(quantity: 7)]
        )
        profile.pantryItems = [storage]

        let shoppingList = ShoppingListModel(
            profile: profile,
            name: "User Shopping List"
        )
        let shoppingItem = ShoppingListItem(
            name: "Catalog Food",
            quantity: 3,
            foodItem: fixtures.food
        )
        shoppingItem.list = shoppingList
        shoppingList.items = [shoppingItem]
        profile.shoppingLists = [shoppingList]

        let userExercise = ExerciseItem(
            name: "User Exercise",
            isUserAdded: true,
            muscleGroups: [.abs],
            durationSeconds: 75
        )
        let workout = ExerciseItem(
            name: "User Workout",
            isUserAdded: true,
            muscleGroups: [.abs],
            isWorkout: true
        )
        let workoutLink = ExerciseLink(
            exercise: fixtures.exercise,
            durationSeconds: 88,
            owner: workout
        )
        workout.exercises = [workoutLink]
        context.insert(userExercise)
        context.insert(workout)

        let trainingPlan = TrainingPlan(
            name: "User Training Plan",
            profile: profile
        )
        let trainingDay = TrainingPlanDay(dayIndex: 1, plan: trainingPlan)
        let trainingWorkout = TrainingPlanWorkout(
            workoutName: "Plan Workout",
            day: trainingDay
        )
        let trainingExercise = TrainingPlanExercise(
            exercise: fixtures.exercise,
            durationSeconds: 99,
            workout: trainingWorkout
        )
        trainingWorkout.exercises = [trainingExercise]
        trainingDay.workouts = [trainingWorkout]
        trainingPlan.days = [trainingDay]
        profile.trainingPlans = [trainingPlan]

        let node = Node(textContent: "User Node", profile: profile)
        node.linkedFoods = [fixtures.food]
        node.linkedExercises = [fixtures.exercise]
        profile.nodes = [node]

        let session = PracticeSession(
            practice: fixtures.practice,
            profile: profile,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            plannedDurationSeconds: 60,
            completed: true
        )
        profile.practiceSessions = [session]
    }

    private static func readAndValidateCombinedStore(
        userStoreURL: URL,
        catalogStoreURL: URL
    ) throws -> Snapshot {
        let container = try CombinedStoreFactory.makeContainer(
            schema: DatabaseSchema.combined,
            userSchema: DatabaseSchema.user,
            catalogSchema: DatabaseSchema.catalog,
            userStoreURL: userStoreURL,
            catalogStoreURL: catalogStoreURL
        )
        let context = container.mainContext
        GlobalState.modelContext = context
        try CatalogPreferenceStore.shared.load(context: context)

        let profiles = try context.fetch(
            FetchDescriptor<Profile>(
                predicate: #Predicate { $0.name == "Migration User" }
            )
        )
        guard let profile = profiles.first else {
            throw SmokeError.failed("user profile was lost")
        }

        // Both configurations expose the same entity schema. Production
        // editors therefore use the single-configuration user writer instead
        // of asking SwiftData to choose a destination in the combined reader.
        let writeContext = try CombinedStoreFactory.makeUserWriteContext(
            from: container
        )
        let routedFood = FoodItem(
            name: "Write Routing Probe Food",
            isUserAdded: true
        )
        let routedExercise = ExerciseItem(
            name: "Write Routing Probe Exercise",
            isUserAdded: true,
            muscleGroups: [.abs]
        )
        writeContext.insert(routedFood)
        writeContext.insert(routedExercise)
        try writeContext.save()
        let userStoreIdentifier = profile.persistentModelID.storeIdentifier
        try require(
            routedFood.persistentModelID.storeIdentifier == userStoreIdentifier
                && routedExercise.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
            "new food/exercise writes were not routed to the user store"
        )

        guard let writeProfile = try CatalogReferenceResolver.userProfile(
            id: profile.id,
            context: writeContext
        ),
        let catalogFood = try context.fetch(FetchDescriptor<FoodItem>())
            .first(where: { $0.id == IDs.catalogFood }),
        let catalogExercise = try context.fetch(FetchDescriptor<ExerciseItem>())
            .first(where: { $0.id == IDs.catalogExercise }),
        let catalogPractice = try context.fetch(FetchDescriptor<Practice>())
            .first(where: { $0.id == IDs.catalogPractice }) else {
            throw SmokeError.failed("post-separation plan probe inputs are missing")
        }

        // New and edited meal/training plans must be committed entirely in
        // the user store while catalogue selections remain scalar UUIDs.
        let routedMealPlan = MealPlan(
            name: "Write Routing Meal Plan",
            profile: writeProfile
        )
        writeContext.insert(routedMealPlan)
        let routedMeal = MealPlanMeal(mealName: "Probe Meal")
        routedMeal.day = routedMealPlan.days[0]
        writeContext.insert(routedMeal)
        routedMealPlan.days[0].meals = [routedMeal]
        let catalogMealEntry = try CatalogReferenceResolver.mealPlanEntry(
            for: catalogFood,
            grams: 11,
            meal: routedMeal,
            userContext: writeContext
        )
        let userMealEntry = try CatalogReferenceResolver.mealPlanEntry(
            for: routedFood,
            grams: 22,
            meal: routedMeal,
            userContext: writeContext
        )
        writeContext.insert(catalogMealEntry)
        writeContext.insert(userMealEntry)
        routedMeal.entries = [catalogMealEntry, userMealEntry]

        let routedShoppingList = ShoppingListModel(
            profile: writeProfile,
            name: "Write Routing Shopping List"
        )
        writeContext.insert(routedShoppingList)
        let catalogShoppingItem = try CatalogReferenceResolver
            .shoppingListItem(
                for: catalogFood,
                name: catalogFood.name,
                quantity: 66,
                price: 1,
                isBought: false,
                list: routedShoppingList,
                userContext: writeContext
            )
        let userShoppingItem = try CatalogReferenceResolver.shoppingListItem(
            for: routedFood,
            name: routedFood.name,
            quantity: 77,
            price: 2,
            isBought: false,
            list: routedShoppingList,
            userContext: writeContext
        )
        writeContext.insert(catalogShoppingItem)
        writeContext.insert(userShoppingItem)
        routedShoppingList.items = [catalogShoppingItem, userShoppingItem]

        let routedStorage = try CatalogReferenceResolver.storageItem(
            for: catalogFood,
            owner: writeProfile,
            userContext: writeContext
        )
        let routedBatch = Batch(
            quantity: 88,
            storageItem: routedStorage
        )
        routedStorage.batches = [routedBatch]
        writeContext.insert(routedStorage)
        writeContext.insert(routedBatch)
        let routedTransaction = try CatalogReferenceResolver
            .storageTransaction(
                for: catalogFood,
                date: Date(),
                type: .addition,
                quantityChange: 88,
                profile: writeProfile,
                userContext: writeContext
            )
        writeContext.insert(routedTransaction)

        let routedTrainingPlan = TrainingPlan(
            name: "Write Routing Training Plan",
            profile: writeProfile
        )
        let routedTrainingDay = TrainingPlanDay(
            dayIndex: 1,
            plan: routedTrainingPlan
        )
        let routedTrainingWorkout = TrainingPlanWorkout(
            workoutName: "Probe Workout",
            day: routedTrainingDay
        )
        let catalogPlanExercise = try CatalogReferenceResolver
            .trainingPlanExercise(
                for: catalogExercise,
                durationSeconds: 33,
                workout: routedTrainingWorkout,
                userContext: writeContext
            )
        let userPlanExercise = try CatalogReferenceResolver
            .trainingPlanExercise(
                for: routedExercise,
                durationSeconds: 44,
                workout: routedTrainingWorkout,
                userContext: writeContext
            )
        routedTrainingWorkout.exercises = [
            catalogPlanExercise,
            userPlanExercise,
        ]
        routedTrainingDay.workouts = [routedTrainingWorkout]
        routedTrainingPlan.days = [routedTrainingDay]
        writeContext.insert(routedTrainingPlan)

        let routedPracticeSession = PracticeSession(
            practice: catalogPractice,
            profile: writeProfile,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_060),
            plannedDurationSeconds: 60,
            completed: true
        )
        writeContext.insert(routedPracticeSession)
        try writeContext.save()

        try require(
            catalogMealEntry.catalogFoodID == catalogFood.id
                && catalogMealEntry.persistedFood == nil
                && userMealEntry.persistedFood?.id == routedFood.id
                && catalogPlanExercise.catalogExerciseID == catalogExercise.id
                && catalogPlanExercise.persistedExercise == nil
                && userPlanExercise.persistedExercise?.id == routedExercise.id
                && catalogShoppingItem.catalogFoodID == catalogFood.id
                && catalogShoppingItem.persistedFoodItem == nil
                && userShoppingItem.persistedFoodItem?.id == routedFood.id
                && routedStorage.catalogFoodID == catalogFood.id
                && routedStorage.persistedFood == nil
                && routedTransaction.catalogFoodID == catalogFood.id
                && routedTransaction.persistedFood == nil
                && routedPracticeSession.persistentModelID.storeIdentifier
                    == userStoreIdentifier
                && routedPracticeSession.profile?.id == writeProfile.id,
            "post-separation user references were not routed correctly"
        )
        routedMealPlan.name = "Write Routing Meal Plan Edited"
        routedTrainingPlan.name = "Write Routing Training Plan Edited"
        routedShoppingList.name = "Write Routing Shopping List Edited"
        catalogShoppingItem.quantity = 99
        routedBatch.quantity = 111
        userPlanExercise.durationSeconds = 55
        try writeContext.save()
        try require(
            routedMealPlan.name.hasSuffix("Edited")
                && routedTrainingPlan.name.hasSuffix("Edited")
                && routedShoppingList.name.hasSuffix("Edited")
                && catalogShoppingItem.quantity == 99
                && routedBatch.quantity == 111
                && userPlanExercise.durationSeconds == 55,
            "post-separation user updates failed"
        )

        writeContext.delete(routedMealPlan)
        writeContext.delete(routedTrainingPlan)
        writeContext.delete(routedShoppingList)
        writeContext.delete(routedStorage)
        writeContext.delete(routedTransaction)
        writeContext.delete(routedPracticeSession)
        writeContext.delete(routedFood)
        writeContext.delete(routedExercise)
        try writeContext.save()

        let foods = try context.fetch(FetchDescriptor<FoodItem>())
        let exercises = try context.fetch(FetchDescriptor<ExerciseItem>())
        guard foods.contains(where: {
            $0.id == IDs.catalogFood
        }) else {
            throw SmokeError.failed("replacement catalogue food was lost")
        }
        let derivedServingFood = FoodItem(
            name: "Derived Serving Probe",
            macronutrients: MacronutrientsData(
                carbohydrates: Nutrient(value: 7.43554791, unit: "g"),
                protein: Nutrient(value: 0.26659375, unit: "g"),
                fat: Nutrient(value: 0.158802, unit: "g")
            )
        )
        let duplicateCopy = FoodItemCopy(from: derivedServingFood)
        let expectedServingWeight = 7.43554791 + 0.26659375 + 0.158802
        try require(
            abs((duplicateCopy.duplicationServingWeightG ?? 0)
                - expectedServingWeight) < 0.000_001,
            "catalogue food duplication did not preserve the displayed serving weight"
        )
        let userFoodNames = foods.filter(\.isUserAdded).map(\.name).sorted()
        let userExerciseNames = exercises.filter(\.isUserAdded).map(\.name).sorted()
        try require(
            userFoodNames == ["User Food", "User Recipe"],
            "user foods/recipes changed"
        )
        try require(
            userExerciseNames == ["User Exercise", "User Workout"],
            "user exercises/workouts changed"
        )

        guard let mealEntry = try context.fetch(FetchDescriptor<MealPlanEntry>())
            .first(where: { $0.grams == 123 }),
              let recipeIngredient = try context.fetch(
                FetchDescriptor<IngredientLink>()
              ).first(where: { $0.grams == 42 }),
              let storage = try context.fetch(FetchDescriptor<StorageItem>()).first,
              let shopping = try context.fetch(
                FetchDescriptor<ShoppingListItem>()
              ).first,
              let planExercise = try context.fetch(
                FetchDescriptor<TrainingPlanExercise>()
              ).first,
              let workoutExercise = try context.fetch(
                FetchDescriptor<ExerciseLink>()
              ).first(where: { $0.durationSeconds == 88 }),
              let node = try context.fetch(FetchDescriptor<Node>()).first,
              let priorityVitamin = profile.priorityVitamins.first,
              let priorityMineral = profile.priorityMinerals.first else {
            throw SmokeError.failed("one or more user references were lost")
        }

        try require(
            mealEntry.food?.name == "Catalog Food Replacement",
            "meal plan did not resolve replacement catalogue food"
        )
        try require(
            planExercise.exercise?.name == "Catalog Exercise Replacement",
            "training plan did not resolve replacement catalogue exercise"
        )

        let preferences = try context.fetch(FetchDescriptor<CatalogPreference>())
            .filter(\.isFavorite)
            .map(\.key)
            .sorted()
        try require(preferences.count == 3, "favorite overlay rows changed")
        try require(
            CatalogPreferenceStore.shared.isFavorite(
                kind: "food",
                itemID: IDs.catalogFood,
                fallback: false
            ),
            "catalogue food favorite is not active"
        )

        return Snapshot(
            profileCount: profiles.count,
            profileName: profile.name,
            userFoodNames: userFoodNames,
            userExerciseNames: userExerciseNames,
            mealEntryGrams: mealEntry.grams,
            mealEntryFoodName: mealEntry.food?.name ?? "",
            recipeIngredientName: recipeIngredient.food?.name ?? "",
            storageQuantity: storage.totalQuantity,
            shoppingQuantity: shopping.quantity,
            trainingDuration: planExercise.durationSeconds,
            trainingExerciseName: planExercise.exercise?.name ?? "",
            workoutExerciseName: workoutExercise.exercise?.name ?? "",
            nodeFoodName: node.linkedFoods?.first?.name ?? "",
            nodeExerciseName: node.linkedExercises?.first?.name ?? "",
            practiceSessionCount: try context.fetchCount(
                FetchDescriptor<PracticeSession>()
            ),
            priorityVitaminName: priorityVitamin.name,
            priorityMineralName: priorityMineral.name,
            favoriteKeys: preferences
        )
    }

    private static func manifest(
        version: Int,
        revision: String
    ) -> CatalogManifest {
        CatalogManifest(
            formatVersion: 1,
            catalogVersion: version,
            contentRevision: revision,
            parts: [],
            expected: .init(
                foods: 1,
                exercises: 1,
                yogaSequences: 1,
                practices: 1,
                practiceCues: 0,
                ayurvedaProfiles: 0,
                ayurvedaLinks: 0,
                vitamins: 1,
                minerals: 1,
                productBuckets: 0,
                vocabularyEntries: 0,
                searchCaches: 0
            )
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw SmokeError.failed(message) }
    }
}
#endif
