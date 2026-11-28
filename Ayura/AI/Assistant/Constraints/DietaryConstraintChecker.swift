import Foundation

/// One food with an amount, as the checker sees it: nutrients per 100 g in the
/// catalogue's canonical units, and the allergen names the catalogue stores.
struct CheckedFood: Equatable, Sendable {
    var name: String
    var grams: Double
    var meal: String
    var per100g: [NutrientType: Double]
    var allergens: Set<String>

    func amount(of nutrient: NutrientType) -> Double {
        (per100g[nutrient] ?? 0) * grams / 100
    }
}

struct ConstraintViolation: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case allergen(food: String, allergen: String)
        case excludedFood(food: String, term: String)
        case overLimit(nutrient: NutrientType, total: Double, limit: Double, unit: String, meal: String?)
        case underTarget(nutrient: NutrientType, total: Double, target: Double, unit: String)
    }

    let kind: Kind

    var id: String { "\(kind)" }

    /// Allergens and excluded foods block; limits ask for a second confirmation.
    var isBlocking: Bool {
        switch kind {
        case .allergen, .excludedFood: true
        case .overLimit, .underTarget: false
        }
    }

    var message: String {
        switch kind {
        case let .allergen(food, allergen):
            return String(localized: "\(food) contains \(allergen), which is in your allergies.")
        case let .excludedFood(food, term):
            return String(localized: "\(food) matches \"\(term)\", which you asked to avoid.")
        case let .overLimit(nutrient, total, limit, unit, meal):
            let name = DietaryNutrientNames.displayName(nutrient)
            if let meal {
                return String(localized: "\(meal) has \(DietaryUnits.format(total)) \(unit) of \(name); your limit is \(DietaryUnits.format(limit)) \(unit) per meal.")
            }
            return String(localized: "This day has \(DietaryUnits.format(total)) \(unit) of \(name); your limit is \(DietaryUnits.format(limit)) \(unit) a day.")
        case let .underTarget(nutrient, total, target, unit):
            let name = DietaryNutrientNames.displayName(nutrient)
            return String(localized: "This day has \(DietaryUnits.format(total)) \(unit) of \(name); your target is at least \(DietaryUnits.format(target)) \(unit).")
        }
    }
}

struct ConstraintReport: Equatable, Sendable {
    var totals: [NutrientType: Double]
    var violations: [ConstraintViolation]

    var isBlocked: Bool { violations.contains(where: \.isBlocking) }
    var needsSecondConfirmation: Bool { !violations.isEmpty && !isBlocked }
}

/// The model proposes; this checks. Pure and deterministic, no model involved.
enum DietaryConstraintChecker {
    /// - Parameters:
    ///   - foods: everything the day will contain if the proposal is applied.
    ///   - isCompleteDay: minimum targets are only checked for a complete
    ///     plan, not while a day is still being logged.
    static func check(
        foods: [CheckedFood],
        constraints: [DietaryConstraint],
        allergens: [Allergen],
        isCompleteDay: Bool
    ) -> ConstraintReport {
        var violations: [ConstraintViolation] = []

        let expanded = Allergen.expanded(from: Set(allergens))
        for food in foods {
            for allergen in expanded.sorted(by: { $0.rawValue < $1.rawValue })
            where food.allergens.contains(where: { $0.localizedCaseInsensitiveContains(allergen.rawValue) }) {
                violations.append(.init(kind: .allergen(food: food.name, allergen: allergen.displayName)))
                break
            }
        }

        for rule in constraints where rule.kind == .excludeFood {
            guard let term = rule.foodTerm else { continue }
            for food in foods where matches(foodName: food.name, term: term) {
                violations.append(.init(kind: .excludedFood(food: food.name, term: term)))
            }
        }

        var totals: [NutrientType: Double] = [:]
        for food in foods {
            for (nutrient, _) in food.per100g {
                totals[nutrient, default: 0] += food.amount(of: nutrient)
            }
        }

        for rule in constraints where rule.isNutrientRule {
            guard let nutrient = rule.nutrientType,
                  let limit = rule.amountInCanonicalUnit else { continue }
            let canonical = FoodItem.canonicalUnit(for: nutrient)
            let shown = rule.unit ?? canonical
            let toShown: (Double) -> Double = {
                DietaryUnits.convert($0, from: canonical, to: shown) ?? $0
            }
            switch (rule.kind, rule.period) {
            case (.nutrientMax, .day):
                let total = totals[nutrient] ?? 0
                if total > limit + 0.000_1 {
                    violations.append(.init(kind: .overLimit(
                        nutrient: nutrient, total: toShown(total), limit: rule.amount ?? 0, unit: shown, meal: nil)))
                }
            case (.nutrientMax, .meal):
                let byMeal = Dictionary(grouping: foods, by: \.meal)
                for meal in byMeal.keys.sorted() {
                    let total = byMeal[meal, default: []].reduce(0) { $0 + $1.amount(of: nutrient) }
                    if total > limit + 0.000_1 {
                        violations.append(.init(kind: .overLimit(
                            nutrient: nutrient, total: toShown(total), limit: rule.amount ?? 0, unit: shown, meal: meal)))
                    }
                }
            case (.nutrientMin, _):
                let total = totals[nutrient] ?? 0
                if isCompleteDay, total + 0.000_1 < limit {
                    violations.append(.init(kind: .underTarget(
                        nutrient: nutrient, total: toShown(total), target: rule.amount ?? 0, unit: shown)))
                }
            default:
                break
            }
        }

        return ConstraintReport(totals: totals, violations: violations)
    }

    /// Whole-word match with simple English plurals: "tomato" matches
    /// "Tomatoes, red, ripe" and "Soup, tomato", not "Tomatillos".
    static func matches(foodName: String, term: String) -> Bool {
        let words = foodName.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .map(singular)
        let termWords = term.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .map(singular)
        guard !termWords.isEmpty else { return false }
        if termWords.count == 1 { return words.contains(termWords[0]) }
        // A phrase must appear in order.
        guard words.count >= termWords.count else { return false }
        for start in 0...(words.count - termWords.count)
        where Array(words[start..<start + termWords.count]) == termWords {
            return true
        }
        return false
    }

    private static func singular(_ word: String) -> String {
        if word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("sses") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 { return String(word.dropLast()) }
        return word
    }
}
