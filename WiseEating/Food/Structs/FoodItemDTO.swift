import Foundation
import SwiftData

// DTO sub-structs remain unchanged...
struct MacronutrientsDTO: Codable {
    var carbohydrates: Nutrient?
    var protein:       Nutrient?
    var fat:           Nutrient?
    var fiber:         Nutrient?
    var totalSugars:   Nutrient?
}
struct LipidsDTO: Codable {
    var totalSaturated: Nutrient?; var totalMonounsaturated: Nutrient?; var totalPolyunsaturated: Nutrient?
    var totalTrans: Nutrient?; var totalTransMonoenoic: Nutrient?; var totalTransPolyenoic: Nutrient?
    var sfa4_0: Nutrient?; var sfa6_0: Nutrient?; var sfa8_0: Nutrient?; var sfa10_0: Nutrient?
    var sfa12_0: Nutrient?; var sfa13_0: Nutrient?; var sfa14_0: Nutrient?; var sfa15_0: Nutrient?
    var sfa16_0: Nutrient?; var sfa17_0: Nutrient?; var sfa18_0: Nutrient?; var sfa20_0: Nutrient?
    var sfa22_0: Nutrient?; var sfa24_0: Nutrient?
    var mufa14_1: Nutrient?; var mufa15_1: Nutrient?; var mufa16_1: Nutrient?; var mufa17_1: Nutrient?
    var mufa18_1: Nutrient?; var mufa20_1: Nutrient?; var mufa22_1: Nutrient?; var mufa24_1: Nutrient?
    var tfa16_1_t: Nutrient?; var tfa18_1_t: Nutrient?; var tfa22_1_t: Nutrient?; var tfa18_2_t: Nutrient?
    var pufa18_2: Nutrient?; var pufa18_3: Nutrient?; var pufa18_4: Nutrient?
    var pufa20_2: Nutrient?; var pufa20_3: Nutrient?; var pufa20_4: Nutrient?; var pufa20_5: Nutrient?
    var pufa21_5: Nutrient?; var pufa22_4: Nutrient?; var pufa22_5: Nutrient?; var pufa22_6: Nutrient?
    var pufa2_4:  Nutrient?
}
struct VitaminsDTO: Codable {
    var vitaminA_RAE: Nutrient?; var retinol: Nutrient?
    var caroteneAlpha: Nutrient?; var caroteneBeta: Nutrient?; var cryptoxanthinBeta: Nutrient?
    var luteinZeaxanthin: Nutrient?; var lycopene: Nutrient?
    var vitaminB1_Thiamin: Nutrient?; var vitaminB2_Riboflavin: Nutrient?; var vitaminB3_Niacin: Nutrient?
    var vitaminB5_PantothenicAcid: Nutrient?; var vitaminB6: Nutrient?
    var folateDFE: Nutrient?; var folateFood: Nutrient?; var folateTotal: Nutrient?; var folicAcid: Nutrient?
    var vitaminB12: Nutrient?
    var vitaminC: Nutrient?; var vitaminD: Nutrient?; var vitaminE: Nutrient?
    var vitaminK: Nutrient?; var choline: Nutrient?
}
struct MineralsDTO: Codable {
    var calcium: Nutrient?; var iron: Nutrient?; var magnesium: Nutrient?
    var phosphorus: Nutrient?; var potassium: Nutrient?; var sodium: Nutrient?
    var selenium: Nutrient?; var zinc: Nutrient?; var copper: Nutrient?
    var manganese: Nutrient?; var fluoride: Nutrient?
}
struct OtherDTO: Codable {
    var alcoholEthyl: Nutrient?; var caffeine: Nutrient?; var theobromine: Nutrient?
    var cholesterol: Nutrient?; var energyKcal: Nutrient?; var water: Nutrient?
    var weightG: Nutrient?; var ash: Nutrient?; var betaine: Nutrient?
    var alkalinityPH: Nutrient?
}

struct AminoAcidsDTO: Codable {
    var alanine: Nutrient?; var arginine: Nutrient?; var asparticAcid: Nutrient?; var cystine: Nutrient?
    var glutamicAcid: Nutrient?; var glycine: Nutrient?; var histidine: Nutrient?; var isoleucine: Nutrient?
    var leucine: Nutrient?; var lysine: Nutrient?; var methionine: Nutrient?; var phenylalanine: Nutrient?
    var proline: Nutrient?; var threonine: Nutrient?; var tryptophan: Nutrient?; var tyrosine: Nutrient?
    var valine: Nutrient?; var serine: Nutrient?; var hydroxyproline: Nutrient?
}
struct CarbDetailsDTO: Codable {
    var starch: Nutrient?; var sucrose: Nutrient?; var glucose: Nutrient?
    var fructose: Nutrient?; var lactose: Nutrient?; var maltose: Nutrient?; var galactose: Nutrient?
}
struct SterolsDTO: Codable {
    var phytosterols: Nutrient?; var betaSitosterol: Nutrient?; var campesterol: Nutrient?; var stigmasterol: Nutrient?
}

// MARK: – Main DTO
struct FoodItemDTO: Codable, Sendable, Identifiable {

    // ───── Basic info ─────
    var id: Int
    var name: String
    var category: [FoodCategory]?
    var minAgeMonths: Int?
    var desctiption: String?
    // ───── Tags/taxonomy ─────
    var diets:     [String]?
    var allergens: [Allergen]?

    // ───── Nested JSON blocks ─────
    var macronutrients: MacronutrientsDTO?
    var lipids:         LipidsDTO?
    var vitamins:       VitaminsDTO?
    var minerals:       MineralsDTO?
    var other:          OtherDTO?
    var aminoAcids:     AminoAcidsDTO?
    var carbDetails:    CarbDetailsDTO?
    var sterols:        SterolsDTO?

    // --- CHANGE: This method now takes the pre-fetched diet map for efficiency ---
    func model(dietMap: [String: Diet]) -> FoodItem {

        // ✅ Case-insensitive, trimmed lookup на Diet
        let fetchedDiets: [Diet]
        if let dietNames = self.diets {
            fetchedDiets = dietNames.compactMap {
                dietMap[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
            }
        } else {
            fetchedDiets = []
        }

        // Base FoodItem
        let item = FoodItem(
            id: id,
            name: name,
            category: category,
            diets: fetchedDiets,           // ← вече са управлявани обекти от същия контекст
            allergens: allergens ?? []
        )
        
        item.itemDescription = desctiption
        // Mapping (без промени)
        if let m = macronutrients {
            item.macronutrients = MacronutrientsData(
                carbohydrates: m.carbohydrates, protein: m.protein, fat: m.fat,
                fiber: m.fiber, totalSugars: m.totalSugars
            )
            item.macronutrients?.foodItem = item
        }
        if let l = lipids {
            item.lipids = LipidsData(
                totalSaturated: l.totalSaturated, totalMonounsaturated: l.totalMonounsaturated, totalPolyunsaturated: l.totalPolyunsaturated,
                totalTrans: l.totalTrans, totalTransMonoenoic: l.totalTransMonoenoic, totalTransPolyenoic: l.totalTransPolyenoic,
                sfa4_0: l.sfa4_0, sfa6_0: l.sfa6_0, sfa8_0: l.sfa8_0, sfa10_0: l.sfa10_0,
                sfa12_0: l.sfa12_0, sfa13_0: l.sfa13_0, sfa14_0: l.sfa14_0, sfa15_0: l.sfa15_0,
                sfa16_0: l.sfa16_0, sfa17_0: l.sfa17_0, sfa18_0: l.sfa18_0, sfa20_0: l.sfa20_0,
                sfa22_0: l.sfa22_0, sfa24_0: l.sfa24_0, mufa14_1: l.mufa14_1, mufa15_1: l.mufa15_1,
                mufa16_1: l.mufa16_1, mufa17_1: l.mufa17_1, mufa18_1: l.mufa18_1, mufa20_1: l.mufa20_1,
                mufa22_1: l.mufa22_1, mufa24_1: l.mufa24_1, tfa16_1_t: l.tfa16_1_t, tfa18_1_t: l.tfa18_1_t,
                tfa22_1_t: l.tfa22_1_t, tfa18_2_t: l.tfa18_2_t, pufa18_2: l.pufa18_2, pufa18_3: l.pufa18_3,
                pufa18_4: l.pufa18_4, pufa20_2: l.pufa20_2, pufa20_3: l.pufa20_3, pufa20_4: l.pufa20_4,
                pufa20_5: l.pufa20_5, pufa21_5: l.pufa21_5, pufa22_4: l.pufa22_4, pufa22_5: l.pufa22_5,
                pufa22_6: l.pufa22_6, pufa2_4:  l.pufa2_4
            )
            item.lipids?.foodItem = item
        }
        if let v = vitamins {
            item.vitamins = VitaminsData(
                vitaminA_RAE: v.vitaminA_RAE, retinol: v.retinol,
                caroteneAlpha: v.caroteneAlpha, caroteneBeta: v.caroteneBeta,
                cryptoxanthinBeta: v.cryptoxanthinBeta, luteinZeaxanthin: v.luteinZeaxanthin,
                lycopene: v.lycopene, vitaminB1_Thiamin: v.vitaminB1_Thiamin,
                vitaminB2_Riboflavin: v.vitaminB2_Riboflavin, vitaminB3_Niacin: v.vitaminB3_Niacin,
                vitaminB5_PantothenicAcid: v.vitaminB5_PantothenicAcid, vitaminB6: v.vitaminB6,
                folateDFE: v.folateDFE, folateFood: v.folateFood, folateTotal: v.folateTotal,
                folicAcid: v.folicAcid, vitaminB12: v.vitaminB12, vitaminC: v.vitaminC,
                vitaminD: v.vitaminD, vitaminE: v.vitaminE, vitaminK: v.vitaminK,
                choline: v.choline
            )
            item.vitamins?.foodItem = item
        }
        if let m = minerals {
            item.minerals = MineralsData(
                calcium: m.calcium, iron: m.iron, magnesium: m.magnesium,
                phosphorus: m.phosphorus, potassium: m.potassium, sodium: m.sodium,
                selenium: m.selenium, zinc: m.zinc, copper: m.copper,
                manganese: m.manganese, fluoride: m.fluoride
            )
            item.minerals?.foodItem = item
        }
        if let o = other {
            item.other = OtherCompoundsData(
                alcoholEthyl: o.alcoholEthyl,
                caffeine:     o.caffeine,
                theobromine:  o.theobromine,
                cholesterol:  o.cholesterol,
                energyKcal:   o.energyKcal,
                water:        o.water,
                weightG:      o.weightG,
                ash:          o.ash,
                betaine:      o.betaine,
                alkalinityPH: o.alkalinityPH
            )
            item.other?.foodItem = item
        }
        if let a = aminoAcids {
            item.aminoAcids = AminoAcidsData(
                alanine: a.alanine, arginine: a.arginine, asparticAcid: a.asparticAcid, cystine: a.cystine,
                glutamicAcid: a.glutamicAcid, glycine: a.glycine, histidine: a.histidine, isoleucine: a.isoleucine,
                leucine: a.leucine, lysine: a.lysine, methionine: a.methionine, phenylalanine: a.phenylalanine,
                proline: a.proline, threonine: a.threonine, tryptophan: a.tryptophan, tyrosine: a.tyrosine,
                valine: a.valine, serine: a.serine, hydroxyproline: a.hydroxyproline
            )
            item.aminoAcids?.foodItem = item
        }
        if let c = carbDetails {
            item.carbDetails = CarbDetailsData(
                starch: c.starch, sucrose: c.sucrose, glucose: c.glucose,
                fructose: c.fructose, lactose: c.lactose, maltose: c.maltose, galactose: c.galactose
            )
            item.carbDetails?.foodItem = item
        }
        if let s = sterols {
            item.sterols = SterolsData(
                phytosterols: s.phytosterols, betaSitosterol: s.betaSitosterol,
                campesterol: s.campesterol, stigmasterol: s.stigmasterol
            )
            item.sterols?.foodItem = item
        }

        item.minAgeMonths = minAgeMonths ?? 0
        return item
    }
}

extension MacronutrientsDataCopy { convenience init(from dto: MacronutrientsDTO?) { guard let d=dto else {self.init();return}; self.init(carbohydrates: d.carbohydrates, protein: d.protein, fat: d.fat, fiber: d.fiber, totalSugars: d.totalSugars)}}
extension LipidsDataCopy { convenience init(from dto: LipidsDTO?) { guard let d=dto else {self.init();return}; self.init(totalSaturated: d.totalSaturated, totalMonounsaturated: d.totalMonounsaturated, totalPolyunsaturated: d.totalPolyunsaturated, totalTrans: d.totalTrans, totalTransMonoenoic: d.totalTransMonoenoic, totalTransPolyenoic: d.totalTransPolyenoic, sfa4_0: d.sfa4_0, sfa6_0: d.sfa6_0, sfa8_0: d.sfa8_0, sfa10_0: d.sfa10_0, sfa12_0: d.sfa12_0, sfa13_0: d.sfa13_0, sfa14_0: d.sfa14_0, sfa15_0: d.sfa15_0, sfa16_0: d.sfa16_0, sfa17_0: d.sfa17_0, sfa18_0: d.sfa18_0, sfa20_0: d.sfa20_0, sfa22_0: d.sfa22_0, sfa24_0: d.sfa24_0, mufa14_1: d.mufa14_1, mufa15_1: d.mufa15_1, mufa16_1: d.mufa16_1, mufa17_1: d.mufa17_1, mufa18_1: d.mufa18_1, mufa20_1: d.mufa20_1, mufa22_1: d.mufa22_1, mufa24_1: d.mufa24_1, tfa16_1_t: d.tfa16_1_t, tfa18_1_t: d.tfa18_1_t, tfa22_1_t: d.tfa22_1_t, tfa18_2_t: d.tfa18_2_t, pufa18_2: d.pufa18_2, pufa18_3: d.pufa18_3, pufa18_4: d.pufa18_4, pufa20_2: d.pufa20_2, pufa20_3: d.pufa20_3, pufa20_4: d.pufa20_4, pufa20_5: d.pufa20_5, pufa21_5: d.pufa21_5, pufa22_4: d.pufa22_4, pufa22_5: d.pufa22_5, pufa22_6: d.pufa22_6, pufa2_4: d.pufa2_4) } }
extension VitaminsDataCopy { convenience init(from dto: VitaminsDTO?) { guard let d=dto else {self.init();return}; self.init(vitaminA_RAE: d.vitaminA_RAE, retinol: d.retinol, caroteneAlpha: d.caroteneAlpha, caroteneBeta: d.caroteneBeta, cryptoxanthinBeta: d.cryptoxanthinBeta, luteinZeaxanthin: d.luteinZeaxanthin, lycopene: d.lycopene, vitaminB1_Thiamin: d.vitaminB1_Thiamin, vitaminB2_Riboflavin: d.vitaminB2_Riboflavin, vitaminB3_Niacin: d.vitaminB3_Niacin, vitaminB5_PantothenicAcid: d.vitaminB5_PantothenicAcid, vitaminB6: d.vitaminB6, folateDFE: d.folateDFE, folateFood: d.folateFood, folateTotal: d.folateTotal, folicAcid: d.folicAcid, vitaminB12: d.vitaminB12, vitaminC: d.vitaminC, vitaminD: d.vitaminD, vitaminE: d.vitaminE, vitaminK: d.vitaminK, choline: d.choline) } }
extension MineralsDataCopy { convenience init(from dto: MineralsDTO?) { guard let d=dto else {self.init();return}; self.init(calcium: d.calcium, iron: d.iron, magnesium: d.magnesium, phosphorus: d.phosphorus, potassium: d.potassium, sodium: d.sodium, selenium: d.selenium, zinc: d.zinc, copper: d.copper, manganese: d.manganese, fluoride: d.fluoride) } }
extension OtherCompoundsDataCopy {
    convenience init(from dto: OtherDTO?) {
        guard let d = dto else { self.init(); return }
        self.init(
            alcoholEthyl: d.alcoholEthyl,
            caffeine:     d.caffeine,
            theobromine:  d.theobromine,
            cholesterol:  d.cholesterol,
            energyKcal:   d.energyKcal,
            water:        d.water,
            weightG:      d.weightG,
            ash:          d.ash,
            betaine:      d.betaine,
            alkalinityPH: d.alkalinityPH   // ← НОВО
        )
    }
}

extension AminoAcidsDataCopy { convenience init(from dto: AminoAcidsDTO?) { guard let d=dto else {self.init();return}; self.init(alanine: d.alanine, arginine: d.arginine, asparticAcid: d.asparticAcid, cystine: d.cystine, glutamicAcid: d.glutamicAcid, glycine: d.glycine, histidine: d.histidine, isoleucine: d.isoleucine, leucine: d.leucine, lysine: d.lysine, methionine: d.methionine, phenylalanine: d.phenylalanine, proline: d.proline, threonine: d.threonine, tryptophan: d.tryptophan, tyrosine: d.tyrosine, valine: d.valine, serine: d.serine, hydroxyproline: d.hydroxyproline) } }
extension CarbDetailsDataCopy { convenience init(from dto: CarbDetailsDTO?) { guard let d=dto else {self.init();return}; self.init(starch: d.starch, sucrose: d.sucrose, glucose: d.glucose, fructose: d.fructose, lactose: d.lactose, maltose: d.maltose, galactose: d.galactose) } }
extension SterolsDataCopy { convenience init(from dto: SterolsDTO?) { guard let d=dto else {self.init();return}; self.init(phytosterols: d.phytosterols, betaSitosterol: d.betaSitosterol, campesterol: d.campesterol, stigmasterol: d.stigmasterol) } }

extension FoodItemCopy {
    convenience init(from dto: FoodItemDTO) {
        self.init(
            name: dto.name,
            category: dto.category,
            isRecipe: false,
            isMenu: false,
            isUserAdded: true,
            dietIDs: dto.diets,
            allergens: dto.allergens,
            photo: nil,
            gallery: nil,
            prepTimeMinutes: nil,
            itemDescription: dto.desctiption,
            macronutrients: .init(from: dto.macronutrients),
            lipids: .init(from: dto.lipids),
            vitamins: .init(from: dto.vitamins),
            minerals: .init(from: dto.minerals),
            other: .init(from: dto.other),
            aminoAcids: .init(from: dto.aminoAcids),
            carbDetails: .init(from: dto.carbDetails),
            sterols: .init(from: dto.sterols),
            ingredients: nil,
            originalID: nil
        )
    }
}

