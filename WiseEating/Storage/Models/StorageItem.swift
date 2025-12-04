import SwiftData
import Foundation

@Model
public final class StorageItem: Identifiable {
    public var id: UUID = UUID()

    @Relationship(inverse: \Profile.pantryItems)
    public var owner: Profile?
    
    // ТУК: само deleteRule, без inverse
    @Relationship(deleteRule: .cascade)
    public var batches: [Batch] = []

    @Relationship(deleteRule: .nullify)
    public var food: FoodItem?

    public init(owner: Profile?, food: FoodItem, batches: [Batch] = []) {
        self.owner = owner
        self.food = food
        self.batches = batches
    }
    
    public var totalQuantity: Double {
        batches.reduce(0) { $0 + $1.quantity }
    }
    
    public var firstExpirationDate: Date? {
        batches.compactMap { $0.expirationDate }.min()
    }
}
