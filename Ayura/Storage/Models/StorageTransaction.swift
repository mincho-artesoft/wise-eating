import Foundation
import SwiftData
import SwiftUI

@Model
public final class StorageTransaction {
    public var id: UUID = UUID()
    public var date: Date
    public var type: TransactionType
    public var quantityChange: Double
    
    @Relationship(inverse: \Profile.transactions)
    public var profile: Profile?
    
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
    
    public init(date: Date, type: TransactionType, quantityChange: Double, profile: Profile?, food: FoodItem?) {
        self.date = date
        self.type = type
        self.quantityChange = quantityChange
        self.profile = profile
        let reference = CatalogReferenceResolver.storedFoodReference(for: food)
        self.persistedFood = reference.stored
        self.catalogFoodID = reference.catalogID
    }
}
