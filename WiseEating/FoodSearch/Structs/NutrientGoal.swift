struct NutrientGoal: Hashable, Sendable {
    let nutrient: NutrientType
    let constraint: ConstraintValue
}
