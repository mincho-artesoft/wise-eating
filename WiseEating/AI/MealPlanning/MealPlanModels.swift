import SwiftData
import Foundation

@Model
public final class MealPlanWeek {
    @Attribute(.unique) public var id: UUID
    @Relationship public var profile: Profile
    public var startDate: Date
    public var endDate: Date
    @Relationship(deleteRule: .cascade) public var days: [PlannedDay]

    public init(profile: Profile, startDate: Date, endDate: Date, days: [PlannedDay]) {
        self.id = UUID()
        self.profile = profile
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: endDate)
        self.days = days
    }
}

@Model
public final class PlannedDay {
    public var date: Date
    @Relationship(deleteRule: .cascade) public var meals: [PlannedMeal]

    public init(date: Date, meals: [PlannedMeal]) {
        self.date = Calendar.current.startOfDay(for: date)
        self.meals = meals
    }
}

@Model
public final class PlannedMeal {
    public var name: String            // comes from user's Meal.name (Breakfast/Lunch/… or custom)
    public var startTime: Date         // copied from user's Meal slot that day
    public var endTime: Date
    @Relationship(deleteRule: .cascade) public var items: [PlannedFood]

    public init(name: String, startTime: Date, endTime: Date, items: [PlannedFood]) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.items = items
    }

    public var kcalTotal: Double {
        items.reduce(0) { $0 + $1.kcal }
    }
}

@Model
public final class PlannedFood {
    // Always a USDA base food
    @Relationship public var food: FoodItem
    public var grams: Double
    public var kcal: Double

    public init(food: FoodItem, grams: Double) {
        self.food = food
        self.grams = grams
        self.kcal = food.calories(for: grams)
    }
}


