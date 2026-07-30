import Foundation
import SwiftData

@Model
public final class RecentlyAddedFood {
    public var id: UUID = UUID()
    public var dateAdded: Date
    
    @Relationship(deleteRule: .nullify)
    public var food: FoodItem?
    
    @Relationship(inverse: \Profile.recentlyAddedFoods)
    public var profile: Profile?
    
    public init(dateAdded: Date, food: FoodItem, profile: Profile?) {
        self.dateAdded = dateAdded
        self.food = food
        self.profile = profile
    }
}
