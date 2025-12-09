// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Main/DBSeed/DatabaseSetup.swift ====
import SwiftData
import Foundation

@MainActor
struct DatabaseSetup {
    
    static func createContainer() -> ModelContainer {
        let schema = Schema([
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
            Node.self, SearchIndexCache.self
        ])
        
        do {
            let fileManager = FileManager.default
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            print("🚀 SwiftData Path: \(applicationSupportURL.path())")
            
            // 1. Основна (потребителска) база данни - Writable
            let writableStoreURL = applicationSupportURL.appendingPathComponent("default.store")
            let writableConfiguration = ModelConfiguration("Default", schema: schema, url: writableStoreURL, allowsSave: true)
            
            let usePreSeededDatabaseCopy = false
            
            if usePreSeededDatabaseCopy {
                print("🏁 Using Pre-Seeded Logic: Attempting Separate Read-Only Store strategy.")
                
                let readOnlyStoreURL = applicationSupportURL.appendingPathComponent("preseeded_reference.store")
                
                if !fileManager.fileExists(atPath: readOnlyStoreURL.path) {
                    print("📦 Preparing reference database...")
                    do {
                        try PreseedLoader.preparePreseededStore(to: readOnlyStoreURL)
                        print("✅ Reference database prepared.")
                    } catch {
                        print("❌ Failed to prepare reference DB: \(error). Fallback to Single Store.")
                        return try ModelContainer(for: schema, configurations: [writableConfiguration])
                    }
                }
                
                // ПРОМЯНА ТУК: Слагаме allowsSave: true
                // SwiftData има нужда от права за писане, за да управлява WAL/SHM файловете при отваряне.
                // Ние логически няма да пишем нови данни там (SeedManager ще ги пропусне).
                let referenceConfiguration = ModelConfiguration("Reference", schema: schema, url: readOnlyStoreURL, allowsSave: true)
                
                do {
                    // Опитваме да заредим и двете
                    let container = try ModelContainer(for: schema, configurations: [writableConfiguration, referenceConfiguration])
                    print("✅ Dual-Store Container loaded successfully.")
                    return container
                } catch {
                    print("⚠️ CRITICAL: Dual-Store load failed: \(error).")
                    print("🔄 FALLBACK: Loading Single Writable Store (Legacy Mode).")
                    return try ModelContainer(for: schema, configurations: [writableConfiguration])
                }
                
            } else {
                print("🏁 Logic: Single Writable Store (Flag is false).")
                return try ModelContainer(for: schema, configurations: [writableConfiguration])
            }
            
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }
}
