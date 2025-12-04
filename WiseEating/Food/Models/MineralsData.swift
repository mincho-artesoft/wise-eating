import SwiftData
import Foundation

@Model
public final class MineralsData: Identifiable {
    @Attribute(.unique) public var id = UUID()

    public var calcium:    Nutrient?
    public var iron:       Nutrient?
    public var magnesium:  Nutrient?
    public var phosphorus: Nutrient?
    public var potassium:  Nutrient?
    public var sodium:     Nutrient?
    public var selenium:   Nutrient?
    public var zinc:       Nutrient?
    public var copper:     Nutrient?
    public var manganese:  Nutrient?
    public var fluoride:   Nutrient?

    @Relationship(inverse: \FoodItem.minerals) public var foodItem: FoodItem?

    public init(
        calcium:    Nutrient? = nil,
        iron:       Nutrient? = nil,
        magnesium:  Nutrient? = nil,
        phosphorus: Nutrient? = nil,
        potassium:  Nutrient? = nil,
        sodium:     Nutrient? = nil,
        selenium:   Nutrient? = nil,
        zinc:       Nutrient? = nil,
        copper:     Nutrient? = nil,
        manganese:  Nutrient? = nil,
        fluoride:   Nutrient? = nil
    ) {
        self.calcium    = calcium
        self.iron       = iron
        self.magnesium  = magnesium
        self.phosphorus = phosphorus
        self.potassium  = potassium
        self.sodium     = sodium
        self.selenium   = selenium
        self.zinc       = zinc
        self.copper     = copper
        self.manganese  = manganese
        self.fluoride   = fluoride
    }

    // MARK: - KeyPath map за Predicate push
    // ключовете са точно тези, които идват от JSON генератора
    public static func keyPath(for id: String) -> KeyPath<MineralsData, Nutrient?> {
        switch id {
        case "calcium": return \.calcium
        case "iron": return \.iron
        case "magnesium": return \.magnesium
        case "phosphorus": return \.phosphorus
        case "potassium": return \.potassium
        case "sodium": return \.sodium
        case "selenium": return \.selenium
        case "zinc": return \.zinc
        case "copper": return \.copper
        case "manganese": return \.manganese
        case "fluoride": return \.fluoride
        default: return \.iron // безопасно по подразбиране
        }
    }
}
