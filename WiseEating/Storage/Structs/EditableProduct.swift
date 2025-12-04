import SwiftUI

struct EditableProduct: Identifiable {
    let id = UUID()
    var food: FoodItem
    var batches: [EditableBatch] = [EditableBatch()]
    var isMarkedForDeletion: Bool = false 
}
