import Foundation
import SwiftData

@Model
public final class RecentlyAddedFood {
    public var id: UUID = UUID()
    public var dateAdded: Date
    
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
    
    @Relationship(inverse: \Profile.recentlyAddedFoods)
    public var profile: Profile?
    
    public init(dateAdded: Date, food: FoodItem, profile: Profile?) {
        self.dateAdded = dateAdded
        let reference = CatalogReferenceResolver.storedFoodReference(for: food)
        self.persistedFood = reference.stored
        self.catalogFoodID = reference.catalogID
        self.profile = profile
    }
}
