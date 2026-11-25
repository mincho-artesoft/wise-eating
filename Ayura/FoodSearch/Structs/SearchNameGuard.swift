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

    /// Foods whose name has every word of a query that mixes ordinary words
    /// with command words ("high protein bread", "chicken without skin",
    /// "low fat yogurt"). The command still runs; these few are shown first,
    /// so a food the user named outright is never filtered away or buried.
    static func fullNameMatches(
        query: String,
        allFoods: [UUID: CompactFoodItem],
        invertedIndex: [String: Set<UUID>],
        knowledge: SearchKnowledgeBase = .shared,
        limit: Int = 10
    ) -> [UUID] {
        let lower = query.lowercased()
        if lower.rangeOfCharacter(from: .decimalDigits) != nil { return [] }
        if lower.rangeOfCharacter(from: CharacterSet(charactersIn: "<>=%")) != nil { return [] }
        let words = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard words.count >= 2, words.count <= 8 else { return [] }

        // The words of a nutrient written as several words ("vitamin c") are
        // command words too, not a name.
        let padded = " " + words.joined(separator: " ") + " "
        var nutrientPhraseWords = Set<String>()
        for key in knowledge.nutrientMap.keys where key.contains(" ") && padded.contains(" \(key) ") {
            nutrientPhraseWords.formUnion(key.split(separator: " ").map(String.init))
        }
        func isCommandWord(_ word: String) -> Bool {
            if commandSignals.contains(word) || nutrientPhraseWords.contains(word) { return true }
            if knowledge.nutrientMap[word] != nil { return true }
            if word.hasSuffix("s"), knowledge.nutrientMap[String(word.dropLast())] != nil { return true }
            return knowledge.phTerms[word] != nil || knowledge.phKeywords.contains(word)
        }
        func variants(_ word: String) -> [String] {
            var out = [word, word + "s"]
            if word.hasSuffix("es"), word.count > 4 { out.append(String(word.dropLast(2))) }
            if word.hasSuffix("s"), word.count > 3 { out.append(String(word.dropLast())) }
            return out
        }

        let filler: Set<String> = ["and", "or", "with", "in", "of", "the", "a", "an"]
        let required = words.filter { !filler.contains($0) && !knowledge.stopWords.contains($0) }
        let ordinary = required.filter { !isCommandWord($0) }
        guard !ordinary.isEmpty, ordinary.count < required.count else { return [] }

        // Narrow through the index by the rarest ordinary word, then read the
        // names. A word right after "without"/"no" is not in the index (the
        // index drops what a name excludes), so it cannot be used to narrow.
        let negators: Set<String> = ["without", "no", "excluding", "except"]
        var candidates: Set<UUID>?
        for (position, word) in required.enumerated() where !isCommandWord(word) {
            if position > 0, negators.contains(required[position - 1]) { continue }
            var ids = Set<UUID>()
            for form in variants(word) { ids.formUnion(invertedIndex[form] ?? []) }
            if candidates == nil || ids.count < candidates!.count { candidates = ids }
        }
        let pool = candidates.map(Array.init) ?? Array(allFoods.keys)

        let phrase = required.joined(separator: " ")
        var matches: [(id: UUID, rank: Int, words: Int, name: String)] = []
        for id in pool {
            guard let name = allFoods[id]?.lowercasedName else { continue }
            let ordered = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let nameWords = Set(ordered)
            guard required.allSatisfy({ word in variants(word).contains(where: nameWords.contains) })
            else { continue }
            // "without skin" must stand together in the name: "grilled
            // without sauce, skin eaten" has the words and the opposite sense.
            let joined = " " + ordered.joined(separator: " ") + " "
            let negationsHold = required.indices.dropLast().allSatisfy { index in
                guard negators.contains(required[index]) else { return true }
                return variants(required[index + 1]).contains {
                    joined.contains(" \(required[index]) \($0) ")
                }
            }
            guard negationsHold else { continue }
            // Best: the name starts with one of the query's ordinary words,
            // as catalogue names lead with the food ("Yogurt, plain, low
            // fat"). Next: the query stands in the name as typed.
            let asTyped = joined.contains(" " + phrase + " ")
            let leads = ordered.first.map { first in
                ordinary.contains { variants($0).contains(first) }
            } ?? false
            let rank = leads ? (asTyped ? 0 : 1) : (asTyped ? 2 : 3)
            matches.append((id, rank, ordered.count, name))
        }
        matches.sort { ($0.rank, $0.words, $0.name) < ($1.rank, $1.words, $1.name) }
        return matches.prefix(limit).map(\.id)
    }

    /// The pH limit in "ph < 6", "ph below 4.5", "ph at least 8" or
    /// "ph between 6 and 7", wherever it stands in the query.
    static func explicitPhConstraint(in query: String) -> ConstraintValue? {
        let text = query.lowercased()
        let number = "([0-9]+(?:\\.[0-9]+)?)"
        func firstMatch(_ pattern: String) -> [Double]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                      in: text, range: NSRange(text.startIndex..., in: text)
                  )
            else { return nil }
            return (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).flatMap { Double(text[$0]) }
            }
        }
        let ph = "\\bph\\s*(?:is\\s+|of\\s+)?"
        if let v = firstMatch(ph + "(?:between|from)\\s+\(number)\\s+(?:and|to)\\s+\(number)"),
           v.count == 2 {
            return .range(min(v[0], v[1]), max(v[0], v[1]))
        }
        if let v = firstMatch(ph + "(?:<=|at most|no more than|max(?:imum)?)\\s*\(number)") {
            return v.first.map(ConstraintValue.max)
        }
        if let v = firstMatch(ph + "(?:>=|at least|no less than|min(?:imum)?)\\s*\(number)") {
            return v.first.map(ConstraintValue.min)
        }
        if let v = firstMatch(ph + "(?:<|less than|lower than|below|under)\\s*\(number)") {
            return v.first.map(ConstraintValue.strictMax)
        }
        if let v = firstMatch(ph + "(?:>|greater than|more than|higher than|above|over)\\s*\(number)") {
            return v.first.map(ConstraintValue.strictMin)
        }
        return nil
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
