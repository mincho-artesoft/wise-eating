import SwiftData
import Foundation
import SwiftUI
import UIKit // Required for UIImage

@Model
public final class FoodItem: Identifiable {

    #Index<FoodItem>([\.name], [\.isUserAdded, \.isRecipe], [\.nameNormalized])

    // MARK: – Basic
    @Attribute(.unique) public var id: Int

    public var searchTokens: [String] = []
    public var searchTokens2: [String] = []

    public var name: String {
        didSet {
            self.nameNormalized = name.foldedSearchKey
            self.searchTokens = FoodItem.makeTokens(from: name)
            self.searchTokens2 = FoodItem.makeTokens2(from: name)
        }
    }
    
    public var minAgeMonths: Int = 0
    public var nameNormalized: String
    public var category: [FoodCategory]?

    public var isRecipe: Bool = false
    public var isMenu: Bool = false
    public var isUserAdded: Bool = true
    public var isFavorite: Bool = false

    // MARK: – Tags
    @Relationship(deleteRule: .nullify)
    public var diets: [Diet]?

    public var allergens: [Allergen]?

    // MARK: – Nutrition Relationships
    @Relationship(deleteRule: .cascade) public var macronutrients: MacronutrientsData?
    @Relationship(deleteRule: .cascade) public var lipids:         LipidsData?
    @Relationship(deleteRule: .cascade) public var vitamins:       VitaminsData?
    @Relationship(deleteRule: .cascade) public var minerals:       MineralsData?
    @Relationship(deleteRule: .cascade) public var other:          OtherCompoundsData?
    @Relationship(deleteRule: .cascade) public var aminoAcids:     AminoAcidsData?
    @Relationship(deleteRule: .cascade) public var carbDetails:    CarbDetailsData?
    @Relationship(deleteRule: .cascade) public var sterols:        SterolsData?

    // MARK: – Media & Meta
    @Attribute(.externalStorage) public var photo: Data?
    @Relationship(deleteRule: .cascade) public var gallery: [FoodPhoto]?
    public var prepTimeMinutes: Int?
    public var itemDescription: String?

    // MARK: – Recipe Links & Storage
    @Relationship(deleteRule: .cascade)
    public var ingredients: [IngredientLink]?

    @Relationship(deleteRule: .cascade, inverse: \StorageItem.food)
    var stockEntries: [StorageItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \MealLogStorageLink.food)
    public var mealLogLinks: [MealLogStorageLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \StorageTransaction.food)
    public var storageTransactions: [StorageTransaction]? = []
    
    @Relationship(inverse: \Node.linkedFoods)
    public var nodes: [Node]? = []

    // MARK: - Tokenization Static Logic
    static func makeTokens(from name: String) -> [String] {
        // normalize
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "[-/_]", with: " ", options: .regularExpression)
            .folding(options: .diacriticInsensitive, locale: .current)

        // split to raw words
        let raw = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        // drop stopwords/negators (kept small and domain-aware)
        let stop: Set<String> = [
            "and","or","with","without","in","of","the","a","an",
            "style","type","made","from","plus","no","low","reduced"
        ]
        let negators: Set<String> = ["excluding","except","without","no"]
        let words = raw.filter { !stop.contains($0) }

        // unigrams
        var tokens = words

        // n-grams (bigrams, trigrams)
        if words.count >= 2 {
            for i in 0..<(words.count-1) {
                tokens.append(words[i] + " " + words[i+1])
            }
        }
        if words.count >= 3 {
            for i in 0..<(words.count-2) {
                tokens.append(words[i] + " " + words[i+1] + " " + words[i+2])
            }
        }

        // keep negator markers as single tokens so we can detect them later in scoring
        tokens.append(contentsOf: raw.filter { negators.contains($0) })

        return tokens
    }
    
    static func makeTokens2(from name: String) -> [String] {
        return name
          .lowercased()
          .folding(options: .diacriticInsensitive, locale: .current)
          .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
          .map { String($0) }
    }
    
    // MARK: – Init
    public init(
        id: Int,
        name: String,
        category: [FoodCategory]? = nil,
        isRecipe: Bool = false,
        isMenu: Bool = false,
        isUserAdded: Bool = true,
        diets: [Diet]? = nil,
        allergens: [Allergen]? = nil,
        photo: Data? = nil,
        gallery: [FoodPhoto]? = nil,
        prepTimeMinutes: Int? = nil,
        itemDescription: String? = nil,
        macronutrients: MacronutrientsData? = nil,
        lipids: LipidsData? = nil,
        vitamins: VitaminsData? = nil,
        minerals: MineralsData? = nil,
        other: OtherCompoundsData? = nil,
        aminoAcids: AminoAcidsData? = nil,
        carbDetails: CarbDetailsData? = nil,
        sterols: SterolsData? = nil,
        ingredients: [IngredientLink]? = nil
    ) {
        self.id = id
        self.name = name
        self.nameNormalized = name.foldedSearchKey
        self.searchTokens = FoodItem.makeTokens(from: name)
        self.searchTokens2 = FoodItem.makeTokens2(from: name)
        self.category = category
        self.isRecipe = isRecipe
        self.isMenu = isMenu
        self.isUserAdded = isUserAdded
        self.diets = diets ?? []
        self.allergens = allergens ?? []
        self.photo = photo
        self.gallery = gallery
        self.prepTimeMinutes = prepTimeMinutes
        self.itemDescription = itemDescription
        self.macronutrients = macronutrients
        self.lipids = lipids
        self.vitamins = vitamins
        self.minerals = minerals
        self.other = other
        self.aminoAcids = aminoAcids
        self.carbDetails = carbDetails
        self.sterols = sterols
        self.ingredients = ingredients
    }
}

// MARK: - Hashable
extension FoodItem: Hashable {
    public static func == (lhs: FoodItem, rhs: FoodItem) -> Bool {
        return lhs.id == rhs.id && lhs.persistentModelID == rhs.persistentModelID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SmartFoodSearch Adapter
// This extension maps the SwiftData Class properties to the Interface required by SmartFoodSearch logic.
extension FoodItem {
    
    // 1. Search Logic Helper Properties
    var originalName: String { self.name }
    
    var lowercasedName: String {
        self.name.lowercased()
    }
    
    var paddedLowercasedName: String {
        " " + lowercasedName + " "
    }
    
    var tokens: Set<String> {
        return Set(self.searchTokens)
    }
    
    var ph: Double {
        return self.other?.alkalinityPH?.value ?? 0.0
    }
    
    // 2. Logic Methods
    func fits(dietName: String) -> Bool {
        guard let diets = self.diets else { return false }
        // Case-insensitive check against connected Diet entities
        return diets.contains { $0.name.localizedCaseInsensitiveContains(dietName) }
    }
    
    func contains(allergen: Allergen) -> Bool {
        guard let allergens = self.allergens else { return false }
        // Case-insensitive check against connected Allergen entities
        return allergens.contains { $0.name.localizedCaseInsensitiveContains(allergen.rawValue) }
    }
    
    // 3. Unified Nutrient Access
    // Maps the `NutrientType` enum (used by Search) to the specific optional properties in the SwiftData model.
    func value(for nutrient: NutrientType) -> Double {
        switch nutrient {
        // Macros
        case .energy: return self.other?.energyKcal?.value ?? 0.0
        case .protein: return self.macronutrients?.protein?.value ?? 0.0
        case .carbs: return self.macronutrients?.carbohydrates?.value ?? 0.0
        case .totalSugar: return self.macronutrients?.totalSugars?.value ?? 0.0
        case .fiber: return self.macronutrients?.fiber?.value ?? 0.0
        case .totalFat: return self.macronutrients?.fat?.value ?? 0.0
        case .water: return self.other?.water?.value ?? 0.0
        case .alcohol: return self.other?.alcoholEthyl?.value ?? 0.0
        case .ash: return self.other?.ash?.value ?? 0.0
        case .starch: return self.carbDetails?.starch?.value ?? 0.0

        // Minerals
        case .calcium: return self.minerals?.calcium?.value ?? 0.0
        case .iron: return self.minerals?.iron?.value ?? 0.0
        case .magnesium: return self.minerals?.magnesium?.value ?? 0.0
        case .phosphorus: return self.minerals?.phosphorus?.value ?? 0.0
        case .potassium: return self.minerals?.potassium?.value ?? 0.0
        case .sodium: return self.minerals?.sodium?.value ?? 0.0
        case .zinc: return self.minerals?.zinc?.value ?? 0.0
        case .copper: return self.minerals?.copper?.value ?? 0.0
        case .manganese: return self.minerals?.manganese?.value ?? 0.0
        case .selenium: return self.minerals?.selenium?.value ?? 0.0
        case .fluoride: return self.minerals?.fluoride?.value ?? 0.0

        // Vitamins
        case .vitaminC: return self.vitamins?.vitaminC?.value ?? 0.0
        case .vitaminB6: return self.vitamins?.vitaminB6?.value ?? 0.0
        case .vitaminB12: return self.vitamins?.vitaminB12?.value ?? 0.0
        case .vitaminA: return self.vitamins?.vitaminA_RAE?.value ?? 0.0
        case .retinol: return self.vitamins?.retinol?.value ?? 0.0
        case .betaCarotene: return self.vitamins?.caroteneBeta?.value ?? 0.0
        case .alphaCarotene: return self.vitamins?.caroteneAlpha?.value ?? 0.0
        case .betaCryptoxanthin: return self.vitamins?.cryptoxanthinBeta?.value ?? 0.0
        case .vitaminE: return self.vitamins?.vitaminE?.value ?? 0.0
        case .vitaminD: return self.vitamins?.vitaminD?.value ?? 0.0
        case .vitaminK: return self.vitamins?.vitaminK?.value ?? 0.0
        case .thiamin: return self.vitamins?.vitaminB1_Thiamin?.value ?? 0.0
        case .riboflavin: return self.vitamins?.vitaminB2_Riboflavin?.value ?? 0.0
        case .niacin: return self.vitamins?.vitaminB3_Niacin?.value ?? 0.0
        case .pantothenicAcid: return self.vitamins?.vitaminB5_PantothenicAcid?.value ?? 0.0
        case .folateTotal: return self.vitamins?.folateTotal?.value ?? 0.0
        case .folateFood: return self.vitamins?.folateFood?.value ?? 0.0
        case .folateDFE: return self.vitamins?.folateDFE?.value ?? 0.0
        case .folicAcid: return self.vitamins?.folicAcid?.value ?? 0.0
        case .choline: return self.vitamins?.choline?.value ?? 0.0
        case .betaine: return self.other?.betaine?.value ?? 0.0

        // Fats - General
        case .saturatedFat: return self.lipids?.totalSaturated?.value ?? 0.0
        case .monounsaturatedFat: return self.lipids?.totalMonounsaturated?.value ?? 0.0
        case .polyunsaturatedFat: return self.lipids?.totalPolyunsaturated?.value ?? 0.0
        case .transFat: return self.lipids?.totalTrans?.value ?? 0.0
        case .cholesterol: return self.other?.cholesterol?.value ?? 0.0
        case .phytosterols: return self.sterols?.phytosterols?.value ?? 0.0
        case .betaSitosterol: return self.sterols?.betaSitosterol?.value ?? 0.0
        case .campesterol: return self.sterols?.campesterol?.value ?? 0.0
        case .stigmasterol: return self.sterols?.stigmasterol?.value ?? 0.0
            
        // Fats - Specific Fatty Acids (SFA)
        case .sfa4_0: return self.lipids?.sfa4_0?.value ?? 0.0
        case .sfa6_0: return self.lipids?.sfa6_0?.value ?? 0.0
        case .sfa8_0: return self.lipids?.sfa8_0?.value ?? 0.0
        case .sfa10_0: return self.lipids?.sfa10_0?.value ?? 0.0
        case .sfa12_0: return self.lipids?.sfa12_0?.value ?? 0.0
        case .sfa13_0: return self.lipids?.sfa13_0?.value ?? 0.0
        case .sfa14_0: return self.lipids?.sfa14_0?.value ?? 0.0
        case .sfa15_0: return self.lipids?.sfa15_0?.value ?? 0.0
        case .sfa16_0: return self.lipids?.sfa16_0?.value ?? 0.0
        case .sfa17_0: return self.lipids?.sfa17_0?.value ?? 0.0
        case .sfa18_0: return self.lipids?.sfa18_0?.value ?? 0.0
        case .sfa20_0: return self.lipids?.sfa20_0?.value ?? 0.0
        case .sfa22_0: return self.lipids?.sfa22_0?.value ?? 0.0
        case .sfa24_0: return self.lipids?.sfa24_0?.value ?? 0.0
            
        // Fats - Specific Fatty Acids (MUFA)
        case .mufa14_1: return self.lipids?.mufa14_1?.value ?? 0.0
        case .mufa15_1: return self.lipids?.mufa15_1?.value ?? 0.0
        case .mufa16_1: return self.lipids?.mufa16_1?.value ?? 0.0
        case .mufa17_1: return self.lipids?.mufa17_1?.value ?? 0.0
        case .mufa18_1: return self.lipids?.mufa18_1?.value ?? 0.0
        case .mufa20_1: return self.lipids?.mufa20_1?.value ?? 0.0
        case .mufa22_1: return self.lipids?.mufa22_1?.value ?? 0.0
        case .mufa24_1: return self.lipids?.mufa24_1?.value ?? 0.0
        case .transMonoenoic: return self.lipids?.totalTransMonoenoic?.value ?? 0.0

        // Fats - Specific Fatty Acids (PUFA)
        case .pufa18_2: return self.lipids?.pufa18_2?.value ?? 0.0
        case .pufa18_3: return self.lipids?.pufa18_3?.value ?? 0.0
        case .pufa18_4: return self.lipids?.pufa18_4?.value ?? 0.0
        case .pufa20_2: return self.lipids?.pufa20_2?.value ?? 0.0
        case .pufa20_3: return self.lipids?.pufa20_3?.value ?? 0.0
        case .pufa20_4: return self.lipids?.pufa20_4?.value ?? 0.0
        case .pufa20_5: return self.lipids?.pufa20_5?.value ?? 0.0
        case .pufa21_5: return self.lipids?.pufa21_5?.value ?? 0.0
        case .pufa22_4: return self.lipids?.pufa22_4?.value ?? 0.0
        case .pufa22_5: return self.lipids?.pufa22_5?.value ?? 0.0
        case .pufa22_6: return self.lipids?.pufa22_6?.value ?? 0.0
        case .pufa2_4: return self.lipids?.pufa2_4?.value ?? 0.0
        case .transPolyenoic: return self.lipids?.totalTransPolyenoic?.value ?? 0.0
            
        // Specific Trans Fats
        case .tfa16_1: return self.lipids?.tfa16_1_t?.value ?? 0.0
        case .tfa18_1: return self.lipids?.tfa18_1_t?.value ?? 0.0
        case .tfa18_2: return self.lipids?.tfa18_2_t?.value ?? 0.0
        case .tfa22_1: return self.lipids?.tfa22_1_t?.value ?? 0.0

        // Amino Acids
        case .alanine: return self.aminoAcids?.alanine?.value ?? 0.0
        case .arginine: return self.aminoAcids?.arginine?.value ?? 0.0
        case .asparticAcid: return self.aminoAcids?.asparticAcid?.value ?? 0.0
        case .cystine: return self.aminoAcids?.cystine?.value ?? 0.0
        case .glutamicAcid: return self.aminoAcids?.glutamicAcid?.value ?? 0.0
        case .glycine: return self.aminoAcids?.glycine?.value ?? 0.0
        case .histidine: return self.aminoAcids?.histidine?.value ?? 0.0
        case .isoleucine: return self.aminoAcids?.isoleucine?.value ?? 0.0
        case .leucine: return self.aminoAcids?.leucine?.value ?? 0.0
        case .lysine: return self.aminoAcids?.lysine?.value ?? 0.0
        case .methionine: return self.aminoAcids?.methionine?.value ?? 0.0
        case .phenylalanine: return self.aminoAcids?.phenylalanine?.value ?? 0.0
        case .proline: return self.aminoAcids?.proline?.value ?? 0.0
        case .serine: return self.aminoAcids?.serine?.value ?? 0.0
        case .threonine: return self.aminoAcids?.threonine?.value ?? 0.0
        case .tryptophan: return self.aminoAcids?.tryptophan?.value ?? 0.0
        case .tyrosine: return self.aminoAcids?.tyrosine?.value ?? 0.0
        case .valine: return self.aminoAcids?.valine?.value ?? 0.0
        case .hydroxyproline: return self.aminoAcids?.hydroxyproline?.value ?? 0.0

        // Phytonutrients
        case .caffeine: return self.other?.caffeine?.value ?? 0.0
        case .theobromine: return self.other?.theobromine?.value ?? 0.0
        case .lycopene: return self.vitamins?.lycopene?.value ?? 0.0
        case .luteinZeaxanthin: return self.vitamins?.luteinZeaxanthin?.value ?? 0.0

        // Sugars
        case .glucose: return self.carbDetails?.glucose?.value ?? 0.0
        case .fructose: return self.carbDetails?.fructose?.value ?? 0.0
        case .galactose: return self.carbDetails?.galactose?.value ?? 0.0
        case .lactose: return self.carbDetails?.lactose?.value ?? 0.0
        case .maltose: return self.carbDetails?.maltose?.value ?? 0.0
        case .sucrose: return self.carbDetails?.sucrose?.value ?? 0.0
        }
    }
}

// MARK: - Legacy / Original Extensions
extension FoodItem {

    // MARK: - Nutrition Aggregation (RECURSIVE)
    // ==== FILE: WiseEating/Food/Models/FoodItem.swift ====

    static func aggregatedNutrition(for item: FoodItem) -> (
        macros: MacronutrientsData?,
        lipids: LipidsData?,
        vitamins: VitaminsData?,
        minerals: MineralsData?,
        other: OtherCompoundsData?,
        aminoAcids: AminoAcidsData?,
        carbDetails: CarbDetailsData?,
        sterols: SterolsData?
    ) {
        guard item.isRecipe || item.isMenu, let links = item.ingredients, !links.isEmpty else {
            return (item.macronutrients, item.lipids, item.vitamins, item.minerals, item.other, item.aminoAcids, item.carbDetails, item.sterols)
        }

        let m  = MacronutrientsData(); let l  = LipidsData(); let v  = VitaminsData()
        let mi = MineralsData(); let o  = OtherCompoundsData(); let a  = AminoAcidsData()
        let cd = CarbDetailsData(); let s  = SterolsData()

        func add(_ tgt: inout Nutrient?, _ src: Nutrient?, _ k: Double) {
            guard let src, let value = src.value, value > 0 else { return }
            if tgt == nil { tgt = Nutrient(value: value * k, unit: src.unit) }
            else if tgt!.unit == src.unit { tgt!.value! += value * k }
        }

        for link in links {
            guard let ing = link.food else { continue }
            
            // Рекурсия: вземаме данните за съставката (която също може да е рецепта)
            let source = aggregatedNutrition(for: ing)
            
            let base = ing.referenceWeightG
            guard base > 0 else { continue }
            let f = link.grams / base

            if let x = source.macros { add(&m.carbohydrates, x.carbohydrates, f); add(&m.protein, x.protein, f); add(&m.fat, x.fat, f); add(&m.fiber, x.fiber, f); add(&m.totalSugars, x.totalSugars, f) }
            if let x = source.lipids { add(&l.totalSaturated, x.totalSaturated, f); add(&l.totalMonounsaturated, x.totalMonounsaturated, f); add(&l.totalPolyunsaturated, x.totalPolyunsaturated, f); add(&l.totalTrans, x.totalTrans, f); add(&l.totalTransMonoenoic, x.totalTransMonoenoic, f); add(&l.totalTransPolyenoic, x.totalTransPolyenoic, f); add(&l.sfa4_0, x.sfa4_0, f); add(&l.sfa6_0, x.sfa6_0, f); add(&l.sfa8_0, x.sfa8_0, f); add(&l.sfa10_0, x.sfa10_0, f); add(&l.sfa12_0, x.sfa12_0, f); add(&l.sfa13_0, x.sfa13_0, f); add(&l.sfa14_0, x.sfa14_0, f); add(&l.sfa15_0, x.sfa15_0, f); add(&l.sfa16_0, x.sfa16_0, f); add(&l.sfa17_0, x.sfa17_0, f); add(&l.sfa18_0, x.sfa18_0, f); add(&l.sfa20_0, x.sfa20_0, f); add(&l.sfa22_0, x.sfa22_0, f); add(&l.sfa24_0, x.sfa24_0, f); add(&l.mufa14_1, x.mufa14_1, f); add(&l.mufa15_1, x.mufa15_1, f); add(&l.mufa16_1, x.mufa16_1, f); add(&l.mufa17_1, x.mufa17_1, f); add(&l.mufa18_1, x.mufa18_1, f); add(&l.mufa20_1, x.mufa20_1, f); add(&l.mufa22_1, x.mufa22_1, f); add(&l.mufa24_1, x.mufa24_1, f); add(&l.tfa16_1_t, x.tfa16_1_t, f); add(&l.tfa18_1_t, x.tfa18_1_t, f); add(&l.tfa22_1_t, x.tfa22_1_t, f); add(&l.tfa18_2_t, x.tfa18_2_t, f); add(&l.pufa18_2, x.pufa18_2, f); add(&l.pufa18_3, x.pufa18_3, f); add(&l.pufa18_4, x.pufa18_4, f); add(&l.pufa20_2, x.pufa20_2, f); add(&l.pufa20_3, x.pufa20_3, f); add(&l.pufa20_4, x.pufa20_4, f); add(&l.pufa20_5, x.pufa20_5, f); add(&l.pufa21_5, x.pufa21_5, f); add(&l.pufa22_4, x.pufa22_4, f); add(&l.pufa22_5, x.pufa22_5, f); add(&l.pufa22_6, x.pufa22_6, f); add(&l.pufa2_4,  x.pufa2_4, f) }
            if let x = source.vitamins { add(&v.vitaminA_RAE, x.vitaminA_RAE, f); add(&v.retinol, x.retinol, f); add(&v.caroteneAlpha, x.caroteneAlpha, f); add(&v.caroteneBeta, x.caroteneBeta, f); add(&v.cryptoxanthinBeta, x.cryptoxanthinBeta, f); add(&v.luteinZeaxanthin,  x.luteinZeaxanthin,  f); add(&v.lycopene, x.lycopene, f); add(&v.vitaminB1_Thiamin, x.vitaminB1_Thiamin, f); add(&v.vitaminB2_Riboflavin, x.vitaminB2_Riboflavin, f); add(&v.vitaminB3_Niacin, x.vitaminB3_Niacin, f); add(&v.vitaminB5_PantothenicAcid, x.vitaminB5_PantothenicAcid, f); add(&v.vitaminB6, x.vitaminB6, f); add(&v.folateDFE, x.folateDFE, f); add(&v.folateFood, x.folateFood, f); add(&v.folateTotal, x.folateTotal, f); add(&v.folicAcid, x.folicAcid, f); add(&v.vitaminB12, x.vitaminB12, f); add(&v.vitaminC, x.vitaminC, f); add(&v.vitaminD, x.vitaminD, f); add(&v.vitaminE, x.vitaminE, f); add(&v.vitaminK, x.vitaminK, f); add(&v.choline, x.choline, f) }
            if let x = source.minerals { add(&mi.calcium, x.calcium, f); add(&mi.iron, x.iron, f); add(&mi.magnesium,  x.magnesium, f); add(&mi.phosphorus, x.phosphorus, f); add(&mi.potassium,  x.potassium, f); add(&mi.sodium, x.sodium, f); add(&mi.selenium, x.selenium, f); add(&mi.zinc, x.zinc, f); add(&mi.copper, x.copper, f); add(&mi.manganese, x.manganese, f); add(&mi.fluoride, x.fluoride, f) }
            
            if let x = source.other {
                add(&o.alcoholEthyl, x.alcoholEthyl, f)
                add(&o.caffeine,     x.caffeine, f)
                add(&o.theobromine,  x.theobromine, f)
                add(&o.cholesterol,  x.cholesterol,  f)
                
                // --- ПОПРАВКА ЗА КАЛОРИИ (Energy Fix) ---
                let storedKcal = x.energyKcal?.value ?? 0
                if storedKcal > 0 {
                    // Имаме записани калории, ползваме ги
                    add(&o.energyKcal, x.energyKcal, f)
                } else {
                    // Нямаме калории, изчисляваме ги от макросите (4-4-9 правило)
                    let prot = source.macros?.protein?.value ?? 0
                    let carbs = source.macros?.carbohydrates?.value ?? 0
                    let fat = source.macros?.fat?.value ?? 0
                    let calculatedKcal = (prot * 4.0) + (carbs * 4.0) + (fat * 9.0)
                    
                    if calculatedKcal > 0 {
                        // Ръчно добавяне към акумулатора
                        if o.energyKcal == nil {
                            o.energyKcal = Nutrient(value: calculatedKcal * f, unit: "kcal")
                        } else {
                            o.energyKcal!.value! += calculatedKcal * f
                        }
                    }
                }
                // ----------------------------------------
                
                add(&o.water,        x.water, f)
                add(&o.weightG,      x.weightG, f)
                add(&o.ash,          x.ash, f)
                add(&o.betaine,      x.betaine, f)

                // ⬇️ pH – take first available value if missing
                if o.alkalinityPH == nil, let ph = x.alkalinityPH {
                    o.alkalinityPH = Nutrient(value: ph.value, unit: ph.unit)
                }
            }
            
            if let x = source.aminoAcids { add(&a.alanine, x.alanine, f); add(&a.arginine, x.arginine, f); add(&a.asparticAcid, x.asparticAcid, f); add(&a.cystine, x.cystine, f); add(&a.glutamicAcid, x.glutamicAcid, f); add(&a.glycine, x.glycine, f); add(&a.histidine, x.histidine, f); add(&a.isoleucine, x.isoleucine, f); add(&a.leucine, x.leucine, f); add(&a.lysine, x.lysine, f); add(&a.methionine, x.methionine, f); add(&a.phenylalanine,  x.phenylalanine, f); add(&a.proline, x.proline, f); add(&a.threonine, x.threonine, f); add(&a.tryptophan, x.tryptophan, f); add(&a.tyrosine, x.tyrosine, f); add(&a.valine, x.valine, f); add(&a.serine, x.serine, f); add(&a.hydroxyproline, x.hydroxyproline, f) }
            if let x = source.carbDetails { add(&cd.starch, x.starch, f); add(&cd.sucrose, x.sucrose, f); add(&cd.glucose,   x.glucose,   f); add(&cd.fructose,  x.fructose,  f); add(&cd.lactose,   x.lactose,   f); add(&cd.maltose,   x.maltose,   f); add(&cd.galactose, x.galactose, f) }
            if let x = source.sterols { add(&s.phytosterols,   x.phytosterols,   f); add(&s.betaSitosterol, x.betaSitosterol, f); add(&s.campesterol,    x.campesterol,    f); add(&s.stigmasterol,   x.stigmasterol,   f) }
        }

        return (m, l, v, mi, o, a, cd, s)
    }

    // MARK: – Public Computed Properties
    var totalWeightG: Double? {
        ingredients?.map(\.grams).reduce(0, +)
    }

    var totalCarbohydrates: Nutrient? { Self.aggregatedNutrition(for: self).macros?.carbohydrates }
    var totalProtein:       Nutrient? { Self.aggregatedNutrition(for: self).macros?.protein }
    var totalFat:           Nutrient? { Self.aggregatedNutrition(for: self).macros?.fat }
    var totalEnergyKcal:    Nutrient? { Self.aggregatedNutrition(for: self).other?.energyKcal }

    public func topVitamins(count n: Int = 2) -> [DisplayableNutrient] {
        let aggregatedData = Self.aggregatedNutrition(for: self).vitamins
        return directTop(dataset: aggregatedData, accessMap: vitaminAccess, labelMap: vitaminLabelById, limit: n)
    }

    public func topMinerals(count n: Int = 2) -> [DisplayableNutrient] {
        let aggregatedData = Self.aggregatedNutrition(for: self).minerals
        return directTop(dataset: aggregatedData, accessMap: mineralAccess, labelMap: mineralLabelById, limit: n)
    }
    
    @MainActor public func allLipids(count n: Int = Int.max) -> [DisplayableNutrient] {
        let aggregatedData = Self.aggregatedNutrition(for: self).lipids
        return directTop(dataset: aggregatedData, accessMap: lipidAccessForDisplay, labelMap: lipidLabelById, limit: n)
    }

    @MainActor public func allOtherCompounds(count n: Int = Int.max) -> [DisplayableNutrient] {
        let aggregatedData = Self.aggregatedNutrition(for: self).other
        return directTop(dataset: aggregatedData, accessMap: otherAccessForDisplay, labelMap: otherLabelById, limit: n)
    }
    
    @MainActor public func allAminoAcids(count n: Int = Int.max) -> [DisplayableNutrient] {
        let aggregatedData = Self.aggregatedNutrition(for: self).aminoAcids
        return directTop(dataset: aggregatedData, accessMap: aminoAccessForDisplay, labelMap: aminoLabelById, limit: n)
    }

    @MainActor public func allCarbDetails(count n: Int = Int.max) -> [DisplayableNutrient] {
        let aggregatedData = Self.aggregatedNutrition(for: self).carbDetails
        return directTop(dataset: aggregatedData, accessMap: carbDetailsAccessForDisplay, labelMap: carbDetailsLabelById, limit: n)
    }

    @MainActor public func allSterols(count n: Int = Int.max) -> [DisplayableNutrient] {
        let aggregatedData = Self.aggregatedNutrition(for: self).sterols
        return directTop(dataset: aggregatedData, accessMap: sterolsAccessForDisplay, labelMap: sterolsLabelById, limit: n)
    }
    
    private func directTop<T>(
        dataset: T?,
        accessMap: [String:(T)->Nutrient?],
        labelMap:  [String:String],
        limit: Int
    ) -> [DisplayableNutrient] {
        guard let data = dataset, let ctx = self.modelContext else { return [] }

        let vitaminsWithColor = (try? ctx.fetch(FetchDescriptor<Vitamin>())) ?? []
        let mineralsWithColor = (try? ctx.fetch(FetchDescriptor<Mineral>())) ?? []
        let colorMap = Dictionary(uniqueKeysWithValues: (vitaminsWithColor.map { ($0.id, Color(hex: $0.colorHex)) } + mineralsWithColor.map { ($0.id, Color(hex: $0.colorHex)) }))

        var pool: [DisplayableNutrient] = []
        for (id, label) in labelMap {
            guard let getter = accessMap[id],
                  let nut = getter(data),
                  let val = nut.value, val > 0,
                  let unit = nut.unit
            else { continue }

            let mg = Self.toMg(value: val, unit: unit)
            let color = colorMap[id]

            pool.append(DisplayableNutrient(name: label,
                                            value: val,
                                            unit: unit,
                                            color: color,
                                            valueMg: mg))
        }
        return pool.sorted { $0.valueMg > $1.valueMg }
                   .prefix(limit)
                   .map { $0 }
    }

    private static func toMg(value: Double, unit: String) -> Double {
        switch unit.lowercased() {
        case "g":           return value * 1_000
        case "µg", "mcg":   return value * 0.001
        case "mg":          return value
        default:            return value
        }
    }
    
    // MARK: - Value & Density Helpers
    func value(of nutrientID: String) -> (Double, String)? {
        let aggregated = Self.aggregatedNutrition(for: self)
        
        if nutrientID.starts(with: "vit_") {
            let key = String(nutrientID.dropFirst(4))
            if let vit = aggregated.vitamins, let n = vitaminAccess[key]?(vit), let v = n.value, let unit = n.unit { return (v, unit) }
        } else if nutrientID.starts(with: "min_") {
            let key = String(nutrientID.dropFirst(4))
            if let min = aggregated.minerals, let n = mineralAccess[key]?(min), let v = n.value, let unit = n.unit { return (v, unit) }
        }
        return nil
    }
    
    var referenceWeightG: Double {
        if isRecipe || isMenu { return totalWeightG ?? 100 }
        return other?.weightG?.value ?? 100
    }
    
    func macro(_ kp: KeyPath<MacronutrientsData, Nutrient?>) -> Double {
        let aggregated = Self.aggregatedNutrition(for: self)
        return aggregated.macros?[keyPath: kp]?.value ?? 0
    }

    func nutrientDensity(of id: String) -> Double? {
        guard let (val, _) = value(of: id) else { return nil }
        let ref = referenceWeightG
        guard ref > 0 else { return nil }
        return val / ref
    }

    func amount(of id: String, grams: Double) -> Double {
        (nutrientDensity(of: id) ?? 0) * grams
    }

    func nutrients(for grams: Double) -> [String: Double] {
        var results: [String: Double] = [:]
        let allNutrientIDs = vitaminLabelById.keys.map { "vit_\($0)" } + mineralLabelById.keys.map { "min_\($0)" }
        for id in allNutrientIDs {
            if let (value, unit) = self.value(of: id) {
                let referenceWeight = self.referenceWeightG
                if referenceWeight > 0 {
                    let valuePerGram = value / referenceWeight
                    let totalValue = valuePerGram * grams
                    let totalValueMg = Self.toMg(value: totalValue, unit: unit)
                    if totalValueMg > 0 {
                        results[id] = totalValueMg
                    }
                }
            }
        }
        return results
    }

    func calories(for grams: Double) -> Double {
        let aggregated = Self.aggregatedNutrition(for: self)
        
        if let kcalPerRef = aggregated.other?.energyKcal?.value {
            let refW = self.referenceWeightG
            if refW > 0 { return kcalPerRef * grams / refW }
        }

        let refW = self.referenceWeightG
        guard refW > 0 else { return 0 }

        let carbsDensity   = (aggregated.macros?.carbohydrates?.value ?? 0) / refW
        let proteinDensity = (aggregated.macros?.protein?.value ?? 0) / refW
        let fatDensity     = (aggregated.macros?.fat?.value ?? 0) / refW
        
        return (carbsDensity * 4 + proteinDensity * 4 + fatDensity * 9) * grams
    }
    
    static func vitaminKeyPath(for key: String) -> KeyPath<FoodItem, Double?> {
            switch key {
            case "vitaminA_RAE": return \.vitamins?.vitaminA_RAE?.value
            case "retinol": return \.vitamins?.retinol?.value
            case "caroteneAlpha": return \.vitamins?.caroteneAlpha?.value
            case "caroteneBeta": return \.vitamins?.caroteneBeta?.value
            case "cryptoxanthinBeta": return \.vitamins?.cryptoxanthinBeta?.value
            case "luteinZeaxanthin": return \.vitamins?.luteinZeaxanthin?.value
            case "lycopene": return \.vitamins?.lycopene?.value
            case "vitaminB1_Thiamin": return \.vitamins?.vitaminB1_Thiamin?.value
            case "vitaminB2_Riboflavin": return \.vitamins?.vitaminB2_Riboflavin?.value
            case "vitaminB3_Niacin": return \.vitamins?.vitaminB3_Niacin?.value
            case "vitaminB5_PantothenicAcid": return \.vitamins?.vitaminB5_PantothenicAcid?.value
            case "vitaminB6": return \.vitamins?.vitaminB6?.value
            case "folateDFE": return \.vitamins?.folateDFE?.value
            case "folateFood": return \.vitamins?.folateFood?.value
            case "folateTotal": return \.vitamins?.folateTotal?.value
            case "folicAcid": return \.vitamins?.folicAcid?.value
            case "vitaminB12": return \.vitamins?.vitaminB12?.value
            case "vitaminC": return \.vitamins?.vitaminC?.value
            case "vitaminD": return \.vitamins?.vitaminD?.value
            case "vitaminE": return \.vitamins?.vitaminE?.value
            case "vitaminK": return \.vitamins?.vitaminK?.value
            case "choline": return \.vitamins?.choline?.value
            default: return \.vitamins?.vitaminC?.value // Safe default
            }
        }

        static func mineralKeyPath(for key: String) -> KeyPath<FoodItem, Double?> {
            switch key {
            case "calcium": return \.minerals?.calcium?.value
            case "iron": return \.minerals?.iron?.value
            case "magnesium": return \.minerals?.magnesium?.value
            case "phosphorus": return \.minerals?.phosphorus?.value
            case "potassium": return \.minerals?.potassium?.value
            case "sodium": return \.minerals?.sodium?.value
            case "selenium": return \.minerals?.selenium?.value
            case "zinc": return \.minerals?.zinc?.value
            case "copper": return \.minerals?.copper?.value
            case "manganese": return \.minerals?.manganese?.value
            case "fluoride": return \.minerals?.fluoride?.value
            default: return \.minerals?.iron?.value // Safe default
            }
        }
    
    @MainActor
    func update(from dto: FoodItemDTO, dietMap: [String: Diet]) {
        // Main fields
        self.itemDescription = dto.desctiption
        self.minAgeMonths = dto.minAgeMonths ?? 0
        self.category = dto.category
        self.allergens = dto.allergens
        
        // Diet linking
        let fetchedDiets: [Diet]
        if let dietNames = dto.diets {
            fetchedDiets = dietNames.compactMap { dietMap[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] }
        } else {
            fetchedDiets = []
        }
        self.diets = fetchedDiets

        // Macros
        if let m = dto.macronutrients {
            self.macronutrients = MacronutrientsData(carbohydrates: m.carbohydrates, protein: m.protein, fat: m.fat, fiber: m.fiber, totalSugars: m.totalSugars)
            self.macronutrients?.foodItem = self
        }
        
        // Vitamins
        if let v = dto.vitamins {
            self.vitamins = VitaminsData(vitaminA_RAE: v.vitaminA_RAE, retinol: v.retinol, caroteneAlpha: v.caroteneAlpha, caroteneBeta: v.caroteneBeta, cryptoxanthinBeta: v.cryptoxanthinBeta, luteinZeaxanthin: v.luteinZeaxanthin, lycopene: v.lycopene, vitaminB1_Thiamin: v.vitaminB1_Thiamin, vitaminB2_Riboflavin: v.vitaminB2_Riboflavin, vitaminB3_Niacin: v.vitaminB3_Niacin, vitaminB5_PantothenicAcid: v.vitaminB5_PantothenicAcid, vitaminB6: v.vitaminB6, folateDFE: v.folateDFE, folateFood: v.folateFood, folateTotal: v.folateTotal, folicAcid: v.folicAcid, vitaminB12: v.vitaminB12, vitaminC: v.vitaminC, vitaminD: v.vitaminD, vitaminE: v.vitaminE, vitaminK: v.vitaminK, choline: v.choline)
            self.vitamins?.foodItem = self
        }
        
        // Minerals
        if let m = dto.minerals {
            self.minerals = MineralsData(calcium: m.calcium, iron: m.iron, magnesium: m.magnesium, phosphorus: m.phosphorus, potassium: m.potassium, sodium: m.sodium, selenium: m.selenium, zinc: m.zinc, copper: m.copper, manganese: m.manganese, fluoride: m.fluoride)
            self.minerals?.foodItem = self
        }
        
        // Other
        if let o = dto.other {
            self.other = OtherCompoundsData(
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
            self.other?.foodItem = self
        }

        // Lipids
        if let l = dto.lipids {
            self.lipids = LipidsData(
                totalSaturated: l.totalSaturated, totalMonounsaturated: l.totalMonounsaturated, totalPolyunsaturated: l.totalPolyunsaturated,
                totalTrans: l.totalTrans, totalTransMonoenoic: l.totalTransMonoenoic, totalTransPolyenoic: l.totalTransPolyenoic,
                sfa4_0: l.sfa4_0, sfa6_0: l.sfa6_0, sfa8_0: l.sfa8_0, sfa10_0: l.sfa10_0, sfa12_0: l.sfa12_0, sfa13_0: l.sfa13_0,
                sfa14_0: l.sfa14_0, sfa15_0: l.sfa15_0, sfa16_0: l.sfa16_0, sfa17_0: l.sfa17_0, sfa18_0: l.sfa18_0, sfa20_0: l.sfa20_0,
                sfa22_0: l.sfa22_0, sfa24_0: l.sfa24_0, mufa14_1: l.mufa14_1, mufa15_1: l.mufa15_1, mufa16_1: l.mufa16_1,
                mufa17_1: l.mufa17_1, mufa18_1: l.mufa18_1, mufa20_1: l.mufa20_1, mufa22_1: l.mufa22_1, mufa24_1: l.mufa24_1,
                tfa16_1_t: l.tfa16_1_t, tfa18_1_t: l.tfa18_1_t, tfa22_1_t: l.tfa22_1_t, tfa18_2_t: l.tfa18_2_t,
                pufa18_2: l.pufa18_2, pufa18_3: l.pufa18_3, pufa18_4: l.pufa18_4, pufa20_2: l.pufa20_2, pufa20_3: l.pufa20_3,
                pufa20_4: l.pufa20_4, pufa20_5: l.pufa20_5, pufa21_5: l.pufa21_5, pufa22_4: l.pufa22_4, pufa22_5: l.pufa22_5,
                pufa22_6: l.pufa22_6, pufa2_4: l.pufa2_4
            )
            self.lipids?.foodItem = self
        }
        
        // Amino Acids
        if let a = dto.aminoAcids {
            self.aminoAcids = AminoAcidsData(
                alanine: a.alanine, arginine: a.arginine, asparticAcid: a.asparticAcid, cystine: a.cystine,
                glutamicAcid: a.glutamicAcid, glycine: a.glycine, histidine: a.histidine, isoleucine: a.isoleucine,
                leucine: a.leucine, lysine: a.lysine, methionine: a.methionine, phenylalanine: a.phenylalanine,
                proline: a.proline, threonine: a.threonine, tryptophan: a.tryptophan, tyrosine: a.tyrosine,
                valine: a.valine, serine: a.serine, hydroxyproline: a.hydroxyproline
            )
            self.aminoAcids?.foodItem = self
        }
        
        // Carb Details
        if let c = dto.carbDetails {
            self.carbDetails = CarbDetailsData(
                starch: c.starch, sucrose: c.sucrose, glucose: c.glucose,
                fructose: c.fructose, lactose: c.lactose, maltose: c.maltose, galactose: c.galactose
            )
            self.carbDetails?.foodItem = self
        }
        
        // Sterols
        if let s = dto.sterols {
            self.sterols = SterolsData(
                phytosterols: s.phytosterols, betaSitosterol: s.betaSitosterol,
                campesterol: s.campesterol, stigmasterol: s.stigmasterol
            )
            self.sterols?.foodItem = self
        }
    }
    
    func foodImage(variant: String) -> UIImage? {
           // 1) Check DB (User added photos)
           if let data = self.photo, let img = UIImage(data: data) {
               return img
           }

           let original = self.name
           // Sanitize filenames
           let sanitizedName = original
               .replacingOccurrences(of: "\"", with: "_")
               .replacingOccurrences(of: "/", with: "_")
               .replacingOccurrences(of: ":", with: "_")

           if let videoImg = FoodVideoSource.shared.getFrame(named: sanitizedName, variant: variant) {
               return videoImg
           }

           return nil
       }
    
    func unit(for nutrient: NutrientType) -> String? {
           switch nutrient {
           // Macros
           case .energy: return self.other?.energyKcal?.unit
           case .protein: return self.macronutrients?.protein?.unit
           case .carbs: return self.macronutrients?.carbohydrates?.unit
           case .totalSugar: return self.macronutrients?.totalSugars?.unit
           case .fiber: return self.macronutrients?.fiber?.unit
           case .totalFat: return self.macronutrients?.fat?.unit
           case .water: return self.other?.water?.unit
           case .alcohol: return self.other?.alcoholEthyl?.unit
           case .ash: return self.other?.ash?.unit
           case .starch: return self.carbDetails?.starch?.unit

           // Minerals
           case .calcium: return self.minerals?.calcium?.unit
           case .iron: return self.minerals?.iron?.unit
           case .magnesium: return self.minerals?.magnesium?.unit
           case .phosphorus: return self.minerals?.phosphorus?.unit
           case .potassium: return self.minerals?.potassium?.unit
           case .sodium: return self.minerals?.sodium?.unit
           case .zinc: return self.minerals?.zinc?.unit
           case .copper: return self.minerals?.copper?.unit
           case .manganese: return self.minerals?.manganese?.unit
           case .selenium: return self.minerals?.selenium?.unit
           case .fluoride: return self.minerals?.fluoride?.unit

           // Vitamins
           case .vitaminC: return self.vitamins?.vitaminC?.unit
           case .vitaminB6: return self.vitamins?.vitaminB6?.unit
           case .vitaminB12: return self.vitamins?.vitaminB12?.unit
           case .vitaminA: return self.vitamins?.vitaminA_RAE?.unit
           case .retinol: return self.vitamins?.retinol?.unit
           case .betaCarotene: return self.vitamins?.caroteneBeta?.unit
           case .alphaCarotene: return self.vitamins?.caroteneAlpha?.unit
           case .betaCryptoxanthin: return self.vitamins?.cryptoxanthinBeta?.unit
           case .vitaminE: return self.vitamins?.vitaminE?.unit
           case .vitaminD: return self.vitamins?.vitaminD?.unit
           case .vitaminK: return self.vitamins?.vitaminK?.unit
           case .thiamin: return self.vitamins?.vitaminB1_Thiamin?.unit
           case .riboflavin: return self.vitamins?.vitaminB2_Riboflavin?.unit
           case .niacin: return self.vitamins?.vitaminB3_Niacin?.unit
           case .pantothenicAcid: return self.vitamins?.vitaminB5_PantothenicAcid?.unit
           case .folateTotal: return self.vitamins?.folateTotal?.unit
           case .folateFood: return self.vitamins?.folateFood?.unit
           case .folateDFE: return self.vitamins?.folateDFE?.unit
           case .folicAcid: return self.vitamins?.folicAcid?.unit
           case .choline: return self.vitamins?.choline?.unit
           case .betaine: return self.other?.betaine?.unit

           // Fats - General
           case .saturatedFat: return self.lipids?.totalSaturated?.unit
           case .monounsaturatedFat: return self.lipids?.totalMonounsaturated?.unit
           case .polyunsaturatedFat: return self.lipids?.totalPolyunsaturated?.unit
           case .transFat: return self.lipids?.totalTrans?.unit
           case .cholesterol: return self.other?.cholesterol?.unit
           case .phytosterols: return self.sterols?.phytosterols?.unit
           case .betaSitosterol: return self.sterols?.betaSitosterol?.unit
           case .campesterol: return self.sterols?.campesterol?.unit
           case .stigmasterol: return self.sterols?.stigmasterol?.unit
               
           // Fats - Specific Fatty Acids (SFA)
           case .sfa4_0: return self.lipids?.sfa4_0?.unit
           case .sfa6_0: return self.lipids?.sfa6_0?.unit
           case .sfa8_0: return self.lipids?.sfa8_0?.unit
           case .sfa10_0: return self.lipids?.sfa10_0?.unit
           case .sfa12_0: return self.lipids?.sfa12_0?.unit
           case .sfa13_0: return self.lipids?.sfa13_0?.unit
           case .sfa14_0: return self.lipids?.sfa14_0?.unit
           case .sfa15_0: return self.lipids?.sfa15_0?.unit
           case .sfa16_0: return self.lipids?.sfa16_0?.unit
           case .sfa17_0: return self.lipids?.sfa17_0?.unit
           case .sfa18_0: return self.lipids?.sfa18_0?.unit
           case .sfa20_0: return self.lipids?.sfa20_0?.unit
           case .sfa22_0: return self.lipids?.sfa22_0?.unit
           case .sfa24_0: return self.lipids?.sfa24_0?.unit
               
           // Fats - Specific Fatty Acids (MUFA)
           case .mufa14_1: return self.lipids?.mufa14_1?.unit
           case .mufa15_1: return self.lipids?.mufa15_1?.unit
           case .mufa16_1: return self.lipids?.mufa16_1?.unit
           case .mufa17_1: return self.lipids?.mufa17_1?.unit
           case .mufa18_1: return self.lipids?.mufa18_1?.unit
           case .mufa20_1: return self.lipids?.mufa20_1?.unit
           case .mufa22_1: return self.lipids?.mufa22_1?.unit
           case .mufa24_1: return self.lipids?.mufa24_1?.unit
           case .transMonoenoic: return self.lipids?.totalTransMonoenoic?.unit

           // Fats - Specific Fatty Acids (PUFA)
           case .pufa18_2: return self.lipids?.pufa18_2?.unit
           case .pufa18_3: return self.lipids?.pufa18_3?.unit
           case .pufa18_4: return self.lipids?.pufa18_4?.unit
           case .pufa20_2: return self.lipids?.pufa20_2?.unit
           case .pufa20_3: return self.lipids?.pufa20_3?.unit
           case .pufa20_4: return self.lipids?.pufa20_4?.unit
           case .pufa20_5: return self.lipids?.pufa20_5?.unit
           case .pufa21_5: return self.lipids?.pufa21_5?.unit
           case .pufa22_4: return self.lipids?.pufa22_4?.unit
           case .pufa22_5: return self.lipids?.pufa22_5?.unit
           case .pufa22_6: return self.lipids?.pufa22_6?.unit
           case .pufa2_4: return self.lipids?.pufa2_4?.unit
           case .transPolyenoic: return self.lipids?.totalTransPolyenoic?.unit
               
           // Specific Trans Fats
           case .tfa16_1: return self.lipids?.tfa16_1_t?.unit
           case .tfa18_1: return self.lipids?.tfa18_1_t?.unit
           case .tfa18_2: return self.lipids?.tfa18_2_t?.unit
           case .tfa22_1: return self.lipids?.tfa22_1_t?.unit

           // Amino Acids
           case .alanine: return self.aminoAcids?.alanine?.unit
           case .arginine: return self.aminoAcids?.arginine?.unit
           case .asparticAcid: return self.aminoAcids?.asparticAcid?.unit
           case .cystine: return self.aminoAcids?.cystine?.unit
           case .glutamicAcid: return self.aminoAcids?.glutamicAcid?.unit
           case .glycine: return self.aminoAcids?.glycine?.unit
           case .histidine: return self.aminoAcids?.histidine?.unit
           case .isoleucine: return self.aminoAcids?.isoleucine?.unit
           case .leucine: return self.aminoAcids?.leucine?.unit
           case .lysine: return self.aminoAcids?.lysine?.unit
           case .methionine: return self.aminoAcids?.methionine?.unit
           case .phenylalanine: return self.aminoAcids?.phenylalanine?.unit
           case .proline: return self.aminoAcids?.proline?.unit
           case .serine: return self.aminoAcids?.serine?.unit
           case .threonine: return self.aminoAcids?.threonine?.unit
           case .tryptophan: return self.aminoAcids?.tryptophan?.unit
           case .tyrosine: return self.aminoAcids?.tyrosine?.unit
           case .valine: return self.aminoAcids?.valine?.unit
           case .hydroxyproline: return self.aminoAcids?.hydroxyproline?.unit

           // Phytonutrients
           case .caffeine: return self.other?.caffeine?.unit
           case .theobromine: return self.other?.theobromine?.unit
           case .lycopene: return self.vitamins?.lycopene?.unit
           case .luteinZeaxanthin: return self.vitamins?.luteinZeaxanthin?.unit

           // Sugars
           case .glucose: return self.carbDetails?.glucose?.unit
           case .fructose: return self.carbDetails?.fructose?.unit
           case .galactose: return self.carbDetails?.galactose?.unit
           case .lactose: return self.carbDetails?.lactose?.unit
           case .maltose: return self.carbDetails?.maltose?.unit
           case .sucrose: return self.carbDetails?.sucrose?.unit
           }
       }
}

// MARK: - UI Formatting Helpers
extension FoodItemDetailView {
     func formattedWeight(_ grams: Double) -> String {
        let display = UnitConversion.formatGramsToFoodDisplay(grams)
        return "\(display.value) \(display.unit)"
    }
}

import Foundation

extension FoodItem {
    
    /// Връща изчислената стойност И мерната единица на нутриент.
    /// За обикновени храни чете от базата.
    /// За рецепти/менюта агрегира стойностите и мерните единици от съставките.
    func calculatedNutrition(for nutrient: NutrientType) -> (value: Double, unit: String?) {
        
        // 1. Оптимизация: Ако е обикновена храна, взимаме директно от базата
        if !self.isRecipe && !self.isMenu {
            let val = self.value(for: nutrient)
            let u = self.unit(for: nutrient)
            return (val, u)
        }
        
        // 2. Агрегация: Изчисляваме стойностите на база съставките (рекурсивно).
        // Това връща tuple с всички data обекти (macros, lipids, vitamins и т.н.)
        let data = Self.aggregatedNutrition(for: self)
        
        // Помощна функция за бързо извличане
        func pair(_ n: Nutrient?) -> (Double, String?) {
            return (n?.value ?? 0.0, n?.unit)
        }
        
        // 3. Мапване на NutrientType към конкретните полета
        switch nutrient {
            
        // MARK: - Macros
        case .energy:      return pair(data.other?.energyKcal)
        case .protein:     return pair(data.macros?.protein)
        case .carbs:       return pair(data.macros?.carbohydrates)
        case .totalSugar:  return pair(data.macros?.totalSugars)
        case .fiber:       return pair(data.macros?.fiber)
        case .totalFat:    return pair(data.macros?.fat)
        case .water:       return pair(data.other?.water)
        case .alcohol:     return pair(data.other?.alcoholEthyl)
        case .ash:         return pair(data.other?.ash)
        case .starch:      return pair(data.carbDetails?.starch)

        // MARK: - Minerals
        case .calcium:     return pair(data.minerals?.calcium)
        case .iron:        return pair(data.minerals?.iron)
        case .magnesium:   return pair(data.minerals?.magnesium)
        case .phosphorus:  return pair(data.minerals?.phosphorus)
        case .potassium:   return pair(data.minerals?.potassium)
        case .sodium:      return pair(data.minerals?.sodium)
        case .zinc:        return pair(data.minerals?.zinc)
        case .copper:      return pair(data.minerals?.copper)
        case .manganese:   return pair(data.minerals?.manganese)
        case .selenium:    return pair(data.minerals?.selenium)
        case .fluoride:    return pair(data.minerals?.fluoride)

        // MARK: - Vitamins
        case .vitaminC:          return pair(data.vitamins?.vitaminC)
        case .vitaminB6:         return pair(data.vitamins?.vitaminB6)
        case .vitaminB12:        return pair(data.vitamins?.vitaminB12)
        case .vitaminA:          return pair(data.vitamins?.vitaminA_RAE)
        case .retinol:           return pair(data.vitamins?.retinol)
        case .betaCarotene:      return pair(data.vitamins?.caroteneBeta)
        case .alphaCarotene:     return pair(data.vitamins?.caroteneAlpha)
        case .betaCryptoxanthin: return pair(data.vitamins?.cryptoxanthinBeta)
        case .vitaminE:          return pair(data.vitamins?.vitaminE)
        case .vitaminD:          return pair(data.vitamins?.vitaminD)
        case .vitaminK:          return pair(data.vitamins?.vitaminK)
        case .thiamin:           return pair(data.vitamins?.vitaminB1_Thiamin)
        case .riboflavin:        return pair(data.vitamins?.vitaminB2_Riboflavin)
        case .niacin:            return pair(data.vitamins?.vitaminB3_Niacin)
        case .pantothenicAcid:   return pair(data.vitamins?.vitaminB5_PantothenicAcid)
        case .folateTotal:       return pair(data.vitamins?.folateTotal)
        case .folateFood:        return pair(data.vitamins?.folateFood)
        case .folateDFE:         return pair(data.vitamins?.folateDFE)
        case .folicAcid:         return pair(data.vitamins?.folicAcid)
        case .choline:           return pair(data.vitamins?.choline)
        case .betaine:           return pair(data.other?.betaine)

        // MARK: - Fats (General)
        case .saturatedFat:       return pair(data.lipids?.totalSaturated)
        case .monounsaturatedFat: return pair(data.lipids?.totalMonounsaturated)
        case .polyunsaturatedFat: return pair(data.lipids?.totalPolyunsaturated)
        case .transFat:           return pair(data.lipids?.totalTrans)
        case .cholesterol:        return pair(data.other?.cholesterol)
        case .phytosterols:       return pair(data.sterols?.phytosterols)
        case .betaSitosterol:     return pair(data.sterols?.betaSitosterol)
        case .campesterol:        return pair(data.sterols?.campesterol)
        case .stigmasterol:       return pair(data.sterols?.stigmasterol)

        // MARK: - Fats (SFA)
        case .sfa4_0:  return pair(data.lipids?.sfa4_0)
        case .sfa6_0:  return pair(data.lipids?.sfa6_0)
        case .sfa8_0:  return pair(data.lipids?.sfa8_0)
        case .sfa10_0: return pair(data.lipids?.sfa10_0)
        case .sfa12_0: return pair(data.lipids?.sfa12_0)
        case .sfa13_0: return pair(data.lipids?.sfa13_0)
        case .sfa14_0: return pair(data.lipids?.sfa14_0)
        case .sfa15_0: return pair(data.lipids?.sfa15_0)
        case .sfa16_0: return pair(data.lipids?.sfa16_0)
        case .sfa17_0: return pair(data.lipids?.sfa17_0)
        case .sfa18_0: return pair(data.lipids?.sfa18_0)
        case .sfa20_0: return pair(data.lipids?.sfa20_0)
        case .sfa22_0: return pair(data.lipids?.sfa22_0)
        case .sfa24_0: return pair(data.lipids?.sfa24_0)
            
        // MARK: - Fats (MUFA)
        case .mufa14_1: return pair(data.lipids?.mufa14_1)
        case .mufa15_1: return pair(data.lipids?.mufa15_1)
        case .mufa16_1: return pair(data.lipids?.mufa16_1)
        case .mufa17_1: return pair(data.lipids?.mufa17_1)
        case .mufa18_1: return pair(data.lipids?.mufa18_1)
        case .mufa20_1: return pair(data.lipids?.mufa20_1)
        case .mufa22_1: return pair(data.lipids?.mufa22_1)
        case .mufa24_1: return pair(data.lipids?.mufa24_1)
        case .transMonoenoic: return pair(data.lipids?.totalTransMonoenoic)

        // MARK: - Fats (PUFA)
        case .pufa18_2: return pair(data.lipids?.pufa18_2)
        case .pufa18_3: return pair(data.lipids?.pufa18_3)
        case .pufa18_4: return pair(data.lipids?.pufa18_4)
        case .pufa20_2: return pair(data.lipids?.pufa20_2)
        case .pufa20_3: return pair(data.lipids?.pufa20_3)
        case .pufa20_4: return pair(data.lipids?.pufa20_4)
        case .pufa20_5: return pair(data.lipids?.pufa20_5)
        case .pufa21_5: return pair(data.lipids?.pufa21_5)
        case .pufa22_4: return pair(data.lipids?.pufa22_4)
        case .pufa22_5: return pair(data.lipids?.pufa22_5)
        case .pufa22_6: return pair(data.lipids?.pufa22_6)
        case .pufa2_4:  return pair(data.lipids?.pufa2_4)
        case .transPolyenoic: return pair(data.lipids?.totalTransPolyenoic)
            
        // MARK: - Fats (Trans Specific)
        case .tfa16_1: return pair(data.lipids?.tfa16_1_t)
        case .tfa18_1: return pair(data.lipids?.tfa18_1_t)
        case .tfa18_2: return pair(data.lipids?.tfa18_2_t)
        case .tfa22_1: return pair(data.lipids?.tfa22_1_t)

        // MARK: - Amino Acids
        case .alanine:        return pair(data.aminoAcids?.alanine)
        case .arginine:       return pair(data.aminoAcids?.arginine)
        case .asparticAcid:   return pair(data.aminoAcids?.asparticAcid)
        case .cystine:        return pair(data.aminoAcids?.cystine)
        case .glutamicAcid:   return pair(data.aminoAcids?.glutamicAcid)
        case .glycine:        return pair(data.aminoAcids?.glycine)
        case .histidine:      return pair(data.aminoAcids?.histidine)
        case .isoleucine:     return pair(data.aminoAcids?.isoleucine)
        case .leucine:        return pair(data.aminoAcids?.leucine)
        case .lysine:         return pair(data.aminoAcids?.lysine)
        case .methionine:     return pair(data.aminoAcids?.methionine)
        case .phenylalanine:  return pair(data.aminoAcids?.phenylalanine)
        case .proline:        return pair(data.aminoAcids?.proline)
        case .serine:         return pair(data.aminoAcids?.serine)
        case .threonine:      return pair(data.aminoAcids?.threonine)
        case .tryptophan:     return pair(data.aminoAcids?.tryptophan)
        case .tyrosine:       return pair(data.aminoAcids?.tyrosine)
        case .valine:         return pair(data.aminoAcids?.valine)
        case .hydroxyproline: return pair(data.aminoAcids?.hydroxyproline)

        // MARK: - Phytonutrients / Other
        case .caffeine:         return pair(data.other?.caffeine)
        case .theobromine:      return pair(data.other?.theobromine)
        case .lycopene:         return pair(data.vitamins?.lycopene)
        case .luteinZeaxanthin: return pair(data.vitamins?.luteinZeaxanthin)

        // MARK: - Sugars (Detailed)
        case .glucose:   return pair(data.carbDetails?.glucose)
        case .fructose:  return pair(data.carbDetails?.fructose)
        case .galactose: return pair(data.carbDetails?.galactose)
        case .lactose:   return pair(data.carbDetails?.lactose)
        case .maltose:   return pair(data.carbDetails?.maltose)
        case .sucrose:   return pair(data.carbDetails?.sucrose)
        }
    }
    
    /// Wrapper функция за съвместимост с SearchIndexStore.
    /// Връща само стойността (Double).
    func calculatedValue(for nutrient: NutrientType) -> Double {
        return calculatedNutrition(for: nutrient).value
    }
}

// MARK: - Canonical nutrient units (single source of truth)
extension FoodItem {
    
    /// Static cache of canonical units for each nutrient type, loaded from NutrientTypeUnits.json.
    /// This is used both by `calculatedNutrition(for:)` and by the search engine when normalising user
    /// numeric constraints.
    nonisolated static let canonicalUnits: [NutrientType: String] = {
        guard let url = Bundle.main.url(forResource: "NutrientTypeUnits", withExtension: "json") else {
            print("⚠️ FoodItem: NutrientTypeUnits.json missing from bundle. Canonical units will default to 'g'.")
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: url)
            let rawMap = try JSONDecoder().decode([String: String].self, from: data)
            
            var map: [NutrientType: String] = [:]
            for (key, unit) in rawMap {
                // Опитваме се да намерим enum case, отговарящ на ключа от JSON-а
                if let type = NutrientType(rawValue: key) {
                    map[type] = unit
                }
            }
            return map
        } catch {
            print("⚠️ FoodItem: Failed to decode NutrientTypeUnits.json: \(error)")
            return [:]
        }
    }()
    
    /// Convenience helper used by SearchKnowledgeBase and anywhere else that
    /// needs the canonical unit for a given nutrient.
    nonisolated static func canonicalUnit(for nutrient: NutrientType) -> String {
        canonicalUnits[nutrient] ?? "g"
    }
}
