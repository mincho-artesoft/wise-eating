import SwiftUI

/// A simple struct to pass information about a nutrient to be displayed.
// ✅ FIX: Add Hashable conformance.
public struct DisplayableNutrient: Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var value: Double
    public var unit: String
    public var color: Color? // Optional color for the nutrient name
    public var valueMg: Double // From the other definition

    public init(name: String, value: Double, unit: String, color: Color? = nil, valueMg: Double) {
        self.name = name
        self.value = value
        self.unit = unit
        self.color = color
        self.valueMg = valueMg
    }

    // ✅ Add custom Hashable and Equatable conformance because `Color` is not hashable.
    // We only need to compare by the unique ID.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DisplayableNutrient, rhs: DisplayableNutrient) -> Bool {
        lhs.id == rhs.id
    }
}
