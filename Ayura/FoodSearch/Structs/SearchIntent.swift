struct SearchIntent {
    let textTokens: Set<String>
    let negativeTokens: Set<String>
    let nutrientGoals: [NutrientGoal]
    let displayNutrients: [NutrientType]
    let targetConsumerAge: Double?
    let allergenExclusions: Set<Allergen>   // or AllergenType in the demo
    let excludeAllAllergens: Bool
    let phConstraint: ConstraintValue?
    let ayurvedaFacetConstraints: [AyurvedaFacetConstraint]
}
