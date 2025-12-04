struct SearchIntent {
    let textTokens: Set<String>
    let negativeTokens: Set<String>
    let nutrientGoals: [NutrientGoal]
    let diets: Set<String>
    let dietFilter: DietType?
    let excludedDiets: Set<String>   // ⬅️ NEW
    let targetConsumerAge: Double?
    let allergenExclusions: Set<Allergen>   // or AllergenType in the demo
    let excludeAllAllergens: Bool
    let phConstraint: ConstraintValue?
}
