import Foundation
import EventKit
import SwiftData

// Тази структура остава без промяна
struct ShoppingListPayload: Codable {
    let id: UUID
    let creationDate: Date
    let isCompleted: Bool
    let items: [ShoppingListItemPayload]

    init(from list: ShoppingListModel) {
        self.id = list.id
        self.creationDate = list.creationDate
        self.isCompleted = list.isCompleted
        self.items = list.items.map { ShoppingListItemPayload(from: $0) }
    }
}
