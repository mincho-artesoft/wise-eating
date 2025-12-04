import SwiftData
import Foundation

@Model
public final class VitaminsData: Identifiable {
    @Attribute(.unique) public var id = UUID()

    public var vitaminA_RAE:        Nutrient?
    public var retinol:             Nutrient?
    public var caroteneAlpha:       Nutrient?
    public var caroteneBeta:        Nutrient?
    public var cryptoxanthinBeta:   Nutrient?
    public var luteinZeaxanthin:    Nutrient?
    public var lycopene:            Nutrient?

    public var vitaminB1_Thiamin:           Nutrient?
    public var vitaminB2_Riboflavin:        Nutrient?
    public var vitaminB3_Niacin:            Nutrient?
    public var vitaminB5_PantothenicAcid:   Nutrient?
    public var vitaminB6:                   Nutrient?
    public var folateDFE:                   Nutrient?
    public var folateFood:                  Nutrient?
    public var folateTotal:                 Nutrient?
    public var folicAcid:                   Nutrient?
    public var vitaminB12:                  Nutrient?

    public var vitaminC:  Nutrient?
    public var vitaminD:  Nutrient?
    public var vitaminE:  Nutrient?
    public var vitaminK:  Nutrient?

    public var choline:   Nutrient?

    @Relationship(inverse: \FoodItem.vitamins) public var foodItem: FoodItem?

    // MARK: – Init
    public init(
        vitaminA_RAE:      Nutrient? = nil,
        retinol:           Nutrient? = nil,
        caroteneAlpha:     Nutrient? = nil,
        caroteneBeta:      Nutrient? = nil,
        cryptoxanthinBeta: Nutrient? = nil,
        luteinZeaxanthin:  Nutrient? = nil,
        lycopene:          Nutrient? = nil,
        vitaminB1_Thiamin:         Nutrient? = nil,
        vitaminB2_Riboflavin:      Nutrient? = nil,
        vitaminB3_Niacin:          Nutrient? = nil,
        vitaminB5_PantothenicAcid: Nutrient? = nil,
        vitaminB6:                 Nutrient? = nil,
        folateDFE:                 Nutrient? = nil,
        folateFood:                Nutrient? = nil,
        folateTotal:               Nutrient? = nil,
        folicAcid:                 Nutrient? = nil,
        vitaminB12:                Nutrient? = nil,
        vitaminC:        Nutrient? = nil,
        vitaminD:        Nutrient? = nil,
        vitaminE:        Nutrient? = nil,
        vitaminK:        Nutrient? = nil,
        choline:         Nutrient? = nil
    ) {
        self.vitaminA_RAE      = vitaminA_RAE
        self.retinol           = retinol
        self.caroteneAlpha     = caroteneAlpha
        self.caroteneBeta      = caroteneBeta
        self.cryptoxanthinBeta = cryptoxanthinBeta
        self.luteinZeaxanthin  = luteinZeaxanthin
        self.lycopene          = lycopene

        self.vitaminB1_Thiamin         = vitaminB1_Thiamin
        self.vitaminB2_Riboflavin      = vitaminB2_Riboflavin
        self.vitaminB3_Niacin          = vitaminB3_Niacin
        self.vitaminB5_PantothenicAcid = vitaminB5_PantothenicAcid
        self.vitaminB6                 = vitaminB6
        self.folateDFE                 = folateDFE
        self.folateFood                = folateFood
        self.folateTotal               = folateTotal
        self.folicAcid                 = folicAcid
        self.vitaminB12                = vitaminB12

        self.vitaminC  = vitaminC
        self.vitaminD  = vitaminD
        self.vitaminE  = vitaminE
        self.vitaminK  = vitaminK

        self.choline   = choline
    }

    // MARK: - KeyPath map за Predicate push
    // ключовете са точно тези, които идват от JSON генератора
    public static func keyPath(for id: String) -> KeyPath<VitaminsData, Nutrient?> {
        switch id {
        case "vitaminA_RAE": return \.vitaminA_RAE
        case "retinol": return \.retinol
        case "caroteneAlpha": return \.caroteneAlpha
        case "caroteneBeta": return \.caroteneBeta
        case "cryptoxanthinBeta": return \.cryptoxanthinBeta
        case "luteinZeaxanthin": return \.luteinZeaxanthin
        case "lycopene": return \.lycopene

        case "vitaminB1_Thiamin": return \.vitaminB1_Thiamin
        case "vitaminB2_Riboflavin": return \.vitaminB2_Riboflavin
        case "vitaminB3_Niacin": return \.vitaminB3_Niacin
        case "vitaminB5_PantothenicAcid": return \.vitaminB5_PantothenicAcid
        case "vitaminB6": return \.vitaminB6
        case "folateDFE": return \.folateDFE
        case "folateFood": return \.folateFood
        case "folateTotal": return \.folateTotal
        case "folicAcid": return \.folicAcid
        case "vitaminB12": return \.vitaminB12

        case "vitaminC": return \.vitaminC
        case "vitaminD": return \.vitaminD
        case "vitaminE": return \.vitaminE
        case "vitaminK": return \.vitaminK

        case "choline": return \.choline
        default: return \.vitaminC // безопасно по подразбиране
        }
    }
}
