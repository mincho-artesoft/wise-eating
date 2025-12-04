import Foundation

struct Tokenizer {
    struct SearchToken { let term: String }

    enum OpToken {
        case lt, lte, gt, gte, eq, neq
    }

    // Used to track what the next number/operator should apply to
    enum ActiveContext {
        case none
        case nutrient(NutrientType)
        case ph
    }

    // MARK: - Normalization

    private static func normalizePercentages(_ text: String) -> String {
        var processed = text
        if processed.contains("%") {
            let percentagePattern = "\\b([0-9]+(\\.[0-9]+)?)%"
            if let regex = try? NSRegularExpression(pattern: percentagePattern, options: []) {
                let range = NSRange(location: 0, length: processed.utf16.count)
                let matches = regex.matches(in: processed, options: [], range: range)
                if !matches.isEmpty {
                    for match in matches.reversed() {
                        if let rRange = Range(match.range, in: processed) {
                            let substring = String(processed[rRange])
                            let replacement = substring.replacingOccurrences(of: "%", with: "_percent")
                            processed.replaceSubrange(rRange, with: replacement)
                        }
                    }
                }
            }
        }
        return processed
    }

    private static func normalizeRanges(_ text: String) -> String {
        var processed = text
        if !processed.contains("between") && !processed.contains("from") { return processed }

        let num = "([0-9]+(?:\\.[0-9]+)?)"
        let strictPattern = "strictly\\s+between\\s+\(num)\\s+and\\s+\(num)"
        processed = processed.replacingOccurrences(
            of: strictPattern,
            with: "_op_gt_ $1 _op_lt_ $2",
            options: .regularExpression
        )

        let rangePatterns = [
            "between\\s+\(num)\\s+and\\s+\(num)",
            "from\\s+\(num)\\s+to\\s+\(num)"
        ]
        for pattern in rangePatterns {
            processed = processed.replacingOccurrences(
                of: pattern,
                with: "_op_gte_ $1 _op_lte_ $2",
                options: .regularExpression
            )
        }
        return processed
    }

    private static func normalizeOperators(_ text: String) -> String {
        var processed = text

        // Strict symbol operators first
        for (pattern, token) in SearchKnowledgeBase.shared.strictOperatorMap {
            if processed.contains(pattern) {
                processed = processed.replacingOccurrences(
                    of: pattern,
                    with: " \(token) "
                )
            }
        }

        // Phrase operators
        for (pattern, token) in SearchKnowledgeBase.shared.operatorPhraseMap {
            if processed.contains(pattern) {
                processed = processed.replacingOccurrences(
                    of: "\\b\(pattern)\\b",
                    with: " \(token) ",
                    options: .regularExpression
                )
            }
        }

        // Comparative adjectives followed by a number
        for (word, token) in SearchKnowledgeBase.shared.comparativeAdjectives {
            if processed.contains(word) {
                let pattern = "\\b\(word)\\s+(?=\\d)"
                processed = processed.replacingOccurrences(
                    of: pattern,
                    with: "\(token) ",
                    options: .regularExpression
                )
            }
        }

        // Post-fix cases: "5 max", "10 min", "20 less"
        let postFixMap: [String: String] = [
            "max": "_op_lte_",
            "min": "_op_gte_",
            "less": "_op_lt_",
            "more": "_op_gt_"
        ]
        for (word, token) in postFixMap {
            if processed.contains(word) {
                let pattern = "(?<=\\d)\\s*\\b\(word)\\b"
                processed = processed.replacingOccurrences(
                    of: pattern,
                    with: " \(token) ",
                    options: .regularExpression
                )
            }
        }

        return processed
    }

    private static func normalizePhPhrases(_ text: String) -> String {
        var processed = text
        // Ensure "low acid" / "high alkaline" etc are mapped first
        for (pattern, token) in SearchKnowledgeBase.shared.phPhraseMap {
            if processed.contains(pattern) {
                processed = processed.replacingOccurrences(
                    of: "\\b\(pattern)\\b",
                    with: " \(token) ",
                    options: .regularExpression
                )
            }
        }
        
        // Extra handling for phrases like:
        // "ph greater than 7", "ph greater than or equal to 7",
        // "ph less than 7", "ph less than or equal to 7"
        let num = "([0-9]+(?:\\.[0-9]+)?)"
        let phPatterns: [(String, String)] = [
            ("ph\\s+greater than or equal to\\s+\(num)", "ph _op_gte_ $1"),
            ("ph\\s+greater than\\s+\(num)",             "ph _op_gt_ $1"),
            ("ph\\s+less than or equal to\\s+\(num)",    "ph _op_lte_ $1"),
            ("ph\\s+less than\\s+\(num)",                "ph _op_lt_ $1")
        ]
        
        for (pattern, replacement) in phPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: processed.utf16.count)
                processed = regex.stringByReplacingMatches(
                    in: processed,
                    options: [],
                    range: range,
                    withTemplate: replacement
                )
            }
        }
        
        return processed
    }

    // MARK: - Main Parser

    @MainActor static func parse(_ query: String, availableDiets: Set<String> = []) -> SearchIntent {
        var processed = query.lowercased()
        processed = normalizePercentages(processed)
        processed = normalizeRanges(processed)
        // 1. Normalize PH phrases FIRST to avoid "low acid" becoming "less than acid"
        processed = normalizePhPhrases(processed)
        // 2. Normalize Operators
        processed = normalizeOperators(processed)

        // Phrase Protection for multi-word nutrients (e.g., "vitamin c" -> "vitamin_c")
        let nutrientPhrases = SearchKnowledgeBase.shared.nutrientMap.keys.filter { $0.contains(" ") }
        for key in nutrientPhrases {
            if processed.contains(key) {
                let protectedKey = key.replacingOccurrences(of: " ", with: "_")
                processed = processed.replacingOccurrences(of: key, with: protectedKey)
            }
        }
        
        // Phrase Protection for multi-word diets (e.g., "low sodium" -> "low_sodium")
        let dietPhraseKeys = Array(SearchKnowledgeBase.shared.dietMap.keys) +
                             Array(SearchKnowledgeBase.shared.dietSynonyms.keys)
        let dietPhrases = dietPhraseKeys.filter { $0.contains(" ") }
        for key in dietPhrases {
            if processed.contains(key) {
                let protectedKey = key.replacingOccurrences(of: " ", with: "_")
                processed = processed.replacingOccurrences(of: key, with: protectedKey)
            }
        }

        // Age Logic
        var detectedAge: Double? = nil
        let agePattern = "(_op_[a-z]+_)?\\s*(\\d+(\\.\\d+)?)\\s*(months?|mos?|mths?|m|years?|yrs?|y\\.o\\.|y\\/o|yo|y)\\b"
        if let regex = try? NSRegularExpression(pattern: agePattern, options: []) {
            if let match = regex.firstMatch(
                in: processed,
                options: [],
                range: NSRange(location: 0, length: processed.utf16.count)
            ) {
                if let rNumber = Range(match.range(at: 2), in: processed),
                   let rUnit   = Range(match.range(at: 4), in: processed) {
                    let val = Double(processed[rNumber]) ?? 0
                    let unit = String(processed[rUnit])

                    var months = unit.starts(with: "y") ? val * 12.0 : val

                    if let rOp = Range(match.range(at: 1), in: processed) {
                        let op = String(processed[rOp])
                        if op == "_op_lt_" { months -= 0.1 }
                        else if op == "_op_gt_" { months += 0.1 }
                    }

                    detectedAge = max(0, months)
                    if let range = Range(match.range, in: processed) {
                        processed.replaceSubrange(range, with: " ")
                    }
                }
            }
        }

        // Tokenize
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-+:"))
        let cleanedString = processed
            .components(separatedBy: allowedChars.inverted)
            .joined(separator: " ")
        let words = cleanedString
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var textTokens = Set<String>()
        var negativeTokens = Set<String>()
        var goals: [NutrientGoal] = []
        var detectedDiets = Set<String>()
        var dietFilter: DietType? = nil
        var dietExclusions = Set<String>()
        var allergenExclusions = Set<Allergen>()
        var excludeAllAllergens = false
        var phGoal: ConstraintValue? = nil

        var activeOperator: OpToken? = nil
        var activeContext: ActiveContext = .none

        var pendingConstraints: [(OpToken, Double)] = []
        var pendingImplicitValue: Double? = nil

        var i = 0
        while i < words.count {
            let word = words[i]
            var consumed = false

            func getOp(_ w: String) -> OpToken? {
                switch w {
                case "_op_lt_":  return .lt
                case "_op_lte_": return .lte
                case "_op_gt_":  return .gt
                case "_op_gte_": return .gte
                case "_op_eq_":  return .eq
                case "_op_neq_": return .neq
                default:         return nil
                }
            }

            var percentValue: Double? = nil
            var wasPercent = false
            if word.contains("_percent") {
                percentValue = Double(word.replacingOccurrences(of: "_percent", with: ""))
                wasPercent = true
            }

            let cleanWord = word.replacingOccurrences(of: "_", with: " ")

            // A. Diet (Positive)
            if let mappedDiet = SearchKnowledgeBase.shared.dietSynonyms[cleanWord] {
                detectedDiets.insert(mappedDiet)
                dietFilter = DietType.from(string: mappedDiet)
                consumed = true
            }
            else if let d = SearchKnowledgeBase.shared.dietMap[cleanWord] {
                // Known, static diet keyword
                dietFilter = d
                detectedDiets.insert(d.rawValue)
                consumed = true
            }
            else if let dynamicMatch = availableDiets.first(where: { $0.lowercased() == cleanWord }) {
                // Dynamic diet coming from DB / user-defined list
                detectedDiets.insert(dynamicMatch)
                if dietFilter == nil {
                    dietFilter = DietType.from(string: dynamicMatch)
                }
                consumed = true
            }

            // B. Age personas
            else if detectedAge == nil,
                    let age = SearchKnowledgeBase.shared.personaAgeMap[cleanWord] {
                detectedAge = age
                consumed = true
            }

            // C. Pre-calculated PH Phrase (e.g. "_ph_acidic_")
            else if word.hasPrefix("_ph_") {
                if word == "_ph_acidic_" {
                    phGoal = .low
                } else if word == "_ph_alkaline_" {
                    phGoal = .high
                } else if word == "_ph_neutral_" {
                    phGoal = .range(6.5, 7.5)
                }
                consumed = true
            }

            // C2. Single-word PH adjectives (acidic / alkaline / neutral)
            else if let phType = SearchKnowledgeBase.shared.phTerms[cleanWord] {
                switch phType {
                case .acidic:   phGoal = .low
                case .alkaline: phGoal = .high
                case .neutral:  phGoal = .range(6.5, 7.5)
                }
                consumed = true
            }

            // D. Explicit PH Trigger (e.g. "ph", "acidity", "p.h.")
            else if SearchKnowledgeBase.shared.phKeywords.contains(word) {
                // If we have pending constraints waiting, apply them to PH
                if !pendingConstraints.isEmpty {
                    for (op, val) in pendingConstraints {
                        phGoal = convertToPhConstraint(op: op, val: val)
                    }
                    pendingConstraints.removeAll()
                }
                activeContext = .ph
                consumed = true
            }

            // E. Operator
            else if let op = getOp(word) {
                activeOperator = op
                consumed = true
            }

            // F. Number
            else if let val = percentValue ?? Double(word) {
                // Apply to active context
                switch activeContext {
                case .nutrient(let nut):
                    if let op = activeOperator {
                        applyGoal(nutrient: nut, op: op, val: val, goals: &goals)
                        activeOperator = nil
                    } else {
                        // e.g. "Protein 50" -> Range
                        goals.append(
                            NutrientGoal(
                                nutrient: nut,
                                constraint: .range(val - 0.5, val + 0.5)
                            )
                        )
                        activeContext = .none
                    }
                    consumed = true

                case .ph:
                    if let op = activeOperator {
                        phGoal = convertToPhConstraint(op: op, val: val)
                        activeOperator = nil
                    } else {
                        // e.g. "ph 7" -> Range
                        phGoal = .range(val - 0.2, val + 0.2)
                        activeContext = .none
                    }
                    consumed = true

                case .none:
                    if let op = activeOperator {
                        pendingConstraints.append((op, val))
                        activeOperator = nil
                    } else {
                        pendingImplicitValue = val
                    }
                    if wasPercent { textTokens.insert(word) }
                    consumed = true
                }
            }

            // G. Nutrient
            else if let nutrient = resolveNutrient(word) {
                if !pendingConstraints.isEmpty {
                    for (op, val) in pendingConstraints {
                        applyGoal(
                            nutrient: nutrient,
                            op: op,
                            val: val,
                            goals: &goals
                        )
                    }
                    pendingConstraints.removeAll()
                }

                if let val = pendingImplicitValue {
                    var postFixOp: OpToken? = nil
                    if i + 1 < words.count,
                       let nextOp = getOp(words[i + 1]) {
                        postFixOp = nextOp
                    }
                    let opToUse = postFixOp ?? activeOperator ?? .eq

                    if opToUse == .eq {
                        goals.append(
                            NutrientGoal(
                                nutrient: nutrient,
                                constraint: .range(val - 0.1, val + 0.1)
                            )
                        )
                    } else {
                        applyGoal(
                            nutrient: nutrient,
                            op: opToUse,
                            val: val,
                            goals: &goals
                        )
                    }
                    if postFixOp != nil { i += 1 }
                    pendingImplicitValue = nil
                    activeOperator = nil
                    activeContext = .nutrient(nutrient) // Stick to nutrient for further ops
                }

                else if i + 1 < words.count,
                        SearchKnowledgeBase.shared.suffixNegationTerms.contains(words[i + 1]) {
                    // "Sugar Free"
                    goals.append(
                        NutrientGoal(
                            nutrient: nutrient,
                            constraint: .strictMax(0.5)
                        )
                    )
                    i += 1
                    activeOperator = nil
                    activeContext = .none
                }

                else if pendingConstraints.isEmpty {
                    activeContext = .nutrient(nutrient)
                    let nextIsOp  = (i + 1 < words.count) && (getOp(words[i + 1]) != nil)
                    let nextIsVal = (i + 1 < words.count) && (Double(words[i + 1]) != nil)

                    // If no number follows, interpret "low/high nutrient" via previous word
                    if activeOperator == nil && !nextIsOp && !nextIsVal {
                        let prevWord = i > 0 ? words[i - 1] : nil
                        let prevClean = prevWord.map { processWord($0) }

                        let lowWords: Set<String>  = ["low", "lower", "less", "small"]
                        let highWords: Set<String> = ["high", "higher", "more", "great", "greater"]

                        let constraint: ConstraintValue
                        if let prev = prevClean, lowWords.contains(prev) {
                            constraint = .low
                        } else if let prev = prevClean, highWords.contains(prev) {
                            constraint = .high
                        } else {
                            // Default: presence bias toward higher amounts
                            constraint = .high
                        }

                        goals.append(
                            NutrientGoal(
                                nutrient: nutrient,
                                constraint: constraint
                            )
                        )
                        activeContext = .none
                    }
                } else {
                    activeContext = .nutrient(nutrient)
                    activeOperator = nil
                }
                consumed = true
            }

            // H. Negation (no / without / free / exclude ...)
            else if isFuzzyMatch(word, targets: SearchKnowledgeBase.shared.negationTerms) {
                if i + 1 < words.count {
                    let nextWord = words[i+1]
                    let cleanNext = processWord(nextWord)

                    if cleanNext == "allergen" || cleanNext == "allergens" {
                        excludeAllAllergens = true
                        i += 1
                    }
                    else if let allergen = SearchKnowledgeBase.shared.allergenAliasMap[cleanNext] {
                        allergenExclusions.insert(allergen)
                        i += 1
                    }
                    // --- DIET SEMANTIC NEGATION ---
                    else if let dietType = SearchKnowledgeBase.shared.dietMap[cleanNext] {
                        // e.g. "no halal", "no keto"
                        dietExclusions.insert(dietType.rawValue)
                        i += 1
                    }
                    else if let mappedDietName = SearchKnowledgeBase.shared.dietSynonyms[cleanNext] {
                        // e.g. "no gluten" -> "Gluten-Free"
                        dietExclusions.insert(mappedDietName)
                        i += 1
                    }
                    else if let ingredientDietName = SearchKnowledgeBase.shared.ingredientToDietMap[cleanNext] {
                        // e.g. "no milk" -> "Dairy-Free"
                        dietExclusions.insert(ingredientDietName)
                        i += 1
                    }
                    else {
                        // Try “<word>-Free” diet that exists in DB
                        let potentialDietName = cleanNext.capitalized + "-Free"
                        if availableDiets.contains(potentialDietName) {
                            dietExclusions.insert(potentialDietName)
                            i += 1
                        }
                        else if let negatedNut = resolveNutrient(nextWord) {
                            goals.append(
                                NutrientGoal(
                                    nutrient: negatedNut,
                                    constraint: .strictMax(0.5)
                                )
                            )
                            i += 1
                        } else {
                            negativeTokens.insert(cleanNext)
                            i += 1
                        }
                    }
                }
                consumed = true
            }

            // I. Text Tokens
            if !consumed {
                if !SearchKnowledgeBase.shared.stopWords.contains(word) {
                    // Ensure we don't treat stray operators as text
                    let isOpPrefix = SearchKnowledgeBase.shared
                        .allOperatorKeywords
                        .contains { $0.hasPrefix(word) }
                    if !isOpPrefix {
                        textTokens.insert(processWord(word))
                        activeContext = .none
                        activeOperator = nil
                        pendingImplicitValue = nil
                        pendingConstraints.removeAll()
                    }
                }
            }

            i += 1
        }

        return SearchIntent(
            textTokens: textTokens,
            negativeTokens: negativeTokens,
            nutrientGoals: goals,
            diets: detectedDiets,
            dietFilter: dietFilter,
            excludedDiets: dietExclusions,           // ⬅️ NEW
            targetConsumerAge: detectedAge,
            allergenExclusions: allergenExclusions,
            excludeAllAllergens: excludeAllAllergens,
            phConstraint: phGoal
        )
    }

    // MARK: - Helpers

    static func process(_ text: String) -> [SearchToken] {
        var processed = text.lowercased()
        processed = normalizePercentages(processed)
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_:"))
        let cleaned = processed
            .components(separatedBy: allowedChars.inverted)
            .joined(separator: " ")
        let words = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var tokens: [SearchToken] = []
        for word in words {
            if SearchKnowledgeBase.shared.stopWords.contains(word) { continue }
            tokens.append(SearchToken(term: processWord(word)))
        }
        return tokens
    }

    static func applyGoal(nutrient: NutrientType, op: OpToken, val: Double, goals: inout [NutrientGoal]) {
        switch op {
        case .lt:
            goals.append(NutrientGoal(nutrient: nutrient, constraint: .strictMax(val)))
        case .lte:
            goals.append(NutrientGoal(nutrient: nutrient, constraint: .max(val)))
        case .gt:
            goals.append(NutrientGoal(nutrient: nutrient, constraint: .strictMin(val)))
        case .gte:
            goals.append(NutrientGoal(nutrient: nutrient, constraint: .min(val)))
        case .eq:
            goals.append(NutrientGoal(nutrient: nutrient, constraint: .range(val - 0.1, val + 0.1)))
        case .neq:
            goals.append(NutrientGoal(nutrient: nutrient, constraint: .notEqual(val)))
        }
    }

    static func convertToPhConstraint(op: OpToken, val: Double) -> ConstraintValue {
        switch op {
        case .lt:  return .strictMax(val)
        case .lte: return .max(val)
        case .gt:  return .strictMin(val)
        case .gte: return .min(val)
        case .eq:  return .range(val - 0.1, val + 0.1)
        case .neq: return .notEqual(val)
        }
    }

    @MainActor static func resolveNutrient(_ word: String) -> NutrientType? {
        // Restore spaces from protected phrases ("vitamin_c" -> "vitamin c")
        let restored = word.replacingOccurrences(of: "_", with: " ")

        // 1. Exact match in the raw nutrient map (for simple names like "protein")
        if let exact = SearchKnowledgeBase.shared.nutrientMap[restored] {
            return exact
        }

        // 2. Normalized lookup using our helper, so variants like
        //    "pufa 18:2", "pufa_18:2", "pufa18:2" all resolve identically.
        let nkRestored = SearchKnowledgeBase.shared.normalizeNutrientKey(restored)
        if let normalized = SearchKnowledgeBase.shared.normalizedNutrientMap[nkRestored] {
            return normalized
        }

        let nkRaw = SearchKnowledgeBase.shared.normalizeNutrientKey(word)
        if let normalized = SearchKnowledgeBase.shared.normalizedNutrientMap[nkRaw] {
            return normalized
        }

        // 3. No semantic guessing here – if it doesn't match a known nutrient,
        //    we treat it as plain text.
        return nil
    }

    static func processWord(_ word: String) -> String {
        var token = word
        if let root = SearchKnowledgeBase.shared.stemmingExceptions[word] {
            token = root
        } else if word.hasSuffix("s"),
                  word.count > 3,
                  !word.hasSuffix("ss") {
            token = String(word.dropLast())
        }
        if let syn = SearchKnowledgeBase.shared.synonyms[token] {
            token = syn
        }
        return token
    }

    static func isFuzzyMatch(_ word: String, targets: Set<String>) -> Bool {
        targets.contains(word)
    }
}
