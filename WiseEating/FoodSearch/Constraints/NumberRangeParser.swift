import Foundation

class NumberRangeParser {
    
    private func parseOperator(_ text: String?) -> ComparisonOperator {
        guard let text = text?.lowercased().trimmingCharacters(in: .whitespaces) else { return .equal }
        if text.isEmpty { return .equal }
        
        // Zero / Negative inclusion
        if ["no", "without", "free", "non", "minus", "except", "zero", "not", "never", "avoid", "exclude", "lack", "nix", "none"].contains(where: { text.contains($0) }) { return .equal }
        
        // Low / Less
        if ["low", "lower", "less", "least", "minimal", "minimum", "min", "under", "below", "fewer", "lite", "light", "poor", "small"].contains(where: { text.contains($0) }) {
             // "Minimum" usually means >=
             if text == "min" || text == "minimum" { return .greaterThanOrEqual }
             return .lessThan
        }
        
        // Max / Cap
        if ["<=", "max", "maximum", "at most", "limit", "cap"].contains(where: { text.contains($0) }) { return .lessThanOrEqual }
        if ["<"].contains(where: { text.contains($0) }) { return .lessThan }
        
        // Min / At Least
        if [">=", "at least", "min", "minimum"].contains(where: { text.contains($0) }) { return .greaterThanOrEqual }
        
        // High / More
        if ["high", "higher", "most", "more", "rich", "source", "potency", "contains", "has", "with", "heavy", "maximal", "great", "greater", "above", "over", "exceeds", "basic", "alkaline"].contains(where: { text.contains($0) }) { return .greaterThan }
        if [">"].contains(where: { text.contains($0) }) { return .greaterThan }
        
        // Equality
        if ["==", "equal", "is", "exactly", "around", "about", "approx", "neutral", "balanced", "normal"].contains(where: { text.contains($0) }) { return .equal }
        if text.contains("between") { return .greaterThanOrEqual }
        
        return .equal
    }
    
    private func parseNumber(_ text: String?) -> Double? {
        guard let text = text else { return nil }
        if let doubleVal = Double(text) { return doubleVal }
        let mapping: [String: Double] = [ "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10 ]
        return mapping[text.lowercased()]
    }

    func parse(candidate: NumberRangeExtractor.ExtractionCandidate) -> [DietaryConstraint] {
        let cleanSubject = candidate.subjectText
        var op1 = parseOperator(candidate.operatorText)
        let finalUnit = candidate.unitText ?? candidate.unitText2
        var val1: Double? = parseNumber(candidate.valueText)
        let val2: Double? = parseNumber(candidate.secondValueText)
        let op2: ComparisonOperator? = candidate.operatorText2 != nil ? parseOperator(candidate.operatorText2) : nil
        let opText = candidate.operatorText?.lowercased() ?? ""
        
        let type = SearchKnowledgeBase.shared.getSubjectType(cleanSubject)

        // --- ABSTRACT VALUE HANDLING ---
        if val1 == nil && candidate.isAbstract {
            
            // 1. Zero/Free Logic (applies to Nutrients, Allergens, Diets)
            // e.g. "No Sugar", "Gluten Free" -> Force 0.0
            if ["no", "free", "zero", "without", "non", "avoid", "exclude", "except"].contains(where: { opText.contains($0) }) {
                op1 = .equal
                val1 = 0.0
            }
            // 2. Diet/Allergen Existence (e.g. "Vegan", "Contains Peanuts")
            // Implies "Must have this tag"
            else if case .diet = type {
                op1 = .greaterThanOrEqual
                val1 = 1.0
            }
            else if case .allergen = type {
                op1 = .greaterThanOrEqual
                val1 = 1.0
            }
            // 3. Low/High/Rich/Poor Logic (Nutrients)
            // CHANGE: We DO NOT assign fake numbers (100,000 or 0.0) here anymore.
            // We leave val1 as nil.
            // The ConstraintMapper will see (op: .lessThan, val: nil) and assign .max(1_000_000).
            // The ConstraintMapper will see (op: .greaterThan, val: nil) and assign .min(0).
        }
        
        // --- PH SPECIAL LOGIC ---
        if case .ph = type {
            return refinePhLogic(subject: cleanSubject, op: op1, val: val1, val2: val2, originalText: candidate.matchedText, abstractOpText: candidate.operatorText)
        }
        
        // --- STANDARD RETURN ---
        var results: [DietaryConstraint] = []
        // NOTE: If val1 is nil here, we pass nil. ConstraintMapper handles nil now.
        
        results.append(DietaryConstraint(originalText: candidate.matchedText, subject: cleanSubject, comparison: op1, value: val1, value2: nil, unit: finalUnit))
        
        if let v2 = val2 {
            if let secondOp = op2 {
                results.append(DietaryConstraint(originalText: candidate.matchedText, subject: cleanSubject, comparison: secondOp, value: v2, value2: nil, unit: finalUnit))
            } else {
                // Range
                let startVal = val1 ?? 0.0 // fallback if range start missing (unlikely in valid range syntax)
                results[0] = DietaryConstraint(originalText: candidate.matchedText, subject: cleanSubject, comparison: .greaterThanOrEqual, value: startVal, value2: v2, unit: finalUnit)
            }
        }
        
        return results
    }
    
    // MARK: - pH Logic Refinement
    // (Kept consistent with previous, but ensures abstract logic flows through)
    private func refinePhLogic(subject: String, op: ComparisonOperator, val: Double?, val2: Double?, originalText: String, abstractOpText: String?) -> [DietaryConstraint] {
        let lowerSubject = subject.lowercased()
        let isAcid = lowerSubject.contains("acid") || lowerSubject.contains("sour")
        let opText = abstractOpText?.lowercased() ?? ""
        
        var finalOp = op
        var finalVal = val
        let finalVal2 = val2
        
        // 1. Invert Operators if subject is "Acid"
        if isAcid {
            if op == .equal && (val == 0.0 || val == nil) {
                // "No Acid" or "Low Acid" (abstract)
                if val == 0.0 {
                    // "No Acid" -> High pH
                    finalOp = .greaterThanOrEqual
                    finalVal = 7.0
                } else if op == .lessThan || op == .lessThanOrEqual {
                   // "Low Acid" -> High pH
                   finalOp = .greaterThanOrEqual
                   finalVal = 7.0
                }
            } else {
                // Numeric inversion: Acid < 5 -> pH > 5 (roughly, logic simplified)
                switch op {
                case .lessThan: finalOp = .greaterThan
                case .lessThanOrEqual: finalOp = .greaterThanOrEqual
                case .greaterThan: finalOp = .lessThan
                case .greaterThanOrEqual: finalOp = .lessThanOrEqual
                default: break
                }
            }
        }
        
        // 2. Map Abstract Terms to Values
        if finalVal == nil {
            if ["neutral", "balanced", "normal"].contains(where: { opText.contains($0) }) {
                return [DietaryConstraint(originalText: originalText, subject: "ph", comparison: .greaterThanOrEqual, value: 6.8, value2: 7.2, unit: nil)]
            }
            
            // "High Alkaline" / "High pH"
            if finalOp == .greaterThan || finalOp == .greaterThanOrEqual {
                finalVal = 7.0
            }
            // "Low pH"
            else if finalOp == .lessThan || finalOp == .lessThanOrEqual {
                finalVal = 6.0
            }
            // "Alkaline" (noun)
            else if op == .equal {
                if lowerSubject.contains("alkaline") || lowerSubject.contains("basic") {
                    finalOp = .greaterThanOrEqual; finalVal = 7.0
                }
                // "Acidic" (noun)
                else if isAcid {
                    finalOp = .lessThanOrEqual; finalVal = 6.0
                }
            }
        }
        
        // 3. Return Constraints
        if let v2 = finalVal2, let v1 = finalVal {
            return [DietaryConstraint(originalText: originalText, subject: "ph", comparison: .greaterThanOrEqual, value: v1, value2: v2, unit: nil)]
        }
        return [DietaryConstraint(originalText: originalText, subject: "ph", comparison: finalOp, value: finalVal ?? 7.0, value2: nil, unit: nil)]
    }
}
