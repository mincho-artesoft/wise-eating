import Foundation
import SwiftData

// FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Meal/Models/MealPlanMeal.swift

@Model
public final class MealPlanMeal: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var mealName: String // e.g., "Breakfast"
    public var descriptiveAIName: String? // NEW: To store the creative name from the AI
    
    // +++ НАЧАЛО НА ПРОМЯНАТА +++
    public var startTime: Date?
    // +++ КРАЙ НА ПРОМЯНАТА +++

    public var linkedMenuID: Int? = nil

    @Relationship(deleteRule: .cascade, inverse: \MealPlanEntry.meal)
    public var entries: [MealPlanEntry] = []
    
    public var day: MealPlanDay?

    public init(mealName: String) {
        self.id = UUID()
        self.mealName = mealName
        // +++ НАЧАЛО НА ПРОМЯНАТА +++
        self.startTime = nil // Инициализираме го като nil
        // +++ КРАЙ НА ПРОМЯНАТА +++
    }
    
    public func entry(for food: FoodItem) -> MealPlanEntry? {
        entries.first { $0.food?.id == food.id }
    }

    public func ensureEntry(for food: FoodItem, defaultGrams: Double = 100) -> MealPlanEntry {
        if let e = entry(for: food) { return e }
        let e = MealPlanEntry(food: food, grams: defaultGrams, meal: self)
        entries.append(e)
        return e
    }

    public func removeEntry(for food: FoodItem) {
        guard let idx = entries.firstIndex(where: { $0.food?.id == food.id }) else { return }
        entries.remove(at: idx)
    }
}
