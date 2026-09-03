import Foundation
import SwiftData

@Model
final class CatalogMigrationState {
    @Attribute(.unique) var key: String
    var separationVersion: Int
    var catalogVersion: Int
    var contentRevision: String
    var completedAt: Date

    init(
        key: String = "catalog-separation",
        separationVersion: Int,
        catalogVersion: Int,
        contentRevision: String,
        completedAt: Date = Date()
    ) {
        self.key = key
        self.separationVersion = separationVersion
        self.catalogVersion = catalogVersion
        self.contentRevision = contentRevision
        self.completedAt = completedAt
    }
}

@Model
final class CatalogPreference {
    @Attribute(.unique) var key: String
    var kind: String
    var itemID: UUID
    var isFavorite: Bool
    var updatedAt: Date

    init(kind: String, itemID: UUID, isFavorite: Bool, updatedAt: Date = Date()) {
        self.key = "\(kind):\(itemID.uuidString.lowercased())"
        self.kind = kind
        self.itemID = itemID
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }
}
