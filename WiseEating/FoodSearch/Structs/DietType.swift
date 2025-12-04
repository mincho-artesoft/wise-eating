enum DietType: String, CaseIterable, Sendable {
    case vegan = "Vegan"
    case vegetarian = "Vegetarian"
    case pescatarian = "Pescatarian"
    case glutenFree = "Gluten-Free"
    case dairyFree = "Dairy-Free"
    case lactoseFree = "Lactose-Free"
    case eggFree = "Egg-Free"
    case nutFree = "Nut-Free"
    case soyFree = "Soy-Free"
    case halal = "Halal"
    case kosher = "Kosher"
    case highProtein = "High-Protein"
    case keto = "Keto"
    case paleo = "Paleo"
    case lowCarb = "Low-Carb"
    case lowFat = "Low-Fat"
    case lowSodium = "Low Sodium"
    case noAddedSugar = "No Added Sugar"
    case mineralRich = "Mineral-Rich"
    case vitaminRich = "Vitamin-Rich"
    case fatFree = "Fat-Free"

    static func from(string: String) -> DietType? {
        DietType(rawValue: string)
    }
}
