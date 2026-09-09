import Foundation
/// Codable версия на ShoppingListItem.
struct ShoppingListItemPayload: Codable, Equatable, Hashable {
    let id: UUID
    let name: String
    let quantity: Double
    let price: Double?
    let isBought: Bool

    init(from item: ShoppingListItem) {
        self.id = item.id
        self.name = item.name
        self.quantity = item.quantity
        self.price = item.price
        self.isBought = item.isBought
    }
}



