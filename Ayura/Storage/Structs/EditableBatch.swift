import SwiftUI

struct EditableBatch: Identifiable {
    let id = UUID()
    // ----- 👇 НАЧАЛО НА ПРОМЯНА 1: Променяме стойността по подразбиране -----
    // Стойността по подразбиране се определя от мерната система
    var quantityString: String = GlobalState.measurementSystem == "Imperial" ? "4" : "100"
    // ----- 👆 КРАЙ НА ПРОМЯНА 1 -----
    var expirationDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
    var hasExpiration: Bool = true
    var isMarkedForDeletion: Bool = false
    
    // ----- 👇 НАЧАЛО НА ПРОМЯНА 2: Обновяваме quantityValue -----
    /// Тази променлива ВИНАГИ връща стойността в ГРАМОВЕ за запис в базата данни.
    var quantityValue: Double {
        let isImperial = GlobalState.measurementSystem == "Imperial"
        guard let displayValue = GlobalState.double(from: quantityString) else { return 0.0 }
        
        // Ако системата е имперска, конвертираме унциите в грамове.
        // В противен случай, стойността вече е в грамове.
        return isImperial ? UnitConversion.ozToG(displayValue) : displayValue
    }
    // ----- 👆 КРАЙ НА ПРОМЯНА 2 -----
}
