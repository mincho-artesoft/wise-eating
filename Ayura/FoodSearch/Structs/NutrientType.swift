enum NutrientType: String, CaseIterable, Sendable {
    // Macros
    case energy, protein, carbs, totalSugar, fiber, totalFat, water, alcohol, ash, starch
    
    // Minerals
    case calcium, iron, magnesium, phosphorus, potassium, sodium, zinc, copper, manganese, selenium, fluoride
    
    // Vitamins
    case vitaminC, vitaminB6, vitaminB12
    case vitaminA, retinol, betaCarotene, alphaCarotene, betaCryptoxanthin
    case vitaminE, vitaminD, vitaminK
    case thiamin, riboflavin, niacin, pantothenicAcid, folateTotal, folateFood, folateDFE, folicAcid
    case choline, betaine
    
    // Fats - General
    case saturatedFat, monounsaturatedFat, polyunsaturatedFat, transFat, cholesterol, phytosterols
    
    // Fats - Specific Sterols
    case betaSitosterol, campesterol, stigmasterol
    
    // Fats - Specific Fatty Acids (SFA)
    case sfa4_0, sfa6_0, sfa8_0, sfa10_0, sfa12_0, sfa13_0, sfa14_0, sfa15_0, sfa16_0, sfa17_0, sfa18_0, sfa20_0, sfa22_0, sfa24_0
    
    // Fats - Specific Fatty Acids (MUFA)
    case mufa14_1, mufa15_1, mufa16_1, mufa17_1, mufa18_1, mufa20_1, mufa22_1, mufa24_1
    case transMonoenoic // "Fatty acids, total trans-monoenoic"
    
    // Fats - Specific Fatty Acids (PUFA)
    case pufa18_2, pufa18_3, pufa18_4
    case pufa20_2, pufa20_3, pufa20_4, pufa20_5 // EPA
    case pufa21_5
    case pufa22_4, pufa22_5, pufa22_6 // DHA
    case pufa2_4
    case transPolyenoic // "Fatty acids, total trans-polyenoic"
    
    // Specific Trans Fats
    case tfa16_1, tfa18_1, tfa18_2, tfa22_1
    
    // Amino Acids
    case alanine, arginine, asparticAcid, cystine, glutamicAcid, glycine, histidine, isoleucine, leucine, lysine, methionine, phenylalanine, proline, serine, threonine, tryptophan, tyrosine, valine, hydroxyproline
    
    // Other / Phytonutrients
    case caffeine, theobromine, lycopene, luteinZeaxanthin
    
    // Sugars Specific (CSV contains Glucose, Fructose etc)
    case glucose, fructose, galactose, lactose, maltose, sucrose

    static func fromID(_ id: String) -> NutrientType? {
        // 1. Премахваме префикса ("vit_" или "min_"), за да вземем чистото ID
        let raw: String
        if id.hasPrefix("vit_") {
            raw = String(id.dropFirst(4)) // маха "vit_"
        } else if id.hasPrefix("min_") {
            raw = String(id.dropFirst(4)) // маха "min_"
        } else if id.starts(with: "macro_") {
            // За макросите в detail views понякога се ползва този префикс
            raw = String(id.dropFirst(6))
        } else {
            raw = id
        }

        // 2. Първи опит: Директно съвпадение с rawValue на енума.
        // Това работи за повечето минерали (напр. "calcium", "iron") и макроси.
        if let directMatch = NutrientType(rawValue: raw) {
            return directMatch
        }

        // 3. Втори опит: Ръчен мапинг за витамините, където ID-тата се различават.
        switch raw {
        // Основни витамини (Където ID е "vitA", а enum е "vitaminA")
        case "vitA": return .vitaminA
        case "vitC": return .vitaminC
        case "vitD": return .vitaminD
        case "vitE": return .vitaminE
        case "vitK": return .vitaminK
        
        // B-комплекс (Където ID е "vitB1", а enum е "thiamin" и т.н.)
        case "vitB1": return .thiamin
        case "vitB2": return .riboflavin
        case "vitB3": return .niacin
        case "vitB5": return .pantothenicAcid
        case "vitB6": return .vitaminB6
        case "vitB12": return .vitaminB12
            
        // Каротеноиди и други
        case "retinol": return .retinol
        case "caroteneAlpha": return .alphaCarotene
        case "caroteneBeta": return .betaCarotene
        case "cryptoxanthinBeta": return .betaCryptoxanthin
        case "luteinZeaxanthin": return .luteinZeaxanthin
        case "lycopene": return .lycopene
            
        // Фолати
        case "folateDFE": return .folateDFE
        case "folateFood": return .folateFood
        case "folateTotal": return .folateTotal
        case "folicAcid": return .folicAcid
            
        // Други
        case "choline": return .choline
        case "betaine": return .betaine
            
        // Специални макроси (ако се подават нестандартно)
        case "totalFat", "fat": return .totalFat
        case "carbohydrates", "carbs": return .carbs
            
        default:
            print("⚠️ NutrientType.fromID: Could not map ID '\(raw)' to NutrientType case.")
            return nil
        }
    }
}
