import Foundation

/// Result of transforming raw DietaryConstraint entries into
/// the structures used by SmartFoodSearch3 / Tokenizer / SearchIntent.
struct ConstraintMapperResult {
    /// Extra numeric / range goals, one per nutrient.
    var nutrientGoals: [NutrientGoal] = []
    
    /// Optional pH constraint derived from phrases like:
    ///   "low acid", "more alkaline", "ph between 6 and 7", etc.
    var phConstraint: ConstraintValue? = nil
    
    /// Diets that must be present (e.g. "Vegan", "Gluten-Free").
    /// These are raw diet names, same as you store in FoodItem / CompactFoodItem.
    var includeDiets: Set<String> = []
    
    /// Diets that must be absent (e.g. "not vegan", "no keto").
    var excludeDiets: Set<String> = []
    
    /// Allergens that must be present (rare, e.g. "contains peanuts").
    var includeAllergens: Set<Allergen> = []
    
    /// Allergens that must be absent (e.g. "no peanuts", "without gluten").
    var excludeAllergens: Set<Allergen> = []
}

/// Translates DietaryConstraint entries (from the regex + parser layer)
/// into high-level search constraints used by SmartFoodSearch3.
enum ConstraintMapper {
    
    static func map(_ constraints: [DietaryConstraint]) -> ConstraintMapperResult {
        var result = ConstraintMapperResult()
        
        for constraint in constraints {
            let subjectType = SearchKnowledgeBase.shared.getSubjectType(constraint.subject)
            
            switch subjectType {
            case .nutrient(let nutrientType):
                if let cv = constraintValue(for: nutrientType, from: constraint) {
                    result.nutrientGoals.append(
                        NutrientGoal(nutrient: nutrientType, constraint: cv)
                    )
                }
                
            case .ph:
                if let cv = constraintValue(from: constraint) {
                    // If multiple PH constraints appear, last one wins for now.
                    // We can later merge ranges if needed.
                    result.phConstraint = cv
                }
                
            case .diet(let dietName):
                mapDietConstraint(constraint, dietName: dietName, into: &result)
                
            case .allergen(let allergen):
                mapAllergenConstraint(constraint, allergen: allergen, into: &result)
                
            case .unknown:
                // Ignore unknown subjects at this layer.
                break
            }
        }
        
        return result
    }
}

// MARK: - Internal helpers

private extension ConstraintMapper {
    /// Heuristic check whether the original constraint text expresses negation
    /// for the given subject (e.g. "no soy", "without gluten", "sugar free",
    /// "not vegan", "non-dairy"). This is used for nutrients, diets, and
    /// allergens when there is no reliable numeric value.
    static func isNegated(_ c: DietaryConstraint) -> Bool {
        let baseText = c.originalText.isEmpty ? c.subject : c.originalText
        var text = baseText.lowercased()
        text = text.replacingOccurrences(of: "-", with: " ")
        text = text.replacingOccurrences(of: "_", with: " ")
        let subject = c.subject.lowercased()
        let subjectPlural = subject + "s"
        
        // Direct patterns like "no soy", "no soy products"
        if text.contains("no \(subject)") || text.contains("no \(subjectPlural)") {
            return true
        }
        if text.contains("without \(subject)") || text.contains("without \(subjectPlural)") {
            return true
        }
        
        // "X free", "X-free", "free of X", "free from X"
        if text.contains("\(subject) free") || text.contains("\(subjectPlural) free") {
            return true
        }
        if text.contains("\(subject) free") || text.contains("\(subject)  free") {
            return true
        }
        if text.contains("\(subject) free") || text.contains("\(subject)  free") {
            return true
        }
        if text.contains("free of \(subject)") || text.contains("free of \(subjectPlural)") {
            return true
        }
        if text.contains("free from \(subject)") || text.contains("free from \(subjectPlural)") {
            return true
        }
        
        // "not vegan", "not keto", "non dairy", "non-vegan"
        if text.contains("not \(subject)") || text.contains("non \(subject)") || text.contains("non \(subjectPlural)") {
            return true
        }
        if text.contains("non-\(subject)") || text.contains("non-\(subjectPlural)") {
            return true
        }
        
        // Fallback: "no" a bit before the subject (e.g. "no added sugar")
        if let noRange = text.range(of: "no "), let subRange = text.range(of: subject) {
            if subRange.lowerBound > noRange.lowerBound {
                let distance = text.distance(from: noRange.upperBound, to: subRange.lowerBound)
                if distance <= 12 { // allow a couple of words between
                    return true
                }
            }
        }
        
        return false
    }

    /// Maps a DietaryConstraint about a concrete nutrient into a ConstraintValue.
    ///
    /// IMPORTANT DESIGN DECISION:
    /// - This function now handles ONLY *textual* negation like:
    ///       "no sodium", "sugar free", "without gluten"
    ///   and turns them into a small inclusive upper bound (soft zero).
    ///
    /// - All explicit numeric constraints:
    ///       "less than 10 vitamin c", "vitamin c < 10 mg",
    ///       "fat between 5 and 10 g"
    ///   are handled exclusively by SmartFoodSearch3.parseNumericNutrientConstraints().
    ///
    /// This restores the old numeric behaviour while keeping the new
    /// "no sodium" / "sugar free" semantics.
    static func constraintValue(for nutrient: NutrientType, from c: DietaryConstraint) -> ConstraintValue? {
        let negated = isNegated(c)

        // 1) HANDLE MISSING VALUES (Abstract / Dangling comparators)
                if c.value == nil && c.value2 == nil {
                    if negated {
                        return .max(softZeroThreshold(for: nutrient))
                    }

                    switch c.comparison {
                    case .lessThan, .lessThanOrEqual:
                        // If it is Fat, apply the specific 12g limit user requested
                        if nutrient == .totalFat {
                            return .max(12.0) // Filters >12g, and Sorts 0->12
                        }
                        return .low

                    case .greaterThan, .greaterThanOrEqual:
                        // User wants "high/more fat".
                        // This maps to .high, which triggers DESCENDING sort (Max -> 0).
                        return .high
                        
                    case .equal:
                         // "Fat" mentioned alone usually implies "High in Fat" / Importance
                        return .high

                    default:
                        return nil
                    }
                }

        // 2) NUMERIC + NEGATION (e.g. "no sodium", "= 0")
        if negated {
            let v1 = c.value ?? 0.0
            switch c.comparison {
            case .equal, .lessThan, .lessThanOrEqual, .unknown:
                if v1 == 0 {
                    return .max(softZeroThreshold(for: nutrient))
                }
            default:
                break
            }
        }

        // 3) STANDARD NUMERIC (e.g. "10g", "< 5")
        if let v1 = c.value {
            if let v2 = c.value2 {
                return .range(v1, v2)
            }
            switch c.comparison {
            case .lessThan:           return .strictMax(v1)
            case .lessThanOrEqual:    return .max(v1)
            case .greaterThan:        return .strictMin(v1)
            case .greaterThanOrEqual: return .min(v1)
            case .equal:              return .range(v1 - 0.1, v1 + 0.1)
            case .notEqual:           return .notEqual(v1)
            case .unknown:            return .min(v1)
            }
        }

        return nil
    }
    
    /// Heuristic soft upper bound used for phrases like "no sugar", "no sodium",
    /// "sugar free", etc. These values are in the same canonical units used by
    /// your nutrient data (per 100 g):
    ///   - macros (protein, fat, carbs, sugar, fiber...) => grams
    ///   - minerals (including sodium) => milligrams
    ///   - some vitamins => micrograms
    static func softZeroThreshold(for nutrient: NutrientType) -> Double {
        let key = String(describing: nutrient).lowercased()
        
        // Energy-like nutrients
        if key.contains("energy") || key.contains("calorie") {
            // e.g. "no calories" => up to ~5 kcal/100 g
            return 5.0
        }
        
        // Macros: protein, fat, carbs, sugar, fiber, alcohol, water, starch
        let macroTokens = ["protein", "carb", "fat", "fiber", "sugar", "alcohol", "water", "ash", "starch"]
        if macroTokens.contains(where: { key.contains($0) }) {
            // e.g. "no sugar" => up to 0.5 g / 100 g
            return 0.5
        }
        
        // Microgram-scale nutrients (most vitamins, selenium, etc.)
        let microTokens = [
            "vitamina", "retinol", "beta", "alpha", "lutein", "lycopene", "cryptoxanthin",
            "vitamind", "vitamink", "vitaminb12", "folate", "folic", "selenium"
        ]
        if microTokens.contains(where: { key.contains($0) }) {
            // Something small but non-zero in µg.
            return 50.0
        }
        
        // Default for minerals (including sodium) that are typically in mg.
        // e.g. "no sodium", "no potassium" => up to 5 mg / 100 g.
        return 5.0
    }
    
    /// Maps a DietaryConstraint numeric relation to your ConstraintValue model
    /// for non-nutrient subjects (currently pH). Nutrient-specific logic lives
    /// in `constraintValue(for:from:)` so that we can handle phrases such as
    /// "no sodium" or "sugar free" in a more natural way.
    static func constraintValue(from c: DietaryConstraint) -> ConstraintValue? {
        guard let v1 = c.value else {
            // Abstract-only constraints (e.g. "high protein") are usually
            // already handled by Tokenizer into .high / .low. The numeric
            // layer focuses on explicit numbers.
            return nil
        }
        
        if let v2 = c.value2 {
            // Ranges: "between 5 and 10" -> [5, 10]
            return .range(v1, v2)
        }
        
        switch c.comparison {
        case .lessThan:
            return .strictMax(v1)
        case .lessThanOrEqual:
            return .max(v1)
        case .greaterThan:
            return .strictMin(v1)
        case .greaterThanOrEqual:
            return .min(v1)
        case .equal:
            // Slight tolerance for equality, handled as a narrow range.
            return .range(v1 - 0.1, v1 + 0.1)
        case .notEqual:
            return .notEqual(v1)
        case .unknown:
            return nil
        }
    }
    
    static func mapDietConstraint(
        _ c: DietaryConstraint,
        dietName: String,
        into result: inout ConstraintMapperResult
    ) {
        let value = c.value ?? 0.0
        // Textual negation ("no vegan", "not vegan", "non-vegan") takes
        // precedence over any numeric encoding.
        if isNegated(c) {
            result.excludeDiets.insert(dietName)
            return
        }
        switch c.comparison {
        case .greaterThan, .greaterThanOrEqual:
            // "Vegan", "High Vegan" -> must have this diet tag.
            result.includeDiets.insert(dietName)
            
        case .equal:
            // "Not Vegan" should have been converted by NumberRangeParser into
            // "= 0" on that diet; "= 1" (or no value) implies presence.
            if value == 0 {
                result.excludeDiets.insert(dietName)
            } else {
                result.includeDiets.insert(dietName)
            }
            
        case .lessThan, .lessThanOrEqual:
            // "Less than 1 Vegan" ~= "not Vegan".
            result.excludeDiets.insert(dietName)
            
        case .notEqual, .unknown:
            break
        }
    }
    
    static func mapAllergenConstraint(
        _ c: DietaryConstraint,
        allergen: Allergen,
        into result: inout ConstraintMapperResult
    ) {
        let value = c.value ?? 0.0
        // Textual negation ("no soy", "soy free", "without gluten") takes
        // precedence over any numeric encoding.
        if isNegated(c) {
            result.excludeAllergens.insert(allergen)
            return
        }
        switch c.comparison {
        case .equal:
            if value == 0 {
                // "No peanuts", "Peanut free" -> allergen must be absent.
                result.excludeAllergens.insert(allergen)
            } else {
                // "Contains peanuts"
                result.includeAllergens.insert(allergen)
            }
            
        case .lessThan, .lessThanOrEqual:
            // "Less than 1 peanut" -> also effectively 0.
            result.excludeAllergens.insert(allergen)
            
        case .greaterThan, .greaterThanOrEqual:
            // "Contains peanuts"
            result.includeAllergens.insert(allergen)
            
        case .notEqual, .unknown:
            break
        }
    }
}
