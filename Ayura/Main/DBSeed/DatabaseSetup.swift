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
        do {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            print("🚀 SwiftData Path: \(appSupportURL.path())")
            
            // The existing path becomes the writable user store. Keeping the
            // path lets an installed app migrate in place without losing data.
            let userStoreURL = appSupportURL.appendingPathComponent(
                "AyurvedaAsanaYoga.store"
            )
            let hadLegacyStore = FileManager.default.fileExists(
                atPath: userStoreURL.path
            )
            removeObsoleteTemplateStore(from: appSupportURL)

            AyurvedaAsanaYogaLaunchProbe.event("preseed-check-begin")
            let preparedCatalog = try CatalogStoreManager.prepareCatalog(
                in: appSupportURL
            )
            let catalogStoreIdentifier = try CatalogStoreManager.storeIdentifier(
                at: preparedCatalog.storeURL
            )
            CatalogReferenceResolver.configure(
                catalogStoreIdentifier: catalogStoreIdentifier
            )

            let separation = try LegacyStoreSeparator.prepareUserStore(
                at: userStoreURL,
                catalogStoreURL: preparedCatalog.storeURL,
                manifest: preparedCatalog.manifest,
                hadLegacyStore: hadLegacyStore
            )
            if separation.performedMigration {
                print(
                    "✅ Catalog/user separation complete: "
                        + "food refs=\(separation.migratedFoodReferences), "
                        + "exercise refs=\(separation.migratedExerciseReferences), "
                        + "preferences=\(separation.preservedPreferences), "
                        + "removed catalog rows=\(separation.removedCatalogObjects)."
                )
            } else if preparedCatalog.installedNewCatalog {
                print("✅ Catalog replaced atomically; user store was not reseeded.")
            } else {
                print("🏁 Catalog and user store are already current.")
            }
            AyurvedaAsanaYogaLaunchProbe.event("preseed-check-end")

            AyurvedaAsanaYogaLaunchProbe.event("model-container-open-begin")
            let container = try CombinedStoreFactory.makeContainer(
                schema: DatabaseSchema.combined,
                userSchema: DatabaseSchema.user,
                catalogSchema: DatabaseSchema.catalog,
                userStoreURL: userStoreURL,
                catalogStoreURL: preparedCatalog.storeURL
            )
            // The new store is now proven mountable. Older immutable versions
            // are no longer needed and can otherwise consume hundreds of MB
            // per application update.
            CatalogStoreManager.removeObsoleteVersions(
                in: appSupportURL,
                keeping: preparedCatalog.storeURL
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
