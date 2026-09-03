import CryptoKit
import CoreData
import Foundation
import SQLite3
import SwiftData

struct CatalogManifest: Codable, Equatable, Sendable {
    struct Part: Codable, Equatable, Sendable {
        let resource: String
        let byteCount: Int64
        let sha256: String
    }

    struct Expected: Codable, Equatable, Sendable {
        let foods: Int
        let exercises: Int
        let yogaSequences: Int
        let practices: Int
        let practiceCues: Int
        let ayurvedaProfiles: Int
        let ayurvedaLinks: Int
        let vitamins: Int
        let minerals: Int
        let productBuckets: Int
        let vocabularyEntries: Int
        let searchCaches: Int
    }

    let formatVersion: Int
    let catalogVersion: Int
    let contentRevision: String
    let parts: [Part]
    let expected: Expected
}

@MainActor
enum CatalogStoreManager {
    struct PreparedCatalog {
        let storeURL: URL
        let manifest: CatalogManifest
        let installedNewCatalog: Bool
    }

    enum CatalogError: Error, LocalizedError {
        case missingManifest
        case unsupportedManifest(Int)
        case invalidPart(String)
        case integrityCheck(String)
        case countMismatch(label: String, expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .missingManifest:
                return "catalog_manifest.json is missing"
            case .unsupportedManifest(let version):
                return "Unsupported catalog manifest format \(version)"
            case .invalidPart(let resource):
                return "Catalog archive part failed validation: \(resource)"
            case .integrityCheck(let result):
                return "Catalog SQLite integrity check failed: \(result)"
            case .countMismatch(let label, let expected, let actual):
                return "Catalog \(label) count mismatch: expected \(expected), got \(actual)"
            }
        }
    }

    private static let directoryName = "Catalog"
    private static let versionsDirectoryName = "Versions"
    private static let storeName = "AyurvedaAsanaYogaCatalog.store"
    private static let installedManifestName = "installed-catalog-manifest.json"

    static func prepareCatalog(
        in applicationSupportURL: URL,
        bundle: Bundle = .main
    ) throws -> PreparedCatalog {
        let manifest = try loadBundledManifest(bundle: bundle)
        guard manifest.formatVersion == 1 else {
            throw CatalogError.unsupportedManifest(manifest.formatVersion)
        }

        let fileManager = FileManager.default
        let catalogDirectory = applicationSupportURL.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: catalogDirectory,
            withIntermediateDirectories: true
        )

        let versionsDirectory = catalogDirectory.appendingPathComponent(
            versionsDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: versionsDirectory,
            withIntermediateDirectories: true
        )
        let versionDirectory = versionsDirectory.appendingPathComponent(
            versionDirectoryName(for: manifest),
            isDirectory: true
        )
        let storeURL = versionDirectory.appendingPathComponent(storeName)
        let installedManifestURL = catalogDirectory.appendingPathComponent(
            installedManifestName
        )

        if fileManager.fileExists(atPath: storeURL.path),
           let installed = try? loadManifest(at: installedManifestURL),
           installed == manifest {
            return PreparedCatalog(
                storeURL: storeURL,
                manifest: manifest,
                installedNewCatalog: false
            )
        }

        try validateBundledParts(manifest: manifest, bundle: bundle)

        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("catalog-install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let stagedStoreURL = stagingDirectory.appendingPathComponent(storeName)
        try PreseedLoader.preparePreseededStore(
            to: stagedStoreURL,
            bundle: bundle,
            temporaryDirectory: stagingDirectory
        )

        // Opening once with the current catalogue schema performs only a
        // lightweight schema migration when an older bundled store is used.
        // Newly rebuilt bundles are already current and this is a cheap open.
        try migrateAndValidateStore(at: stagedStoreURL, manifest: manifest)
        try checkpointAndValidateSQLite(at: stagedStoreURL)
        // SwiftData's persistent model metadata also depends on the complete
        // multi-configuration container schema. Finalize the staged file with
        // the exact combined model before it is published read-only.
        try finalizeForCombinedMount(at: stagedStoreURL)
        try checkpointAndValidateSQLite(at: stagedStoreURL)
        try assignFreshStoreIdentifier(at: stagedStoreURL)
        try checkpointAndValidateSQLite(at: stagedStoreURL)

        // SwiftData external-storage blobs live in a sibling support folder.
        // Move one version directory containing both artifacts, then switch
        // the manifest. This avoids exposing a database/support-folder pair
        // from different catalogue versions.
        let incomingDirectory = catalogDirectory.appendingPathComponent(
            ".incoming-catalog-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: incomingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: incomingDirectory) }

        let incomingStoreURL = incomingDirectory.appendingPathComponent(storeName)
        try fileManager.copyItem(at: stagedStoreURL, to: incomingStoreURL)
        let stagedSupportURL = externalStorageSupportURL(for: stagedStoreURL)
        if fileManager.fileExists(atPath: stagedSupportURL.path) {
            try fileManager.copyItem(
                at: stagedSupportURL,
                to: externalStorageSupportURL(for: incomingStoreURL)
            )
        }
        try removeSidecars(for: incomingStoreURL, fileManager: fileManager)

        if fileManager.fileExists(atPath: versionDirectory.path) {
            _ = try fileManager.replaceItemAt(
                versionDirectory,
                withItemAt: incomingDirectory,
                backupItemName: "previous-catalog-version",
                options: []
            )
            let backupURL = versionsDirectory.appendingPathComponent(
                "previous-catalog-version"
            )
            try? fileManager.removeItem(at: backupURL)
        } else {
            try fileManager.moveItem(at: incomingDirectory, to: versionDirectory)
        }

        let manifestData = try JSONEncoder.catalogEncoder.encode(manifest)
        try manifestData.write(to: installedManifestURL, options: .atomic)

        return PreparedCatalog(
            storeURL: storeURL,
            manifest: manifest,
            installedNewCatalog: true
        )
    }

    static func storeIdentifier(at storeURL: URL) throws -> String {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        guard let identifier = metadata[NSStoreUUIDKey] as? String,
              !identifier.isEmpty else {
            throw CatalogError.integrityCheck("catalog store identifier is missing")
        }
        return identifier
    }

    /// Rewrites only Core Data's model metadata so the store can later be
    /// mounted read-only in the app's two-configuration container.
    static func finalizeForCombinedMount(at storeURL: URL) throws {
        let catalogConfiguration = ModelConfiguration(
            DatabaseSchema.catalogConfigurationName,
            schema: DatabaseSchema.catalog,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let emptyUserConfiguration = ModelConfiguration(
            DatabaseSchema.userConfigurationName,
            schema: DatabaseSchema.user,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: DatabaseSchema.combined,
            configurations: [catalogConfiguration, emptyUserConfiguration]
        )
        var descriptor = FetchDescriptor<FoodItem>()
        descriptor.fetchLimit = 1
        guard try !container.mainContext.fetch(descriptor).isEmpty else {
            throw CatalogError.integrityCheck("finalized catalog is empty")
        }
        withExtendedLifetime(container) {}
    }

    static func removeObsoleteVersions(
        in applicationSupportURL: URL,
        keeping currentStoreURL: URL
    ) {
        let fileManager = FileManager.default
        let versionsDirectory = applicationSupportURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(versionsDirectoryName, isDirectory: true)
        let currentDirectory = currentStoreURL.deletingLastPathComponent()
            .standardizedFileURL

        guard let candidates = try? fileManager.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for candidate in candidates
        where candidate.standardizedFileURL != currentDirectory
            && candidate.lastPathComponent.hasPrefix("v") {
            do {
                try fileManager.removeItem(at: candidate)
                print("🧹 Removed obsolete catalogue version: \(candidate.lastPathComponent)")
            } catch {
                print(
                    "⚠️ Could not remove obsolete catalogue version "
                        + "\(candidate.lastPathComponent): \(error)"
                )
            }
        }
    }

    /// The bundled archive and a legacy user store can originate from the
    /// same SQLite file, so they initially share Core Data's internal store
    /// UUID. Mounting both would make persistent IDs collide. Re-key every
    /// staged catalogue before it becomes live; stable domain UUIDs remain
    /// unchanged and continue to resolve user references across updates.
    private static func assignFreshStoreIdentifier(at storeURL: URL) throws {
        let identifier = UUID().uuidString
        var metadata = try NSPersistentStoreCoordinator
            .metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL,
                options: nil
            )
        metadata[NSStoreUUIDKey] = identifier
        try NSPersistentStoreCoordinator.setMetadata(
            metadata,
            forPersistentStoreOfType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )

        // Core Data stores the persistent-ID UUID in Z_METADATA.Z_UUID in
        // addition to its metadata plist. setMetadata updates the latter but
        // does not re-key existing object IDs, so update and verify the
        // dedicated column while the staged store is closed.
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw CatalogError.integrityCheck("unable to re-key catalog store")
        }
        defer { sqlite3_close(database) }

        var update: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "UPDATE Z_METADATA SET Z_UUID = ?",
            -1,
            &update,
            nil
        ) == SQLITE_OK, let update else {
            throw CatalogError.integrityCheck("unable to prepare catalog re-key")
        }
        defer { sqlite3_finalize(update) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(update, 1, identifier, -1, transient) == SQLITE_OK,
              sqlite3_step(update) == SQLITE_DONE,
              sqlite3_changes(database) == 1 else {
            throw CatalogError.integrityCheck("catalog re-key did not update metadata")
        }
    }

    private static func loadBundledManifest(bundle: Bundle) throws -> CatalogManifest {
        guard let url = bundle.url(
            forResource: "catalog_manifest",
            withExtension: "json"
        ) else {
            throw CatalogError.missingManifest
        }
        return try loadManifest(at: url)
    }

    private static func loadManifest(at url: URL) throws -> CatalogManifest {
        try JSONDecoder().decode(CatalogManifest.self, from: Data(contentsOf: url))
    }

    private static func validateBundledParts(
        manifest: CatalogManifest,
        bundle: Bundle
    ) throws {
        for part in manifest.parts {
            let resourceURL = bundleURL(for: part.resource, bundle: bundle)
            guard let resourceURL,
                  let attributes = try? FileManager.default.attributesOfItem(
                    atPath: resourceURL.path
                  ),
                  (attributes[.size] as? NSNumber)?.int64Value == part.byteCount,
                  try sha256(of: resourceURL) == part.sha256.lowercased() else {
                throw CatalogError.invalidPart(part.resource)
            }
        }
    }

    private static func bundleURL(for resource: String, bundle: Bundle) -> URL? {
        let url = URL(fileURLWithPath: resource)
        let extensionWithDot = url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent
        return bundle.url(
            forResource: name,
            withExtension: extensionWithDot.isEmpty ? nil : extensionWithDot
        )
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func migrateAndValidateStore(
        at storeURL: URL,
        manifest: CatalogManifest
    ) throws {
        let configuration = ModelConfiguration(
            DatabaseSchema.catalogConfigurationName,
            schema: DatabaseSchema.catalog,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: DatabaseSchema.catalog,
            configurations: [configuration]
        )
        let context = container.mainContext

        // Practices were historically shipped as JSON rather than in the
        // SQLite archive. Install them into the staged catalogue, never into
        // the live user store. This also upgrades a partially populated staged
        // catalogue deterministically before its atomic replacement.
        if try !PracticeSeeder.isInstalled(context: context) {
            _ = try PracticeSeeder.run(context: context)
        }

        try requireCount(
            "foods",
            expected: manifest.expected.foods,
            actual: context.fetchCount(FetchDescriptor<FoodItem>())
        )
        try requireCount(
            "exercises",
            expected: manifest.expected.exercises,
            actual: context.fetchCount(FetchDescriptor<ExerciseItem>())
        )
        try requireCount(
            "yoga sequences",
            expected: manifest.expected.yogaSequences,
            actual: context.fetchCount(FetchDescriptor<YogaSequence>())
        )
        try requireCount(
            "practices",
            expected: manifest.expected.practices,
            actual: context.fetchCount(FetchDescriptor<Practice>())
        )
        try requireCount(
            "practice cues",
            expected: manifest.expected.practiceCues,
            actual: context.fetchCount(FetchDescriptor<PracticeCue>())
        )
        try requireCount(
            "Ayurveda profiles",
            expected: manifest.expected.ayurvedaProfiles,
            actual: context.fetchCount(FetchDescriptor<AyurvedaProfile>())
        )
        try requireCount(
            "Ayurveda links",
            expected: manifest.expected.ayurvedaLinks,
            actual: context.fetchCount(FetchDescriptor<AyurvedaLink>())
        )
        try requireCount(
            "vitamins",
            expected: manifest.expected.vitamins,
            actual: context.fetchCount(FetchDescriptor<Vitamin>())
        )
        try requireCount(
            "minerals",
            expected: manifest.expected.minerals,
            actual: context.fetchCount(FetchDescriptor<Mineral>())
        )
        try requireCount(
            "product buckets",
            expected: manifest.expected.productBuckets,
            actual: context.fetchCount(FetchDescriptor<ProductBucket>())
        )
        try requireCount(
            "vocabulary entries",
            expected: manifest.expected.vocabularyEntries,
            actual: context.fetchCount(FetchDescriptor<VocabularyEntry>())
        )
        try requireCount(
            "search caches",
            expected: manifest.expected.searchCaches,
            actual: context.fetchCount(FetchDescriptor<SearchIndexCache>())
        )

        if context.hasChanges { try context.save() }
        withExtendedLifetime(container) {}
    }

    private static func requireCount(
        _ label: String,
        expected: Int,
        actual: Int
    ) throws {
        guard actual == expected else {
            throw CatalogError.countMismatch(
                label: label,
                expected: expected,
                actual: actual
            )
        }
    }

    private static func checkpointAndValidateSQLite(at storeURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw CatalogError.integrityCheck("unable to open store")
        }
        defer { sqlite3_close(database) }

        sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA integrity_check",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw CatalogError.integrityCheck("unable to prepare integrity_check")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let resultCString = sqlite3_column_text(statement, 0) else {
            throw CatalogError.integrityCheck("integrity_check returned no result")
        }
        let result = String(cString: resultCString)
        guard result == "ok" else {
            throw CatalogError.integrityCheck(result)
        }
    }

    private static func removeSidecars(
        for storeURL: URL,
        fileManager: FileManager
    ) throws {
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
        }
    }

    private static func externalStorageSupportURL(for storeURL: URL) -> URL {
        let baseName = storeURL.deletingPathExtension().lastPathComponent
        return storeURL.deletingLastPathComponent().appendingPathComponent(
            ".\(baseName)_SUPPORT",
            isDirectory: true
        )
    }

    private static func versionDirectoryName(
        for manifest: CatalogManifest
    ) -> String {
        let safeRevision = manifest.contentRevision.map { character in
            character.isLetter || character.isNumber || character == "-"
                ? character
                : "-"
        }
        return "v\(manifest.catalogVersion)-\(String(safeRevision))"
    }
}

private extension JSONEncoder {
    static let catalogEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
