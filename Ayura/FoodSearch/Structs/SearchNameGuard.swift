import Foundation

/// Switches for search behaviour proven against the golden queries
/// (tools/search-golden).
enum SearchFeatureFlags {
    /// Read a query as a food name before reading it as a command, keep one
    /// consistent filter per nutrient, and stop synonyms narrowing a search.
    /// On by default; the launch argument `-SearchNameFirstEnabled NO` brings
    /// back the previous behaviour.
    nonisolated(unsafe) static var nameFirst: Bool =
        UserDefaults.standard.object(forKey: "SearchNameFirstEnabled") as? Bool ?? true
}

/// Decides when a nutrient or pH word in a query is part of a food's name
/// ("sour cream", "coconut water", "brown sugar") and not a command.
enum SearchNameGuard {
    /// Words that make a nutrient word a command: "low fat", "sugar free",
    /// "no salt", "more protein". A query containing one is left alone.
    private static let commandSignals: Set<String> = [
        "low", "lower", "less", "small", "high", "higher", "more", "great",
        "greater", "rich", "poor", "max", "maximum", "min", "minimum", "limit",
        "under", "below", "over", "above", "equal", "between", "than", "least",
        "most", "no", "without", "free", "non", "minus", "except", "zero",
        "not", "never", "nix", "none", "avoid", "exclude", "excluding",
        "excepting",
    ]

    private static let comparisonWords: Set<String> = [
        "less", "more", "greater", "lower", "higher", "than", "under", "below",
        "over", "above", "least", "most", "between", "equal", "max", "min",
        "maximum", "minimum",
    ]

    static func isComparisonWord(_ word: String) -> Bool {
        comparisonWords.contains(word)
    }

    /// The words `FoodItem.makeTokens` leaves out of the index.
    private static let indexStopWords: Set<String> = [
        "and", "or", "with", "without", "in", "of", "the", "a", "an", "style",
        "type", "made", "from", "plus", "no", "low", "reduced",
    ]

    /// The index tokens to search by when the query names a food, or nil when
    /// the query should go through the command parsers as before.
    ///
    /// A query is a name when it has no number, comparison or command signal,
    /// every nutrient/pH word in it sits next to another query word the same
    /// way it does in some food's name, and one food's name has all the words.
    static func nameTokens(
        query: String,
        invertedIndex: [String: Set<UUID>],
        knowledge: SearchKnowledgeBase = .shared
    ) -> [String]? {
        let lower = query.lowercased()
        if lower.rangeOfCharacter(from: .decimalDigits) != nil { return nil }
        if lower.rangeOfCharacter(from: CharacterSet(charactersIn: "<>=%")) != nil { return nil }

        let words = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard words.count >= 2, words.count <= 8 else { return nil }
        if words.contains(where: commandSignals.contains) { return nil }

        // Nutrients and pH phrases written as several words stay commands.
        let padded = " " + words.joined(separator: " ") + " "
        for key in knowledge.nutrientMap.keys where key.contains(" ") {
            if padded.contains(" \(key) ") { return nil }
        }
        for (pattern, _) in knowledge.phPhraseMap {
            if padded.contains(" \(pattern) ") { return nil }
        }

        func forms(_ word: String) -> [String] {
            var candidates = [word, word + "s"]
            if word.hasSuffix("es"), word.count > 4 { candidates.append(String(word.dropLast(2))) }
            if word.hasSuffix("s"), word.count > 3 { candidates.append(String(word.dropLast())) }
            return candidates.filter { invertedIndex[$0] != nil }
        }
        func isCommandWord(_ word: String) -> Bool {
            if knowledge.nutrientMap[word] != nil { return true }
            if word.hasSuffix("s"), knowledge.nutrientMap[String(word.dropLast())] != nil { return true }
            return knowledge.phTerms[word] != nil || knowledge.phKeywords.contains(word)
        }

        let content = words.filter { !indexStopWords.contains($0) }
        var wordForms: [[String]] = []
        var commandPositions: [Int] = []
        for word in content {
            let found = forms(word)
            if found.isEmpty {
                // Filler such as "added" is fine; an unknown word is not.
                if knowledge.stopWords.contains(word) { continue }
                return nil
            }
            if isCommandWord(word) { commandPositions.append(wordForms.count) }
            wordForms.append(found)
        }
        guard !commandPositions.isEmpty, wordForms.count >= 2 else { return nil }

        func adjacentInSomeName(_ a: [String], _ b: [String]) -> Bool {
            for x in a {
                for y in b where invertedIndex["\(x) \(y)"] != nil || invertedIndex["\(y) \(x)"] != nil {
                    return true
                }
            }
            return false
        }
        for position in commandPositions {
            let before = position > 0 && adjacentInSomeName(wordForms[position - 1], wordForms[position])
            let after = position + 1 < wordForms.count
                && adjacentInSomeName(wordForms[position], wordForms[position + 1])
            if !before && !after { return nil }
        }

        var shared: Set<UUID>?
        for found in wordForms {
            var ids = Set<UUID>()
            for form in found { ids.formUnion(invertedIndex[form] ?? []) }
            shared = shared.map { $0.intersection(ids) } ?? ids
            if shared?.isEmpty == true { return nil }
        }

        // The shortest form, so that prefix matching also reaches the plural.
        return wordForms.map { $0.min(by: { $0.count < $1.count })! }
    }

    /// One filter per nutrient. A numeric limit wins; otherwise the direction
    /// the tokenizer read from the words ("low", "high", "free").
    static func consistentGoals(
        _ merged: [NutrientGoal],
        tokenizerGoals: [NutrientGoal]
    ) -> [NutrientGoal] {
        func isNumeric(_ constraint: ConstraintValue) -> Bool {
            switch constraint {
            case .min, .max, .strictMin, .strictMax, .range, .notEqual: return true
            case .high, .low, .lowest, .highest: return false
            }
        }
        var order: [NutrientType] = []
        var byNutrient: [NutrientType: [NutrientGoal]] = [:]
        for goal in merged {
            if byNutrient[goal.nutrient] == nil { order.append(goal.nutrient) }
            byNutrient[goal.nutrient, default: []].append(goal)
        }
        return order.compactMap { nutrient in
            let goals = byNutrient[nutrient] ?? []
            // The constraint mapper knows per-nutrient thresholds ("low fat"
            // is at most 12 g), so its number is preferred to the tokenizer's.
            if let numeric = goals.first(where: { isNumeric($0.constraint) }) { return numeric }
            let fromWords = tokenizerGoals.first { $0.nutrient == nutrient }
            return fromWords ?? goals.first
        }
    }
}
