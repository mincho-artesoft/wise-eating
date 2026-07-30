import SwiftData
import Foundation

@Model
public final class CarbDetailsData: Identifiable {
    @Attribute(.unique) public var id = UUID()

    // Съвпадат 1:1 с генератора ("carb_details")
    public var starch:    Nutrient?
    public var sucrose:   Nutrient?
    public var glucose:   Nutrient?
    public var fructose:  Nutrient?
    public var lactose:   Nutrient?
    public var maltose:   Nutrient?
    public var galactose: Nutrient?

    @Relationship(inverse: \FoodItem.carbDetails) public var foodItem: FoodItem?

    public init(
        starch: Nutrient? = nil,
        sucrose: Nutrient? = nil,
        glucose: Nutrient? = nil,
        fructose: Nutrient? = nil,
        lactose: Nutrient? = nil,
        maltose: Nutrient? = nil,
        galactose: Nutrient? = nil
    ) {
        self.starch = starch
        self.sucrose = sucrose
        self.glucose = glucose
        self.fructose = fructose
        self.lactose = lactose
        self.maltose = maltose
        self.galactose = galactose
    }

    public static func keyPath(for id: String) -> KeyPath<CarbDetailsData, Nutrient?> {
        switch id {
        case "starch": return \.starch
        case "sucrose": return \.sucrose
        case "glucose": return \.glucose
        case "fructose": return \.fructose
        case "lactose": return \.lactose
        case "maltose": return \.maltose
        case "galactose": return \.galactose
        default: return \.starch
        }
    }
}
