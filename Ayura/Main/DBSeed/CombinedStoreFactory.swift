import Foundation
import SwiftData

/// Opens the read-only catalogue and writable user databases in one container.
///
/// SwiftData exposes configurations as an unordered `Set`, while overlapping
/// entity schemas send a new object to the last configuration in that set. The
/// user URL is expressed through an equivalent `..` path so its hash can vary;
/// candidates are accepted only after a real insert/save/delete probe proves
/// writable-store routing. An unverified container is never returned to the app.
@MainActor
enum CombinedStoreFactory {
    private static let maximumAttempts = 128
    private static var cachedUserWriteContainer: ModelContainer?
    private static var cachedUserWriteURL: URL?

    /// Creates an unambiguous write context for user-owned shared models.
    /// The main app container mounts both stores for combined reads, but
    /// SwiftData does not expose an API for selecting the destination
    /// configuration of an insert. A single-configuration container removes
    /// that ambiguity while writing the same user SQLite store.
    static func makeUserWriteContext(
        from combinedContainer: ModelContainer
    ) throws -> ModelContext {
        guard let userConfiguration = combinedContainer.configurations.first(
            where: { $0.name == DatabaseSchema.userConfigurationName }
        ) else {
            throw CombinedStoreError.missingUserConfiguration
        }
        let writeContainer: ModelContainer
        if cachedUserWriteURL == userConfiguration.url,
           let cachedUserWriteContainer {
            writeContainer = cachedUserWriteContainer
        } else {
            writeContainer = try ModelContainer(
                for: DatabaseSchema.user,
                configurations: [userConfiguration]
            )
            cachedUserWriteURL = userConfiguration.url
            cachedUserWriteContainer = writeContainer
        }
        let context = ModelContext(writeContainer)
        context.autosaveEnabled = false
        return context
    }

    static func makeContainer(
        schema: Schema,
        userSchema: Schema,
        catalogSchema: Schema,
        userStoreURL: URL,
        catalogStoreURL: URL
    ) throws -> ModelContainer {
        let parent = userStoreURL.deletingLastPathComponent()
        let routingRoot = parent
            .appendingPathComponent(".swiftdata-store-routes", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: routingRoot,
            withIntermediateDirectories: true
        )

        for attempt in 0..<maximumAttempts {
            let routeDirectory = routingRoot.appendingPathComponent(
                "route-\(attempt)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: routeDirectory,
                withIntermediateDirectories: true
            )
            let userAliasURL = routeDirectory.appendingPathComponent(
                "../../../\(userStoreURL.lastPathComponent)"
            )

            let userConfiguration = ModelConfiguration(
                DatabaseSchema.userConfigurationName,
                schema: userSchema,
                url: userAliasURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let catalogConfiguration = ModelConfiguration(
                DatabaseSchema.catalogConfigurationName,
                schema: catalogSchema,
                url: catalogStoreURL,
                allowsSave: false,
                cloudKitDatabase: .none
            )

            // ModelContainer internally exposes configurations as a Set and
            // assigns an overlapping model to the last matching entry. Avoid
            // opening both SQLite files and running a write probe for aliases
            // whose in-process Set order already ends in the catalogue.
            let configurationOrder = Array(Set([
                catalogConfiguration,
                userConfiguration,
            ]))
            guard configurationOrder.last?.name
                    == DatabaseSchema.userConfigurationName else {
                continue
            }

            let container = try ModelContainer(
                for: schema,
                configurations: [catalogConfiguration, userConfiguration]
            )

            do {
                try verifyWritableRouting(in: container)
                if ProcessInfo.processInfo.arguments.contains(
                    "-catalogSeparationSmokeTest"
                ) {
                    print("WRITE_ROUTING|PASS|attempt=\(attempt)")
                }
                return container
            } catch {
                // The candidate container is discarded without ever modifying
                // the read-only catalogue; try another equivalent user URL.
                if ProcessInfo.processInfo.arguments.contains(
                    "-catalogSeparationSmokeTest"
                ) {
                    print("WRITE_ROUTING|RETRY|attempt=\(attempt)|\(error)")
                }
                continue
            }
        }

        throw CombinedStoreError.couldNotRouteWrites
    }

    private static func verifyWritableRouting(
        in container: ModelContainer
    ) throws {
        let context = container.mainContext
        context.autosaveEnabled = false
        let token = UUID().uuidString
        guard let userStoreIdentifier = try context.fetch(
            FetchDescriptor<CatalogMigrationState>()
        ).first?.persistentModelID.storeIdentifier else {
            throw CombinedStoreError.missingUserStoreIdentifier
        }

        do {
            // Match FoodItemEditorView exactly: insert only the root first and
            // let SwiftData discover the newly assigned nutrient graph. This
            // is deliberately different from explicitly inserting every
            // child; SwiftData can route the two transaction shapes to
            // different stores when configurations overlap.
            let food = FoodItem(
                name: "Write Routing Editor Food \(token)",
                isUserAdded: true
            )
            context.insert(food)
            let macronutrients = MacronutrientsData()
            let lipids = LipidsData()
            let vitamins = VitaminsData()
            let minerals = MineralsData()
            let other = OtherCompoundsData()
            let aminoAcids = AminoAcidsData()
            let carbDetails = CarbDetailsData()
            let sterols = SterolsData()
            food.macronutrients = macronutrients
            food.lipids = lipids
            food.vitamins = vitamins
            food.minerals = minerals
            food.other = other
            food.aminoAcids = aminoAcids
            food.carbDetails = carbDetails
            food.sterols = sterols
            macronutrients.foodItem = food
            lipids.foodItem = food
            vitamins.foodItem = food
            minerals.foodItem = food
            other.foodItem = food
            aminoAcids.foodItem = food
            carbDetails.foodItem = food
            sterols.foodItem = food
            try context.save()
            let identifiers = [
                food.persistentModelID.storeIdentifier,
                macronutrients.persistentModelID.storeIdentifier,
                lipids.persistentModelID.storeIdentifier,
                vitamins.persistentModelID.storeIdentifier,
                minerals.persistentModelID.storeIdentifier,
                other.persistentModelID.storeIdentifier,
                aminoAcids.persistentModelID.storeIdentifier,
                carbDetails.persistentModelID.storeIdentifier,
                sterols.persistentModelID.storeIdentifier,
            ]
            guard identifiers.allSatisfy({ $0 == userStoreIdentifier }) else {
                throw CombinedStoreError.misroutedWrite
            }

            // Match editing an existing food without replacing its persisted
            // one-to-one children. Replacing those objects can leave Core Data
            // holding a retired object ID; the production editor updates the
            // existing graph in place for this reason.
            food.name = "Write Routing Edited Food \(token)"
            macronutrients.carbohydrates = Nutrient(value: 1, unit: "g")
            other.energyKcal = Nutrient(value: 2, unit: "kcal")
            try context.save()
            guard food.persistentModelID.storeIdentifier == userStoreIdentifier,
                  macronutrients.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  other.persistentModelID.storeIdentifier
                    == userStoreIdentifier else {
                throw CombinedStoreError.misroutedWrite
            }
            context.delete(food)
            try context.save()

            // Probe the independent Ayurveda row before combining it with a
            // recipe graph below. If it is routed to the catalogue, no food
            // transaction has been partially committed in the user store.
            let ayurveda = makeRoutingAyurveda(
                token: token,
                foodID: UUID()
            )
            context.insert(ayurveda)
            try context.save()
            guard ayurveda.persistentModelID.storeIdentifier
                    == userStoreIdentifier else {
                throw CombinedStoreError.misroutedWrite
            }
            context.delete(ayurveda)
            try context.save()

            // Match ExerciseItemEditorView, including implicitly inserted
            // gallery children.
            let exercise = ExerciseItem(
                name: "Write Routing Editor Exercise \(token)",
                isUserAdded: true,
                muscleGroups: [.abs]
            )
            context.insert(exercise)
            let exercisePhoto = ExercisePhoto(data: Data())
            exercise.gallery = [exercisePhoto]
            try context.save()
            guard exercise.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  exercisePhoto.persistentModelID.storeIdentifier
                    == userStoreIdentifier else {
                throw CombinedStoreError.misroutedWrite
            }
            context.delete(exercise)
            try context.save()

            // Recipe/workout editors create link graphs, so verify those as
            // separate transactions too.
            let ingredientFood = FoodItem(
                name: "Write Routing Ingredient \(token)",
                isUserAdded: true
            )
            let recipe = FoodItem(
                name: "Write Routing Recipe \(token)",
                isRecipe: true,
                isUserAdded: true
            )
            context.insert(ingredientFood)
            context.insert(recipe)
            let ingredientLink = IngredientLink(
                food: ingredientFood,
                grams: 1,
                owner: recipe
            )
            // This second link has the same persisted shape as a catalogue
            // ingredient: a stable UUID and no cross-store relationship.
            let catalogIngredientLink = IngredientLink(
                food: ingredientFood,
                grams: 2,
                owner: recipe
            )
            catalogIngredientLink.persistedFood = nil
            catalogIngredientLink.catalogFoodID = UUID()
            recipe.ingredients = [ingredientLink, catalogIngredientLink]
            let foodPhoto = FoodPhoto(data: Data())
            recipe.gallery = [foodPhoto]
            let recipeAyurveda = makeRoutingAyurveda(
                token: "recipe-\(token)",
                foodID: recipe.id
            )
            try context.save()
            guard ingredientFood.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  recipe.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  ingredientLink.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  catalogIngredientLink.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  foodPhoto.persistentModelID.storeIdentifier
                    == userStoreIdentifier else {
                throw CombinedStoreError.misroutedWrite
            }
            context.insert(recipeAyurveda)
            try context.save()
            guard recipeAyurveda.persistentModelID.storeIdentifier
                    == userStoreIdentifier else {
                throw CombinedStoreError.misroutedWrite
            }
            context.delete(recipeAyurveda)
            context.delete(recipe)
            context.delete(ingredientFood)
            try context.save()

            let workoutExercise = ExerciseItem(
                name: "Write Routing Workout Exercise \(token)",
                isUserAdded: true,
                muscleGroups: [.abs]
            )
            let workout = ExerciseItem(
                name: "Write Routing Workout \(token)",
                isUserAdded: true,
                muscleGroups: [.abs],
                isWorkout: true
            )
            context.insert(workoutExercise)
            context.insert(workout)
            let exerciseLink = ExerciseLink(
                exercise: workoutExercise,
                durationSeconds: 1,
                owner: workout
            )
            context.insert(exerciseLink)
            workout.exercises = [exerciseLink]
            let catalogExerciseLink = ExerciseLink(
                exercise: workoutExercise,
                durationSeconds: 2,
                owner: workout
            )
            catalogExerciseLink.persistedExercise = nil
            catalogExerciseLink.catalogExerciseID = UUID()
            context.insert(catalogExerciseLink)
            workout.exercises?.append(catalogExerciseLink)
            let workoutPhoto = ExercisePhoto(data: Data())
            workout.gallery = [workoutPhoto]
            try context.save()
            guard workoutExercise.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  workout.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  exerciseLink.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  catalogExerciseLink.persistentModelID.storeIdentifier
                    == userStoreIdentifier,
                  workoutPhoto.persistentModelID.storeIdentifier
                    == userStoreIdentifier else {
                throw CombinedStoreError.misroutedWrite
            }
            context.delete(workout)
            context.delete(workoutExercise)
            try context.save()

            // Search index cache is catalogue-shaped but also written at
            // runtime, so it must route to the user store as well.
            let searchCache = SearchIndexCache(
                key: "write-routing-\(token)",
                payloadData: Data(),
                foodsCount: 0,
                version: -1
            )
            context.insert(searchCache)
            try context.save()
            guard searchCache.persistentModelID.storeIdentifier
                    == userStoreIdentifier else {
                throw CombinedStoreError.misroutedWrite
            }
            context.delete(searchCache)
            try context.save()

            try removeAbandonedRoutingRows(from: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// A multi-store save is not atomic. Older versions of the probe could
    /// leave its user-store half behind when a second model was rejected by
    /// the read-only catalogue. Remove only rows with the private probe prefix.
    private static func removeAbandonedRoutingRows(
        from context: ModelContext
    ) throws {
        let namePrefix = "Write Routing "
        let keyPrefix = "write-routing-"

        let foods = try context.fetch(
            FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.name.starts(with: namePrefix) }
            )
        )
        let exercises = try context.fetch(
            FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.name.starts(with: namePrefix) }
            )
        )
        let ayurvedaProfiles = try context.fetch(
            FetchDescriptor<AyurvedaProfile>(
                predicate: #Predicate { $0.key.starts(with: keyPrefix) }
            )
        )
        let searchCaches = try context.fetch(
            FetchDescriptor<SearchIndexCache>(
                predicate: #Predicate { $0.key.starts(with: keyPrefix) }
            )
        )

        for model in foods { context.delete(model) }
        for model in exercises { context.delete(model) }
        for model in ayurvedaProfiles { context.delete(model) }
        for model in searchCaches { context.delete(model) }
        if context.hasChanges {
            try context.save()
        }
    }

    private static func makeRoutingAyurveda(
        token: String,
        foodID: UUID
    ) -> AyurvedaProfile {
        AyurvedaProfile(
            id: UUID(),
            key: "write-routing-\(token)",
            kind: "user",
            foodId: foodID,
            name: "Write Routing Ayurveda",
            doshaVata: 0,
            doshaPitta: 0,
            doshaKapha: 0,
            seasons: [],
            timeOfDay: [],
            viruddha: [],
            provenance: ["write-routing-probe"],
            confidenceAyur: 0,
            confidenceSci: nil,
            reviewNote: nil,
            seedVersion: -1,
            sanskrit: nil,
            virya: nil,
            vipaka: nil,
            prabhava: nil,
            agniEffect: nil,
            digestibility: nil,
            preparation: nil,
            servingsJSON: nil,
            meal: nil,
            servingsCount: nil,
            prepMinutes: nil,
            cookMinutes: nil,
            guidance: nil
        )
    }
}

private enum CombinedStoreError: Error, LocalizedError {
    case couldNotRouteWrites
    case missingUserConfiguration
    case missingUserStoreIdentifier
    case misroutedWrite

    var errorDescription: String? {
        switch self {
        case .couldNotRouteWrites:
            return "SwiftData could not route new records to the writable user store."
        case .missingUserConfiguration:
            return "The writable user store configuration is unavailable."
        case .missingUserStoreIdentifier:
            return "The writable user store identifier is unavailable."
        case .misroutedWrite:
            return "SwiftData routed a probe record outside the writable user store."
        }
    }
}
