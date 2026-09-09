import Foundation
import SwiftData

@Model
final class SearchIndexCache {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String        // напр. "main"
    var payloadData: Data                      // сериализираният индекс
    var createdAt: Date
    var foodsCount: Int                        // колко FoodItem е имало при build
    var version: Int                           // за бъдещи промени на формата

    init(
        id: UUID = UUID(),
        key: String = "main",
        payloadData: Data,
        foodsCount: Int,
        version: Int = 1,
        createdAt: Date = .now
    ) {
        self.id = id
        self.key = key
        self.payloadData = payloadData
        self.foodsCount = foodsCount
        self.version = version
        self.createdAt = createdAt
    }
}
