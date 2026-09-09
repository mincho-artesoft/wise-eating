import Foundation
import SwiftData

@Model
public final class MealLogStorageLink {
    public var id: UUID = UUID()
    public var date: Date
    public var mealID: UUID
    public var deductedQuantity: Double
    
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
    
    @Relationship(inverse: \Profile.mealStorageLinks)
    public var profile: Profile?
    
    public init(date: Date, mealID: UUID, deductedQuantity: Double, food: FoodItem?, profile: Profile?) {
        self.date = Calendar.current.startOfDay(for: date)
        self.mealID = mealID
        self.deductedQuantity = deductedQuantity
        let reference = CatalogReferenceResolver.storedFoodReference(for: food)
        self.persistedFood = reference.stored
        self.catalogFoodID = reference.catalogID
        self.profile = profile
    }
}
