import Foundation
import SwiftData

@Model
public final class ShoppingListItem: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var quantity: Double
    public var price: Double?
    public var isBought: Bool
    
    public var list: ShoppingListModel? // Връзка към родителския списък
    
    @Relationship(deleteRule: .nullify, originalName: "foodItem")
    var persistedFoodItem: FoodItem?
    public var catalogFoodID: UUID?

    public var foodItem: FoodItem? {
        get {
            CatalogReferenceResolver.resolveFood(
                stored: persistedFoodItem,
                catalogID: catalogFoodID
            )
        }
        set {
            let reference = CatalogReferenceResolver.storedFoodReference(for: newValue)
            persistedFoodItem = reference.stored
            catalogFoodID = reference.catalogID
        }
    }
    
    public init(name: String, quantity: Double = 1.0, price: Double? = nil, isBought: Bool = false, foodItem: FoodItem? = nil) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.price = price
        self.isBought = isBought
        let reference = CatalogReferenceResolver.storedFoodReference(for: foodItem)
        self.persistedFoodItem = reference.stored
        self.catalogFoodID = reference.catalogID
    }
}
