import SwiftData
import Foundation

@Model
public final class FoodPhoto: Identifiable {

    @Attribute(.unique) public var id = UUID()
    @Attribute(.externalStorage) public var data: Data          // JPEG / HEIC оригинал
    public var createdAt: Date = Date.now                       // ✔︎ напълно квалифицирано

    // inverse към FoodItem.gallery
    @Relationship(inverse: \FoodItem.gallery) public var foodItem: FoodItem?

    public init(data: Data, createdAt: Date = Date.now) {
        self.data = data
        self.createdAt = createdAt
    }
}
