import Foundation
import SwiftData

@Model
public final class MealLogStorageLink {
    public var id: UUID = UUID()
    public var date: Date
    public var mealID: UUID
    public var deductedQuantity: Double
    
    @Relationship(deleteRule: .nullify)
    public var food: FoodItem?
    
    @Relationship(inverse: \Profile.mealStorageLinks)
    public var profile: Profile?
    
    public init(date: Date, mealID: UUID, deductedQuantity: Double, food: FoodItem?, profile: Profile?) {
        self.date = Calendar.current.startOfDay(for: date)
        self.mealID = mealID
        self.deductedQuantity = deductedQuantity
        self.food = food
        self.profile = profile
    }
}
