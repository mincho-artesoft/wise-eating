import Foundation
import SwiftData

@Model
public final class Batch: Identifiable {
    public var id: UUID = UUID()
    
    public var quantity: Double
    public var expirationDate: Date?

    // ТУК: inverse към StorageItem.batches
    @Relationship(inverse: \StorageItem.batches)
    public var storageItem: StorageItem?

    public init(quantity: Double,
                expirationDate: Date? = nil,
                storageItem: StorageItem? = nil) {
        self.quantity = quantity
        self.expirationDate = expirationDate
        self.storageItem = storageItem
    }
}
