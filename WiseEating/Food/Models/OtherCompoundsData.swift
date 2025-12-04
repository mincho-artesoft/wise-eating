import SwiftData
import Foundation

@Model
public final class OtherCompoundsData: Identifiable {

    // MARK: – Идентификация
    @Attribute(.unique) public var id = UUID()

    // MARK: – Полеви стойности (флатнати)
    public var alcoholEthyl: Nutrient?
    public var caffeine:     Nutrient?
    public var theobromine:  Nutrient?
    public var cholesterol:  Nutrient?
    public var energyKcal:   Nutrient?
    public var water:        Nutrient?
    public var weightG:      Nutrient?
    public var ash:          Nutrient?   // Ash (G)
    public var betaine:      Nutrient?   // Betaine (MG)
    public var alkalinityPH: Nutrient?   // pH (0–14)  ← НОВО


    // MARK: – Връзка
    @Relationship(inverse: \FoodItem.other) public var foodItem: FoodItem?

    // MARK: – Init
    public init(
        alcoholEthyl: Nutrient? = nil,
        caffeine:     Nutrient? = nil,
        theobromine:  Nutrient? = nil,
        cholesterol:  Nutrient? = nil,
        energyKcal:   Nutrient? = nil,
        water:        Nutrient? = nil,
        weightG:      Nutrient? = nil,
        ash:          Nutrient? = nil,
        betaine:      Nutrient? = nil,
        alkalinityPH: Nutrient? = nil
    ) {
        self.alcoholEthyl = alcoholEthyl
        self.caffeine     = caffeine
        self.theobromine  = theobromine
        self.cholesterol  = cholesterol
        self.energyKcal   = energyKcal
        self.water        = water
        self.weightG      = weightG
        self.ash          = ash
        self.betaine      = betaine
        self.alkalinityPH = alkalinityPH   
    }

}
