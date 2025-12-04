import Foundation

class SearchKnowledgeBase: @unchecked Sendable {
    static let shared = SearchKnowledgeBase()

    // Maps any allergen keyword ("milk", "cheese", "walnut", "shrimp"...) to the
    // corresponding Allergen enum, using allergenKeywords(for:).
    lazy var allergenAliasMap: [String: Allergen] = {
        var map: [String: Allergen] = [:]
        
        for allergen in Allergen.allCases {
            let keywords = allergenKeywords(for: allergen)
            for key in keywords {
                map[key.lowercased()] = allergen
            }
            
            // Also index the rawValue itself as a fallback
            map[allergen.rawValue.lowercased()] = allergen
        }
        
        return map
    }()

    // MARK: - Generic key normalization for subjects (nutrients, diets, allergens, pH)
    func normalizeKey(_ raw: String) -> String {
        return raw
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func normalizeNutrientKey(_ raw: String) -> String {
        return raw
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
    }
    
    // MARK: - Stop Words & Negation

    let stopWords: Set<String> = [
        "with", "and", "of", "in", "style", "type", "ns", "nfs",
        "based", "added", "to", "or", "a", "an", "the", "contain", "containing",
        "source", "content", "amount", "for", "old", "my", "safe", "can", "eat",
        "is", "are", "was", "were", "be", "being", "been",
        "strictly", "exactly", "roughly", "approximately", "around", "about",
        "just", "almost", "nearly", "virtually",
        "value", "values", "level", "levels", "scale", "balance",
        "than", "then", "g", "mg", "ug", "kcal", "diet", "diets"
    ]

    let negationTerms: Set<String> = [
        "no", "without", "free", "non", "minus", "except", "zero",
        "not", "never", "nix", "none", "avoid",
        "exclude", "excluding", "excepting"
    ]

    let suffixNegationTerms: Set<String> = ["free", "zero", "less"]

    // MARK: - Nutrient Map

    // Maps BOTH:
    // 1. Lowercased User Queries ("vitamin c", "omega 3")
    // 2. Normalized CSV Headers (stripped of units/case)
    let nutrientMap: [String: NutrientType] = [
        // --- Macronutrients ---
        "protein": .protein, "proteins": .protein, "prot": .protein,
        "carbs": .carbs, "carb": .carbs,
        "carbohydrate": .carbs, "carbohydrate, by difference": .carbs, "cho": .carbs,
        "fat": .totalFat, "fats": .totalFat, "total fat": .totalFat,
        "total lipid (fat)": .totalFat, "lipids": .totalFat,
        "fiber": .fiber, "fiber, total dietary": .fiber,
        "sugar": .totalSugar, "sugars": .totalSugar, "total sugars": .totalSugar,
        "calories": .energy, "energy": .energy, "kcal": .energy,
        "water": .water, "moisture": .water,
        "alcohol": .alcohol, "alcohol, ethyl": .alcohol,
        "ash": .ash,
        "starch": .starch,

        // --- Specific Sugars ---
        "glucose": .glucose, "fructose": .fructose, "galactose": .galactose,
        "lactose": .lactose, "sucrose": .sucrose, "maltose": .maltose,

        // --- Minerals ---
        "calcium": .calcium, "calcium, ca": .calcium,
        "iron": .iron, "iron, fe": .iron,
        "magnesium": .magnesium, "magnesium, mg": .magnesium,
        "phosphorus": .phosphorus, "phosphorus, p": .phosphorus,
        "potassium": .potassium, "potassium, k": .potassium,
        "sodium": .sodium, "sodium, na": .sodium, "salt": .sodium,
        "zinc": .zinc, "zinc, zn": .zinc,
        "copper": .copper, "copper, cu": .copper,
        "manganese": .manganese, "manganese, mn": .manganese,
        "selenium": .selenium, "selenium, se": .selenium,
        "fluoride": .fluoride, "fluoride, f": .fluoride,

        // --- Vitamins ---
        "vitamin c": .vitaminC, "vitamin c, total ascorbic acid": .vitaminC, "vit c": .vitaminC,
        "vitamin a": .vitaminA, "vitamin a, rae": .vitaminA, "vit a": .vitaminA,
        "retinol": .retinol,
        "carotene, beta": .betaCarotene, "beta carotene": .betaCarotene,
        "carotene, alpha": .alphaCarotene, "alpha carotene": .alphaCarotene,
        "cryptoxanthin, beta": .betaCryptoxanthin,
        "lycopene": .lycopene,
        "lutein + zeaxanthin": .luteinZeaxanthin, "lutein": .luteinZeaxanthin,

        "vitamin e": .vitaminE, "vit e": .vitaminE,
        "vitamin d": .vitaminD, "vitamin d (d2 + d3)": .vitaminD,"vitamin d2": .vitaminD,"vitamin d3": .vitaminD, "vit d2": .vitaminD,"vit d-3": .vitaminD, "vit d": .vitaminD,
        "vitamin k": .vitaminK, "vit k": .vitaminK,

        "thiamin": .thiamin, "vitamin b1": .thiamin, "vit b-1": .thiamin,"vit b1": .thiamin,
        "riboflavin": .riboflavin, "vitamin b2": .riboflavin, "vit b-2": .riboflavin,"vit b2": .riboflavin,
        "niacin": .niacin, "vitamin b3": .niacin, "vit b-3": .niacin,"vit b3": .niacin,
        "pantothenic acid": .pantothenicAcid, "vitamin b5": .pantothenicAcid,"vit b-5": .pantothenicAcid ,"vit b5": .pantothenicAcid,

        "vitamin b6": .vitaminB6, "vitamin b-6": .vitaminB6, "vit b-6": .vitaminB6, "vit b6": .vitaminB6,
        "vitamin b12": .vitaminB12, "vitamin b-12": .vitaminB12, "vit b-12": .vitaminB12,"vit b12": .vitaminB12, "cobalamin": .vitaminB12,

        "folate": .folateTotal, "folate, total": .folateTotal, "total folate": .folateTotal,
        "folate, food": .folateFood,
        "folate, dfe": .folateDFE,
        "folic acid": .folicAcid,

        "choline": .choline, "choline, total": .choline,
        "betaine": .betaine,

        // --- Fats & Fatty Acids ---
        "saturated fat": .saturatedFat,
        "fatty acids, total saturated": .saturatedFat,
        "sat fat": .saturatedFat,

        "monounsaturated": .monounsaturatedFat,
        "fatty acids, total monounsaturated": .monounsaturatedFat,
        "mufa": .monounsaturatedFat,

        "polyunsaturated": .polyunsaturatedFat,
        "fatty acids, total polyunsaturated": .polyunsaturatedFat,
        "pufa": .polyunsaturatedFat,

        "trans fat": .transFat,
        "fatty acids, total trans": .transFat,

        "cholesterol": .cholesterol,
        "phytosterols": .phytosterols,

        // Sterols
        "beta-sitosterol": .betaSitosterol,
        "campesterol": .campesterol,
        "stigmasterol": .stigmasterol,

        // Specific SFAs
        "sfa 4:0": .sfa4_0, "sfa 6:0": .sfa6_0, "sfa 8:0": .sfa8_0, "sfa 10:0": .sfa10_0,
        "sfa 12:0": .sfa12_0, "sfa 13:0": .sfa13_0, "sfa 14:0": .sfa14_0, "sfa 15:0": .sfa15_0,
        "sfa 16:0": .sfa16_0, "sfa 17:0": .sfa17_0, "sfa 18:0": .sfa18_0,
        "sfa 20:0": .sfa20_0, "sfa 22:0": .sfa22_0, "sfa 24:0": .sfa24_0,

        // Specific MUFAs
        "mufa 14:1": .mufa14_1, "mufa 15:1": .mufa15_1, "mufa 16:1": .mufa16_1,
        "mufa 17:1": .mufa17_1, "mufa 18:1": .mufa18_1, "oleic": .mufa18_1,
        "mufa 20:1": .mufa20_1, "mufa 22:1": .mufa22_1, "mufa 24:1": .mufa24_1,
        "fatty acids, total trans-monoenoic": .transMonoenoic,

        // Specific PUFAs
        "pufa 18:2": .pufa18_2, "linoleic": .pufa18_2,
        "pufa 18:3": .pufa18_3, "linolenic": .pufa18_3, "ala": .pufa18_3,
        "pufa 18:4": .pufa18_4,
        "pufa 20:2": .pufa20_2, "pufa 20:3": .pufa20_3, "pufa 20:4": .pufa20_4, "arachidonic": .pufa20_4,
        "pufa 20:5": .pufa20_5, "epa": .pufa20_5,
        "pufa 21:5": .pufa21_5,
        "pufa 22:4": .pufa22_4, "pufa 22:5": .pufa22_5, "dpa": .pufa22_5,
        "pufa 22:6": .pufa22_6, "dha": .pufa22_6,
        "pufa 2:4": .pufa2_4,
        "fatty acids, total trans-polyenoic": .transPolyenoic,

        // Specific Trans Fats
        "tfa 16:1 t": .tfa16_1, "tfa 18:1 t": .tfa18_1,
        "tfa 18:2 t": .tfa18_2, "tfa 22:1 t": .tfa22_1,

        // --- Amino Acids ---
        "alanine": .alanine, "arginine": .arginine, "aspartic acid": .asparticAcid,
        "cystine": .cystine, "glutamic acid": .glutamicAcid, "glycine": .glycine,
        "histidine": .histidine, "hydroxyproline": .hydroxyproline,
        "isoleucine": .isoleucine, "leucine": .leucine, "lysine": .lysine,
        "methionine": .methionine, "phenylalanine": .phenylalanine, "proline": .proline,
        "serine": .serine, "threonine": .threonine, "tryptophan": .tryptophan,
        "tyrosine": .tyrosine, "valine": .valine,

        // --- Other ---
        "caffeine": .caffeine, "theobromine": .theobromine
    ]

    lazy var normalizedNutrientMap: [String: NutrientType] = {
        var map: [String: NutrientType] = [:]

        for (key, nutrient) in self.nutrientMap {
            // Base normalized form of the original key
            let base = self.normalizeNutrientKey(key)
            map[base] = nutrient

            // Underscored form of multi-word keys (e.g. "vitamin c" -> "vitamin_c")
            let underscored = key.replacingOccurrences(of: " ", with: "_")
            map[self.normalizeNutrientKey(underscored)] = nutrient

            // Condensed form without spaces (e.g. "pufa 18:2" -> "pufa18:2")
            let condensed = key.replacingOccurrences(of: " ", with: "")
            map[self.normalizeNutrientKey(condensed)] = nutrient
        }

        return map
    }()


    // MARK: - Diets (mapped to DietType enum)

    let dietMap: [String: DietType] = [
        "vegan": .vegan,
        "vegetarian": .vegetarian,
        "veg": .vegetarian,

        "keto": .keto,
        "ketogenic": .keto,

        "paleo": .paleo,

        "gluten free": .glutenFree,
        "gf": .glutenFree,
        "gluten-free": .glutenFree,

        "dairy free": .dairyFree,
        "df": .dairyFree,
        "dairy-free": .dairyFree,

        "lactose free": .lactoseFree,
        "lactose-free": .lactoseFree,

        "halal": .halal,
        "kosher": .kosher,

        "low carb": .lowCarb,
        "low-carb": .lowCarb,

        "low fat": .lowFat,
        "low-fat": .lowFat,

        "low sodium": .lowSodium,
        "low-sodium": .lowSodium,

        "high protein": .highProtein,
        "high-protein": .highProtein,

        "nut free": .nutFree,
        "nut-free": .nutFree,

        "egg free": .eggFree,
        "egg-free": .eggFree,

        "soy free": .soyFree,
        "soy-free": .soyFree,

        "fat free": .fatFree,
        "fat-free": .fatFree,

        "no added sugar": .noAddedSugar,

        "mineral rich": .mineralRich,
        "mineral-rich": .mineralRich,

        "vitamin rich": .vitaminRich,
        "vitamin-rich": .vitaminRich,

        "pescatarian": .pescatarian
    ]

    let dietSynonyms: [String: String] = [
        "plant based": "Vegan",
        "no animal products": "Vegan",
        "veggie": "Vegetarian",
        "whole30": "Paleo",
        "no gluten": "Gluten-Free",
        "no dairy": "Dairy-Free",
        "no nuts": "Nut-Free",
        "zero fat": "Fat-Free"
    ]

    // Used when a word is an ingredient that implies a diet flag
    let ingredientToDietMap: [String: String] = [
        "milk": "Dairy-Free", "cream": "Dairy-Free", "cheese": "Dairy-Free", "lactose": "Lactose-Free",
        "cow milk": "Dairy-Free", "yoghurt": "Dairy-Free", "yogurt": "Dairy-Free",

        "egg": "Egg-Free", "eggs": "Egg-Free",

        "nut": "Nut-Free", "nuts": "Nut-Free",
        "peanut": "Nut-Free", "peanuts": "Nut-Free",
        "almond": "Nut-Free", "cashew": "Nut-Free", "walnut": "Nut-Free",

        "soy": "Soy-Free", "soya": "Soy-Free", "tofu": "Soy-Free",

        "gluten": "Gluten-Free", "wheat": "Gluten-Free", "bread": "Gluten-Free",
        "pasta": "Gluten-Free", "flour": "Gluten-Free", "barley": "Gluten-Free", "rye": "Gluten-Free",

        "sugar": "No Added Sugar", "added sugar": "No Added Sugar",

        "meat": "Vegetarian", "animal": "Vegan", "beef": "Vegetarian",
        "pork": "Vegetarian", "chicken": "Vegetarian",

        "salt": "Low Sodium", "sodium": "Low Sodium"
    ]

    // MARK: - PH Logic

    enum PhType { case acidic, alkaline, neutral }

    let phKeywords: Set<String> = [
        "ph", "p.h.", "acid", "acidity", "alkaline", "alkalinity", "base", "basic"
    ]

    let phTerms: [String: PhType] = [
        "acid": .acidic, "acidic": .acidic, "sour": .acidic,
        "alkaline": .alkaline, "basic": .alkaline, "alkalizing": .alkaline,
        "neutral": .neutral, "balanced": .neutral,
        "normal": .neutral
    ]

    // Normalizes phrases into tokens so PH logic works consistently.
    let phPhraseMap: [(pattern: String, token: String)] = [
        ("neutral ph", "_ph_neutral_"),
        ("balanced ph", "_ph_neutral_"),
        ("ph 7", "_ph_neutral_"),

        ("low ph", "_ph_acidic_"),
        ("high acidity", "_ph_acidic_"),
        ("high acid", "_ph_acidic_"),
        ("most acidic", "_ph_acidic_"),

        ("high ph", "_ph_alkaline_"),
        ("low acidity", "_ph_alkaline_"),
        ("low acid", "_ph_alkaline_"),
        ("no acid", "_ph_alkaline_"),
        ("least acidic", "_ph_alkaline_"),

        ("high alkalinity", "_ph_alkaline_"),
        ("most alkaline", "_ph_alkaline_"),

        ("low alkalinity", "_ph_acidic_"),
        ("least alkaline", "_ph_acidic_"),

        // Additional comparative variants
        ("more acidic", "_ph_acidic_"),
        ("less acidic", "_ph_alkaline_"),
        ("more alkaline", "_ph_alkaline_"),
        ("less alkaline", "_ph_acidic_"),

        ("alkaline food", "_ph_alkaline_"),
        ("acidic food", "_ph_acidic_"),

        // Phrase Normalization (Cleaning up "Ph Levels" -> "Ph")
        ("ph levels", "ph"),
        ("ph level", "ph"),
        ("ph value", "ph"),
        ("ph values", "ph"),
        ("ph scale", "ph"),

        ("acidity levels", "acidity"),
        ("acidity level", "acidity"),

        ("alkalinity levels", "alkalinity"),
        ("alkalinity level", "alkalinity")
    ]

    // MARK: - Operators

    let strictOperatorMap: [(pattern: String, token: String)] = [
        ("<=", "_op_lte_"), (">=", "_op_gte_"), ("!=", "_op_neq_"),
        ("<", "_op_lt_"), (">", "_op_gt_"), ("=", "_op_eq_")
    ]

    let operatorPhraseMap: [(pattern: String, token: String)] = [
        ("less than or equal to", "_op_lte_"),
        ("no more than", "_op_lte_"),
        ("at most", "_op_lte_"),
        ("max", "_op_lte_"),
        ("maximum", "_op_lte_"),
        ("limit", "_op_lte_"),

        ("greater than or equal to", "_op_gte_"),
        ("at least", "_op_gte_"),
        ("min", "_op_gte_"),
        ("minimum", "_op_gte_"),

        ("less than", "_op_lt_"),
        ("lower than", "_op_lt_"),
        ("under", "_op_lt_"),
        ("below", "_op_lt_"),

        ("greater than", "_op_gt_"),
        ("more than", "_op_gt_"),
        ("over", "_op_gt_"),
        ("above", "_op_gt_"),

        ("equal to", "_op_eq_"),
        ("not equal", "_op_neq_")
    ]

    let comparativeAdjectives: [String: String] = [
        "less": "_op_lt_",
        "lower": "_op_lt_",
        "low": "_op_lt_",
        "small": "_op_lt_",

        "greater": "_op_gt_",
        "great": "_op_gt_",
        "more": "_op_gt_",
        "high": "_op_gt_",

        "equal": "_op_eq_",
        "not": "_op_neq_"
    ]

    let operatorConnectors: Set<String> = ["between", "from", "to", "range"]

    lazy var allOperatorKeywords: Set<String> = {
        var keys = Set(comparativeAdjectives.keys)
        for (pattern, _) in operatorPhraseMap {
            let words = pattern.components(separatedBy: " ")
            for w in words { keys.insert(w) }
        }
        keys.formUnion(operatorConnectors)
        return keys
    }()

    // MARK: - Age & Allergens

    let personaAgeMap: [String: Double] = [
        "newborn": 0.0,
        "baby": 6.0,
        "infant": 6.0,
        "toddler": 12.0,
        "kid": 24.0,
        "child": 24.0
    ]

    // Generic allergen *types* used by the search engine
    let allergenMap: [String: Allergen] = [
        // Celery
        "celery": .celery,

        // Cereals containing gluten
        "gluten": .cerealsContainingGluten,
        "wheat": .cerealsContainingGluten,
        "barley": .cerealsContainingGlutenBarley,
        "oats": .cerealsContainingGlutenOats,
        "rye": .cerealsContainingGlutenRye,
        "cereal": .cerealsContainingGluten,
        "cereals": .cerealsContainingGluten,

        // Crustaceans / shellfish
        "crustacean": .crustaceans,
        "crustaceans": .crustaceans,
        "shellfish": .crustaceans,

        // Eggs
        "egg": .eggs,
        "eggs": .eggs,

        // Fish
        "fish": .fish,

        // Milk / dairy
        "milk": .milk,
        "dairy": .milk,
        "cheese": .milk,
        "lactose": .milk,

        // Molluscs
        "mollusc": .molluscs,
        "molluscs": .molluscs,

        // Mustard
        "mustard": .mustard,

        // Nuts (parent)
        "nut": .nuts,
        "nuts": .nuts,

        // Specific nuts
        "brazil nut": .nutsBrazilNuts,
        "brazil nuts": .nutsBrazilNuts,
        "almond": .nutsAlmonds,
        "almonds": .nutsAlmonds,
        "cashew": .nutsCashews,
        "cashews": .nutsCashews,
        "chestnut": .nutsChestnuts,
        "chestnuts": .nutsChestnuts,
        "coconut": .nutsCoconut,
        "hazelnut": .nutsHazelnuts,
        "hazelnuts": .nutsHazelnuts,
        "macadamia": .nutsMacadamiaNuts,
        "macadamia nut": .nutsMacadamiaNuts,
        "macadamia nuts": .nutsMacadamiaNuts,
        "pecan": .nutsPecans,
        "pecans": .nutsPecans,
        "pine nut": .nutsPineNuts,
        "pine nuts": .nutsPineNuts,
        "pistachio": .nutsPistachioNuts,
        "pistachios": .nutsPistachioNuts,
        "walnut": .nutsWalnuts,
        "walnuts": .nutsWalnuts,

        // Peanuts
        "peanut": .peanuts,
        "peanuts": .peanuts,

        // Sesame
        "sesame": .sesameSeeds,
        "sesame seed": .sesameSeeds,
        "sesame seeds": .sesameSeeds,

        // Soy
        "soy": .soybeans,
        "soya": .soybeans,
        "soybean": .soybeans,
        "soybeans": .soybeans,

        // Sulphites
        "sulphite": .sulphurDioxideSulphites,
        "sulphites": .sulphurDioxideSulphites,
        "sulfur dioxide": .sulphurDioxideSulphites,
        "sulphur dioxide": .sulphurDioxideSulphites
    ]

    let stemmingExceptions: [String: String] = [
        "fries": "fry",
        "berries": "berry",
        "tomatoes": "tomato"
    ]

    var synonyms: [String: String] = [:]

    func loadSynonymsFromBundle() {
        guard let url = Bundle.main.url(forResource: "food_synonyms", withExtension: "json") else { return }
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.synonyms = loaded
        }
    }

    // MARK: - SYSTEM KEYWORD PREFIX CHECK

    lazy var allSystemKeywords: Set<String> = {
        var keys = Set<String>()
//        keys.formUnion(nutrientMap.keys)
        keys.formUnion(dietSynonyms.keys)
        keys.formUnion(dietMap.keys)
        keys.formUnion(ingredientToDietMap.keys)
        keys.formUnion(allergenMap.keys)
        keys.formUnion(phKeywords)
        keys.formUnion(phTerms.keys)
        keys.formUnion(negationTerms)
        keys.formUnion(allOperatorKeywords)
        return keys
    }()

    func isSystemKeywordPrefix(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.count < 2 { return false }
        return allSystemKeywords.contains { $0.hasPrefix(lower) }
    }

    func allergenKeywords(for type: Allergen) -> [String] {
        switch type {
        case .celery:
            return ["celery"]

        case .cerealsContainingGluten:
            return ["gluten", "wheat", "barley", "rye", "oats"]
        case .cerealsContainingGlutenBarley:
            return ["barley"]
        case .cerealsContainingGlutenOats:
            return ["oats"]
        case .cerealsContainingGlutenRye:
            return ["rye"]

        case .crustaceans:
            return ["crustacean", "crustaceans", "shellfish", "shrimp", "prawn", "crab", "lobster"]

        case .eggs:
            return ["egg", "eggs"]

        case .fish:
            return ["fish"]

        case .lowSodium:
            return ["low sodium", "low-sodium", "reduced sodium"]

        case .milk:
            return ["milk", "dairy", "cheese", "lactose", "cream", "yogurt", "yoghurt"]

        case .molluscs:
            return ["mollusc", "molluscs", "mussels", "oyster", "oysters", "clam", "clams", "scallops"]

        case .mustard:
            return ["mustard"]

        case .nuts:
            return ["nut", "nuts"]
        case .nutsBrazilNuts:
            return ["brazil nut", "brazil nuts"]
        case .nutsAlmonds:
            return ["almond", "almonds"]
        case .nutsCashews:
            return ["cashew", "cashews"]
        case .nutsChestnuts:
            return ["chestnut", "chestnuts"]
        case .nutsCoconut:
            return ["coconut"]
        case .nutsHazelnuts:
            return ["hazelnut", "hazelnuts"]
        case .nutsMacadamiaNuts:
            return ["macadamia", "macadamia nut", "macadamia nuts"]
        case .nutsPecans:
            return ["pecan", "pecans"]
        case .nutsPineNuts:
            return ["pine nut", "pine nuts"]
        case .nutsPistachioNuts:
            return ["pistachio", "pistachios"]
        case .nutsWalnuts:
            return ["walnut", "walnuts"]

        case .peanuts:
            return ["peanut", "peanuts"]

        case .sesameSeeds:
            return ["sesame", "sesame seed", "sesame seeds"]

        case .soybeans:
            return ["soy", "soya", "soybean", "soybeans"]

        case .sulphurDioxideSulphites:
            return ["sulphite", "sulphites", "sulfur dioxide", "sulphur dioxide"]
        }
    }
    
    /// Maps a free-text ingredient (e.g. "milk", "cheese", "walnut") to an Allergen, if possible.
    func allergenForIngredient(_ raw: String) -> Allergen? {
        let key = normalizeKey(raw)

        // First try the alias map built from allergenKeywords(for:)
        if let fromAlias = allergenAliasMap[key] {
            return fromAlias
        }

        // Fallback: direct allergenMap (base terms like "milk", "peanut", etc.)
        if let fromBase = allergenMap[key] {
            return fromBase
        }

        return nil
    }

    /// Normalizes nutrient-like strings so that different spellings map together.
    /// Examples:
    ///   "Vitamin C"      -> "vitamin c"
    ///   "pufa 18:2"      -> "pufa 18 2"
    ///   "pufa18_2"       -> "pufa 18 2"
    ///   " PUFA-18:2 "    -> "pufa 18 2"
    static func normalizeNutrientString(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }

        // Lowercase first
        let lower = raw.lowercased()

        // Characters that we treat as separators between tokens
        let separatorScalars = CharacterSet(charactersIn: "._/:,-")

        var buffer = ""
        var prevWasLetter = false
        var prevWasDigit  = false

        for scalar in lower.unicodeScalars {
            let ch = Character(scalar)

            // Treat whitespace or separators as a single space
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || separatorScalars.contains(scalar) {
                if buffer.last != " " {
                    buffer.append(" ")
                }
                prevWasLetter = false
                prevWasDigit  = false
                continue
            }

            let isLetter = ch.isLetter
            let isDigit  = ch.isNumber

            // Insert space between letter → digit or digit → letter
            if (isLetter && prevWasDigit) || (isDigit && prevWasLetter) {
                if buffer.last != " " {
                    buffer.append(" ")
                }
            }

            buffer.append(ch)
            prevWasLetter = isLetter
            prevWasDigit  = isDigit
        }

        // Collapse multiple spaces to a single space and trim
        let pieces = buffer.split(whereSeparator: { $0.isWhitespace })
        return pieces.joined(separator: " ")
    }

    /// Best-effort mapping from an arbitrary phrase (e.g. "beef vitamin c")
    /// to a NutrientType using `nutrientMap`.
    ///
    /// It:
    ///  1. Normalizes the entire phrase.
    ///  2. Normalizes all nutrientMap keys.
    ///  3. Picks the **longest key** that appears as a sequence of whole tokens.
    func bestNutrientMatch(in phrase: String) -> NutrientType? {
        let normalizedPhrase = Self.normalizeNutrientString(phrase)
        guard !normalizedPhrase.isEmpty else { return nil }

        // Split phrase into tokens
        let phraseTokens = normalizedPhrase
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        // Build a normalized nutrient map on the fly (few hundred keys → cheap).
        var normalizedMap: [String: NutrientType] = [:]
        for (key, nutrient) in nutrientMap {
            let nk = Self.normalizeNutrientString(key)
            normalizedMap[nk] = nutrient
        }

        // Helper: does phraseTokens contain keyTokens as a contiguous subsequence?
        func phraseContainsKeyTokens(_ key: String) -> Bool {
            let keyTokens = key.split(separator: " ").map(String.init)
            guard !keyTokens.isEmpty, keyTokens.count <= phraseTokens.count else { return false }

            // Single-word key – require exact token match
            if keyTokens.count == 1 {
                return phraseTokens.contains { $0 == keyTokens[0] }
            }

            // Multi-word key – require contiguous token sequence
            outer: for start in 0...(phraseTokens.count - keyTokens.count) {
                for offset in 0..<keyTokens.count {
                    if phraseTokens[start + offset] != keyTokens[offset] {
                        continue outer
                    }
                }
                return true
            }

            return false
        }

        // 1) Exact normalized match first
        if let exact = normalizedMap[normalizedPhrase] {
            return exact
        }

        // 2) Otherwise choose the *longest* key that appears as whole tokens.
        var bestKey: String?
        var bestNutrient: NutrientType?

        for (key, nutrient) in normalizedMap {
            if phraseContainsKeyTokens(key) {
                if let currentBest = bestKey {
                    if key.count > currentBest.count {
                        bestKey = key
                        bestNutrient = nutrient
                    }
                } else {
                    bestKey = key
                    bestNutrient = nutrient
                }
            }
        }

        return bestNutrient
    }
    
    /// High-level classification of a parsed subject: can be a nutrient, diet,
    /// allergen, pH concept, or unknown.
    enum SubjectType {
        case nutrient(NutrientType)
        case diet(String)
        case allergen(Allergen)
        case ph
        case unknown
    }

    /// Returns true if the given raw subject string can be interpreted as a
    /// known nutrient, diet, allergen, or pH-related term.
    func isValidSubject(_ raw: String) -> Bool {
        let key = normalizeKey(raw)

        // 1. Nutrients
        if bestNutrientMatch(in: key) != nil {
            return true
        }

        // 2. Diets (both direct map and synonyms)
        if dietMap[key] != nil {
            return true
        }
        if dietSynonyms[key] != nil {
            return true
        }

        // 3. Allergens (direct map and alias map)
        if allergenMap[key] != nil {
            return true
        }
        if allergenAliasMap[key] != nil {
            return true
        }

        // 4. pH-related terms
        if phKeywords.contains(key) { return true }
        if phTerms.keys.contains(key) { return true }

        return false
    }

    /// Provides a more precise classification of the subject, including the
    /// concrete NutrientType, Diet name, or Allergen where applicable.
    func getSubjectType(_ raw: String) -> SubjectType {
        let key = normalizeKey(raw)

        // 1. pH-related subjects ("ph", "acid", "alkaline", etc.)
        if phKeywords.contains(key) || phTerms.keys.contains(key) {
            return .ph
        }

        // 2. Nutrients (best-effort fuzzy matching over nutrientMap keys)
        if let nutrient = bestNutrientMatch(in: key) {
            return .nutrient(nutrient)
        }

        // 3. Diets
        if let dietType = dietMap[key] {
            // Use the DietType's rawValue as the canonical diet name string
            return .diet(dietType.rawValue)
        }
        if let dietName = dietSynonyms[key] {
            return .diet(dietName)
        }

        // 4. Allergens
        if let allergen = allergenMap[key] {
            return .allergen(allergen)
        }
        if let allergen = allergenAliasMap[key] {
            return .allergen(allergen)
        }

        return .unknown
    }

    /// Optional helper to map a subject to a nutrient ID string, if needed by
    /// other layers (e.g. NutrientIndex). For pH we return "ph".
    func getNutrientID(_ raw: String) -> String? {
        switch getSubjectType(raw) {
        case .nutrient(let nutrient):
            return nutrient.rawValue
        case .ph:
            return "ph"
        default:
            return nil
        }
    }
}
