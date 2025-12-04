import Foundation

// MARK: - Search Intent Models

struct SearchSignature: Equatable {
    let effectiveTokens: [String]
    let nutrientGoals: [NutrientGoal]
    let negativeTokens: Set<String>
    let diets: Set<String>
    let dietFilter: DietType?
    let age: Double?
    let allergens: Set<Allergen>
    let excludeAllAllergens: Bool
    let ph: ConstraintValue?
    
    init(effectiveTokens: [String], intent: SearchIntent) {
        self.effectiveTokens = effectiveTokens
        self.nutrientGoals = intent.nutrientGoals
        self.negativeTokens = intent.negativeTokens
        self.diets = intent.diets
        self.dietFilter = intent.dietFilter
        self.age = intent.targetConsumerAge
        self.allergens = intent.allergenExclusions
        self.excludeAllAllergens = intent.excludeAllAllergens
        self.ph = intent.phConstraint
    }
}
