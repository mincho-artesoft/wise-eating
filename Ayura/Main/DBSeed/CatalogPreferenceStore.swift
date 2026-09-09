import Combine
import Foundation
import SwiftData

/// Keeps user-owned state for immutable catalogue rows in the writable store.
/// Catalogue models themselves are never changed, so replacing the catalogue
/// file cannot overwrite favorites selected by the user.
@MainActor
final class CatalogPreferenceStore: ObservableObject {
    static let shared = CatalogPreferenceStore()

    @Published private(set) var revision: UInt64 = 0

    private var favoritesByKey: [String: Bool] = [:]
    private var loadedContextID: ObjectIdentifier?

    private init() {}

    func load(context: ModelContext) throws {
        let contextID = ObjectIdentifier(context)
        guard loadedContextID != contextID else { return }

        favoritesByKey = Dictionary(
            uniqueKeysWithValues: try context.fetch(
                FetchDescriptor<CatalogPreference>()
            ).map { ($0.key, $0.isFavorite) }
        )
        loadedContextID = contextID
        revision &+= 1
    }

    func isFavorite(
        kind: String,
        itemID: UUID,
        fallback: Bool
    ) -> Bool {
        favoritesByKey[Self.key(kind: kind, itemID: itemID)] ?? fallback
    }

    func favoriteIDs(kind: String) -> [UUID] {
        let prefix = kind + ":"
        return favoritesByKey.compactMap { key, isFavorite in
            guard isFavorite, key.hasPrefix(prefix) else { return nil }
            return UUID(uuidString: String(key.dropFirst(prefix.count)))
        }
    }

    func setFavorite(
        _ isFavorite: Bool,
        kind: String,
        itemID: UUID,
        context: ModelContext
    ) throws {
        try load(context: context)
        let key = Self.key(kind: kind, itemID: itemID)
        let descriptor = FetchDescriptor<CatalogPreference>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.isFavorite = isFavorite
            existing.updatedAt = Date()
        } else {
            context.insert(
                CatalogPreference(
                    kind: kind,
                    itemID: itemID,
                    isFavorite: isFavorite
                )
            )
        }
        try context.save()
        favoritesByKey[key] = isFavorite
        revision &+= 1
    }

    private static func key(kind: String, itemID: UUID) -> String {
        "\(kind):\(itemID.uuidString.lowercased())"
    }
}

@MainActor
extension FoodItem {
    var effectiveIsFavorite: Bool {
        CatalogPreferenceStore.shared.isFavorite(
            kind: "food",
            itemID: id,
            fallback: isFavorite
        )
    }

    func setEffectiveFavorite(_ value: Bool, context: ModelContext) throws {
        if CatalogReferenceResolver.isCatalog(self) {
            try CatalogPreferenceStore.shared.setFavorite(
                value,
                kind: "food",
                itemID: id,
                context: context
            )
        } else {
            isFavorite = value
            try context.save()
        }
    }
}

@MainActor
extension ExerciseItem {
    var effectiveIsFavorite: Bool {
        CatalogPreferenceStore.shared.isFavorite(
            kind: "exercise",
            itemID: id,
            fallback: isFavorite
        )
    }

    func setEffectiveFavorite(_ value: Bool, context: ModelContext) throws {
        if CatalogReferenceResolver.isCatalog(self) {
            try CatalogPreferenceStore.shared.setFavorite(
                value,
                kind: "exercise",
                itemID: id,
                context: context
            )
        } else {
            isFavorite = value
            try context.save()
        }
    }
}

@MainActor
extension Practice {
    var effectiveIsFavorite: Bool {
        CatalogPreferenceStore.shared.isFavorite(
            kind: "practice",
            itemID: id,
            fallback: isFavorite
        )
    }

    func setEffectiveFavorite(_ value: Bool, context: ModelContext) throws {
        if CatalogReferenceResolver.isCatalog(self) {
            try CatalogPreferenceStore.shared.setFavorite(
                value,
                kind: "practice",
                itemID: id,
                context: context
            )
        } else {
            isFavorite = value
            try context.save()
        }
    }
}
