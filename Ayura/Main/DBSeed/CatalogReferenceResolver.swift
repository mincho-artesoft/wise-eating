import Foundation
import SwiftData

enum CatalogReferenceError: LocalizedError {
    case missingUserProfile(UUID)
    case missingUserFood(UUID)
    case missingUserExercise(UUID)
    case missingUserMealPlan(UUID)
    case missingUserTrainingPlan(UUID)

    var errorDescription: String? {
        switch self {
        case .missingUserProfile:
            return "The active profile could not be found in the user database."
        case .missingUserFood:
            return "A selected user food could not be found. Please select it again."
        case .missingUserExercise:
            return "A selected user exercise could not be found. Please select it again."
        case .missingUserMealPlan:
            return "The meal plan could not be found in the user database."
        case .missingUserTrainingPlan:
            return "The training plan could not be found in the user database."
        }
    }
}

enum CatalogReferenceResolver {
    nonisolated(unsafe) private(set) static var catalogStoreIdentifier: String?

    static func configure(catalogStoreIdentifier: String) {
        self.catalogStoreIdentifier = catalogStoreIdentifier
    }

    static func isCatalog<T: PersistentModel>(_ model: T) -> Bool {
        guard let catalogStoreIdentifier else { return false }
        return model.persistentModelID.storeIdentifier == catalogStoreIdentifier
    }

    static func storedFoodReference(
        for food: FoodItem?
    ) -> (stored: FoodItem?, catalogID: UUID?) {
        guard let food else { return (nil, nil) }
        return isCatalog(food) ? (nil, food.id) : (food, nil)
    }

    static func storedExerciseReference(
        for exercise: ExerciseItem?
    ) -> (stored: ExerciseItem?, catalogID: UUID?) {
        guard let exercise else { return (nil, nil) }
        return isCatalog(exercise) ? (nil, exercise.id) : (exercise, nil)
    }

    static func userFood(
        id: UUID,
        context: ModelContext
    ) throws -> FoodItem? {
        var descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func userProfile(
        id: UUID,
        context: ModelContext
    ) throws -> Profile? {
        var descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func userExercise(
        id: UUID,
        context: ModelContext
    ) throws -> ExerciseItem? {
        var descriptor = FetchDescriptor<ExerciseItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func userMealPlan(
        id: UUID,
        context: ModelContext
    ) throws -> MealPlan? {
        var descriptor = FetchDescriptor<MealPlan>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func userTrainingPlan(
        id: UUID,
        context: ModelContext
    ) throws -> TrainingPlan? {
        var descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func ingredientLink(
        for source: FoodItem,
        grams: Double,
        owner: FoodItem,
        userContext: ModelContext
    ) throws -> IngredientLink {
        if isCatalog(source) {
            return IngredientLink(
                persistedFood: nil,
                catalogFoodID: source.id,
                grams: grams,
                owner: owner
            )
        }
        guard let userFood = try userFood(id: source.id, context: userContext) else {
            throw CatalogReferenceError.missingUserFood(source.id)
        }
        return IngredientLink(
            persistedFood: userFood,
            catalogFoodID: nil,
            grams: grams,
            owner: owner
        )
    }

    static func exerciseLink(
        for source: ExerciseItem,
        durationSeconds: Double,
        owner: ExerciseItem,
        userContext: ModelContext
    ) throws -> ExerciseLink {
        if isCatalog(source) {
            return ExerciseLink(
                persistedExercise: nil,
                catalogExerciseID: source.id,
                durationSeconds: durationSeconds,
                owner: owner
            )
        }
        guard let userExercise = try userExercise(
            id: source.id,
            context: userContext
        ) else {
            throw CatalogReferenceError.missingUserExercise(source.id)
        }
        return ExerciseLink(
            persistedExercise: userExercise,
            catalogExerciseID: nil,
            durationSeconds: durationSeconds,
            owner: owner
        )
    }

    static func mealPlanEntry(
        for source: FoodItem,
        grams: Double,
        meal: MealPlanMeal,
        userContext: ModelContext
    ) throws -> MealPlanEntry {
        if isCatalog(source) {
            return MealPlanEntry(food: source, grams: grams, meal: meal)
        }
        guard let userFood = try userFood(id: source.id, context: userContext) else {
            throw CatalogReferenceError.missingUserFood(source.id)
        }
        return MealPlanEntry(food: userFood, grams: grams, meal: meal)
    }

    static func trainingPlanExercise(
        for source: ExerciseItem,
        durationSeconds: Double,
        workout: TrainingPlanWorkout,
        userContext: ModelContext
    ) throws -> TrainingPlanExercise {
        if isCatalog(source) {
            return TrainingPlanExercise(
                exercise: source,
                durationSeconds: durationSeconds,
                workout: workout
            )
        }
        guard let userExercise = try userExercise(
            id: source.id,
            context: userContext
        ) else {
            throw CatalogReferenceError.missingUserExercise(source.id)
        }
        return TrainingPlanExercise(
            exercise: userExercise,
            durationSeconds: durationSeconds,
            workout: workout
        )
    }

    /// Returns a food value that can safely be handed to a user-store model
    /// initializer. Catalogue foods are converted to scalar UUIDs by the
    /// model; user foods must first be refetched in the destination context.
    static func foodForUserWrite(
        _ source: FoodItem,
        userContext: ModelContext
    ) throws -> FoodItem {
        if isCatalog(source) {
            return source
        }
        guard let food = try userFood(id: source.id, context: userContext) else {
            throw CatalogReferenceError.missingUserFood(source.id)
        }
        return food
    }

    /// Returns an exercise that is safe to reference from a user-store model.
    /// Catalogue exercises are represented by their UUID by the destination
    /// model; user exercises have to be fetched in the destination context.
    static func exerciseForUserWrite(
        _ source: ExerciseItem,
        userContext: ModelContext
    ) throws -> ExerciseItem {
        if isCatalog(source) {
            return source
        }
        guard let exercise = try userExercise(
            id: source.id,
            context: userContext
        ) else {
            throw CatalogReferenceError.missingUserExercise(source.id)
        }
        return exercise
    }

    static func shoppingListItem(
        for source: FoodItem?,
        name: String,
        quantity: Double,
        price: Double?,
        isBought: Bool,
        list: ShoppingListModel,
        userContext: ModelContext
    ) throws -> ShoppingListItem {
        let writableFood = try source.map {
            try foodForUserWrite($0, userContext: userContext)
        }
        let item = ShoppingListItem(
            name: name,
            quantity: quantity,
            price: price,
            isBought: isBought,
            foodItem: writableFood
        )
        item.list = list
        return item
    }

    static func storageItem(
        for source: FoodItem,
        owner: Profile?,
        userContext: ModelContext
    ) throws -> StorageItem {
        let writableFood = try foodForUserWrite(
            source,
            userContext: userContext
        )
        return StorageItem(owner: owner, food: writableFood)
    }

    static func storageTransaction(
        for source: FoodItem?,
        date: Date,
        type: TransactionType,
        quantityChange: Double,
        profile: Profile?,
        userContext: ModelContext
    ) throws -> StorageTransaction {
        let writableFood = try source.map {
            try foodForUserWrite($0, userContext: userContext)
        }
        return StorageTransaction(
            date: date,
            type: type,
            quantityChange: quantityChange,
            profile: profile,
            food: writableFood
        )
    }

    static func resolveFood(
        stored: FoodItem?,
        catalogID: UUID?
    ) -> FoodItem? {
        if let stored { return stored }
        guard let catalogID, let context = GlobalState.modelContext else { return nil }
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.id == catalogID }
        )
        return (try? context.fetch(descriptor))?.first(where: isCatalog)
    }

    static func resolveExercise(
        stored: ExerciseItem?,
        catalogID: UUID?
    ) -> ExerciseItem? {
        if let stored { return stored }
        guard let catalogID, let context = GlobalState.modelContext else { return nil }
        let descriptor = FetchDescriptor<ExerciseItem>(
            predicate: #Predicate { $0.id == catalogID }
        )
        return (try? context.fetch(descriptor))?.first(where: isCatalog)
    }

    static func resolveVitamin(id: UUID) -> Vitamin? {
        guard let context = GlobalState.modelContext else { return nil }
        let descriptor = FetchDescriptor<Vitamin>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first(where: isCatalog)
    }

    static func resolveMineral(id: UUID) -> Mineral? {
        guard let context = GlobalState.modelContext else { return nil }
        let descriptor = FetchDescriptor<Mineral>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first(where: isCatalog)
    }

    static func splitVitamins(
        _ vitamins: [Vitamin]
    ) -> (stored: [Vitamin], catalogIDs: [UUID]) {
        var stored: [Vitamin] = []
        var catalogIDs: [UUID] = []
        for vitamin in vitamins {
            if isCatalog(vitamin) {
                catalogIDs.append(vitamin.id)
            } else {
                stored.append(vitamin)
            }
        }
        return (stored, catalogIDs)
    }

    static func splitMinerals(
        _ minerals: [Mineral]
    ) -> (stored: [Mineral], catalogIDs: [UUID]) {
        var stored: [Mineral] = []
        var catalogIDs: [UUID] = []
        for mineral in minerals {
            if isCatalog(mineral) {
                catalogIDs.append(mineral.id)
            } else {
                stored.append(mineral)
            }
        }
        return (stored, catalogIDs)
    }

    static func resolveVitamins(stored: [Vitamin], catalogIDs: [UUID]) -> [Vitamin] {
        stored + catalogIDs.compactMap(resolveVitamin)
    }

    static func resolveMinerals(stored: [Mineral], catalogIDs: [UUID]) -> [Mineral] {
        stored + catalogIDs.compactMap(resolveMineral)
    }

    static func splitFoods(
        _ foods: [FoodItem]
    ) -> (stored: [FoodItem], catalogIDs: [UUID]) {
        var stored: [FoodItem] = []
        var catalogIDs: [UUID] = []
        for food in foods {
            if isCatalog(food) {
                catalogIDs.append(food.id)
            } else {
                stored.append(food)
            }
        }
        return (stored, catalogIDs)
    }

    static func splitExercises(
        _ exercises: [ExerciseItem]
    ) -> (stored: [ExerciseItem], catalogIDs: [UUID]) {
        var stored: [ExerciseItem] = []
        var catalogIDs: [UUID] = []
        for exercise in exercises {
            if isCatalog(exercise) {
                catalogIDs.append(exercise.id)
            } else {
                stored.append(exercise)
            }
        }
        return (stored, catalogIDs)
    }

    static func resolveFoods(stored: [FoodItem], catalogIDs: [UUID]) -> [FoodItem] {
        guard !catalogIDs.isEmpty, let context = GlobalState.modelContext else {
            return stored
        }
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { catalogIDs.contains($0.id) }
        )
        let catalog = ((try? context.fetch(descriptor)) ?? []).filter(isCatalog)
        return stored + catalog
    }

    static func resolveExercises(
        stored: [ExerciseItem],
        catalogIDs: [UUID]
    ) -> [ExerciseItem] {
        guard !catalogIDs.isEmpty, let context = GlobalState.modelContext else {
            return stored
        }
        let descriptor = FetchDescriptor<ExerciseItem>(
            predicate: #Predicate { catalogIDs.contains($0.id) }
        )
        let catalog = ((try? context.fetch(descriptor)) ?? []).filter(isCatalog)
        return stored + catalog
    }
}
