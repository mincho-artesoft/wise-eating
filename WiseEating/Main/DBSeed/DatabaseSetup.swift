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
            TrainingPlanSet.self,
            AyurvedaProfile.self, AyurvedaLink.self
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
            
            // Конфигурация 1: Основна база
            let mainStoreURL = appSupportURL.appendingPathComponent("default.store")
            let mainConfig = ModelConfiguration(
                "Default",
                schema: mainSchema,
                url: mainStoreURL
            )

            // Конфигурация 2: Темплейти
            let templateStoreURL = appSupportURL.appendingPathComponent("templates.store")
            let templateConfig = ModelConfiguration(
                "Templates",
                schema: templateSchema,
                url: templateStoreURL
            )
            
            // --- Логика за копиране на Pre-seeded база ---
            let usePreSeededDatabaseCopy = true
            
            // Използваме ключ, за да копираме само веднъж при първо стартиране на тази версия
            let didCopyDatabaseKey = "didCopyPreSeededDatabase_v1"

            if usePreSeededDatabaseCopy && !UserDefaults.standard.bool(forKey: didCopyDatabaseKey) {
                print("🏁 First launch with pre-seed logic. Preparing to copy databases…")
                let fm = FileManager.default

                // =====================================================
                // 1. MAIN STORE COPY (Архивирана или обикновена)
                // =====================================================
                // Почистване на дестинацията за Main Store
                let mainDir = mainStoreURL.deletingLastPathComponent()
                let mainBase = mainStoreURL.lastPathComponent
                let mainWal = mainDir.appendingPathComponent(mainBase + "-wal")
                let mainShm = mainDir.appendingPathComponent(mainBase + "-shm")
                
                for fileURL in [mainStoreURL, mainWal, mainShm] {
                    if fm.fileExists(atPath: fileURL.path) {
                        try? fm.removeItem(at: fileURL)
                    }
                }

                do {
                    // PreseedLoader се грижи за default.store (обикновено .gz)
                    try PreseedLoader.preparePreseededStore(to: mainStoreURL)
                    print("✅ Successfully prepared pre-seeded MAIN database.")
                } catch {
                    print("❌ Failed to prepare pre-seeded MAIN database: \(error). Using empty DB.")
                }
                
                // =====================================================
                // 2. TEMPLATES STORE COPY (Директно копиране)
                // =====================================================
                // Търсим файл "templates.store" в Bundle-а на приложението
                if let bundleTemplateURL = Bundle.main.url(forResource: "templates", withExtension: "store") {
                    print("📄 Found pre-seeded 'templates.store' in Bundle. Copying...")
                    
                    // Почистване на дестинацията за Templates Store
                    // Важно е да изтрием и WAL/SHM файловете, за да не се получи корупция
                    let tBase = templateStoreURL.lastPathComponent
                    let tWal = appSupportURL.appendingPathComponent(tBase + "-wal")
                    let tShm = appSupportURL.appendingPathComponent(tBase + "-shm")
                    
                    for fileURL in [templateStoreURL, tWal, tShm] {
                        if fm.fileExists(atPath: fileURL.path) {
                            try? fm.removeItem(at: fileURL)
                        }
                    }
                    
                    do {
                        // Директно копиране
                        try fm.copyItem(at: bundleTemplateURL, to: templateStoreURL)
                        print("✅ Successfully copied pre-seeded TEMPLATES database.")
                    } catch {
                        print("❌ Failed to copy templates.store: \(error)")
                    }
                } else {
                    print("⚠️ 'templates.store' not found in Bundle resources. Skipping templates seed.")
                }

                // Маркираме, че сме приключили с първоначалното зареждане
                UserDefaults.standard.set(true, forKey: didCopyDatabaseKey)
                
            } else if usePreSeededDatabaseCopy {
                print("🏁 Database already pre-seeded in a previous launch. Skipping copy.")
            }
            
            // Създаваме контейнера с двете именувани конфигурации
            return try ModelContainer(for: fullSchema, configurations: [mainConfig, templateConfig])
            
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }
}
