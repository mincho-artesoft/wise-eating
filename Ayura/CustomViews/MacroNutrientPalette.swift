import SwiftUI

/// One shared, opaque palette for macronutrients across every surface.
/// Keeping the colors opaque prevents cards and backgrounds from changing
/// their perceived shade.
enum MacroNutrientPalette {
    static let carbohydrates = Color(hex: "3394FF")
    static let protein = Color(hex: "FF9F1A")
    static let fat = Color(hex: "C786E8")
}
