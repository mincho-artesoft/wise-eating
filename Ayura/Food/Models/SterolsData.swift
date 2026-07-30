import SwiftData
import Foundation

@Model
public final class SterolsData: Identifiable {
    @Attribute(.unique) public var id = UUID()

    // Съвпадат 1:1 с генератора ("sterols")
    public var phytosterols:    Nutrient?
    public var betaSitosterol:  Nutrient?
    public var campesterol:     Nutrient?
    public var stigmasterol:    Nutrient?

    @Relationship(inverse: \FoodItem.sterols) public var foodItem: FoodItem?

    public init(
        phytosterols: Nutrient? = nil,
        betaSitosterol: Nutrient? = nil,
        campesterol: Nutrient? = nil,
        stigmasterol: Nutrient? = nil
    ) {
        self.phytosterols = phytosterols
        self.betaSitosterol = betaSitosterol
        self.campesterol = campesterol
        self.stigmasterol = stigmasterol
    }

    public static func keyPath(for id: String) -> KeyPath<SterolsData, Nutrient?> {
        switch id {
        case "phytosterols": return \.phytosterols
        case "betaSitosterol": return \.betaSitosterol
        case "campesterol": return \.campesterol
        case "stigmasterol": return \.stigmasterol
        default: return \.phytosterols
        }
    }
}
