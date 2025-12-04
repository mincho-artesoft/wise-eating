import Foundation
import SwiftData

@Model
public final class MealPlan: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var creationDate: Date
    
    public var minAgeMonths: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \MealPlanDay.plan)
    public var days: [MealPlanDay] = []

    @Relationship(inverse: \Profile.mealPlans)
    public var profile: Profile?

    public init(name: String, profile: Profile?, minAgeMonths: Int = 0) {
        self.id = UUID()
        self.name = name
        self.creationDate = Date()
        self.profile = profile
        self.minAgeMonths = minAgeMonths
        
        let todayWeekday = Calendar.current.component(.weekday, from: Date())
        let firstDay = MealPlanDay(dayIndex: 1) // Always start with Day 1
        firstDay.plan = self
        self.days = [firstDay]
    }
}
