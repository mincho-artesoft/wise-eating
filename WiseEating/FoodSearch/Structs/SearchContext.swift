struct SearchContext {
    var displayNutrients: [NutrientType] = []
    var activeDiet: DietType?
    var activeConstraint: String?
    var activeAgeLimit: String?
    var isPhActive: Bool = false
}

extension NutrientGoal {
    var searchContextDescription: String {
        let value: String
        switch constraint {
        case .high:
            value = "high"
        case .low:
            value = "low"
        case .min(let minimum):
            value = "≥ \(minimum)"
        case .max(let maximum):
            value = "≤ \(maximum)"
        case .strictMin(let minimum):
            value = "> \(minimum)"
        case .strictMax(let maximum):
            value = "< \(maximum)"
        case .range(let lower, let upper):
            value = "\(lower)…\(upper)"
        case .notEqual(let excluded):
            value = "≠ \(excluded)"
        case .lowest:
            value = "lowest"
        case .highest:
            value = "highest"
        }
        return "\(nutrient.rawValue): \(value)"
    }
}
