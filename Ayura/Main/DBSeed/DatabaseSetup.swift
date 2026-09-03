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

struct DatabaseLaunchState {
    let container: ModelContainer?
    let diagnostic: String?
    let isRecoveryMode: Bool

    static func ready(
        _ container: ModelContainer,
        isRecoveryMode: Bool = false
    ) -> DatabaseLaunchState {
        DatabaseLaunchState(
            container: container,
            diagnostic: nil,
            isRecoveryMode: isRecoveryMode
        )
    }

    static func unavailable(_ diagnostic: String) -> DatabaseLaunchState {
        DatabaseLaunchState(
            container: nil,
            diagnostic: diagnostic,
            isRecoveryMode: false
        )
    }
}

@MainActor
struct DatabaseSetup {
    private static let logger = Logger(
        subsystem: "AyurvedaAsanaYoga.Arte-Soft",
        category: "DatabaseLaunch"
    )
    private static let recoveryModeKey =
        "AyurvedaAsanaYoga_DatabaseRecoveryMode_v1"
    private static let recoveryStoreName =
        "AyurvedaAsanaYogaRecovery.store"

    /// Database creation is intentionally non-fatal. A SwiftData/Core Data
    /// error must never terminate the process before SwiftUI can show a frame.
    static func createContainer() -> DatabaseLaunchState {
        AyurvedaAsanaYogaLaunchProbe.event("database-setup-begin")
        do {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            print("🚀 SwiftData Path: \(appSupportURL.path())")

            if UserDefaults.standard.bool(forKey: recoveryModeKey) {
                do {
                    let container = try makeRecoveryContainer(
                        in: appSupportURL
                    )
                    CatalogReferenceResolver.reset()
                    logger.notice("Database recovery mode reopened successfully")
                    return .ready(container, isRecoveryMode: true)
                } catch {
                    return unavailableState(
                        primaryError: nil,
                        recoveryError: error
                    )
                }
            }

            do {
                let container = try makePrimaryContainer(in: appSupportURL)
                return .ready(container)
            } catch {
                let primaryError = error
                logger.error(
                    "Primary database startup failed: \(String(reflecting: primaryError), privacy: .public)"
                )
                print("DATABASE_RECOVERY|PRIMARY_FAILED|\(primaryError)")

                do {
                    let container = try makeRecoveryContainer(
                        in: appSupportURL
                    )
                    CatalogReferenceResolver.reset()
                    UserDefaults.standard.set(
                        true,
                        forKey: recoveryModeKey
                    )
                    logger.notice("Database recovery mode activated successfully")
                    print("DATABASE_RECOVERY|ACTIVE")
                    return .ready(container, isRecoveryMode: true)
                } catch {
                    return unavailableState(
                        primaryError: primaryError,
                        recoveryError: error
                    )
                }
            }
        } catch {
            logger.fault(
                "Application Support directory is unavailable: \(String(reflecting: error), privacy: .public)"
            )
            return .unavailable("Application Support: \(error)")
        }
    }

    private static func makePrimaryContainer(
        in appSupportURL: URL
    ) throws -> ModelContainer {
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
    }

    /// Last-resort persistent store used when the two-store SwiftData setup is
    /// rejected by a newer OS. It is deliberately a single writable store and
    /// therefore does not depend on configuration Set ordering or write
    /// routing. The primary user store is never deleted or modified here.
    private static func makeRecoveryContainer(
        in appSupportURL: URL
    ) throws -> ModelContainer {
        let fileManager = FileManager.default
        let storeURL = appSupportURL.appendingPathComponent(recoveryStoreName)
        let storeExists = fileManager.fileExists(atPath: storeURL.path)

        if !storeExists {
            let stagingDirectory = appSupportURL.appendingPathComponent(
                ".database-recovery-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            defer { try? fileManager.removeItem(at: stagingDirectory) }

            let stagedStoreURL = stagingDirectory.appendingPathComponent(
                recoveryStoreName
            )
            try PreseedLoader.preparePreseededStore(
                to: stagedStoreURL,
                temporaryDirectory: stagingDirectory
            )
            try fileManager.moveItem(at: stagedStoreURL, to: storeURL)
        }

        // This is the configuration name used by the original monolithic
        // preseed. Retaining it avoids an unnecessary configuration migration.
        let configuration = ModelConfiguration(
            "AyurvedaAsanaYogaDefault",
            schema: DatabaseSchema.user,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: DatabaseSchema.user,
            configurations: [configuration]
        )

        if !storeExists {
            var descriptor = FetchDescriptor<FoodItem>()
            descriptor.fetchLimit = 1
            guard try !container.mainContext.fetch(descriptor).isEmpty else {
                throw DatabaseRecoveryError.preseedIsEmpty
            }
        }
        return container
    }

    private static func unavailableState(
        primaryError: Error?,
        recoveryError: Error
    ) -> DatabaseLaunchState {
        let primaryDescription = primaryError.map(String.init(describing:))
            ?? "Recovery mode was already active"
        let diagnostic = "Primary: \(primaryDescription); "
            + "Recovery: \(recoveryError)"
        logger.fault(
            "All database startup modes failed: \(diagnostic, privacy: .public)"
        )
        print("DATABASE_RECOVERY|UNAVAILABLE|\(diagnostic)")
        return .unavailable(diagnostic)
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

private enum DatabaseRecoveryError: LocalizedError {
    case preseedIsEmpty

    var errorDescription: String? {
        switch self {
        case .preseedIsEmpty:
            return "The recovery database did not contain its bundled catalogue."
        }
    }
}
