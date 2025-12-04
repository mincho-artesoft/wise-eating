struct CompactFoodItem: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let searchTokens: Set<String>
    let minAgeMonths: Int
    let diets: Set<String>
    let allergens: Set<String>
    let ph: Double
    let referenceWeightG: Double
    let isRecipe: Bool
    let isMenu: Bool
    let isFavorite: Bool
    // Store nutrients as a raw dictionary for scoring
    let nutrientValues: [NutrientType: Double]
    
    // Helper for the search logic to access values
    func value(for type: NutrientType) -> Double {
        return nutrientValues[type] ?? 0.0
    }
    
    // Helpers for logic compatibility
    var lowercasedName: String { name.lowercased() }
    var paddedLowercasedName: String { " " + lowercasedName + " " }
    
    func fits(dietName: String) -> Bool {
        diets.contains { $0.localizedCaseInsensitiveContains(dietName) }
    }
    
    func contains(allergen: String) -> Bool {
        allergens.contains { $0.localizedCaseInsensitiveContains(allergen) }
    }
}
