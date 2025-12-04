import SwiftUI

/// Defines the different kinds of storage transactions.
public enum TransactionType: String, Codable, Sendable {
    case addition = "Addition"
    case consumption = "Consumption"
    case mealConsumption = "Meal Consumption"
    case manualCorrection = "Manual Correction"
    case manualRemoval = "Manual Removal"
    case fullDeletion = "Deleted from Storage"
    
    // ✅ НОВ ТИП ТРАНЗАКЦИЯ
    case shoppingAddition = "Shopping Addition"
    
    var iconName: String {
        switch self {
        case .addition: "plus.circle.fill"
        // ✅ ИКОНА ЗА НОВИЯ ТИП
        case .shoppingAddition: "cart.badge.plus"
        case .consumption: "minus.circle.fill"
        case .mealConsumption: "fork.knife.circle.fill"
        case .manualCorrection: "pencil.circle.fill"
        case .manualRemoval: "trash.circle.fill"
        case .fullDeletion: "xmark.bin.fill"
        }
    }
    
    var color: Color {
        switch self {
        // ✅ ЦВЯТ ЗА НОВИЯ ТИП
        case .addition, .shoppingAddition: .green
        case .consumption: .orange
        case .mealConsumption: .yellow
        case .manualCorrection: .blue
        case .manualRemoval, .fullDeletion: .red
        }
    }
}
