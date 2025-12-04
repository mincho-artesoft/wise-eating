import Foundation
import SwiftData

// MARK: - FoodItemCopy -----------------------------------------------------

public final class FoodItemCopy: Identifiable, Codable {
    public var originalID: Int?

    // MARK: – Basic
    public var name: String
    public var nameNormalized: String
    public var category:  [FoodCategory]?
    public var isRecipe:    Bool
    public var isMenu:      Bool
    public var isUserAdded: Bool

    // MARK: – Tags
    public var dietIDs:     [String]?
    public var allergens: [Allergen]?

    // MARK: – Nutrition
    public var macronutrients: MacronutrientsDataCopy?
    public var lipids:         LipidsDataCopy?
    public var vitamins:       VitaminsDataCopy?
    public var minerals:       MineralsDataCopy?
    public var other:          OtherCompoundsDataCopy?
    public var aminoAcids:     AminoAcidsDataCopy?
    public var carbDetails:    CarbDetailsDataCopy?
    public var sterols:        SterolsDataCopy?

    // MARK: – Media & meta
    public var photo: Data?
    public var gallery: [FoodPhotoCopy]?
    public var prepTimeMinutes: Int?
    public var itemDescription: String?

    // MARK: – Recipe links
    public var ingredients: [IngredientLinkCopy]?

    // MARK: – Init
    public init(
        name: String,
        category: [FoodCategory]? = nil,
        isRecipe: Bool = false,
        isMenu: Bool = false,
        isUserAdded: Bool = true,
        dietIDs: [String]? = nil,
        allergens: [Allergen]? = nil,
        photo: Data? = nil,
        gallery: [FoodPhotoCopy]? = nil,
        prepTimeMinutes: Int? = nil,
        itemDescription: String? = nil,
        macronutrients: MacronutrientsDataCopy? = nil,
        lipids: LipidsDataCopy? = nil,
        vitamins: VitaminsDataCopy? = nil,
        minerals: MineralsDataCopy? = nil,
        other: OtherCompoundsDataCopy? = nil,
        aminoAcids: AminoAcidsDataCopy? = nil,
        carbDetails: CarbDetailsDataCopy? = nil,
        sterols: SterolsDataCopy? = nil,
        ingredients: [IngredientLinkCopy]? = nil,
        originalID: Int? = nil
    ) {
        self.name               = name
        self.nameNormalized     = name.foldedSearchKey
        self.category           = category
        self.isRecipe           = isRecipe
        self.isMenu             = isMenu
        self.isUserAdded        = isUserAdded
        self.dietIDs            = dietIDs
        self.allergens          = allergens
        self.photo              = photo
        self.gallery            = gallery
        self.prepTimeMinutes    = prepTimeMinutes
        self.itemDescription    = itemDescription
        self.macronutrients     = macronutrients
        self.lipids             = lipids
        self.vitamins           = vitamins
        self.minerals           = minerals
        self.other              = other
        self.aminoAcids         = aminoAcids
        self.carbDetails        = carbDetails
        self.sterols            = sterols
        self.ingredients        = ingredients
        self.originalID         = originalID
    }
    
    @MainActor
    convenience init(
        from dto: ResolvedRecipeResponseDTO,
        recipeName: String,
        context: ModelContext
    ) {
        // --- НАЧАЛО НА КОРЕКЦИЯТА ---
        
        // 1. (Ефективност) Създаваме Set от ID-тата, за да премахнем дубликатите.
        let uniqueFoodItemIDs = Set(dto.ingredients.map { $0.foodItemID })
        
        // Извличаме всеки FoodItem от базата данни само по веднъж.
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { uniqueFoodItemIDs.contains($0.id) })
        let foodItems = (try? context.fetch(descriptor)) ?? []
        
        // 2. (Сигурност) Създаваме речника безопасно, като му казваме да запази първата срещната
        // стойност при дублиращ се ключ. Това прави кода по-устойчив.
        let foodItemMap = Dictionary(foodItems.map { ($0.id, $0) }, uniquingKeysWith: { (first, _) in first })
        
        // --- КРАЙ НА КОРЕКЦИЯТА ---

        var cache: [ObjectIdentifier: FoodItemCopy] = [:]
        
        let ingredientLinks: [IngredientLinkCopy] = dto.ingredients.compactMap { resolvedIngredient in
            guard let foodItem = foodItemMap[resolvedIngredient.foodItemID] else { return nil }
            let foodItemCopy = FoodItemCopy(from: foodItem, cache: &cache)
            return IngredientLinkCopy(food: foodItemCopy, grams: resolvedIngredient.grams)
        }
        
        self.init(
            name: recipeName,
            isRecipe: true,
            prepTimeMinutes: dto.prepTimeMinutes, itemDescription: dto.description,
            ingredients: ingredientLinks
        )
        
        self.ingredients?.forEach { $0.owner = self }
    }
    
    
    @MainActor
    convenience init(
        from dto: ResolvedRecipeResponseDTO,
        menuName: String, // Използваме различно име на параметъра, за да го разграничим
        context: ModelContext
    ) {
        // --- НАЧАЛО НА КОРЕКЦИЯТА (приложена и тук за консистентност) ---
        
        // 1. (Ефективност)
        let uniqueFoodItemIDs = Set(dto.ingredients.map { $0.foodItemID })
        
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { uniqueFoodItemIDs.contains($0.id) })
        let foodItems = (try? context.fetch(descriptor)) ?? []
        
        // 2. (Сигурност)
        let foodItemMap = Dictionary(foodItems.map { ($0.id, $0) }, uniquingKeysWith: { (first, _) in first })

        // --- КРАЙ НА КОРЕКЦИЯТА ---
        
        var cache: [ObjectIdentifier: FoodItemCopy] = [:]
        
        let ingredientLinks: [IngredientLinkCopy] = dto.ingredients.compactMap { resolvedIngredient in
            guard let foodItem = foodItemMap[resolvedIngredient.foodItemID] else { return nil }
            let foodItemCopy = FoodItemCopy(from: foodItem, cache: &cache)
            return IngredientLinkCopy(food: foodItemCopy, grams: resolvedIngredient.grams)
        }
        
        self.init(
            name: menuName,
            isRecipe: false, // Менюто не е рецепта
            isMenu: true,    // Маркираме го като меню
            prepTimeMinutes: dto.prepTimeMinutes,
            itemDescription: dto.description,
            ingredients: ingredientLinks
        )
        
        self.ingredients?.forEach { $0.owner = self }
    }
    // --- Ръчна имплементация на Codable ---
    enum CodingKeys: String, CodingKey {
        case originalID, name, nameNormalized, category, isRecipe, isMenu, isUserAdded
        case dietIDs = "diets" // Казваме му да използва "diets" в JSON
        case allergens, macronutrients, lipids, vitamins, minerals, other, aminoAcids, carbDetails, sterols
        case photo, gallery, prepTimeMinutes, itemDescription, ingredients
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalID = try container.decodeIfPresent(Int.self, forKey: .originalID)
        name = try container.decode(String.self, forKey: .name)
        nameNormalized = try container.decode(String.self, forKey: .nameNormalized)
        category = try container.decodeIfPresent([FoodCategory].self, forKey: .category)
        isRecipe = try container.decode(Bool.self, forKey: .isRecipe)
        isMenu = try container.decode(Bool.self, forKey: .isMenu)
        isUserAdded = try container.decode(Bool.self, forKey: .isUserAdded)
        dietIDs = try container.decodeIfPresent([String].self, forKey: .dietIDs)
        allergens = try container.decodeIfPresent([Allergen].self, forKey: .allergens)
        macronutrients = try container.decodeIfPresent(MacronutrientsDataCopy.self, forKey: .macronutrients)
        lipids = try container.decodeIfPresent(LipidsDataCopy.self, forKey: .lipids)
        vitamins = try container.decodeIfPresent(VitaminsDataCopy.self, forKey: .vitamins)
        minerals = try container.decodeIfPresent(MineralsDataCopy.self, forKey: .minerals)
        other = try container.decodeIfPresent(OtherCompoundsDataCopy.self, forKey: .other)
        aminoAcids = try container.decodeIfPresent(AminoAcidsDataCopy.self, forKey: .aminoAcids)
        carbDetails = try container.decodeIfPresent(CarbDetailsDataCopy.self, forKey: .carbDetails)
        sterols = try container.decodeIfPresent(SterolsDataCopy.self, forKey: .sterols)
        photo = try container.decodeIfPresent(Data.self, forKey: .photo)
        gallery = try container.decodeIfPresent([FoodPhotoCopy].self, forKey: .gallery)
        prepTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .prepTimeMinutes)
        itemDescription = try container.decodeIfPresent(String.self, forKey: .itemDescription)
        ingredients = try container.decodeIfPresent([IngredientLinkCopy].self, forKey: .ingredients)
        
        // Възстановяваме обратните връзки
        ingredients?.forEach { $0.owner = self }
        gallery?.forEach { $0.foodItem = self }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(originalID, forKey: .originalID)
        try container.encode(name, forKey: .name)
        try container.encode(nameNormalized, forKey: .nameNormalized)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(isRecipe, forKey: .isRecipe)
        try container.encode(isMenu, forKey: .isMenu)
        try container.encode(isUserAdded, forKey: .isUserAdded)
        try container.encodeIfPresent(dietIDs, forKey: .dietIDs)
        try container.encodeIfPresent(allergens, forKey: .allergens)
        try container.encodeIfPresent(macronutrients, forKey: .macronutrients)
        try container.encodeIfPresent(lipids, forKey: .lipids)
        try container.encodeIfPresent(vitamins, forKey: .vitamins)
        try container.encodeIfPresent(minerals, forKey: .minerals)
        try container.encodeIfPresent(other, forKey: .other)
        try container.encodeIfPresent(aminoAcids, forKey: .aminoAcids)
        try container.encodeIfPresent(carbDetails, forKey: .carbDetails)
        try container.encodeIfPresent(sterols, forKey: .sterols)
        try container.encodeIfPresent(photo, forKey: .photo)
        try container.encodeIfPresent(gallery, forKey: .gallery)
        try container.encodeIfPresent(prepTimeMinutes, forKey: .prepTimeMinutes)
        try container.encodeIfPresent(itemDescription, forKey: .itemDescription)
        try container.encodeIfPresent(ingredients, forKey: .ingredients)
    }
}

// MARK: - Helper "Copy" Types ---------------------------------------------

public struct DisplayNutrientCopy: Identifiable, Codable {
    public var id = UUID()
    public let name:    String
    public let value:   Double
    public let unit:    String
    public let valueMg: Double
}

public final class FoodPhotoCopy: Identifiable, Codable {
    public var id = UUID()
    public var data: Data
    public var createdAt: Date
    public weak var foodItem: FoodItemCopy?

    enum CodingKeys: String, CodingKey { case id, data, createdAt } // Игнорираме weak foodItem
    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); data = try c.decode(Data.self, forKey: .data); createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(data, forKey: .data); try c.encode(createdAt, forKey: .createdAt)
    }
    
    public init(data: Data, createdAt: Date = .now) { self.data = data; self.createdAt = createdAt }
}

public final class IngredientLinkCopy: Identifiable, Codable {
    public var id = UUID()
    public var food: FoodItemCopy? // Променяме го на strong, за да е Codable
    public var grams: Double
    public weak var owner: FoodItemCopy?

    enum CodingKeys: String, CodingKey { case id, food, grams } // Игнорираме owner, за да избегнем цикъл
    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); food = try c.decodeIfPresent(FoodItemCopy.self, forKey: .food); grams = try c.decode(Double.self, forKey: .grams)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encodeIfPresent(food, forKey: .food); try c.encode(grams, forKey: .grams)
    }

    public init(food: FoodItemCopy? = nil, grams: Double = 0, owner: FoodItemCopy? = nil) {
        self.food = food; self.grams = grams; self.owner = owner
    }
}

// MARK: - Copy data groups

public final class MacronutrientsDataCopy: Identifiable, Codable {
    public var id = UUID()
    public var carbohydrates: Nutrient?
    public var protein:       Nutrient?
    public var fat:           Nutrient?
    public var fiber:         Nutrient?
    public var totalSugars:   Nutrient?

    public init(carbohydrates: Nutrient? = nil, protein: Nutrient? = nil, fat: Nutrient? = nil, fiber: Nutrient? = nil, totalSugars: Nutrient? = nil) {
        self.carbohydrates = carbohydrates; self.protein = protein; self.fat = fat; self.fiber = fiber; self.totalSugars = totalSugars
    }
}

public final class LipidsDataCopy: Identifiable, Codable {
    public var id = UUID()
    public var totalSaturated:        Nutrient?
    public var totalMonounsaturated:  Nutrient?
    public var totalPolyunsaturated:  Nutrient?
    public var totalTrans:            Nutrient?
    public var totalTransMonoenoic:   Nutrient?
    public var totalTransPolyenoic:   Nutrient?
    public var sfa4_0: Nutrient?;  public var sfa6_0: Nutrient?;  public var sfa8_0: Nutrient?;  public var sfa10_0: Nutrient?
    public var sfa12_0: Nutrient?; public var sfa13_0: Nutrient?; public var sfa14_0: Nutrient?; public var sfa15_0: Nutrient?
    public var sfa16_0: Nutrient?; public var sfa17_0: Nutrient?; public var sfa18_0: Nutrient?; public var sfa20_0: Nutrient?
    public var sfa22_0: Nutrient?; public var sfa24_0: Nutrient?
    public var mufa14_1: Nutrient?; public var mufa15_1: Nutrient?; public var mufa16_1: Nutrient?; public var mufa17_1: Nutrient?
    public var mufa18_1: Nutrient?; public var mufa20_1: Nutrient?; public var mufa22_1: Nutrient?; public var mufa24_1: Nutrient?
    public var tfa16_1_t: Nutrient?; public var tfa18_1_t: Nutrient?; public var tfa22_1_t: Nutrient?; public var tfa18_2_t: Nutrient?
    public var pufa18_2: Nutrient?; public var pufa18_3: Nutrient?; public var pufa18_4: Nutrient?
    public var pufa20_2: Nutrient?; public var pufa20_3: Nutrient?; public var pufa20_4: Nutrient?; public var pufa20_5: Nutrient?
    public var pufa21_5: Nutrient?; public var pufa22_4: Nutrient?; public var pufa22_5: Nutrient?; public var pufa22_6: Nutrient?
    public var pufa2_4:  Nutrient?

    public init(
        totalSaturated: Nutrient? = nil, totalMonounsaturated: Nutrient? = nil, totalPolyunsaturated: Nutrient? = nil,
        totalTrans: Nutrient? = nil, totalTransMonoenoic: Nutrient? = nil, totalTransPolyenoic: Nutrient? = nil,
        sfa4_0: Nutrient? = nil, sfa6_0: Nutrient? = nil, sfa8_0: Nutrient? = nil, sfa10_0: Nutrient? = nil,
        sfa12_0: Nutrient? = nil, sfa13_0: Nutrient? = nil, sfa14_0: Nutrient? = nil, sfa15_0: Nutrient? = nil,
        sfa16_0: Nutrient? = nil, sfa17_0: Nutrient? = nil, sfa18_0: Nutrient? = nil, sfa20_0: Nutrient? = nil,
        sfa22_0: Nutrient? = nil, sfa24_0: Nutrient? = nil,
        mufa14_1: Nutrient? = nil, mufa15_1: Nutrient? = nil, mufa16_1: Nutrient? = nil, mufa17_1: Nutrient? = nil,
        mufa18_1: Nutrient? = nil, mufa20_1: Nutrient? = nil, mufa22_1: Nutrient? = nil, mufa24_1: Nutrient? = nil,
        tfa16_1_t: Nutrient? = nil, tfa18_1_t: Nutrient? = nil, tfa22_1_t: Nutrient? = nil, tfa18_2_t: Nutrient? = nil,
        pufa18_2: Nutrient? = nil, pufa18_3: Nutrient? = nil, pufa18_4: Nutrient? = nil,
        pufa20_2: Nutrient? = nil, pufa20_3: Nutrient? = nil, pufa20_4: Nutrient? = nil, pufa20_5: Nutrient? = nil,
        pufa21_5: Nutrient? = nil, pufa22_4: Nutrient? = nil, pufa22_5: Nutrient? = nil, pufa22_6: Nutrient? = nil,
        pufa2_4: Nutrient? = nil
    ) {
        self.totalSaturated = totalSaturated; self.totalMonounsaturated = totalMonounsaturated; self.totalPolyunsaturated = totalPolyunsaturated
        self.totalTrans = totalTrans; self.totalTransMonoenoic = totalTransMonoenoic; self.totalTransPolyenoic = totalTransPolyenoic
        self.sfa4_0 = sfa4_0; self.sfa6_0 = sfa6_0; self.sfa8_0 = sfa8_0; self.sfa10_0 = sfa10_0
        self.sfa12_0 = sfa12_0; self.sfa13_0 = sfa13_0; self.sfa14_0 = sfa14_0; self.sfa15_0 = sfa15_0
        self.sfa16_0 = sfa16_0; self.sfa17_0 = sfa17_0; self.sfa18_0 = sfa18_0; self.sfa20_0 = sfa20_0
        self.sfa22_0 = sfa22_0; self.sfa24_0 = sfa24_0
        self.mufa14_1 = mufa14_1; self.mufa15_1 = mufa15_1; self.mufa16_1 = mufa16_1; self.mufa17_1 = mufa17_1
        self.mufa18_1 = mufa18_1; self.mufa20_1 = mufa20_1; self.mufa22_1 = mufa22_1; self.mufa24_1 = mufa24_1
        self.tfa16_1_t = tfa16_1_t; self.tfa18_1_t = tfa18_1_t; self.tfa22_1_t = tfa22_1_t; self.tfa18_2_t = tfa18_2_t
        self.pufa18_2 = pufa18_2; self.pufa18_3 = pufa18_3; self.pufa18_4 = pufa18_4
        self.pufa20_2 = pufa20_2; self.pufa20_3 = pufa20_3; self.pufa20_4 = pufa20_4; self.pufa20_5 = pufa20_5
        self.pufa21_5 = pufa21_5; self.pufa22_4 = pufa22_4; self.pufa22_5 = pufa22_5; self.pufa22_6 = pufa22_6
        self.pufa2_4 = pufa2_4
    }
}

public final class MineralsDataCopy: Identifiable, Codable {
    public var id = UUID()
    public var calcium: Nutrient?; public var iron: Nutrient?; public var magnesium: Nutrient?
    public var phosphorus: Nutrient?; public var potassium: Nutrient?; public var sodium: Nutrient?
    public var selenium: Nutrient?; public var zinc: Nutrient?; public var copper: Nutrient?
    public var manganese: Nutrient?; public var fluoride: Nutrient?

    public init(calcium: Nutrient? = nil, iron: Nutrient? = nil, magnesium: Nutrient? = nil, phosphorus: Nutrient? = nil, potassium: Nutrient? = nil, sodium: Nutrient? = nil, selenium: Nutrient? = nil, zinc: Nutrient? = nil, copper: Nutrient? = nil, manganese: Nutrient? = nil, fluoride: Nutrient? = nil) {
        self.calcium = calcium; self.iron = iron; self.magnesium = magnesium; self.phosphorus = phosphorus; self.potassium = potassium; self.sodium = sodium; self.selenium = selenium; self.zinc = zinc; self.copper = copper; self.manganese = manganese; self.fluoride = fluoride
    }
}

public final class OtherCompoundsDataCopy: Identifiable, Codable {
    public var id = UUID()
    
    public var alcoholEthyl: Nutrient?
    public var caffeine:     Nutrient?
    public var theobromine:  Nutrient?
    public var cholesterol:  Nutrient?
    public var energyKcal:   Nutrient?
    public var water:        Nutrient?
    public var weightG:      Nutrient?
    public var ash:          Nutrient?
    public var betaine:      Nutrient?
    public var alkalinityPH: Nutrient?

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

public final class VitaminsDataCopy: Identifiable, Codable {
    public var id = UUID()
    public var vitaminA_RAE: Nutrient?; public var retinol: Nutrient?; public var caroteneAlpha: Nutrient?
    public var caroteneBeta: Nutrient?; public var cryptoxanthinBeta: Nutrient?; public var luteinZeaxanthin: Nutrient?
    public var lycopene: Nutrient?
    public var vitaminB1_Thiamin: Nutrient?; public var vitaminB2_Riboflavin: Nutrient?
    public var vitaminB3_Niacin: Nutrient?; public var vitaminB5_PantothenicAcid: Nutrient?
    public var vitaminB6: Nutrient?
    public var folateDFE: Nutrient?; public var folateFood: Nutrient?; public var folateTotal: Nutrient?; public var folicAcid: Nutrient?
    public var vitaminB12: Nutrient?
    public var vitaminC: Nutrient?; public var vitaminD: Nutrient?; public var vitaminE: Nutrient?; public var vitaminK: Nutrient?
    public var choline: Nutrient?

    public init(vitaminA_RAE: Nutrient? = nil, retinol: Nutrient? = nil, caroteneAlpha: Nutrient? = nil, caroteneBeta: Nutrient? = nil, cryptoxanthinBeta: Nutrient? = nil, luteinZeaxanthin: Nutrient? = nil, lycopene: Nutrient? = nil, vitaminB1_Thiamin: Nutrient? = nil, vitaminB2_Riboflavin: Nutrient? = nil, vitaminB3_Niacin: Nutrient? = nil, vitaminB5_PantothenicAcid: Nutrient? = nil, vitaminB6: Nutrient? = nil, folateDFE: Nutrient? = nil, folateFood: Nutrient? = nil, folateTotal: Nutrient? = nil, folicAcid: Nutrient? = nil, vitaminB12: Nutrient? = nil, vitaminC: Nutrient? = nil, vitaminD: Nutrient? = nil, vitaminE: Nutrient? = nil, vitaminK: Nutrient? = nil, choline: Nutrient? = nil) {
        self.vitaminA_RAE = vitaminA_RAE; self.retinol = retinol; self.caroteneAlpha = caroteneAlpha; self.caroteneBeta = caroteneBeta; self.cryptoxanthinBeta = cryptoxanthinBeta; self.luteinZeaxanthin = luteinZeaxanthin; self.lycopene = lycopene; self.vitaminB1_Thiamin = vitaminB1_Thiamin; self.vitaminB2_Riboflavin = vitaminB2_Riboflavin; self.vitaminB3_Niacin = vitaminB3_Niacin; self.vitaminB5_PantothenicAcid = vitaminB5_PantothenicAcid; self.vitaminB6 = vitaminB6; self.folateDFE = folateDFE; self.folateFood = folateFood; self.folateTotal = folateTotal; self.folicAcid = folicAcid; self.vitaminB12 = vitaminB12; self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminE = vitaminE; self.vitaminK = vitaminK; self.choline = choline
    }
}

public final class AminoAcidsDataCopy: Identifiable, Codable {
    public var id = UUID()
    public var alanine: Nutrient?; public var arginine: Nutrient?; public var asparticAcid: Nutrient?; public var cystine: Nutrient?
    public var glutamicAcid: Nutrient?; public var glycine: Nutrient?; public var histidine: Nutrient?; public var isoleucine: Nutrient?
    public var leucine: Nutrient?; public var lysine: Nutrient?; public var methionine: Nutrient?; public var phenylalanine: Nutrient?
    public var proline: Nutrient?; public var threonine: Nutrient?; public var tryptophan: Nutrient?; public var tyrosine: Nutrient?
    public var valine: Nutrient?; public var serine: Nutrient?; public var hydroxyproline: Nutrient?

    public init(alanine: Nutrient? = nil, arginine: Nutrient? = nil, asparticAcid: Nutrient? = nil, cystine: Nutrient? = nil, glutamicAcid: Nutrient? = nil, glycine: Nutrient? = nil, histidine: Nutrient? = nil, isoleucine: Nutrient? = nil, leucine: Nutrient? = nil, lysine: Nutrient? = nil, methionine: Nutrient? = nil, phenylalanine: Nutrient? = nil, proline: Nutrient? = nil, threonine: Nutrient? = nil, tryptophan: Nutrient? = nil, tyrosine: Nutrient? = nil, valine: Nutrient? = nil, serine: Nutrient? = nil, hydroxyproline: Nutrient? = nil) {
        self.alanine = alanine; self.arginine = arginine; self.asparticAcid = asparticAcid; self.cystine = cystine; self.glutamicAcid = glutamicAcid; self.glycine = glycine; self.histidine = histidine; self.isoleucine = isoleucine; self.leucine = leucine; self.lysine = lysine; self.methionine = methionine; self.phenylalanine = phenylalanine; self.proline = proline; self.threonine = threonine; self.tryptophan = tryptophan; self.tyrosine = tyrosine; self.valine = valine; self.serine = serine; self.hydroxyproline = hydroxyproline
    }
}

public final class CarbDetailsDataCopy: Identifiable, Codable {
    public var id = UUID()
    public var starch: Nutrient?; public var sucrose: Nutrient?; public var glucose: Nutrient?
    public var fructose: Nutrient?; public var lactose: Nutrient?; public var maltose: Nutrient?; public var galactose: Nutrient?

    public init(starch: Nutrient? = nil, sucrose: Nutrient? = nil, glucose: Nutrient? = nil, fructose: Nutrient? = nil, lactose: Nutrient? = nil, maltose: Nutrient? = nil, galactose: Nutrient? = nil) {
        self.starch = starch; self.sucrose = sucrose; self.glucose = glucose; self.fructose = fructose; self.lactose = lactose; self.maltose = maltose; self.galactose = galactose
    }
}

public final class SterolsDataCopy: Identifiable, Codable {
    public var id = UUID()
    public var phytosterols: Nutrient?; public var betaSitosterol: Nutrient?; public var campesterol: Nutrient?; public var stigmasterol: Nutrient?

    public init(phytosterols: Nutrient? = nil, betaSitosterol: Nutrient? = nil, campesterol: Nutrient? = nil, stigmasterol: Nutrient? = nil) {
        self.phytosterols = phytosterols; self.betaSitosterol = betaSitosterol; self.campesterol = campesterol; self.stigmasterol = stigmasterol
    }
}

// MARK: - Convenience Inits (Original -> Copy) -----------------------------

extension MacronutrientsDataCopy { convenience init?(from src: MacronutrientsData?) { guard let s = src else { return nil }; self.init(carbohydrates: s.carbohydrates, protein: s.protein, fat: s.fat, fiber: s.fiber, totalSugars: s.totalSugars) } }
extension LipidsDataCopy { convenience init?(from src: LipidsData?) { guard let s = src else { return nil }; self.init(totalSaturated: s.totalSaturated, totalMonounsaturated: s.totalMonounsaturated, totalPolyunsaturated: s.totalPolyunsaturated, totalTrans: s.totalTrans, totalTransMonoenoic: s.totalTransMonoenoic, totalTransPolyenoic: s.totalTransPolyenoic, sfa4_0: s.sfa4_0, sfa6_0: s.sfa6_0, sfa8_0: s.sfa8_0, sfa10_0: s.sfa10_0, sfa12_0: s.sfa12_0, sfa13_0: s.sfa13_0, sfa14_0: s.sfa14_0, sfa15_0: s.sfa15_0, sfa16_0: s.sfa16_0, sfa17_0: s.sfa17_0, sfa18_0: s.sfa18_0, sfa20_0: s.sfa20_0, sfa22_0: s.sfa22_0, sfa24_0: s.sfa24_0, mufa14_1: s.mufa14_1, mufa15_1: s.mufa15_1, mufa16_1: s.mufa16_1, mufa17_1: s.mufa17_1, mufa18_1: s.mufa18_1, mufa20_1: s.mufa20_1, mufa22_1: s.mufa22_1, mufa24_1: s.mufa24_1, tfa16_1_t: s.tfa16_1_t, tfa18_1_t: s.tfa18_1_t, tfa22_1_t: s.tfa22_1_t, tfa18_2_t: s.tfa18_2_t, pufa18_2: s.pufa18_2, pufa18_3: s.pufa18_3, pufa18_4: s.pufa18_4, pufa20_2: s.pufa20_2, pufa20_3: s.pufa20_3, pufa20_4: s.pufa20_4, pufa20_5: s.pufa20_5, pufa21_5: s.pufa21_5, pufa22_4: s.pufa22_4, pufa22_5: s.pufa22_5, pufa22_6: s.pufa22_6, pufa2_4: s.pufa2_4) } }
extension MineralsDataCopy { convenience init?(from src: MineralsData?) { guard let s = src else { return nil }; self.init(calcium: s.calcium, iron: s.iron, magnesium: s.magnesium, phosphorus: s.phosphorus, potassium: s.potassium, sodium: s.sodium, selenium: s.selenium, zinc: s.zinc, copper: s.copper, manganese: s.manganese, fluoride: s.fluoride) } }
extension OtherCompoundsDataCopy {
    convenience init?(from src: OtherCompoundsData?) {
        guard let s = src else { return nil }
        self.init(
            alcoholEthyl: s.alcoholEthyl,
            caffeine:     s.caffeine,
            theobromine:  s.theobromine,
            cholesterol:  s.cholesterol,
            energyKcal:   s.energyKcal,
            water:        s.water,
            weightG:      s.weightG,
            ash:          s.ash,
            betaine:      s.betaine,
            alkalinityPH: s.alkalinityPH
        )
    }
}
extension VitaminsDataCopy { convenience init?(from src: VitaminsData?) { guard let s = src else { return nil }; self.init(vitaminA_RAE: s.vitaminA_RAE, retinol: s.retinol, caroteneAlpha: s.caroteneAlpha, caroteneBeta: s.caroteneBeta, cryptoxanthinBeta: s.cryptoxanthinBeta, luteinZeaxanthin: s.luteinZeaxanthin, lycopene: s.lycopene, vitaminB1_Thiamin: s.vitaminB1_Thiamin, vitaminB2_Riboflavin: s.vitaminB2_Riboflavin, vitaminB3_Niacin: s.vitaminB3_Niacin, vitaminB5_PantothenicAcid: s.vitaminB5_PantothenicAcid, vitaminB6: s.vitaminB6, folateDFE: s.folateDFE, folateFood: s.folateFood, folateTotal: s.folateTotal, folicAcid: s.folicAcid, vitaminB12: s.vitaminB12, vitaminC: s.vitaminC, vitaminD: s.vitaminD, vitaminE: s.vitaminE, vitaminK: s.vitaminK, choline: s.choline) } }
extension AminoAcidsDataCopy { convenience init?(from src: AminoAcidsData?) { guard let s = src else { return nil }; self.init(alanine: s.alanine, arginine: s.arginine, asparticAcid: s.asparticAcid, cystine: s.cystine, glutamicAcid: s.glutamicAcid, glycine: s.glycine, histidine: s.histidine, isoleucine: s.isoleucine, leucine: s.leucine, lysine: s.lysine, methionine: s.methionine, phenylalanine: s.phenylalanine, proline: s.proline, threonine: s.threonine, tryptophan: s.tryptophan, tyrosine: s.tyrosine, valine: s.valine, serine: s.serine, hydroxyproline: s.hydroxyproline) } }
extension CarbDetailsDataCopy { convenience init?(from src: CarbDetailsData?) { guard let s = src else { return nil }; self.init(starch: s.starch, sucrose: s.sucrose, glucose: s.glucose, fructose: s.fructose, lactose: s.lactose, maltose: s.maltose, galactose: s.galactose) } }
extension SterolsDataCopy { convenience init?(from src: SterolsData?) { guard let s = src else { return nil }; self.init(phytosterols: s.phytosterols, betaSitosterol: s.betaSitosterol, campesterol: s.campesterol, stigmasterol: s.stigmasterol) } }
extension FoodPhotoCopy { convenience init(from src: FoodPhoto) { self.init(data: src.data, createdAt: src.createdAt) } }

extension IngredientLinkCopy {
    convenience init(from src: IngredientLink, cache: inout [ObjectIdentifier : FoodItemCopy]) {
        let itemCopy: FoodItemCopy? = src.food.map { FoodItemCopy(from: $0, cache: &cache) }
        self.init(food: itemCopy, grams: src.grams)
    }
}

extension FoodItemCopy {
    public convenience init(from src: FoodItem, cache: inout [ObjectIdentifier : FoodItemCopy]) {
        let key = ObjectIdentifier(src)
        if let hit = cache[key] {
            self.init(from: hit)
            return
        }
        let mac = MacronutrientsDataCopy(from: src.macronutrients)
        let lip = LipidsDataCopy(from: src.lipids)
        let vit = VitaminsDataCopy(from: src.vitamins)
        let min = MineralsDataCopy(from: src.minerals)
        let oth = OtherCompoundsDataCopy(from: src.other)
        let aa  = AminoAcidsDataCopy(from: src.aminoAcids)
        let cd  = CarbDetailsDataCopy(from: src.carbDetails)
        let st  = SterolsDataCopy(from: src.sterols)

        let ingCopies = src.ingredients?.map { IngredientLinkCopy(from: $0, cache: &cache) }
        
        self.init(
            name: src.name, category: src.category, isRecipe: src.isRecipe, isMenu: src.isMenu, isUserAdded: src.isUserAdded,
            dietIDs: src.diets?.map(\.id), // <-- КОРЕКЦИЯТА Е ТУК
            allergens: src.allergens, photo: src.photo, gallery: src.gallery?.map { FoodPhotoCopy(from: $0) },
            prepTimeMinutes: src.prepTimeMinutes, itemDescription: src.itemDescription,
            macronutrients: mac, lipids: lip, vitamins: vit, minerals: min, other: oth,
            aminoAcids: aa, carbDetails: cd, sterols: st,
            ingredients: ingCopies, originalID: src.id
        )
        
        ingCopies?.forEach { $0.owner = self }
        cache[key] = self
    }

    public convenience init(from src: FoodItem) {
        var tmp: [ObjectIdentifier : FoodItemCopy] = [:]
        self.init(from: src, cache: &tmp)
    }

    private convenience init(from copy: FoodItemCopy) {
        self.init(
            name: copy.name, category: copy.category, isRecipe: copy.isRecipe, isMenu: copy.isMenu, isUserAdded: copy.isUserAdded,
            dietIDs: copy.dietIDs,
            allergens: copy.allergens, photo: copy.photo, gallery: copy.gallery,
            prepTimeMinutes: copy.prepTimeMinutes, itemDescription: copy.itemDescription,
            macronutrients: copy.macronutrients, lipids: copy.lipids, vitamins: copy.vitamins, minerals: copy.minerals, other: copy.other,
            aminoAcids: copy.aminoAcids, carbDetails: copy.carbDetails, sterols: copy.sterols,
            ingredients: copy.ingredients, originalID: copy.originalID
        )
    }
}

// MARK: - Conversion Protocol & Helpers (Copy -> Original) -----------------

protocol CopyConvertible {
    associatedtype Original
    func toOriginal() -> Original
}

extension Optional where Wrapped : CopyConvertible {
    var orig: Wrapped.Original? { self?.toOriginal() }
}

extension MacronutrientsDataCopy: CopyConvertible { func toOriginal() -> MacronutrientsData { .init(carbohydrates: carbohydrates, protein: protein, fat: fat, fiber: fiber, totalSugars: totalSugars) } }
extension LipidsDataCopy: CopyConvertible { func toOriginal() -> LipidsData { .init(totalSaturated: totalSaturated, totalMonounsaturated: totalMonounsaturated, totalPolyunsaturated: totalPolyunsaturated, totalTrans: totalTrans, totalTransMonoenoic: totalTransMonoenoic, totalTransPolyenoic: totalTransPolyenoic, sfa4_0: sfa4_0, sfa6_0: sfa6_0, sfa8_0: sfa8_0, sfa10_0: sfa10_0, sfa12_0: sfa12_0, sfa13_0: sfa13_0, sfa14_0: sfa14_0, sfa15_0: sfa15_0, sfa16_0: sfa16_0, sfa17_0: sfa17_0, sfa18_0: sfa18_0, sfa20_0: sfa20_0, sfa22_0: sfa22_0, sfa24_0: sfa24_0, mufa14_1: mufa14_1, mufa15_1: mufa15_1, mufa16_1: mufa16_1, mufa17_1: mufa17_1, mufa18_1: mufa18_1, mufa20_1: mufa20_1, mufa22_1: mufa22_1, mufa24_1: mufa24_1, tfa16_1_t: tfa16_1_t, tfa18_1_t: tfa18_1_t, tfa22_1_t: tfa22_1_t, tfa18_2_t: tfa18_2_t, pufa18_2: pufa18_2, pufa18_3: pufa18_3, pufa18_4: pufa18_4, pufa20_2: pufa20_2, pufa20_3: pufa20_3, pufa20_4: pufa20_4, pufa20_5: pufa20_5, pufa21_5: pufa21_5, pufa22_4: pufa22_4, pufa22_5: pufa22_5, pufa22_6: pufa22_6, pufa2_4: pufa2_4) } }
extension MineralsDataCopy: CopyConvertible { func toOriginal() -> MineralsData { .init(calcium: calcium, iron: iron, magnesium: magnesium, phosphorus: phosphorus, potassium: potassium, sodium: sodium, selenium: selenium, zinc: zinc, copper: copper, manganese: manganese, fluoride: fluoride) } }
extension VitaminsDataCopy: CopyConvertible { func toOriginal() -> VitaminsData { .init(vitaminA_RAE: vitaminA_RAE, retinol: retinol, caroteneAlpha: caroteneAlpha, caroteneBeta: caroteneBeta, cryptoxanthinBeta: cryptoxanthinBeta, luteinZeaxanthin: luteinZeaxanthin, lycopene: lycopene, vitaminB1_Thiamin: vitaminB1_Thiamin, vitaminB2_Riboflavin: vitaminB2_Riboflavin, vitaminB3_Niacin: vitaminB3_Niacin, vitaminB5_PantothenicAcid: vitaminB5_PantothenicAcid, vitaminB6: vitaminB6, folateDFE: folateDFE, folateFood: folateFood, folateTotal: folateTotal, folicAcid: folicAcid, vitaminB12: vitaminB12, vitaminC: vitaminC, vitaminD: vitaminD, vitaminE: vitaminE, vitaminK: vitaminK, choline: choline) } }
extension OtherCompoundsDataCopy: CopyConvertible {
    func toOriginal() -> OtherCompoundsData {
        .init(
            alcoholEthyl: alcoholEthyl,
            caffeine:     caffeine,
            theobromine:  theobromine,
            cholesterol:  cholesterol,
            energyKcal:   energyKcal,
            water:        water,
            weightG:      weightG,
            ash:          ash,
            betaine:      betaine,
            alkalinityPH: alkalinityPH 
        )
    }
}
extension AminoAcidsDataCopy: CopyConvertible { func toOriginal() -> AminoAcidsData { .init(alanine: alanine, arginine: arginine, asparticAcid: asparticAcid, cystine: cystine, glutamicAcid: glutamicAcid, glycine: glycine, histidine: histidine, isoleucine: isoleucine, leucine: leucine, lysine: lysine, methionine: methionine, phenylalanine: phenylalanine, proline: proline, threonine: threonine, tryptophan: tryptophan, tyrosine: tyrosine, valine: valine, serine: serine, hydroxyproline: hydroxyproline) } }
extension CarbDetailsDataCopy: CopyConvertible { func toOriginal() -> CarbDetailsData { .init(starch: starch, sucrose: sucrose, glucose: glucose, fructose: fructose, lactose: lactose, maltose: maltose, galactose: galactose) } }
extension SterolsDataCopy: CopyConvertible { func toOriginal() -> SterolsData { .init(phytosterols: phytosterols, betaSitosterol: betaSitosterol, campesterol: campesterol, stigmasterol: stigmasterol) } }
extension FoodPhotoCopy : CopyConvertible { func toOriginal() -> FoodPhoto { FoodPhoto(data: data, createdAt: createdAt) } }

extension FoodItemCopy: Equatable {
    public static func == (lhs: FoodItemCopy, rhs: FoodItemCopy) -> Bool {
        lhs.name == rhs.name && lhs.isRecipe == rhs.isRecipe && lhs.isMenu == rhs.isMenu
    }
}

@MainActor
extension IngredientLinkCopy {
    func toOriginal(context: ModelContext, cache: inout [ObjectIdentifier : FoodItem]) -> IngredientLink {
        let foodOrig: FoodItem = food?.toOriginal(context: context, cache: &cache) ?? FoodItem(id: -1, name: "Unknown")
        return IngredientLink(food: foodOrig, grams: grams)
    }
}

@MainActor
extension FoodItemCopy {
    func toOriginal(context: ModelContext, cache: inout [ObjectIdentifier : FoodItem]) -> FoodItem {
        let key = ObjectIdentifier(self)
        if let hit = cache[key] { return hit }

        if let id = originalID,
           let found = try? context.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })).first {
            cache[key] = found
            return found
        }
        
        // --- НАЧАЛО НА КОРЕКЦИЯТА ---
        // Извличаме стойностите в локални константи преди да създадем предиката.
        let nameToFind = self.name
        let isRecipeToFind = self.isRecipe
        let isMenuToFind = self.isMenu

        // Сега предикатът използва простите, заснети стойности, а не self.
        let pred = #Predicate<FoodItem> {
            $0.name == nameToFind &&
            $0.isRecipe == isRecipeToFind &&
            $0.isMenu == isMenuToFind
        }
        // --- КРАЙ НА КОРЕКЦИЯТА ---
        
        if let found = try? context.fetch(FetchDescriptor<FoodItem>(predicate: pred)).first {
            cache[key] = found
            return found
        }
        
        let dietNames = Set(self.dietIDs ?? [])
        let fetchedDiets: [Diet]
        if !dietNames.isEmpty {
            let predicate = #Predicate<Diet> { diet in dietNames.contains(diet.name) }
            fetchedDiets = (try? context.fetch(FetchDescriptor<Diet>(predicate: predicate))) ?? []
        } else {
            fetchedDiets = []
        }

        let fi = FoodItem(
            id: originalID ?? Self.generateNewID(in: context),
            name: name,
            category: category,
            isRecipe: isRecipe,
            isMenu: isMenu,
            isUserAdded: isUserAdded,
            diets: fetchedDiets,
            allergens: allergens,
            photo: photo,
            gallery: gallery?.map { $0.toOriginal() },
            prepTimeMinutes: prepTimeMinutes,
            itemDescription: itemDescription,
            macronutrients: macronutrients.orig,
            lipids: lipids.orig,
            vitamins: vitamins.orig,
            minerals: minerals.orig,
            other: other.orig,
            aminoAcids: aminoAcids.orig,
            carbDetails: carbDetails.orig,
            sterols: sterols.orig
        )

        context.insert(fi)
        cache[key] = fi

        if let ing = ingredients {
            fi.ingredients = ing.map {
                let link = $0.toOriginal(context: context, cache: &cache)
                link.owner = fi
                return link
            }
        }
        return fi
    }
    
    private static func generateNewID(in context: ModelContext) -> Int {
        let count = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        return count + 1
    }
    
    @MainActor
    func toOriginal(in context: ModelContext) -> FoodItem {
        var tmp: [ObjectIdentifier : FoodItem] = [:]
        return toOriginal(context: context, cache: &tmp)
    }
    
}
