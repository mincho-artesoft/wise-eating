import SwiftData
import Foundation

@Model
public final class IngredientLink: Identifiable {
    @Attribute(.unique) public var id: UUID

    /// Конкретният продукт / суровина
    /// ⬇︎  ВАЖНО: вече е .nullify, за да не трие FoodItem-a при изтриване на връзката
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

    /// Колко грама от продукта участват в рецептата
    public var grams: Double = 0

    /// Обратна връзка към рецептата-собственик
    @Relationship(inverse: \FoodItem.ingredients)
    public var owner: FoodItem?

    // MARK: – Init
    public init(id: UUID = UUID(),
                food: FoodItem,
                grams: Double = 0,
                owner: FoodItem? = nil)
    {
        self.id = id
        let reference = CatalogReferenceResolver.storedFoodReference(for: food)
        self.persistedFood = reference.stored
        self.catalogFoodID = reference.catalogID
        self.grams = grams
        self.owner = owner
    }

    /// Creates a link whose reference has already been routed to the correct
    /// store. Catalogue foods use only `catalogFoodID`; user foods use the
    /// relationship from the user-only write context.
    public init(
        id: UUID = UUID(),
        persistedFood: FoodItem?,
        catalogFoodID: UUID?,
        grams: Double = 0,
        owner: FoodItem? = nil
    ) {
        self.id = id
        self.persistedFood = persistedFood
        self.catalogFoodID = catalogFoodID
        self.grams = grams
        self.owner = owner
    }
}
