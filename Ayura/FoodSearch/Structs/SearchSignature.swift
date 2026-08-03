import Foundation

// MARK: - Search Intent Models

struct SearchSignature: Equatable {
    let effectiveTokens: [String]
    let nutrientGoals: [NutrientGoal]
    let displayNutrients: [NutrientType]
    let negativeTokens: Set<String>
    let age: Double?
    let allergens: Set<Allergen>
    let excludeAllAllergens: Bool
    let ph: ConstraintValue?
    let ayurvedaFacetConstraints: [AyurvedaFacetConstraint]
    
    init(effectiveTokens: [String], intent: SearchIntent) {
        self.effectiveTokens = effectiveTokens
        self.nutrientGoals = intent.nutrientGoals
        self.displayNutrients = intent.displayNutrients
        self.negativeTokens = intent.negativeTokens
        self.age = intent.targetConsumerAge
        self.allergens = intent.allergenExclusions
        self.excludeAllAllergens = intent.excludeAllAllergens
        self.ph = intent.phConstraint
        self.ayurvedaFacetConstraints = intent.ayurvedaFacetConstraints
    }
}
