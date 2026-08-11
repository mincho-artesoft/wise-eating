// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/AyurvedaAsanaYoga-clean/AyurvedaAsanaYoga/Main/DBSeed/DatabaseSetup.swift ====
import SwiftData
import Foundation
import os

enum AyurvedaAsanaYogaLaunchProbe {
    private static let signpostLog = OSLog(
        subsystem: "AyurvedaAsanaYoga.Arte-Soft",
        category: .pointsOfInterest
    )
    private static let isEnabled = ProcessInfo.processInfo.arguments.contains(
        "-ayurvedaasanayogaLaunchProfile"
    )

    static func event(_ name: StaticString) {
        guard isEnabled else { return }
        os_signpost(.event, log: signpostLog, name: name)
        print(
            "AYURVEDAASANAYOGA_PROFILE|\(name)|"
                + String(format: "%.6f", ProcessInfo.processInfo.systemUptime)
        )
    }
}

@MainActor
struct DatabaseSetup {
    
    static func createContainer() -> ModelContainer {
        AyurvedaAsanaYogaLaunchProbe.event("database-setup-begin")
        // 1. Дефинираме типовете за ОСНОВНАТА база (AyurvedaAsanaYoga.store)
        let mainTypes: [any PersistentModel.Type] = [
            Profile.self, UserSettings.self,
            FoodItem.self, Mineral.self,
            Vitamin.self, Meal.self,
            StorageItem.self, StorageTransaction.self,
            MealLogStorageLink.self, WeightHeightRecord.self,
            ShoppingListItem.self, ShoppingListModel.self,
            RecentlyAddedFood.self, DismissedFoodID.self,
            AminoAcidsData.self, CarbDetailsData.self,
            SterolsData.self,
            WaterLog.self, MealPlanEntry.self,
            MealPlan.self, MealPlanDay.self,
            MealPlanMeal.self, Training.self,
            ExerciseItem.self, ExercisePhoto.self, YogaSequence.self,
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
        
        // Създаваме единствената схема на приложението.
        let mainSchema = Schema(mainTypes)

        do {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            print("🚀 SwiftData Path: \(appSupportURL.path())")
            
            // Основна база
            let mainStoreURL = appSupportURL.appendingPathComponent("AyurvedaAsanaYoga.store")
            let mainConfig = ModelConfiguration(
                "AyurvedaAsanaYogaDefault",
                schema: mainSchema,
                url: mainStoreURL
            )
            removeObsoleteTemplateStore(from: appSupportURL)
            
            // --- Логика за копиране на Pre-seeded база ---
            let usePreSeededDatabaseCopy = true
            
            // Използваме ключ, за да копираме само веднъж при първо стартиране на тази версия
            let didCopyDatabaseKey = "AyurvedaAsanaYoga_DidCopyPreSeededDatabase_v1"

            AyurvedaAsanaYogaLaunchProbe.event("preseed-check-begin")
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
                    // PreseedLoader подготвя AyurvedaAsanaYoga.store от архивирания seed.
                    try PreseedLoader.preparePreseededStore(to: mainStoreURL)
                    print("✅ Successfully prepared pre-seeded MAIN database.")
                } catch {
                    print("❌ Failed to prepare pre-seeded MAIN database: \(error). Using empty DB.")
                }
                
                // Маркираме, че сме приключили с първоначалното зареждане
                UserDefaults.standard.set(true, forKey: didCopyDatabaseKey)
                
            } else if usePreSeededDatabaseCopy {
                print("🏁 Database already pre-seeded in a previous launch. Skipping copy.")
            }
            AyurvedaAsanaYogaLaunchProbe.event("preseed-check-end")
            
            // Създаваме контейнера само с основната конфигурация.
            AyurvedaAsanaYogaLaunchProbe.event("model-container-open-begin")
            let container = try ModelContainer(
                for: mainSchema,
                configurations: [mainConfig]
            )
            AyurvedaAsanaYogaLaunchProbe.event("model-container-open-end")
            return container
            
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    private static func removeObsoleteTemplateStore(from directory: URL) {
        let baseName = "AyurvedaAsanaYogaTemplates.store"
        let fileManager = FileManager.default
        for filename in [baseName, baseName + "-wal", baseName + "-shm"] {
            let url = directory.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
                print("🧹 Removed obsolete training-plan template store: \(filename)")
            } catch {
                print("⚠️ Could not remove obsolete template store \(filename): \(error)")
            }
        }
    }
}
