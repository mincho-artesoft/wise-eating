import Foundation
import SwiftData

@Model
public final class MealPlanEntry: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var grams: Double
    public var food: FoodItem?
    public var meal: MealPlanMeal?

    public init(food: FoodItem, grams: Double, meal: MealPlanMeal? = nil) {
        self.id = UUID()
        self.food = food
        self.grams = grams
        self.meal = meal
    }
}
