import SwiftData
import Foundation

@Model
public final class MacronutrientsData: Identifiable {
    @Attribute(.unique) public var id: UUID

    public var carbohydrates: Nutrient?
    public var protein:       Nutrient?
    public var fat:           Nutrient?
    public var fiber:         Nutrient?
    public var totalSugars:   Nutrient?

    @Relationship(inverse: \FoodItem.macronutrients) public var foodItem: FoodItem?

    public init(id: UUID = UUID(),
                carbohydrates: Nutrient? = nil,
                protein:       Nutrient? = nil,
                fat:           Nutrient? = nil,
                fiber:         Nutrient? = nil,
                totalSugars:   Nutrient? = nil) {
        self.id = id
        self.carbohydrates = carbohydrates
        self.protein       = protein
        self.fat           = fat
        self.fiber         = fiber
        self.totalSugars   = totalSugars
    }
}
