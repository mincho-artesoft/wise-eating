// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Main/DBSeed/DatabaseSetup.swift ====
import SwiftData
import Foundation

@MainActor
struct DatabaseSetup {
    
    static func createContainer() -> ModelContainer {
        // 1. Дефинираме типовете за ОСНОВНАТА база (default.store)
        let mainTypes: [any PersistentModel.Type] = [
            Profile.self, UserSettings.self,
            FoodItem.self, Mineral.self,
            Vitamin.self, Meal.self,
            StorageItem.self, StorageTransaction.self,
            MealLogStorageLink.self, WeightHeightRecord.self,
            ShoppingListItem.self, ShoppingListModel.self,
            RecentlyAddedFood.self, DismissedFoodID.self,
            AminoAcidsData.self, CarbDetailsData.self,
            SterolsData.self, Diet.self,
            WaterLog.self, MealPlanEntry.self,
            MealPlan.self, MealPlanDay.self,
            MealPlanMeal.self, Training.self,
            ExerciseItem.self, ExercisePhoto.self,
            ExerciseLink.self, AIGenerationJob.self,
            TrainingPlan.self, TrainingPlanDay.self,
            TrainingPlanWorkout.self, TrainingPlanExercise.self,
            ProductBucket.self, VocabularyEntry.self,
            Node.self, SearchIndexCache.self,
            Prompt.self, Requirement.self,
            FoodPhoto.self,IngredientLink.self,
            LipidsData.self, MacronutrientsData.self,
            MineralsData.self, OtherCompoundsData.self,
            VitaminsData.self, Batch.self,
            TrainingPlanSet.self
        ]
        
        // 2. Дефинираме типовете за ТЕМПЛЕЙТНАТА база (templates.store)
        let templateTypes: [any PersistentModel.Type] = [
            TemplatePlan.self,
            TemplateDay.self,
            TemplateWorkout.self,
            TemplateExercise.self,
            TemplateSet.self
        ]
        
        // 3. Създаваме отделните схеми
        let mainSchema = Schema(mainTypes)
        let templateSchema = Schema(templateTypes)
        
        // 4. Обединена схема за контейнера
        let fullSchema = Schema(mainTypes + templateTypes)

        do {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            print("🚀 SwiftData Path: \(appSupportURL.path())")
            
            // ---------------------------------------------------------------------
            // ✅ КОРЕКЦИЯТА Е ТУК: Добавяме име ("Default") и ("Templates")
            // ---------------------------------------------------------------------
            
            // Конфигурация 1: Основна база
            let mainStoreURL = appSupportURL.appendingPathComponent("default.store")
            let mainConfig = ModelConfiguration(
                "Default", // <--- ВАЖНО: Име на конфигурацията
                schema: mainSchema,
                url: mainStoreURL
            )

            // Конфигурация 2: Темплейти
            let templateStoreURL = appSupportURL.appendingPathComponent("templates.store")
            let templateConfig = ModelConfiguration(
                "Templates", // <--- ВАЖНО: Име на конфигурацията
                schema: templateSchema,
                url: templateStoreURL
            )
            
            // --- Логика за копиране на Pre-seeded база (само за main store) ---
            let usePreSeededDatabaseCopy = true
            let didCopyDatabaseKey = "didCopyPreSeededDatabase_v1"

            if usePreSeededDatabaseCopy && !UserDefaults.standard.bool(forKey: didCopyDatabaseKey) {
                print("🏁 First launch with pre-seed logic. Preparing to copy database…")

                // Ensure a clean destination for main store
                let dir = mainStoreURL.deletingLastPathComponent()
                let base = mainStoreURL.lastPathComponent
                let walURL = dir.appendingPathComponent(base + "-wal")
                let shmURL = dir.appendingPathComponent(base + "-shm")
                for fileURL in [mainStoreURL, walURL, shmURL] {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }

                do {
                    try PreseedLoader.preparePreseededStore(to: mainStoreURL)
                    print("✅ Successfully prepared pre-seeded database.")
                    UserDefaults.standard.set(true, forKey: didCopyDatabaseKey)
                } catch {
                    print("❌ Failed to prepare pre-seeded database: \(error). Using empty DB.")
                }
            } else if usePreSeededDatabaseCopy {
                print("🏁 Database already pre-seeded. Skipping copy.")
            }
            
            // Създаваме контейнера с двете именувани конфигурации
            return try ModelContainer(for: fullSchema, configurations: [mainConfig, templateConfig])
            
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }
}
