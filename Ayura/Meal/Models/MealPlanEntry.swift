import Foundation
import SwiftData

@Model
public final class MealPlanEntry: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var grams: Double
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
    public var meal: MealPlanMeal?

    public init(food: FoodItem, grams: Double, meal: MealPlanMeal? = nil) {
        self.id = UUID()
        let reference = CatalogReferenceResolver.storedFoodReference(for: food)
        self.persistedFood = reference.stored
        self.catalogFoodID = reference.catalogID
        self.grams = grams
        self.meal = meal
    }
}
