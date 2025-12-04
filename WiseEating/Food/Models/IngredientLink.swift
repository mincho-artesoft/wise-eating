import SwiftData
import Foundation

@Model
public final class IngredientLink: Identifiable {

    /// Конкретният продукт / суровина
    /// ⬇︎  ВАЖНО: вече е .nullify, за да не трие FoodItem-a при изтриване на връзката
    @Relationship(deleteRule: .nullify)
    public var food: FoodItem?

    /// Колко грама от продукта участват в рецептата
    public var grams: Double = 0

    /// Обратна връзка към рецептата-собственик
    @Relationship(inverse: \FoodItem.ingredients)
    public var owner: FoodItem?

    // MARK: – Init
    public init(food: FoodItem,
                grams: Double = 0,
                owner: FoodItem? = nil)
    {
        self.food  = food
        self.grams = grams
        self.owner = owner
    }
}
