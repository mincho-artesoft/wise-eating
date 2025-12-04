import Foundation
import SwiftData
import SwiftUI

@Model
public final class StorageTransaction {
    public var id: UUID = UUID()
    public var date: Date
    public var type: TransactionType
    public var quantityChange: Double
    
    @Relationship(inverse: \Profile.transactions)
    public var profile: Profile?
    
    @Relationship(deleteRule: .nullify)
    public var food: FoodItem?
    
    public init(date: Date, type: TransactionType, quantityChange: Double, profile: Profile?, food: FoodItem?) {
        self.date = date
        self.type = type
        self.quantityChange = quantityChange
        self.profile = profile
        self.food = food
    }
}
