import Foundation
import SwiftUI

//────────────────────────────────────────────────────────────────────────────
// MARK: –  MacroForm
//────────────────────────────────────────────────────────────────────────────
struct MacroForm: Sendable {
    var carbohydrates: Nutrient? = nil
    var protein:       Nutrient? = nil
    var fat:           Nutrient? = nil
    var fiber:         Nutrient? = nil
    var totalSugars:   Nutrient? = nil

    init(from data: MacronutrientsData?) {
        self.init()
        guard let d = data else { return }
        carbohydrates = d.carbohydrates; protein = d.protein; fat = d.fat
        fiber = d.fiber; totalSugars = d.totalSugars
    }
    init() { }
}

//────────────────────────────────────────────────────────────────────────────
// MARK: –  LipidForm
//────────────────────────────────────────────────────────────────────────────
struct LipidForm: Sendable {
    // Totals
    var totalSaturated: Nutrient? = nil; var totalMonounsaturated: Nutrient? = nil; var totalPolyunsaturated: Nutrient? = nil
    var totalTrans: Nutrient? = nil; var totalTransMonoenoic: Nutrient? = nil; var totalTransPolyenoic: Nutrient? = nil
    // SFA
    var sfa4_0: Nutrient? = nil; var sfa6_0: Nutrient? = nil; var sfa8_0: Nutrient? = nil; var sfa10_0: Nutrient? = nil
    var sfa12_0: Nutrient? = nil; var sfa13_0: Nutrient? = nil; var sfa14_0: Nutrient? = nil; var sfa15_0: Nutrient? = nil
    var sfa16_0: Nutrient? = nil; var sfa17_0: Nutrient? = nil; var sfa18_0: Nutrient? = nil; var sfa20_0: Nutrient? = nil
    var sfa22_0: Nutrient? = nil; var sfa24_0: Nutrient? = nil
    // MUFA
    var mufa14_1: Nutrient? = nil; var mufa15_1: Nutrient? = nil; var mufa16_1: Nutrient? = nil; var mufa17_1: Nutrient? = nil
    var mufa18_1: Nutrient? = nil; var mufa20_1: Nutrient? = nil; var mufa22_1: Nutrient? = nil; var mufa24_1: Nutrient? = nil
    // TFA
    var tfa16_1_t: Nutrient? = nil; var tfa18_1_t: Nutrient? = nil; var tfa22_1_t: Nutrient? = nil; var tfa18_2_t: Nutrient? = nil
    // PUFA
    var pufa18_2: Nutrient? = nil; var pufa18_3: Nutrient? = nil; var pufa18_4: Nutrient? = nil; var pufa20_2: Nutrient? = nil
    var pufa20_3: Nutrient? = nil; var pufa20_4: Nutrient? = nil; var pufa20_5: Nutrient? = nil; var pufa21_5: Nutrient? = nil
    var pufa22_4: Nutrient? = nil; var pufa22_5: Nutrient? = nil; var pufa22_6: Nutrient? = nil; var pufa2_4: Nutrient? = nil

    init(from data: LipidsData?) {
        self.init()
        guard let d = data else { return }
        totalSaturated = d.totalSaturated; totalMonounsaturated = d.totalMonounsaturated; totalPolyunsaturated = d.totalPolyunsaturated
        totalTrans = d.totalTrans; totalTransMonoenoic = d.totalTransMonoenoic; totalTransPolyenoic = d.totalTransPolyenoic
        sfa4_0 = d.sfa4_0; sfa6_0 = d.sfa6_0; sfa8_0 = d.sfa8_0; sfa10_0 = d.sfa10_0; sfa12_0 = d.sfa12_0; sfa13_0 = d.sfa13_0; sfa14_0 = d.sfa14_0; sfa15_0 = d.sfa15_0
        sfa16_0 = d.sfa16_0; sfa17_0 = d.sfa17_0; sfa18_0 = d.sfa18_0; sfa20_0 = d.sfa20_0; sfa22_0 = d.sfa22_0; sfa24_0 = d.sfa24_0
        mufa14_1 = d.mufa14_1; mufa15_1 = d.mufa15_1; mufa16_1 = d.mufa16_1; mufa17_1 = d.mufa17_1; mufa18_1 = d.mufa18_1; mufa20_1 = d.mufa20_1; mufa22_1 = d.mufa22_1; mufa24_1 = d.mufa24_1
        tfa16_1_t = d.tfa16_1_t; tfa18_1_t = d.tfa18_1_t; tfa22_1_t = d.tfa22_1_t; tfa18_2_t = d.tfa18_2_t
        pufa18_2 = d.pufa18_2; pufa18_3 = d.pufa18_3; pufa18_4 = d.pufa18_4; pufa20_2 = d.pufa20_2; pufa20_3 = d.pufa20_3; pufa20_4 = d.pufa20_4; pufa20_5 = d.pufa20_5
        pufa21_5 = d.pufa21_5; pufa22_4 = d.pufa22_4; pufa22_5 = d.pufa22_5; pufa22_6 = d.pufa22_6; pufa2_4 = d.pufa2_4
    }
    init() { }
}

//────────────────────────────────────────────────────────────────────────────
// MARK: –  VitaminForm
//────────────────────────────────────────────────────────────────────────────
struct VitaminForm: Sendable {
    var vitaminA_RAE: Nutrient? = nil; var retinol: Nutrient? = nil; var caroteneAlpha: Nutrient? = nil
    var caroteneBeta: Nutrient? = nil; var cryptoxanthinBeta: Nutrient? = nil; var luteinZeaxanthin: Nutrient? = nil
    var lycopene: Nutrient? = nil; var vitaminB1_Thiamin: Nutrient? = nil; var vitaminB2_Riboflavin: Nutrient? = nil
    var vitaminB3_Niacin: Nutrient? = nil; var vitaminB5_PantothenicAcid: Nutrient? = nil; var vitaminB6: Nutrient? = nil
    var folateDFE: Nutrient? = nil; var folateFood: Nutrient? = nil; var folateTotal: Nutrient? = nil; var folicAcid: Nutrient? = nil
    var vitaminB12: Nutrient? = nil; var vitaminC: Nutrient? = nil; var vitaminD: Nutrient? = nil
    var vitaminE: Nutrient? = nil; var vitaminK: Nutrient? = nil; var choline:  Nutrient? = nil

    init(from data: VitaminsData?) {
        self.init()
        guard let d = data else { return }
        vitaminA_RAE = d.vitaminA_RAE; retinol = d.retinol; caroteneAlpha = d.caroteneAlpha; caroteneBeta = d.caroteneBeta; cryptoxanthinBeta = d.cryptoxanthinBeta
        luteinZeaxanthin = d.luteinZeaxanthin; lycopene = d.lycopene; vitaminB1_Thiamin = d.vitaminB1_Thiamin; vitaminB2_Riboflavin = d.vitaminB2_Riboflavin
        vitaminB3_Niacin = d.vitaminB3_Niacin; vitaminB5_PantothenicAcid = d.vitaminB5_PantothenicAcid; vitaminB6 = d.vitaminB6; folateDFE = d.folateDFE
        folateFood = d.folateFood; folateTotal = d.folateTotal; folicAcid = d.folicAcid; vitaminB12 = d.vitaminB12; vitaminC = d.vitaminC; vitaminD = d.vitaminD
        vitaminE = d.vitaminE; vitaminK = d.vitaminK; choline = d.choline
    }
    init() { }
}

//────────────────────────────────────────────────────────────────────────────
// MARK: –  MineralForm
//────────────────────────────────────────────────────────────────────────────
struct MineralForm: Sendable {
    var calcium: Nutrient? = nil; var phosphorus: Nutrient? = nil; var magnesium:  Nutrient? = nil
    var potassium:  Nutrient? = nil; var sodium: Nutrient? = nil; var iron: Nutrient? = nil
    var zinc: Nutrient? = nil; var copper: Nutrient? = nil; var manganese:  Nutrient? = nil
    var selenium:   Nutrient? = nil; var fluoride:   Nutrient? = nil

    init(from data: MineralsData?) {
        self.init()
        guard let d = data else { return }
        calcium = d.calcium; phosphorus = d.phosphorus; magnesium = d.magnesium; potassium = d.potassium; sodium = d.sodium
        iron = d.iron; zinc = d.zinc; copper = d.copper; manganese = d.manganese; selenium = d.selenium; fluoride = d.fluoride
    }
    init() { }
}

//────────────────────────────────────────────────────────────────────────────
// MARK: –  OtherForm
//────────────────────────────────────────────────────────────────────────────
struct OtherForm: Sendable {
    var alcoholEthyl: Nutrient? = nil
    var caffeine:     Nutrient? = nil
    var theobromine:  Nutrient? = nil
    var cholesterol:  Nutrient? = nil
    var energyKcal:   Nutrient? = nil
    var water:        Nutrient? = nil
    var weightG:      Nutrient? = nil
    var ash:          Nutrient? = nil
    var betaine:      Nutrient? = nil
    var alkalinityPH: Nutrient? = nil

    init(from data: OtherCompoundsData?) {
        self.init()
        guard let d = data else { return }
        alcoholEthyl = d.alcoholEthyl
        caffeine     = d.caffeine
        theobromine  = d.theobromine
        cholesterol  = d.cholesterol
        energyKcal   = d.energyKcal
        water        = d.water
        weightG      = d.weightG
        ash          = d.ash
        betaine      = d.betaine
        alkalinityPH = d.alkalinityPH
    }
    init() { }
}


// MARK: - NEW FORMS
//────────────────────────────────────────────────────────────────────────────
// MARK: –  AminoAcidsForm
//────────────────────────────────────────────────────────────────────────────
struct AminoAcidsForm: Sendable {
    var alanine: Nutrient? = nil; var arginine: Nutrient? = nil; var asparticAcid: Nutrient? = nil; var cystine: Nutrient? = nil
    var glutamicAcid: Nutrient? = nil; var glycine: Nutrient? = nil; var histidine: Nutrient? = nil; var isoleucine: Nutrient? = nil
    var leucine: Nutrient? = nil; var lysine: Nutrient? = nil; var methionine: Nutrient? = nil; var phenylalanine: Nutrient? = nil
    var proline: Nutrient? = nil; var threonine: Nutrient? = nil; var tryptophan: Nutrient? = nil; var tyrosine: Nutrient? = nil
    var valine: Nutrient? = nil; var serine: Nutrient? = nil; var hydroxyproline: Nutrient? = nil

    init(from data: AminoAcidsData?) {
        self.init()
        guard let d = data else { return }
        alanine = d.alanine; arginine = d.arginine; asparticAcid = d.asparticAcid; cystine = d.cystine; glutamicAcid = d.glutamicAcid
        glycine = d.glycine; histidine = d.histidine; isoleucine = d.isoleucine; leucine = d.leucine; lysine = d.lysine; methionine = d.methionine
        phenylalanine = d.phenylalanine; proline = d.proline; threonine = d.threonine; tryptophan = d.tryptophan; tyrosine = d.tyrosine
        valine = d.valine; serine = d.serine; hydroxyproline = d.hydroxyproline
    }
    init() { }
}

//────────────────────────────────────────────────────────────────────────────
// MARK: –  CarbDetailsForm
//────────────────────────────────────────────────────────────────────────────
struct CarbDetailsForm: Sendable {
    var starch: Nutrient? = nil; var sucrose: Nutrient? = nil; var glucose: Nutrient? = nil
    var fructose: Nutrient? = nil; var lactose: Nutrient? = nil; var maltose: Nutrient? = nil; var galactose: Nutrient? = nil
    
    init(from data: CarbDetailsData?) {
        self.init()
        guard let d = data else { return }
        starch = d.starch; sucrose = d.sucrose; glucose = d.glucose; fructose = d.fructose
        lactose = d.lactose; maltose = d.maltose; galactose = d.galactose
    }
    init() { }
}

//────────────────────────────────────────────────────────────────────────────
// MARK: –  SterolsForm
//────────────────────────────────────────────────────────────────────────────
struct SterolsForm: Sendable {
    var phytosterols: Nutrient? = nil; var betaSitosterol: Nutrient? = nil
    var campesterol: Nutrient? = nil; var stigmasterol: Nutrient? = nil
    
    init(from data: SterolsData?) {
        self.init()
        guard let d = data else { return }
        phytosterols = d.phytosterols; betaSitosterol = d.betaSitosterol
        campesterol = d.campesterol; stigmasterol = d.stigmasterol
    }
    init() { }
}


//────────────────────────────────────────────────────────────────────────────
// MARK: –  Binding helper
//────────────────────────────────────────────────────────────────────────────
func nutBinding<Root: Sendable>(
    _ keyPath: WritableKeyPath<Root, Nutrient?>,
    state: Binding<Root>,
    unit: String = "g"
) -> Binding<String> {
    Binding<String>(
        get: {
            if let v = state.wrappedValue[keyPath: keyPath]?.value {
                return String(v)
            }
            return ""
        },
        set: { newStr in
            let trimmed = newStr.trimmingCharacters(in: .whitespaces)
            if let number = Double(trimmed) {
                if state.wrappedValue[keyPath: keyPath] == nil {
                    state.wrappedValue[keyPath: keyPath] =
                        Nutrient(value: number, unit: unit)
                } else {
                    state.wrappedValue[keyPath: keyPath]?.value = number
                }
            } else if trimmed.isEmpty {
                state.wrappedValue[keyPath: keyPath] = nil
            }
        }
    )
}

//────────────────────────────────────────────────────────────────────────────
// MARK: –  Речници: id → кратък етикет
//────────────────────────────────────────────────────────────────────────────

let vitaminLabelById: [String: String] = [
    "vitA": "Vit A",
    "retinol": "Retinol",
    "caroteneAlpha": "α-Carotene",
    "caroteneBeta": "β-Carotene",
    "cryptoxanthinBeta": "β-Cryptoxanthin",
    "luteinZeaxanthin": "Lutein + Zeax.",
    "lycopene": "Lycopene",

    "vitB1": "B1 Thiamin",
    "vitB2": "B2 Riboflavin",
    "vitB3": "B3 Niacin",
    "vitB5": "B5 Pant. acid",
    "vitB6": "B6",

    "folateDFE": "Folate DFE",
    "folateFood": "Folate food",
    "folateTotal": "Folate total",
    "folicAcid": "Folic acid",

    "vitB12": "B12",

    "vitC": "Vit C",
    "vitD": "Vit D",
    "vitE": "Vit E",
    "vitK": "Vit K",
    "choline": "Choline"
]

let mineralLabelById: [String: String] = [
    "calcium": "Calcium",
    "phosphorus": "Phosphorus",
    "magnesium": "Magnesium",
    "potassium": "Potassium",
    "sodium": "Sodium",

    "iron": "Iron",
    "zinc": "Zinc",
    "copper": "Copper",
    "manganese": "Manganese",
    "selenium": "Selenium",
    "fluoride": "Fluoride"
]

let lipidLabelById: [String: String] = [
    // Totals
    "totalSaturated":        "Sat. fat",
    "totalMonounsaturated":  "Mono-unsat.",
    "totalPolyunsaturated":  "Poly-unsat.",
    "totalTrans":            "Trans fat",
    "totalTransMonoenoic":   "Trans monoenoic",
    "totalTransPolyenoic":   "Trans polyenoic",

    // SFA
    "sfa4_0":  "C4:0",
    "sfa6_0":  "C6:0",
    "sfa8_0":  "C8:0",
    "sfa10_0": "C10:0",
    "sfa12_0": "C12:0",
    "sfa13_0": "C13:0",
    "sfa14_0": "C14:0",
    "sfa15_0": "C15:0",
    "sfa16_0": "C16:0",
    "sfa17_0": "C17:0",
    "sfa18_0": "C18:0",
    "sfa20_0": "C20:0",
    "sfa22_0": "C22:0",
    "sfa24_0": "C24:0",

    // MUFA
    "mufa14_1": "C14:1",
    "mufa15_1": "C15:1",
    "mufa16_1": "C16:1",
    "mufa17_1": "C17:1",
    "mufa18_1": "C18:1",
    "mufa20_1": "C20:1",
    "mufa22_1": "C22:1",
    "mufa24_1": "C24:1",

    // TFA
    "tfa16_1_t": "C16:1 t",
    "tfa18_1_t": "C18:1 t",
    "tfa22_1_t": "C22:1 t",
    "tfa18_2_t": "C18:2 t",

    // PUFA
    "pufa18_2": "C18:2",
    "pufa18_3": "C18:3",
    "pufa18_4": "C18:4",
    "pufa20_2": "C20:2",
    "pufa20_3": "C20:3",
    "pufa20_4": "C20:4",
    "pufa20_5": "C20:5",
    "pufa21_5": "C21:5",
    "pufa22_4": "C22:4",
    "pufa22_5": "C22:5",
    "pufa22_6": "C22:6",
    "pufa2_4":  "C2:4"
]


let otherLabelById: [String: String] = [
    "alcoholEthyl": "Alcohol",
    "caffeine": "Caffeine",
    "theobromine": "Theobromine",
    "cholesterol": "Cholesterol",
    "water": "Water",
    "energyKcal": "Energy",
    "ash": "Ash",
    "betaine": "Betaine",
    "alkalinityPH": "pH"
]

//────────────────────────────────────────────────────────────────────────────
// MARK: –  Access maps (id → getter)
//────────────────────────────────────────────────────────────────────────────

nonisolated(unsafe) let vitaminAccess: [String : (VitaminsData) -> Nutrient?] = [
    "vitA": { $0.vitaminA_RAE },
    "retinol": { $0.retinol },
    "caroteneAlpha": { $0.caroteneAlpha },
    "caroteneBeta": { $0.caroteneBeta },
    "cryptoxanthinBeta": { $0.cryptoxanthinBeta },
    "luteinZeaxanthin": { $0.luteinZeaxanthin },
    "lycopene": { $0.lycopene },

    "vitB1": { $0.vitaminB1_Thiamin },
    "vitB2": { $0.vitaminB2_Riboflavin },
    "vitB3": { $0.vitaminB3_Niacin },
    "vitB5": { $0.vitaminB5_PantothenicAcid },
    "vitB6": { $0.vitaminB6 },

    "folateDFE": { $0.folateDFE },
    "folateFood": { $0.folateFood },
    "folateTotal": { $0.folateTotal },
    "folicAcid": { $0.folicAcid },

    "vitB12": { $0.vitaminB12 },

    "vitC": { $0.vitaminC },
    "vitD": { $0.vitaminD },
    "vitE": { $0.vitaminE },
    "vitK": { $0.vitaminK },

    "choline": { $0.choline }
]

nonisolated(unsafe) let mineralAccess: [String : (MineralsData) -> Nutrient?] = [
    "calcium": { $0.calcium },
    "phosphorus": { $0.phosphorus },
    "magnesium": { $0.magnesium },
    "potassium": { $0.potassium },
    "sodium": { $0.sodium },

    "iron": { $0.iron },
    "zinc": { $0.zinc },
    "copper": { $0.copper },
    "manganese": { $0.manganese },
    "selenium": { $0.selenium },
    "fluoride": { $0.fluoride }
]

@MainActor let lipidAccessForDisplay: [String: (LipidsData) -> Nutrient?] = [
    // Totals
    "totalSaturated":        { $0.totalSaturated },
    "totalMonounsaturated":  { $0.totalMonounsaturated },
    "totalPolyunsaturated":  { $0.totalPolyunsaturated },
    "totalTrans":            { $0.totalTrans },
    "totalTransMonoenoic":   { $0.totalTransMonoenoic },
    "totalTransPolyenoic":   { $0.totalTransPolyenoic },

    // SFA
    "sfa4_0":  { $0.sfa4_0  },
    "sfa6_0":  { $0.sfa6_0  },
    "sfa8_0":  { $0.sfa8_0  },
    "sfa10_0": { $0.sfa10_0 },
    "sfa12_0": { $0.sfa12_0 },
    "sfa13_0": { $0.sfa13_0 },
    "sfa14_0": { $0.sfa14_0 },
    "sfa15_0": { $0.sfa15_0 },
    "sfa16_0": { $0.sfa16_0 },
    "sfa17_0": { $0.sfa17_0 },
    "sfa18_0": { $0.sfa18_0 },
    "sfa20_0": { $0.sfa20_0 },
    "sfa22_0": { $0.sfa22_0 },
    "sfa24_0": { $0.sfa24_0 },

    // MUFA
    "mufa14_1": { $0.mufa14_1 },
    "mufa15_1": { $0.mufa15_1 },
    "mufa16_1": { $0.mufa16_1 },
    "mufa17_1": { $0.mufa17_1 },
    "mufa18_1": { $0.mufa18_1 },
    "mufa20_1": { $0.mufa20_1 },
    "mufa22_1": { $0.mufa22_1 },
    "mufa24_1": { $0.mufa24_1 },

    // TFA
    "tfa16_1_t": { $0.tfa16_1_t },
    "tfa18_1_t": { $0.tfa18_1_t },
    "tfa22_1_t": { $0.tfa22_1_t },
    "tfa18_2_t": { $0.tfa18_2_t },

    // PUFA
    "pufa18_2": { $0.pufa18_2 },
    "pufa18_3": { $0.pufa18_3 },
    "pufa18_4": { $0.pufa18_4 },
    "pufa20_2": { $0.pufa20_2 },
    "pufa20_3": { $0.pufa20_3 },
    "pufa20_4": { $0.pufa20_4 },
    "pufa20_5": { $0.pufa20_5 },
    "pufa21_5": { $0.pufa21_5 },
    "pufa22_4": { $0.pufa22_4 },
    "pufa22_5": { $0.pufa22_5 },
    "pufa22_6": { $0.pufa22_6 },
    "pufa2_4":  { $0.pufa2_4  }
]


@MainActor let otherAccessForDisplay: [String: (OtherCompoundsData) -> Nutrient?] = [
    "alcoholEthyl": { $0.alcoholEthyl },
    "caffeine":     { $0.caffeine },
    "theobromine":  { $0.theobromine },
    "cholesterol":  { $0.cholesterol },
    "water":        { $0.water },
    "energyKcal":   { $0.energyKcal },
    "ash":          { $0.ash },
    "betaine":      { $0.betaine },
    "alkalinityPH": { $0.alkalinityPH }
]

// ────────────────────────────────────────────────────────────────────────────
// MARK: – Labels (Amino, CarbDetails, Sterols)
// ────────────────────────────────────────────────────────────────────────────

let aminoLabelById: [String: String] = [
    "alanine":"Alanine","arginine":"Arginine","asparticAcid":"Aspartic Acid","cystine":"Cystine",
    "glutamicAcid":"Glutamic Acid","glycine":"Glycine","histidine":"Histidine","isoleucine":"Isoleucine",
    "leucine":"Leucine","lysine":"Lysine","methionine":"Methionine","phenylalanine":"Phenylalanine",
    "proline":"Proline","threonine":"Threonine","tryptophan":"Tryptophan","tyrosine":"Tyrosine",
    "valine":"Valine","serine":"Serine","hydroxyproline":"Hydroxyproline"
]

let carbDetailsLabelById: [String: String] = [
    "starch":"Starch","sucrose":"Sucrose","glucose":"Glucose","fructose":"Fructose",
    "lactose":"Lactose","maltose":"Maltose","galactose":"Galactose"
]

let sterolsLabelById: [String: String] = [
    "phytosterols":"Phytosterols","betaSitosterol":"Beta-Sitosterol",
    "campesterol":"Campesterol","stigmasterol":"Stigmasterol"
]

// ────────────────────────────────────────────────────────────────────────────
// MARK: – Access maps (Amino, CarbDetails, Sterols)
// ────────────────────────────────────────────────────────────────────────────

@MainActor let aminoAccessForDisplay: [String: (AminoAcidsData) -> Nutrient?] = [
    "alanine": { $0.alanine }, "arginine": { $0.arginine }, "asparticAcid": { $0.asparticAcid },
    "cystine": { $0.cystine }, "glutamicAcid": { $0.glutamicAcid }, "glycine": { $0.glycine },
    "histidine": { $0.histidine }, "isoleucine": { $0.isoleucine }, "leucine": { $0.leucine },
    "lysine": { $0.lysine }, "methionine": { $0.methionine }, "phenylalanine": { $0.phenylalanine },
    "proline": { $0.proline }, "threonine": { $0.threonine }, "tryptophan": { $0.tryptophan },
    "tyrosine": { $0.tyrosine }, "valine": { $0.valine }, "serine": { $0.serine },
    "hydroxyproline": { $0.hydroxyproline }
]

@MainActor let carbDetailsAccessForDisplay: [String: (CarbDetailsData) -> Nutrient?] = [
    "starch": { $0.starch }, "sucrose": { $0.sucrose }, "glucose": { $0.glucose },
    "fructose": { $0.fructose }, "lactose": { $0.lactose }, "maltose": { $0.maltose },
    "galactose": { $0.galactose }
]

@MainActor let sterolsAccessForDisplay: [String: (SterolsData) -> Nutrient?] = [
    "phytosterols": { $0.phytosterols }, "betaSitosterol": { $0.betaSitosterol },
    "campesterol": { $0.campesterol }, "stigmasterol": { $0.stigmasterol }
]

struct NutrientRow {
    let label: String
    let unit:  String
    let field: Binding<String>
}

extension MacroForm {
    init(
        carbohydrates: Nutrient? = nil,
        protein: Nutrient? = nil,
        fat: Nutrient? = nil,
        fiber: Nutrient? = nil,
        totalSugars: Nutrient? = nil
    ) {
        self.carbohydrates = carbohydrates
        self.protein = protein
        self.fat = fat
        self.fiber = fiber
        self.totalSugars = totalSugars
    }
}

// MARK: - Convenience inits so we can use named params

extension OtherForm {
    init(
        alcoholEthyl: Nutrient? = nil, caffeine: Nutrient? = nil, theobromine: Nutrient? = nil,
        cholesterol: Nutrient? = nil, energyKcal: Nutrient? = nil, water: Nutrient? = nil,
        weightG: Nutrient? = nil, ash: Nutrient? = nil, betaine: Nutrient? = nil,
        alkalinityPH: Nutrient? = nil
    ) {
        self.init()
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


extension LipidForm {
    init(
        // Totals
        totalSaturated: Nutrient? = nil, totalMonounsaturated: Nutrient? = nil, totalPolyunsaturated: Nutrient? = nil,
        totalTrans: Nutrient? = nil, totalTransMonoenoic: Nutrient? = nil, totalTransPolyenoic: Nutrient? = nil,
        // SFA
        sfa4_0: Nutrient? = nil, sfa6_0: Nutrient? = nil, sfa8_0: Nutrient? = nil, sfa10_0: Nutrient? = nil,
        sfa12_0: Nutrient? = nil, sfa13_0: Nutrient? = nil, sfa14_0: Nutrient? = nil, sfa15_0: Nutrient? = nil,
        sfa16_0: Nutrient? = nil, sfa17_0: Nutrient? = nil, sfa18_0: Nutrient? = nil, sfa20_0: Nutrient? = nil,
        sfa22_0: Nutrient? = nil, sfa24_0: Nutrient? = nil,
        // MUFA
        mufa14_1: Nutrient? = nil, mufa15_1: Nutrient? = nil, mufa16_1: Nutrient? = nil, mufa17_1: Nutrient? = nil,
        mufa18_1: Nutrient? = nil, mufa20_1: Nutrient? = nil, mufa22_1: Nutrient? = nil, mufa24_1: Nutrient? = nil,
        // TFA
        tfa16_1_t: Nutrient? = nil, tfa18_1_t: Nutrient? = nil, tfa22_1_t: Nutrient? = nil, tfa18_2_t: Nutrient? = nil,
        // PUFA
        pufa18_2: Nutrient? = nil, pufa18_3: Nutrient? = nil, pufa18_4: Nutrient? = nil, pufa20_2: Nutrient? = nil,
        pufa20_3: Nutrient? = nil, pufa20_4: Nutrient? = nil, pufa20_5: Nutrient? = nil, pufa21_5: Nutrient? = nil,
        pufa22_4: Nutrient? = nil, pufa22_5: Nutrient? = nil, pufa22_6: Nutrient? = nil, pufa2_4: Nutrient? = nil
    ) {
        self.init()
        self.totalSaturated = totalSaturated
        self.totalMonounsaturated = totalMonounsaturated
        self.totalPolyunsaturated = totalPolyunsaturated
        self.totalTrans = totalTrans
        self.totalTransMonoenoic = totalTransMonoenoic
        self.totalTransPolyenoic = totalTransPolyenoic

        self.sfa4_0 = sfa4_0; self.sfa6_0 = sfa6_0; self.sfa8_0 = sfa8_0; self.sfa10_0 = sfa10_0
        self.sfa12_0 = sfa12_0; self.sfa13_0 = sfa13_0; self.sfa14_0 = sfa14_0; self.sfa15_0 = sfa15_0
        self.sfa16_0 = sfa16_0; self.sfa17_0 = sfa17_0; self.sfa18_0 = sfa18_0; self.sfa20_0 = sfa20_0
        self.sfa22_0 = sfa22_0; self.sfa24_0 = sfa24_0

        self.mufa14_1 = mufa14_1; self.mufa15_1 = mufa15_1; self.mufa16_1 = mufa16_1; self.mufa17_1 = mufa17_1
        self.mufa18_1 = mufa18_1; self.mufa20_1 = mufa20_1; self.mufa22_1 = mufa22_1; self.mufa24_1 = mufa24_1

        self.tfa16_1_t = tfa16_1_t; self.tfa18_1_t = tfa18_1_t; self.tfa22_1_t = tfa22_1_t; self.tfa18_2_t = tfa18_2_t

        self.pufa18_2 = pufa18_2; self.pufa18_3 = pufa18_3; self.pufa18_4 = pufa18_4; self.pufa20_2 = pufa20_2
        self.pufa20_3 = pufa20_3; self.pufa20_4 = pufa20_4; self.pufa20_5 = pufa20_5; self.pufa21_5 = pufa21_5
        self.pufa22_4 = pufa22_4; self.pufa22_5 = pufa22_5; self.pufa22_6 = pufa22_6; self.pufa2_4 = pufa2_4
    }
}

extension VitaminForm {
    init(
        vitaminA_RAE: Nutrient? = nil, retinol: Nutrient? = nil, caroteneAlpha: Nutrient? = nil,
        caroteneBeta: Nutrient? = nil, cryptoxanthinBeta: Nutrient? = nil, luteinZeaxanthin: Nutrient? = nil,
        lycopene: Nutrient? = nil, vitaminB1_Thiamin: Nutrient? = nil, vitaminB2_Riboflavin: Nutrient? = nil,
        vitaminB3_Niacin: Nutrient? = nil, vitaminB5_PantothenicAcid: Nutrient? = nil, vitaminB6: Nutrient? = nil,
        folateDFE: Nutrient? = nil, folateFood: Nutrient? = nil, folateTotal: Nutrient? = nil, folicAcid: Nutrient? = nil,
        vitaminB12: Nutrient? = nil, vitaminC: Nutrient? = nil, vitaminD: Nutrient? = nil,
        vitaminE: Nutrient? = nil, vitaminK: Nutrient? = nil, choline: Nutrient? = nil
    ) {
        self.init()
        self.vitaminA_RAE = vitaminA_RAE; self.retinol = retinol; self.caroteneAlpha = caroteneAlpha
        self.caroteneBeta = caroteneBeta; self.cryptoxanthinBeta = cryptoxanthinBeta; self.luteinZeaxanthin = luteinZeaxanthin
        self.lycopene = lycopene; self.vitaminB1_Thiamin = vitaminB1_Thiamin; self.vitaminB2_Riboflavin = vitaminB2_Riboflavin
        self.vitaminB3_Niacin = vitaminB3_Niacin; self.vitaminB5_PantothenicAcid = vitaminB5_PantothenicAcid; self.vitaminB6 = vitaminB6
        self.folateDFE = folateDFE; self.folateFood = folateFood; self.folateTotal = folateTotal; self.folicAcid = folicAcid
        self.vitaminB12 = vitaminB12; self.vitaminC = vitaminC; self.vitaminD = vitaminD
        self.vitaminE = vitaminE; self.vitaminK = vitaminK; self.choline = choline
    }
}

extension MineralForm {
    init(
        calcium: Nutrient? = nil, phosphorus: Nutrient? = nil, magnesium: Nutrient? = nil,
        potassium: Nutrient? = nil, sodium: Nutrient? = nil, iron: Nutrient? = nil,
        zinc: Nutrient? = nil, copper: Nutrient? = nil, manganese: Nutrient? = nil,
        selenium: Nutrient? = nil, fluoride: Nutrient? = nil
    ) {
        self.init()
        self.calcium = calcium; self.phosphorus = phosphorus; self.magnesium = magnesium
        self.potassium = potassium; self.sodium = sodium; self.iron = iron
        self.zinc = zinc; self.copper = copper; self.manganese = manganese
        self.selenium = selenium; self.fluoride = fluoride
    }
}

extension AminoAcidsForm {
    init(
        alanine: Nutrient? = nil, arginine: Nutrient? = nil, asparticAcid: Nutrient? = nil, cystine: Nutrient? = nil,
        glutamicAcid: Nutrient? = nil, glycine: Nutrient? = nil, histidine: Nutrient? = nil, isoleucine: Nutrient? = nil,
        leucine: Nutrient? = nil, lysine: Nutrient? = nil, methionine: Nutrient? = nil, phenylalanine: Nutrient? = nil,
        proline: Nutrient? = nil, threonine: Nutrient? = nil, tryptophan: Nutrient? = nil, tyrosine: Nutrient? = nil,
        valine: Nutrient? = nil, serine: Nutrient? = nil, hydroxyproline: Nutrient? = nil
    ) {
        self.init()
        self.alanine = alanine; self.arginine = arginine; self.asparticAcid = asparticAcid; self.cystine = cystine
        self.glutamicAcid = glutamicAcid; self.glycine = glycine; self.histidine = histidine; self.isoleucine = isoleucine
        self.leucine = leucine; self.lysine = lysine; self.methionine = methionine; self.phenylalanine = phenylalanine
        self.proline = proline; self.threonine = threonine; self.tryptophan = tryptophan; self.tyrosine = tyrosine
        self.valine = valine; self.serine = serine; self.hydroxyproline = hydroxyproline
    }
}

extension CarbDetailsForm {
    init(
        starch: Nutrient? = nil, sucrose: Nutrient? = nil, glucose: Nutrient? = nil,
        fructose: Nutrient? = nil, lactose: Nutrient? = nil, maltose: Nutrient? = nil, galactose: Nutrient? = nil
    ) {
        self.init()
        self.starch = starch; self.sucrose = sucrose; self.glucose = glucose
        self.fructose = fructose; self.lactose = lactose; self.maltose = maltose; self.galactose = galactose
    }
}

extension SterolsForm {
    init(
        phytosterols: Nutrient? = nil, betaSitosterol: Nutrient? = nil,
        campesterol: Nutrient? = nil, stigmasterol: Nutrient? = nil
    ) {
        self.init()
        self.phytosterols = phytosterols
        self.betaSitosterol = betaSitosterol
        self.campesterol = campesterol
        self.stigmasterol = stigmasterol
    }
}
