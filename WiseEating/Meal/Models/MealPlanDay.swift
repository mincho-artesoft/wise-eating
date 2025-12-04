import Foundation
import SwiftData

@Model
public final class MealPlanDay: Identifiable {
    @Attribute(.unique) public var id: UUID
    
    // --- НАЧАЛО НА ПРОМЯНАТА: Преименуваме dayOfWeek на dayIndex ---
    public var dayIndex: Int // Вече е просто пореден номер (1, 2, 3...)
    // --- КРАЙ НА ПРОМЯНАТА ---

    @Relationship(deleteRule: .cascade, inverse: \MealPlanMeal.day)
    public var meals: [MealPlanMeal] = []
    
    public var plan: MealPlan?

    // --- НАЧАЛО НА ПРОМЯНАТА: Актуализираме init ---
    public init(dayIndex: Int) {
        self.id = UUID()
        self.dayIndex = dayIndex
    }
    // --- КРАЙ НА ПРОМЯНАТА ---
    
    // Тази функция вече не е необходима, тъй като нямаме връзка с ден от седмицата
    // public func dayName(calendar: Calendar = .current) -> String { ... }
}
