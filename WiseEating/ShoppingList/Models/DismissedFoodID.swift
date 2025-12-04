import Foundation
import SwiftData

@Model
public final class DismissedFoodID: Identifiable { // Identifiable може да е полезно, макар и не строго нужно тук
    public var foodID: Int
    public var list: ShoppingListModel? // Връзка към родителския ShoppingListModel

    public init(foodID: Int, list: ShoppingListModel? = nil) {
        self.foodID = foodID
        self.list = list // Връзката ще се управлява от SwiftData при добавяне към list.dismissedSuggestions
    }
}
