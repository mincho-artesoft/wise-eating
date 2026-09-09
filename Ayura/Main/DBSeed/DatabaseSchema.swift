import SwiftData

enum DatabaseSchema {
    /// Configuration names are part of Core Data's store model metadata.
    /// Every open of a given store must use the same name, otherwise a
    /// read-only catalogue can be mistaken for a store needing migration.
    static let catalogConfigurationName = "AyurvedaAsanaYogaCatalog"
    static let userConfigurationName = "AyurvedaAsanaYogaUser"

    /// Models that contain shipped catalogue rows. Keeping user-only entities
    /// out of this configuration gives them an unambiguous writable store.
    static let catalogTypes: [any PersistentModel.Type] = [
        FoodItem.self, Mineral.self,
        Vitamin.self,
        AminoAcidsData.self, CarbDetailsData.self,
        SterolsData.self,
        ExerciseItem.self, ExercisePhoto.self, YogaSequence.self,
        Practice.self, PracticeCue.self,
        ExerciseLink.self,
        ProductBucket.self, VocabularyEntry.self,
        SearchIndexCache.self,
        Requirement.self,
        FoodPhoto.self, IngredientLink.self,
        LipidsData.self, MacronutrientsData.self,
        MineralsData.self, OtherCompoundsData.self,
        VitaminsData.self,
        AyurvedaProfile.self, AyurvedaLink.self,
    ]

    static let userTypes: [any PersistentModel.Type] = catalogTypes + [
        Profile.self, UserSettings.self,
        Meal.self,
        StorageItem.self, StorageTransaction.self,
        MealLogStorageLink.self, WeightHeightRecord.self,
        ShoppingListItem.self, ShoppingListModel.self,
        RecentlyAddedFood.self, DismissedFoodID.self,
        WaterLog.self, MealPlanEntry.self,
        MealPlan.self, MealPlanDay.self,
        MealPlanMeal.self, Training.self,
        PracticeSession.self,
        AIGenerationJob.self,
        TrainingPlan.self, TrainingPlanDay.self,
        TrainingPlanWorkout.self, TrainingPlanExercise.self,
        Node.self,
        Prompt.self,
        Batch.self,
        TrainingPlanSet.self,
        CatalogMigrationState.self,
        CatalogPreference.self,
    ]

    static let catalog = Schema(catalogTypes)
    static let user = Schema(userTypes)
    static let combined = Schema(userTypes)
}
