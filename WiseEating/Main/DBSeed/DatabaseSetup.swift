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
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            print("🚀 SwiftData Path: \(applicationSupportURL.path())")
            
            let storeURL = applicationSupportURL.appendingPathComponent("default.store")
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            
            let usePreSeededDatabaseCopy = true
            let didCopyDatabaseKey = "didCopyPreSeededDatabase_v1"

            if usePreSeededDatabaseCopy && !UserDefaults.standard.bool(forKey: didCopyDatabaseKey) {
                print("🏁 First launch with pre-seed logic. Preparing to copy database…")

                // Ensure a clean destination (store + -wal + -shm)
                let dir = storeURL.deletingLastPathComponent()
                let base = storeURL.lastPathComponent
                let walURL = dir.appendingPathComponent(base + "-wal")
                let shmURL = dir.appendingPathComponent(base + "-shm")
                for fileURL in [storeURL, walURL, shmURL] {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        do {
                            try FileManager.default.removeItem(at: fileURL)
                            print("🧹 Removed existing file: \(fileURL.lastPathComponent)")
                        } catch {
                            fatalError("❌ Failed to remove existing database file \(fileURL.lastPathComponent): \(error)")
                        }
                    }
                }

                do {
                    try PreseedLoader.preparePreseededStore(to: storeURL)
                    print("✅ Successfully prepared (combined + decompressed) pre-seeded database.")
                    UserDefaults.standard.set(true, forKey: didCopyDatabaseKey)
                } catch {
                    fatalError("❌ Failed to prepare pre-seeded database: \(error)")
                }
            } else if usePreSeededDatabaseCopy {
                print("🏁 Database already pre-seeded. Skipping copy.")
            }
            
            return try ModelContainer(for: schema, configurations: [configuration])
            
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }
}
