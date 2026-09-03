import Foundation
import SwiftData

@Model
public final class DismissedFoodID: Identifiable { // Identifiable може да е полезно, макар и не строго нужно тук
    @Attribute(.unique) public var id: UUID
    public var foodID: UUID
    public var list: ShoppingListModel? // Връзка към родителския ShoppingListModel

    public init(id: UUID = UUID(), foodID: UUID, list: ShoppingListModel? = nil) {
        self.id = id
        self.foodID = foodID
        self.list = list // Връзката ще се управлява от SwiftData при добавяне към list.dismissedSuggestions
    }
}
