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

    @Relationship(deleteRule: .nullify, originalName: "food")
    var persistedFood: FoodItem?
    public var catalogFoodID: UUID?

    public var food: FoodItem? {
        get {
            CatalogReferenceResolver.resolveFood(
                stored: persistedFood,
                catalogID: catalogFoodID
            )
        }
        set {
            let reference = CatalogReferenceResolver.storedFoodReference(for: newValue)
            persistedFood = reference.stored
            catalogFoodID = reference.catalogID
        }
    }

    public init(owner: Profile?, food: FoodItem, batches: [Batch] = []) {
        self.owner = owner
        let reference = CatalogReferenceResolver.storedFoodReference(for: food)
        self.persistedFood = reference.stored
        self.catalogFoodID = reference.catalogID
        self.batches = batches
    }
    
    public var totalQuantity: Double {
        batches.reduce(0) { $0 + $1.quantity }
    }
    
    public var firstExpirationDate: Date? {
        batches.compactMap { $0.expirationDate }.min()
    }
}
