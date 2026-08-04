import SwiftData
import Foundation
import FoundationModels

// MP2_TESTABLE_BEGIN
enum PlannerMacroNutrient: String, Sendable {
    case protein
    case fat
    case carbohydrates
}

enum PlannerMacroConstraint: String, Sendable {
    case exactly
    case lessThan
    case moreThan
}

struct PlannerMacroTarget: Sendable {
    let nutrient: PlannerMacroNutrient
    let constraint: PlannerMacroConstraint
    let value: Double
}

struct PlannerResolvedMacroItem: Sendable {
    let mealIndex: Int
    let itemIndex: Int
    let name: String
    var grams: Double
    let caloriesPerGram: Double
    let referenceWeightGrams: Double
    let proteinPerReference: Double
    let fatPerReference: Double
    let carbohydratesPerReference: Double

    func density(for nutrient: PlannerMacroNutrient) -> Double {
        guard referenceWeightGrams > 0 else { return 0 }
        switch nutrient {
        case .protein:
            return proteinPerReference / referenceWeightGrams
        case .fat:
            return fatPerReference / referenceWeightGrams
        case .carbohydrates:
            return carbohydratesPerReference / referenceWeightGrams
        }
    }
}

struct PlannerMacroTotals: Sendable {
    var protein = 0.0
    var fat = 0.0
    var carbohydrates = 0.0
}

struct PlannerMacroAdjustmentResult: Sendable {
    let items: [PlannerResolvedMacroItem]
    let before: PlannerMacroTotals
    let after: PlannerMacroTotals
    let unresolvedComponentCount: Int
}

enum PlannerMacroGoalAdjuster {
    // Preserve the former adjustment thresholds exactly: >5 g/100 g and 20 g.
    private static let adjustableDensityFloor = 0.05
    private static let minimumAdjustedGrams = 20.0

    static func totals(for items: [PlannerResolvedMacroItem]) -> PlannerMacroTotals {
        items.reduce(into: PlannerMacroTotals()) { totals, item in
            guard item.grams > 0 else { return }
            totals.protein += item.density(for: .protein) * item.grams
            totals.fat += item.density(for: .fat) * item.grams
            totals.carbohydrates += item.density(for: .carbohydrates) * item.grams
        }
    }

    static func adjust(
        items: [PlannerResolvedMacroItem],
        targets: [PlannerMacroTarget],
        unresolvedComponentCount: Int
    ) -> PlannerMacroAdjustmentResult {
        let before = totals(for: items)
        var adjustedItems = items

        for target in targets {
            let currentTotal = adjustedItems.reduce(0.0) { total, item in
                guard item.grams > 0 else { return total }
                return total + item.density(for: target.nutrient) * item.grams
            }
            let error = currentTotal - target.value

            let needsAdjustment: Bool
            switch target.constraint {
            case .exactly:
                needsAdjustment = abs(error) > target.value * 0.1
            case .lessThan:
                needsAdjustment = currentTotal > target.value
            case .moreThan:
                needsAdjustment = currentTotal < target.value
            }
            guard needsAdjustment else { continue }

            let adjustableIndices = adjustedItems.indices.filter { index in
                let item = adjustedItems[index]
                return item.grams > 0
                    && item.density(for: target.nutrient) > adjustableDensityFloor
            }
            guard !adjustableIndices.isEmpty else { continue }

            let adjustmentPerSource = -error / Double(adjustableIndices.count)
            for index in adjustableIndices {
                let item = adjustedItems[index]
                let density = item.density(for: target.nutrient)
                let currentNutrientAmount = item.grams * density
                adjustedItems[index].grams = max(
                    minimumAdjustedGrams,
                    (currentNutrientAmount + adjustmentPerSource) / density
                )
            }
        }

        return PlannerMacroAdjustmentResult(
            items: adjustedItems,
            before: before,
            after: totals(for: adjustedItems),
            unresolvedComponentCount: unresolvedComponentCount
        )
    }
}
// MP2_TESTABLE_END

// MP3_TESTABLE_BEGIN
enum PlannerResolutionTier: String, Codable, Equatable, Sendable {
    case estimated
    case derived
    case classical

    var rank: Int {
        switch self {
        case .estimated: return 0
        case .derived: return 1
        case .classical: return 2
        }
    }
}

struct PlannerResolutionCandidate: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let isRecipe: Bool
    let tier: PlannerResolutionTier
}

struct PlannerResolutionDecision: Codable, Equatable, Sendable {
    let candidate: PlannerResolutionCandidate
    let score: Double
    let headMatched: Bool
    let matchedQualifiers: [String]
    let missingQualifiers: [String]
    let extraTokens: [String]
}

struct PlannerPreparedResolutionCandidate: Sendable {
    let candidate: PlannerResolutionCandidate
    let normalizedName: String
    let tokens: [String]
    let tokenSet: Set<String>
    let nameSegments: [[String]]
}

enum PlannerDeterministicFoodResolver {
    private struct PreparedConcept {
        let normalized: String
        let tokens: [String]
        let tokenSet: Set<String>
        let aliases: [String]
        let headTokenSets: [Set<String>]
        let qualifiers: [String]
        let impliedTokens: Set<String>
        let forms: Set<String>
        let composite: Bool
        let requiresSubstantiveHeadword: Bool
    }

    static let minimumScore = 46.0

    static let formVocabulary: Set<String> = [
        "baby", "bake", "boil", "breast", "can", "cook", "dal", "dry",
        "flour", "fresh", "freeze", "fry", "grill", "ground", "instant",
        "leaf", "milk", "oil", "powder", "prepare", "raw", "roast", "seed",
        "split", "steam", "tadka", "tea", "whip", "whole"
    ]
    private static let trailingFormTokens: Set<String> = [
        "breast", "dal", "flour", "leaf", "milk", "oil", "powder", "seed",
        "tadka", "tea"
    ]
    private static let preferenceFormTokens: Set<String> = [
        "bake", "boil", "can", "cook", "dry", "fresh", "freeze", "fry",
        "grill", "ground", "powder", "raw", "roast", "steam"
    ]
    private static let modifierOnlyFormTokens = preferenceFormTokens.union(
        ["baby", "instant", "prepare", "whip"]
    )
    private static let nonContentFormTokens: Set<String> = [
        "bake", "boil", "cook", "dry", "fresh", "fry", "grill", "ground",
        "raw", "roast", "split", "steam"
    ]
    private static let ignoredExtraTokens: Set<String> = [
        "all", "boneless", "broiler", "commercial", "common", "domesticated",
        "enriched", "food", "fryer", "grain", "lean", "long", "mature",
        "meat", "medium", "nfs", "nut", "only", "plain", "purpose", "regular",
        "separable", "short", "spice", "standard", "table", "type", "unenriched",
        "variety", "whole"
    ]
    private static let strongExtraTokens: Set<String> = [
        "ajwain", "ale", "almond", "apple", "baby", "babyfood", "bacon",
        "badam", "bar", "barley", "bean", "beer", "bell", "bitter", "black",
        "blend", "bottle", "bouillon", "bread", "breakfast", "breast", "broth",
        "brown", "butter", "cabbage", "cake", "can", "candied", "canned",
        "cayenne",
        "cereal", "chai", "chestnut", "chicken", "chili", "chip", "chocolate",
        "chutney", "cilantro", "coconut", "condensed", "cookie", "cracker",
        "cream", "crisp", "curd", "curry", "dip",
        "dressing", "drink", "drumstick", "evaporated", "extract", "falafel",
        "fat", "flavor", "flour", "freeze", "frozen", "garlic", "graham",
        "gruel", "halva",
        "halwa", "ham", "honey", "honeydew", "hummus", "ice", "juice",
        "ketchup", "kombucha", "latte", "leg", "lemonade", "lily", "liquid",
        "liver", "marzipan", "meatless", "meringue", "milk", "mix", "murabba",
        "mushroom", "mustard", "neck",
        "noodle", "nugget", "oat", "oil", "onion", "paper", "paste", "peanut",
        "peppermint", "pickled", "pie", "pot", "powder", "pudding", "pumpkin",
        "red", "rice", "ridge", "roll", "salad", "salt", "sauce", "sausage",
        "seasoning", "skin", "snap", "snack", "soup", "souffle", "soy",
        "sprout", "syrup", "tahini",
        "tadka", "tail", "tapenade", "thigh", "tofu", "tonic", "sugar",
        "vinegar", "water", "wax", "white", "wine", "wing", "woods"
    ]
    private static let recipeConceptTokens: Set<String> = [
        "curry", "kitchari", "khichdi", "kichadi", "stew"
    ]

    static func queries(
        for concept: String,
        ontologyAliases: [String: String] = [:]
    ) -> [String] {
        let normalizedConcept = normalize(concept)
        guard !normalizedConcept.isEmpty else { return [] }

        var ordered = [normalizedConcept]
        ordered.append(
            contentsOf: aliasPhrases(
                for: normalizedConcept,
                ontologyAliases: ontologyAliases
            )
        )
        if let head = headToken(for: tokenized(normalizedConcept)) {
            ordered.append(head)
        }

        var seen = Set<String>()
        return ordered.filter { query in
            let normalizedQuery = normalize(query)
            return !normalizedQuery.isEmpty && seen.insert(normalizedQuery).inserted
        }
    }

    static func resolve(
        concept: String,
        ontologyAliases: [String: String] = [:],
        candidates: [PlannerResolutionCandidate]
    ) -> PlannerResolutionDecision? {
        resolve(
            concept: concept,
            ontologyAliases: ontologyAliases,
            candidates: prepare(candidates)
        )
    }

    static func prepare(
        _ candidates: [PlannerResolutionCandidate]
    ) -> [PlannerPreparedResolutionCandidate] {
        candidates.compactMap { candidate in
            let normalizedName = normalize(candidate.name)
            let tokens = tokenized(normalizedName)
            guard !tokens.isEmpty else { return nil }
            let nameSegments = candidate.name
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { tokenized(String($0)) }
                .filter { !$0.isEmpty }
            return PlannerPreparedResolutionCandidate(
                candidate: candidate,
                normalizedName: normalizedName,
                tokens: tokens,
                tokenSet: Set(tokens),
                nameSegments: nameSegments
            )
        }
    }

    static func resolve(
        concept: String,
        ontologyAliases: [String: String] = [:],
        candidates: [PlannerPreparedResolutionCandidate]
    ) -> PlannerResolutionDecision? {
        let normalizedConcept = normalize(concept)
        guard !normalizedConcept.isEmpty, !candidates.isEmpty else { return nil }
        let conceptTokens = tokenized(normalizedConcept)
        guard !conceptTokens.isEmpty else { return nil }
        let aliases = aliasPhrases(
            for: normalizedConcept,
            ontologyAliases: ontologyAliases
        )
        let head = headToken(for: conceptTokens)
        let qualifiers = Array(
            Set(conceptTokens.filter { token in
                token != head
                    && !formVocabulary.contains(token)
                    && !trailingFormTokens.contains(token)
            })
        ).sorted()
        let aliasTokenSets = aliases.map { Set(tokenized($0)) }
        var impliedTokens = Set(conceptTokens)
        for aliasTokens in aliasTokenSets {
            impliedTokens.formUnion(aliasTokens)
        }
        let headTokenSets = headPhrases(
            for: conceptTokens,
            aliases: aliases
        ).map { Set(tokenized($0)) }
        let matchingHeadCount = candidates.reduce(into: 0) { count, candidate in
            if headTokenSets.contains(where: {
                $0.isSubset(of: candidate.tokenSet)
            }) {
                count += 1
            }
        }
        let commonHeadFloor = max(
            64,
            Int(ceil(Double(candidates.count) * 0.005))
        )
        let preparedConcept = PreparedConcept(
            normalized: normalizedConcept,
            tokens: conceptTokens,
            tokenSet: Set(conceptTokens),
            aliases: aliases,
            headTokenSets: headTokenSets,
            qualifiers: qualifiers,
            impliedTokens: impliedTokens,
            forms: Set(conceptTokens).intersection(formVocabulary),
            composite: isCompositeConcept(normalizedConcept),
            requiresSubstantiveHeadword: conceptTokens.count == 1
                && matchingHeadCount >= commonHeadFloor
        )

        var best: PlannerResolutionDecision?
        for candidate in candidates {
            guard let decision = score(
                concept: preparedConcept,
                candidate: candidate
            ) else {
                continue
            }
            if let incumbent = best {
                if isPreferred(
                    decision,
                    over: incumbent,
                    composite: preparedConcept.composite
                ) {
                    best = decision
                }
            } else {
                best = decision
            }
        }
        guard let best, best.score >= minimumScore else {
            return nil
        }
        return best
    }

    private static func isPreferred(
        _ candidate: PlannerResolutionDecision,
        over incumbent: PlannerResolutionDecision,
        composite: Bool
    ) -> Bool {
        if abs(candidate.score - incumbent.score) > 0.000_001 {
            return candidate.score > incumbent.score
        }
        if candidate.candidate.tier.rank != incumbent.candidate.tier.rank {
            return candidate.candidate.tier.rank > incumbent.candidate.tier.rank
        }
        if composite,
           candidate.candidate.isRecipe != incumbent.candidate.isRecipe {
            return candidate.candidate.isRecipe
        }
        let candidateName = normalize(candidate.candidate.name)
        let incumbentName = normalize(incumbent.candidate.name)
        if candidateName != incumbentName { return candidateName < incumbentName }
        return candidate.candidate.id.uuidString < incumbent.candidate.id.uuidString
    }

    private static func score(
        concept: PreparedConcept,
        candidate: PlannerPreparedResolutionCandidate
    ) -> PlannerResolutionDecision? {
        let candidateName = candidate.normalizedName
        let candidateTokens = candidate.tokens
        let candidateSet = candidate.tokenSet
        guard !candidateTokens.isEmpty else { return nil }

        let headMatched = concept.headTokenSets.contains { headTokens in
            headTokens.isSubset(of: candidateSet)
        }
        guard headMatched else { return nil }
        if concept.requiresSubstantiveHeadword,
           !hasSubstantiveHeadword(concept: concept, candidate: candidate) {
            return nil
        }

        let matchedQualifiers = concept.qualifiers.filter(candidateSet.contains)
        let missingQualifiers = concept.qualifiers.filter {
            !candidateSet.contains($0)
        }

        var extraTokenSet = Set(candidateTokens.filter { token in
            !concept.impliedTokens.contains(token)
                && !ignoredExtraTokens.contains(token)
                && !nonContentFormTokens.contains(token)
        })
        if candidateName.contains("without salt") {
            extraTokenSet.remove("salt")
        }
        if candidateName.contains("no added fat") {
            extraTokenSet.subtract(["added", "fat", "no"])
        }
        let extraTokens = Array(extraTokenSet).sorted()
        let strongExtras = extraTokens.filter(strongExtraTokens.contains)
        let ordinaryExtraCount = extraTokens.count - strongExtras.count

        var score = 42.0
        if candidateName == concept.normalized {
            score += 100
        } else if concept.aliases.contains(where: {
            normalize($0) == candidateName
        }) {
            score += 80
        }
        if containsPhrase(candidateName, phrase: concept.normalized) {
            score += 26
        }
        if concept.aliases.contains(where: {
            containsPhrase(candidateName, phrase: $0)
        }) {
            score += 26
        }
        if concept.tokenSet.isSubset(of: candidateSet) {
            score += 18
        }

        score += Double(matchedQualifiers.count) * 14
        score -= Double(missingQualifiers.count) * 24

        for form in concept.forms {
            if formMatches(form, candidateTokens: candidateSet) {
                score += 10
            } else {
                score -= 14
            }
        }
        score += formPreference(
            requestedForms: concept.forms,
            candidateTokens: candidateSet
        )

        if concept.composite {
            score += candidate.candidate.isRecipe ? 28 : -10
        } else if candidate.candidate.isRecipe {
            score -= 36
            if !concept.forms.isDisjoint(with: preferenceFormTokens) {
                score -= 42
            }
        }

        switch candidate.candidate.tier {
        case .classical: score += 9
        case .derived: score += 5
        case .estimated: break
        }

        score -= Double(strongExtras.count) * 50
        score -= Double(ordinaryExtraCount) * 4
        if let first = candidateTokens.first,
           !concept.impliedTokens.contains(first),
           !ignoredExtraTokens.contains(first),
           !nonContentFormTokens.contains(first) {
            score -= 20
        }
        if extraTokens.isEmpty { score += 6 }

        return PlannerResolutionDecision(
            candidate: candidate.candidate,
            score: score,
            headMatched: headMatched,
            matchedQualifiers: matchedQualifiers,
            missingQualifiers: missingQualifiers,
            extraTokens: extraTokens
        )
    }

    private static func hasSubstantiveHeadword(
        concept: PreparedConcept,
        candidate: PlannerPreparedResolutionCandidate
    ) -> Bool {
        if concept.tokenSet.isSubset(of: modifierOnlyFormTokens) {
            return false
        }

        func substantiveTokens(_ tokens: [String]) -> [String] {
            tokens.filter { token in
                concept.impliedTokens.contains(token)
                    || (
                        !ignoredExtraTokens.contains(token)
                            && !nonContentFormTokens.contains(token)
                    )
            }
        }

        let substantiveSegments = candidate.nameSegments.map(substantiveTokens)
        guard let firstSegment = substantiveSegments.first else { return false }

        func containsHead(_ tokens: [String]) -> Bool {
            let tokenSet = Set(tokens)
            return concept.headTokenSets.contains {
                !$0.isEmpty && $0.isSubset(of: tokenSet)
            }
        }

        let firstIsAnchor = !firstSegment.isEmpty
            && firstSegment.allSatisfy(concept.impliedTokens.contains)
            && containsHead(firstSegment)
        let secondIsWrappedAnchor: Bool = {
            guard candidate.nameSegments.first?.count == 1,
                  candidate.nameSegments.count > 1 else {
                return false
            }
            let secondSegment = candidate.nameSegments[1]
            let secondSet = Set(secondSegment)
            return !secondSet.isEmpty
                && secondSet.allSatisfy(concept.impliedTokens.contains)
                && containsHead(secondSegment)
                && !secondSet.isSubset(of: formVocabulary)
                && !secondSet.isSubset(of: ignoredExtraTokens)
        }()
        guard firstIsAnchor || secondIsWrappedAnchor else { return false }

        var substantiveSet = Set(substantiveSegments.flatMap { $0 })
        if secondIsWrappedAnchor {
            substantiveSet.subtract(firstSegment)
        }
        if candidate.normalizedName.contains("without salt") {
            substantiveSet.remove("salt")
        }
        if candidate.normalizedName.contains("no added fat") {
            substantiveSet.subtract(["added", "fat", "no"])
        }
        guard !substantiveSet.isEmpty else { return false }
        let explainedCount = substantiveSet
            .intersection(concept.impliedTokens)
            .count
        return explainedCount * 2 >= substantiveSet.count
    }

    private static func isCompositeConcept(_ concept: String) -> Bool {
        let tokens = Set(tokenized(concept))
        if !tokens.isDisjoint(with: recipeConceptTokens) {
            if tokens.contains("curry")
                && (tokens.contains("leaf") || tokens.contains("powder")) {
                return false
            }
            return true
        }
        return tokens.contains("dal") && tokens.contains("tadka")
    }

    private static func headPhrases(
        for tokens: [String],
        aliases: [String]
    ) -> [String] {
        var phrases = aliases
        if let head = headToken(for: tokens) {
            phrases.insert(head, at: 0)
        }
        return phrases
    }

    private static func headToken(for tokens: [String]) -> String? {
        guard !tokens.isEmpty else { return nil }
        guard tokens.count > 1, let last = tokens.last,
              trailingFormTokens.contains(last) else {
            return tokens.last
        }

        let genericModifiers: Set<String> = [
            "black", "brown", "green", "red", "white", "whole", "yellow"
        ]
        for token in tokens.dropLast().reversed()
            where !formVocabulary.contains(token)
                && !genericModifiers.contains(token) {
            return token
        }
        return last
    }

    private static func formMatches(
        _ form: String,
        candidateTokens: Set<String>
    ) -> Bool {
        switch form {
        case "fresh", "raw":
            return !candidateTokens.isDisjoint(with: ["fresh", "raw"])
        case "ground", "powder":
            return !candidateTokens.isDisjoint(with: ["ground", "powder"])
        case "cook":
            return !candidateTokens.isDisjoint(
                with: [
                    "bake", "boil", "cook", "fry", "grill", "roast", "steam"
                ]
            )
        case "dal":
            return !candidateTokens.isDisjoint(
                with: ["bean", "dal", "gram", "lentil", "pea"]
            )
        default:
            return candidateTokens.contains(form)
        }
    }

    private static func formPreference(
        requestedForms: Set<String>,
        candidateTokens: Set<String>
    ) -> Double {
        for form in requestedForms.sorted()
            where preferenceFormTokens.contains(form) {
            if formMatches(form, candidateTokens: candidateTokens) {
                return 14
            }
            if formConflicts(form, candidateTokens: candidateTokens) {
                return -28
            }
        }
        return 0
    }

    private static func formConflicts(
        _ requested: String,
        candidateTokens: Set<String>
    ) -> Bool {
        let rawForms: Set<String> = ["fresh", "raw"]
        let dryForms: Set<String> = ["dry", "ground", "powder"]
        let preservedForms: Set<String> = ["can", "freeze"]
        let specificCookedForms: Set<String> = [
            "bake", "boil", "fry", "grill", "roast", "steam"
        ]
        let cookedForms = specificCookedForms.union(["cook"])

        switch requested {
        case "fresh", "raw":
            return !candidateTokens.isDisjoint(
                with: dryForms.union(preservedForms).union(cookedForms)
            )
        case "dry", "ground", "powder":
            return !candidateTokens.isDisjoint(with: rawForms)
        case "can", "freeze":
            return !candidateTokens.isDisjoint(
                with: rawForms.union(preservedForms.subtracting([requested]))
            )
        case "cook":
            return !candidateTokens.isDisjoint(with: rawForms)
        case let method where specificCookedForms.contains(method):
            return !candidateTokens.isDisjoint(with: rawForms)
                || !candidateTokens.isDisjoint(
                    with: specificCookedForms.subtracting([method])
                )
        case "whole":
            return candidateTokens.contains("split")
        case "split":
            return candidateTokens.contains("whole")
        case "seed":
            return candidateTokens.contains("leaf")
        case "leaf":
            return candidateTokens.contains("seed")
        default:
            return false
        }
    }

    private static func aliasPhrases(
        for concept: String,
        ontologyAliases: [String: String]
    ) -> [String] {
        let tokens = Set(tokenized(concept))
        var aliases: [String] = []

        if tokens.contains("moong") {
            aliases.append(contentsOf: ["mung", "mung bean"])
        }
        if tokens.contains("basmati") {
            aliases.append("white basmati rice")
        }
        if tokens.contains("toor") || tokens.contains("arhar") {
            aliases.append(contentsOf: ["pigeon pea", "arhar"])
        }
        if tokens.contains("chana") {
            aliases.append(contentsOf: ["chickpea", "garbanzo", "bengal gram"])
        }
        if tokens.contains("urad") || tokens.contains("urd") {
            aliases.append(contentsOf: ["black gram", "urd"])
        }
        if tokens.contains("ghee") {
            aliases.append(contentsOf: ["butter oil", "clarified butter"])
        }
        if tokens.contains("paneer") { aliases.append("cheese") }
        if tokens.contains("yogurt") {
            aliases.append(contentsOf: ["yoghurt", "curd"])
        }
        if tokens.contains("cilantro") { aliases.append("coriander leaf") }
        if tokens.contains("chili") {
            aliases.append(contentsOf: ["cayenne", "red pepper"])
        }
        if concept.contains("ash gourd") {
            aliases.append(contentsOf: ["winter melon", "wax gourd"])
        }
        if concept.contains("bitter gourd") {
            aliases.append(contentsOf: ["bitter melon", "balsam pear"])
        }
        if tokens.contains("jaggery") || tokens.contains("gur") {
            aliases.append(contentsOf: ["raw sugar", "palm sugar", "gur"])
        }
        if concept.contains("whole wheat flour") {
            aliases.append("atta")
        }
        if tokens.contains("kitchari") {
            aliases.append(contentsOf: ["khichdi", "kichadi"])
        }
        if concept.contains("dal tadka") {
            aliases.append(contentsOf: ["dhal tadka", "lentil tadka"])
        }
        if tokens.contains("lemongrass") { aliases.append("lemon grass") }

        if let canonical = ontologyAliases[concept] {
            aliases.append(canonical)
        }

        var seen = Set<String>()
        return aliases.map(normalize).filter { seen.insert($0).inserted }
    }

    private static func containsPhrase(_ value: String, phrase: String) -> Bool {
        let valueTokens = tokenized(value)
        let phraseTokens = tokenized(phrase)
        guard !phraseTokens.isEmpty, phraseTokens.count <= valueTokens.count else {
            return false
        }
        if phraseTokens.count == 1 {
            return valueTokens.contains(phraseTokens[0])
        }
        for index in 0...(valueTokens.count - phraseTokens.count) {
            if Array(valueTokens[index..<(index + phraseTokens.count)])
                == phraseTokens {
                return true
            }
        }
        return false
    }

    private static func tokenized(_ value: String) -> [String] {
        normalize(value)
            .split(separator: " ")
            .map { canonicalToken(String($0)) }
            .filter { !$0.isEmpty && !stopTokens.contains($0) }
    }

    private static let stopTokens: Set<String> = [
        "a", "an", "and", "for", "from", "in", "made", "of", "or", "the",
        "with", "without"
    ]

    private static func canonicalToken(_ token: String) -> String {
        let irregular: [String: String] = [
            "almonds": "almond", "beans": "bean", "berries": "berry",
            "baked": "bake", "boiled": "boil", "cakes": "cake",
            "canned": "can", "chickpeas": "chickpea", "chilies": "chili",
            "chillies": "chili", "chilli": "chili", "chips": "chip",
            "cooked": "cook", "cookies": "cookie", "crisps": "crisp",
            "curries": "curry", "dried": "dry", "foods": "food",
            "fried": "fry", "fries": "fry", "frozen": "freeze",
            "grilled": "grill", "leaves": "leaf", "lentils": "lentil",
            "mixes": "mix", "noodles": "noodle", "nuts": "nut",
            "oats": "oat", "olives": "olive", "peas": "pea",
            "potatoes": "potato", "powdered": "powder",
            "prepared": "prepare", "roasted": "roast", "seeds": "seed",
            "spices": "spice", "sprouted": "sprout", "sprouts": "sprout",
            "steamed": "steam", "tomatoes": "tomato",
            "walnuts": "walnut", "whipped": "whip", "whipping": "whip"
        ]
        if let canonical = irregular[token] { return canonical }
        if token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") {
            return String(token.dropLast())
        }
        return token
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }
}
// MP3_TESTABLE_END

struct PlannerConceptExclusions: Sendable {
    static let none = PlannerConceptExclusions(
        concepts: [],
        explicitFoodIDs: [],
        exactTerms: [],
        seededFoodIDs: [],
        promptTerms: []
    )

    let concepts: Set<String>
    let explicitFoodIDs: Set<UUID>
    let exactTerms: Set<String>
    let seededFoodIDs: Set<UUID>
    let promptTerms: [String]

    func filtering(_ candidates: [CompactFoodItem]) -> [CompactFoodItem] {
        let candidateIDs = Set(candidates.map(\.id))
        let blockedIDs = blockedFoodIDs(in: candidates)
        let allowedIDs = candidateIDs.subtracting(blockedIDs)
        return candidates.filter { allowedIDs.contains($0.id) }
    }

    func excludes(_ food: CompactFoodItem) -> Bool {
        blockedFoodIDs(in: [food]).contains(food.id)
    }

    func excludes(
        foodID: UUID,
        allergens: Set<String>
    ) -> Bool {
        if explicitFoodIDs.contains(foodID) {
            return true
        }
        return concepts.contains { concept in
            isAuthoritativeMember(
                foodID: foodID,
                concept: concept,
                allergens: allergens
            )
        }
    }

    func excludesUnresolvedName(_ value: String) -> Bool {
        let normalized = AyurvedaRules.modifierTokens(value)
            .joined(separator: " ")
        if exactTerms.contains(normalized) {
            return true
        }
        guard let concept = FoodConcepts.shared.conceptID(for: value) else {
            return false
        }
        return concepts.contains(concept)
    }

    private func blockedFoodIDs(
        in candidates: [CompactFoodItem]
    ) -> Set<UUID> {
        let candidateIDs = Set(candidates.map(\.id))
        var blockedIDs = explicitFoodIDs.intersection(candidateIDs)

        for concept in concepts {
            let ontologyIDs = Set(
                FoodConcepts.shared.members(of: concept)
            )
            let plainUSDAIDs = candidateIDs.subtracting(seededFoodIDs)
            blockedIDs.formUnion(plainUSDAIDs.intersection(ontologyIDs))

            for food in candidates where seededFoodIDs.contains(food.id) {
                if seededSafetyMatches(food, concept: concept) {
                    blockedIDs.insert(food.id)
                }
            }
        }
        return blockedIDs
    }

    private func isAuthoritativeMember(
        foodID: UUID,
        concept: String,
        allergens: Set<String>
    ) -> Bool {
        if !seededFoodIDs.contains(foodID) {
            return FoodConcepts.shared.members(of: concept)
                .contains(foodID)
        }
        if concept == "meat" {
            return FoodConcepts.shared.members(of: concept).contains(foodID)
        }
        return seededSafetyMatches(allergens: allergens, concept: concept)
    }

    private func seededSafetyMatches(
        _ food: CompactFoodItem,
        concept: String
    ) -> Bool {
        if concept == "meat" {
            return FoodConcepts.shared.members(of: concept).contains(food.id)
        }
        return seededSafetyMatches(allergens: food.allergens, concept: concept)
    }

    private func seededSafetyMatches(
        allergens: Set<String>,
        concept: String
    ) -> Bool {
        switch concept {
        case "dairy":
            return allergens.contains("Milk")
        case "egg":
            return allergens.contains("Eggs")
        case "gluten":
            return allergens.contains {
                $0.hasPrefix("Cereals containing gluten")
            }
        case "soy":
            return allergens.contains("Soybeans")
        case "sesame":
            return allergens.contains("Sesame seeds")
        case "peanut":
            return allergens.contains("Peanuts")
        case "tree_nuts":
            return allergens.contains {
                $0 == "Nuts" || $0.hasPrefix("Nuts (")
            }
        case "fish":
            return allergens.contains("Fish")
        case "crustacean":
            return allergens.contains("Crustaceans")
        case "mollusc":
            return allergens.contains("Molluscs")
        case "shellfish":
            return !allergens.isDisjoint(
                with: ["Crustaceans", "Molluscs"]
            )
        default:
            // WE-8 has no equivalent canonical predicate for this concept.
            return false
        }
    }
}

@available(iOS 26.0, *)
public final class USDAWeeklyMealPlanner: Sendable {
    private let container: ModelContainer

    @MainActor
    private static var prewarmedIntentSession: LanguageModelSession?

    @MainActor
    private static func makeIntentSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Instructions {
            """
            Extract the user's meal-planning intent into the supplied schema.
            Copy food mentions in the user's own words. Do not suggest foods,
            database identifiers, gram weights, or calorie values the user did
            not explicitly provide. Put unsupported requests in `unmapped`.
            """
        })
    }

    /// Called from generation UI appearance so model loading is not paid after
    /// the user submits. Unavailable devices keep the deterministic fallback.
    @MainActor
    public static func prewarmIntentModel() {
        guard case .available = SystemLanguageModel.default.availability else {
            return
        }
        guard prewarmedIntentSession == nil else { return }
        let session = makeIntentSession()
        session.prewarm()
        prewarmedIntentSession = session
    }

    @MainActor
    private static func takeIntentSession() -> LanguageModelSession {
        let session = prewarmedIntentSession ?? makeIntentSession()
        prewarmedIntentSession = nil
        return session
    }

    public init(container: ModelContainer) {
        self.container = container
    }

    private struct IntentInterpretation {
        let atomicPrompts: [String]
        let includedFoods: [String]
        let excludedFoods: [String]
        let interpretedPrompts: InterpretedPrompts
        let caveat: String?
        let usedFallback: Bool
    }

    private func mappedAllergens(for tags: [AllergenTag]) -> Set<Allergen> {
        Set(tags.flatMap { tag -> [Allergen] in
            switch tag {
            case .dairy: return [.milk]
            case .gluten: return [.cerealsContainingGluten]
            case .treeNuts: return [.nuts]
            case .peanuts: return [.peanuts]
            case .soy: return [.soybeans]
            case .egg: return [.eggs]
            case .shellfish: return [.crustaceans, .molluscs]
            case .fish: return [.fish]
            case .sesame: return [.sesameSeeds]
            }
        })
    }

    private func allergenExclusionTerms(
        for allergens: Set<Allergen>
    ) -> [String] {
        let expanded = Allergen.expanded(from: allergens)
        var seen = Set<String>()
        return expanded
            .sorted { $0.rawValue < $1.rawValue }
            .flatMap { SearchKnowledgeBase.shared.allergenKeywords(for: $0) }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private func termIsEnforcedByAllergen(
        _ term: String,
        allergens: Set<Allergen>
    ) -> Bool {
        guard let mapped = SearchKnowledgeBase.shared
            .allergenForIngredient(term) else {
            return false
        }
        let enforced = Allergen.expanded(from: allergens)
        let termFamily = Allergen.expanded(from: [mapped])
        return !enforced.isDisjoint(with: termFamily)
    }

    @MainActor
    private func resolveIntentTerm(
        _ term: String,
        smartSearch: SmartFoodSearch3,
        onLog: (@Sendable (String) -> Void)?
    ) async -> String? {
        let canonical = FoodConcepts.shared.canonical(alias: term) ?? term
        let context = ConceptualMeal(
            name: "Intent",
            descriptiveTitle: "User request",
            components: []
        )
        return await resolveFoodConcept(
            smartSearch: smartSearch,
            conceptName: canonical,
            mealContext: context,
            relevantPrompts: [term],
            onLog: onLog
        )?.resolvedName
    }

    private func interpretationGoals(for request: ParsedRequest) -> InterpretedPrompts {
        var interpreted = InterpretedPrompts()

        if request.statedKcal > 0 {
            interpreted.qualitativeGoals.append(
                "Aim for about \(request.statedKcal) kcal per day"
            )
        }
        if let dosha = request.doshaFocus {
            interpreted.qualitativeGoals.append(
                "Use the named \(dosha.rawValue) dosha preference"
            )
        }
        if let agni = request.agni {
            interpreted.qualitativeGoals.append(
                "Use the named \(agni.rawValue) digestion preference"
            )
        }
        return interpreted
    }

    private func caveatLine(
        unresolved: [String],
        unmapped: [String],
        adjustments: [RequestSanitizer.Adjustment]
    ) -> String? {
        var clauses: [String] = []
        if !unresolved.isEmpty {
            clauses.append(
                "I could not resolve "
                    + unresolved.map { "“\($0)”" }.joined(separator: ", ")
            )
        }
        if !unmapped.isEmpty {
            clauses.append(
                "I could not apply "
                    + unmapped.map { "“\($0)”" }.joined(separator: ", ")
            )
        }
        clauses.append(contentsOf: adjustments.map {
            $0.message.trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
        })
        guard !clauses.isEmpty else { return nil }
        return "Planner note: " + clauses.joined(separator: "; ") + "."
    }

    @MainActor
    private func interpretIntent(
        prompts: [String],
        profile: Profile,
        smartSearch: SmartFoodSearch3,
        onLog: (@Sendable (String) -> Void)?
    ) async -> IntentInterpretation {
        let availability = SystemLanguageModel.default.availability
        let modelAvailable: Bool
        switch availability {
        case .available:
            modelAvailable = true
        case .unavailable(let reason):
            modelAvailable = false
            emitLog(
                "  -> Intent parser fallback: \(String(describing: reason)).",
                onLog: onLog
            )
        @unknown default:
            modelAvailable = false
            emitLog(
                "  -> Intent parser fallback: unknown availability.",
                onLog: onLog
            )
        }

        let outcome = await MealPlanIntentCoordinator.parse(
            prompts: prompts,
            modelAvailable: modelAvailable,
            modelResponse: { combined in
                let session = Self.takeIntentSession()
                if PlannerTelemetry.isEnabled {
                    await PlannerTelemetry.shared.noteSession(
                        site: "mealPlanIntentParse"
                    )
                }
                let response = try await session.respond(
                    to: combined,
                    generating: PlanRequest.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(sampling: .greedy)
                )
                return ParsedRequest(response.content)
            },
            onModelCall: { ok, elapsed in
                if PlannerTelemetry.isEnabled {
                    await PlannerTelemetry.shared.noteRespond(
                        site: "mealPlanIntentParse",
                        ok: ok,
                        ms: elapsed
                    )
                }
            }
        )

        let maintenance = Int(TDEECalculator.calculate(for: profile).rounded())
        let sanitized = RequestSanitizer.sanitize(
            outcome.request,
            computedMaintenanceKcal: maintenance
        )
        let request = sanitized.request
        let allergens = mappedAllergens(for: request.allergens)
        var unresolved: [String] = []
        var includedFoods: [String] = []
        var excludedFoods = allergenExclusionTerms(for: allergens)

        for term in request.prefer {
            if let resolved = await resolveIntentTerm(
                term,
                smartSearch: smartSearch,
                onLog: onLog
            ) {
                includedFoods.append(resolved)
            } else {
                unresolved.append(term)
            }
        }
        for term in request.avoid {
            if termIsEnforcedByAllergen(term, allergens: allergens) {
                continue
            }
            if let resolved = await resolveIntentTerm(
                term,
                smartSearch: smartSearch,
                onLog: onLog
            ) {
                excludedFoods.append(resolved)
            } else {
                unresolved.append(term)
            }
        }

        func deduplicated(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.filter { seen.insert($0.lowercased()).inserted }
        }

        let cleanPrompts = prompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let caveat = caveatLine(
            unresolved: deduplicated(unresolved),
            unmapped: request.unmapped,
            adjustments: sanitized.adjustments
        )
        emitLog(
            "  -> Intent parser: "
                + (outcome.usedFallback ? "deterministic fallback" : "one guided call"),
            onLog: onLog
        )
        if let caveat {
            emitLog("  -> \(caveat)", onLog: onLog)
        }
        return IntentInterpretation(
            atomicPrompts: cleanPrompts,
            includedFoods: deduplicated(includedFoods),
            excludedFoods: deduplicated(excludedFoods),
            interpretedPrompts: interpretationGoals(for: request),
            caveat: caveat,
            usedFallback: outcome.usedFallback
        )
    }
    
    private func splitIntoAtomicPrompts(_ prompts: [String]) -> [String] {
        var atoms: [String] = []
        let seps = CharacterSet.newlines.union(CharacterSet(charactersIn: ";|"))
        for p in prompts {
            for raw in p.components(separatedBy: seps) {
                var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                line = line.replacingOccurrences(of: #"^\s*([\-–—•\*]+)\s*"#,
                                                 with: "",
                                                 options: .regularExpression)
                if line.hasSuffix(".") { line.removeLast() }
                if !line.isEmpty { atoms.append(line) }
            }
        }
        var seen = Set<String>()
        return atoms.filter { seen.insert($0.lowercased()).inserted }
    }
    
    
    @MainActor
    private func aiSplitIntoAtomicPrompts(
        _ prompts: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        guard !prompts.isEmpty else { return [] }
        
        @MainActor
        func aiSplitSinglePrompt(_ single: String) async -> [String] {
            let instructions = Instructions {
                """
                You split messy, compound meal-planning requests into atomic, standalone directives.
                RULES:
                - Each unit MUST express exactly one requirement (frequency, inclusion/exclusion, replacement, meal-time).
                - Preserve negations (“no”, “avoid”, “without”) and numeric patterns (“once every 3 days”, “daily”).
                - Map time-of-day to meals: morning→Breakfast, noon→Lunch, evening→Dinner.
                - If a line has multiple 'and/;/-/•' parts, split into multiple units.
                - Keep wording concise; do not add new constraints; keep the user's intent.
                - Return at most 16 units.
                """
            }
            let session = LanguageModelSession(instructions: instructions)
            if PlannerTelemetry.isEnabled {
                await PlannerTelemetry.shared.noteSession(site: "aiSplitSinglePrompt")
            }
            let prompt = """
            Split the following user text into atomic directives:
            
            \(single)
            """
            
            var telemetryRespondStartedAt: UInt64?
            var telemetryRespondRecorded = false
            do {
                try Task.checkCancellation()
                if PlannerTelemetry.isEnabled {
                    telemetryRespondStartedAt = DispatchTime.now().uptimeNanoseconds
                }
                let resp = try await session.respond(
                    to: prompt,
                    generating: AIAtomicPromptsResponse.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(sampling: .greedy)
                )
                if let startedAt = telemetryRespondStartedAt {
                    await PlannerTelemetry.shared.noteRespond(
                        site: "aiSplitSinglePrompt",
                        ok: true,
                        ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                    )
                    telemetryRespondRecorded = true
                }
                try Task.checkCancellation()
                var atoms = resp.content.directives
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                atoms = atoms.map { s in
                    var x = s
                    if x.hasSuffix(".") { x.removeLast() }
                    if let first = x.first { x.replaceSubrange(x.startIndex...x.startIndex, with: String(first).uppercased()) }
                    return x
                }
                try Task.checkCancellation()
                var seen = Set<String>()
                atoms = atoms.filter { seen.insert($0.lowercased()).inserted }
                atoms = Array(atoms.prefix(16))
                try Task.checkCancellation()
                
                return filterMetaDirectives(atoms)
            } catch {
                if let startedAt = telemetryRespondStartedAt, !telemetryRespondRecorded {
                    await PlannerTelemetry.shared.noteRespond(
                        site: "aiSplitSinglePrompt",
                        ok: false,
                        ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                    )
                }
                onLog?("    - ⚠️ Atomic split via AI failed for prompt: '\(single)'. Falling back to heuristic.")
                return filterMetaDirectives(splitIntoAtomicPrompts([single]))
            }
        }
        
        var all: [String] = []
        for raw in prompts {
            let perPrompt = await aiSplitSinglePrompt(raw)
            all.append(contentsOf: perPrompt)
        }
        var seen = Set<String>()
        let deduped = all.filter { seen.insert($0.lowercased()).inserted }
        let finalAtoms = Array(deduped.prefix(16))
        if !finalAtoms.isEmpty { onLog?("   -> Atomic prompts (AI): \(finalAtoms)") }
        return finalAtoms
    }
    
    @MainActor
    private func aiExtractRequestedFoods(from prompts: [String], onLog: (@Sendable (String) -> Void)?) async -> (included: [String], excluded: [String]) {
        
        guard !prompts.isEmpty else { return (included: [], excluded: []) }
        
        let session = LanguageModelSession(instructions: Instructions {
            """
            You extract and categorize food names from user prompts.
            - From the user's prompts, create two lists:
              1. `includedFoods`: Concrete food names explicitly asked to be INCLUDED.
              2. `excludedFoods`: Concrete food names explicitly asked to be EXCLUDED or AVOIDED.
            - Ignore frequencies, meals, numbers, and nutrition goals for this task.
            - Normalize all names to simple USDA-like forms without portions.
            """
        })
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.noteSession(site: "aiExtractRequestedFoods")
        }
        
        let prompt = """
        Extract both included and excluded food names the user mentioned.
        
        PROMPTS:
        \(prompts.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        var telemetryRespondStartedAt: UInt64?
        var telemetryRespondRecorded = false
        do {
            try Task.checkCancellation()
            if PlannerTelemetry.isEnabled {
                telemetryRespondStartedAt = DispatchTime.now().uptimeNanoseconds
            }
            let resp = try await session.respond(to: prompt, generating: AIFoodExtractionResponse.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy))
            if let startedAt = telemetryRespondStartedAt {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiExtractRequestedFoods",
                    ok: true,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
                telemetryRespondRecorded = true
            }
            try Task.checkCancellation()
            var seenIncluded = Set<String>()
            let cleanedIncluded: [String] = resp.content.includedFoods.compactMap { raw in
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let key = name.lowercased()
                guard !seenIncluded.contains(key) else { return nil }
                seenIncluded.insert(key)
                return name
            }
            try Task.checkCancellation()
            var seenExcluded = Set<String>()
            let cleanedExcluded: [String] = resp.content.excludedFoods.compactMap { raw in
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let key = name.lowercased()
                guard !seenExcluded.contains(key) else { return nil }
                seenExcluded.insert(key)
                return name
            }
            try Task.checkCancellation()
            let includedLower = Set(cleanedIncluded.map { $0.lowercased() })
            let prunedExcluded: [String] = cleanedExcluded.filter { !includedLower.contains($0.lowercased()) }
            let dropped = cleanedExcluded.filter { includedLower.contains($0.lowercased()) }
            
            try Task.checkCancellation()
            
            if !cleanedIncluded.isEmpty { onLog?("  -> Requested foods to include: \(cleanedIncluded)") }
            if !prunedExcluded.isEmpty { onLog?("  -> Requested foods to exclude: \(prunedExcluded)") }
            if !dropped.isEmpty {
                onLog?("  -> Note: removed from global excludes due to simultaneous inclusion: \(dropped)")
            }
            
            try Task.checkCancellation()
            
            return (included: cleanedIncluded, excluded: prunedExcluded)
            
        } catch {
            if let startedAt = telemetryRespondStartedAt, !telemetryRespondRecorded {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiExtractRequestedFoods",
                    ok: false,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
            }
            onLog?("    - ⚠️ Food-name extraction failed: \(error.localizedDescription). Falling back to heuristic.")
        }
        
        let includedResults = [String]()
        let excludedResults = [String]()
        
        if !includedResults.isEmpty { onLog?("  -> Included foods (heuristic): \(includedResults)") }
        if !excludedResults.isEmpty { onLog?("  -> Excluded foods (heuristic): \(excludedResults)") }
        return (included: includedResults, excluded: excludedResults)
    }
    
    @MainActor
    private func aiFixAtomsAndFoods(
        originalPrompts: [String],
        atoms: [String],
        included: [String],
        excluded: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> (directives: [String], included: [String], excluded: [String]) {
        guard !originalPrompts.isEmpty else { return (atoms, included, excluded) }
        
        let instructions = Instructions {
            """
            You reconcile a list of atomic meal-planning directives with the user's raw prompts and the extracted food lists.
            GOALS:
            - Preserve the user's explicit foods EXACTLY as written in the raw prompts unless they are clear plural or casing variants. Do NOT replace or substitute them with different foods.
            - If a food is negated in any raw prompt (using terms like 'no', 'avoid', or 'without'), ensure it appears in the excludedFoods list unless it is also explicitly required for specific meals or days.
            - If a food is explicitly requested positively in any raw prompt, ensure it appears in includedFoods.
            - Correct any mistaken substitutions in `directives` so they align with the actual foods from the raw prompts.
            - Keep directives concise and limited to a maximum of 16 total. Omit meta or vague items.
            OUTPUT STRICTLY the JSON schema fields: fixedDirectives, includedFoods, excludedFoods. No extra text.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.noteSession(site: "aiFixAtomsAndFoods")
        }
        let prompt = """
        RAW_PROMPTS:\n\(originalPrompts.map { "- \($0)" }.joined(separator: "\n"))
        
        CURRENT_ATOMIC_DIRECTIVES:\n\(atoms.map { "- \($0)" }.joined(separator: "\n"))
        
        CURRENT_INCLUDED_FOODS:\n\(included)
        CURRENT_EXCLUDED_FOODS:\n\(excluded)
        """
        
        var telemetryRespondStartedAt: UInt64?
        var telemetryRespondRecorded = false
        do {
            try Task.checkCancellation()
            if PlannerTelemetry.isEnabled {
                telemetryRespondStartedAt = DispatchTime.now().uptimeNanoseconds
            }
            let resp = try await session.respond(
                to: prompt,
                generating: AIAtomsAndFoodsFixResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            if let startedAt = telemetryRespondStartedAt {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiFixAtomsAndFoods",
                    ok: true,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
                telemetryRespondRecorded = true
            }
            try Task.checkCancellation()
            var dirs = resp.content.fixedDirectives
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            dirs = dirs.map { s in
                var x = s
                if x.hasSuffix(".") { x.removeLast() }
                if let first = x.first { x.replaceSubrange(x.startIndex...x.startIndex, with: String(first).uppercased()) }
                return x
            }
            try Task.checkCancellation()
            var seen = Set<String>()
            dirs = dirs.filter { seen.insert($0.lowercased()).inserted }
            dirs = Array(dirs.prefix(16))
            try Task.checkCancellation()
            func cleanFoods(_ arr: [String]) -> [String] {
                var out: [String] = []
                var s = Set<String>()
                for r in arr {
                    let n = r.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !n.isEmpty else { continue }
                    let k = n.lowercased()
                    if s.insert(k).inserted { out.append(n) }
                }
                return out
            }
            try Task.checkCancellation()
            let inc = cleanFoods(resp.content.includedFoods)
            let exc0 = cleanFoods(resp.content.excludedFoods)
            let incSet = Set(inc.map { $0.lowercased() })
            let exc = exc0.filter { !incSet.contains($0.lowercased()) }
            try Task.checkCancellation()
            if !dirs.isEmpty { onLog?("   -> Atomic prompts (fixed): \(dirs)") }
            if !inc.isEmpty { onLog?("   -> Included foods (fixed): \(inc)") }
            if !exc.isEmpty { onLog?("   -> Excluded foods (fixed): \(exc)") }
            
            return (dirs, inc, exc)
        } catch {
            if let startedAt = telemetryRespondStartedAt, !telemetryRespondRecorded {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiFixAtomsAndFoods",
                    ok: false,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
            }
            onLog?("    - ⚠️ Post-fix AI pass failed: \(error.localizedDescription). Keeping previous atoms/foods.")
            return (atoms, included, excluded)
        }
    }
    
    private func emitLog(_ message: String, onLog: (@Sendable (String) -> Void)?) {
        onLog?(message)
    }
    
    @MainActor
    private func saveProgress(
        jobID: PersistentIdentifier,
        progress: MealPlanGenerationProgress,
        onLog: (@Sendable (String) -> Void)?
    ) async {
        // ако задачата е отменена – не записваме
        if Task.isCancelled {
            emitLog("⏹️ [Progress] Task cancelled; skip meal plan progress save.", onLog: onLog)
            return
        }

        do {
            // fresh контекст за писане (избягва сблъсък с UI/mainContext)
            let writeCtx = ModelContext(self.container)

            // важно: ре-фетч по persistentModelID (НЕ context.model(for:))
            let fd = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.persistentModelID == jobID })
            guard let job = try writeCtx.fetch(fd).first else {
                emitLog("⚠️ [Progress] Could not find job with ID \(jobID) to save progress (deleted?).", onLog: onLog)
                return
            }

            // последна проверка за отмяна точно преди сетъра
            try Task.checkCancellation()

            let data = try JSONEncoder().encode(progress)
            job.intermediateResultData = data
            try writeCtx.save()

            emitLog("💾 [Progress] Meal plan progress saved.", onLog: onLog)
        } catch is CancellationError {
            emitLog("⏹️ [Progress] Cancelled mid-save; skipping meal plan progress.", onLog: onLog)
        } catch {
            emitLog("❌ [Progress] Failed to save progress: \(error.localizedDescription)", onLog: onLog)
        }
    }

    
    @MainActor
    public func fillPlanDetails(
        jobID: PersistentIdentifier,
        profileID: PersistentIdentifier,
        daysAndMeals: [Int: [String]],
        prompts: [String]?,
        mealTimings: [String: Date]?,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> MealPlanPreview {
        if PlannerTelemetry.isEnabled {
            let mealCount = daysAndMeals.values.reduce(0) { $0 + $1.count }
            let promptLabel = (prompts ?? []).joined(separator: " | ")
            await PlannerTelemetry.shared.reset(
                label: "days=\(daysAndMeals.count);meals=\(mealCount);prompts=\(promptLabel)"
            )
        }
        do {
        // --- START OF CHANGE (2/3): Load or initialize progress ---
        let ctx = ModelContext(self.container)
        emitLog("🚫 AyurvedaGate: AyurvedaGate active, 0 candidates filtered", onLog: onLog)
        guard let job = ctx.model(for: jobID) as? AIGenerationJob else {
            throw NSError(domain: "MealPlannerError", code: 404, userInfo: [NSLocalizedDescriptionKey: "AIGenerationJob not found."])
        }
        
        var progress: MealPlanGenerationProgress
        if let data = job.intermediateResultData, let loadedProgress = try? JSONDecoder().decode(MealPlanGenerationProgress.self, from: data) {
            progress = loadedProgress
            emitLog("🔄 Resuming meal plan generation.", onLog: onLog)
        } else {
            progress = MealPlanGenerationProgress()
            emitLog("  -> No existing progress found. Starting from scratch.", onLog: onLog)
        }
        
        guard let profile = ctx.model(for: profileID) as? Profile else {
            throw NSError(domain: "MealPlannerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile not found."])
        }
        try Task.checkCancellation()
        // --- END OF CHANGE (2/3) ---
        
        // REPLACED: Use SmartFoodSearch3
        let smartSearch = SmartFoodSearch3(container: self.container)
        smartSearch.loadData() // Populate in-memory index
        try Task.checkCancellation()
        
        // --- Checkpoint 1: Interpretation ---
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.beginStage("interpretation")
        }
        let atomicPrompts: [String]
        var includedFoods: [String]
        let excludedFoods: [String]
        var interpretedPrompts: InterpretedPrompts
        let interpretationCaveat: String?
        
        if let cached = progress.interpretedPrompts, let atoms = progress.atomicPrompts, let incl = progress.includedFoods, let excl = progress.excludedFoods {
            atomicPrompts = atoms
            includedFoods = incl
            excludedFoods = excl
            interpretedPrompts = cached
            interpretationCaveat = progress.interpretationCaveat
            emitLog("  -> ✅ Checkpoint 1: Using cached interpretation results.", onLog: onLog)
        } else {
            let interpretation = await interpretIntent(
                prompts: prompts ?? [],
                profile: profile,
                smartSearch: smartSearch,
                onLog: onLog
            )
            try Task.checkCancellation()

            atomicPrompts = interpretation.atomicPrompts
            includedFoods = interpretation.includedFoods
            excludedFoods = interpretation.excludedFoods
            interpretedPrompts = interpretation.interpretedPrompts
            interpretationCaveat = interpretation.caveat
            
            progress.atomicPrompts = atomicPrompts
            progress.includedFoods = includedFoods
            progress.excludedFoods = excludedFoods
            progress.interpretedPrompts = interpretedPrompts
            progress.interpretationCaveat = interpretationCaveat
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
            emitLog("  -> ✅ Checkpoint 1: Interpretation complete and saved.", onLog: onLog)
        }
        
        logInterpretedGoals(interpretedPrompts, onLog: onLog)
        try Task.checkCancellation()
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.endStage("interpretation")
        }
        
        // --- Checkpoint 2: deterministic assembly ---
        // MP-5 deliberately has no FoundationModels call between this stage
        // boundary and the returned preview.
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.beginStage("deterministic_assembly")
        }
        let hardExclusions = await makePlannerExclusions(
            extractedTerms: excludedFoods,
            structuralRequests: interpretedPrompts.structuralRequests,
            smartSearch: smartSearch,
            context: ctx
        )
        try Task.checkCancellation()

        var placementTopics = buildMustContainRules(
            structuralRequests: interpretedPrompts.structuralRequests,
            daysAndMeals: daysAndMeals,
            onLog: onLog
        )
        let explicitlyPlaced = Set(placementTopics.map {
            $0.topic.lowercased()
        })
        let orderedSlots = daysAndMeals.keys.sorted().flatMap { day in
            (daysAndMeals[day] ?? []).map { (day, $0) }
        }
        for (index, included) in includedFoods.enumerated()
        where !explicitlyPlaced.contains(included.lowercased())
            && !orderedSlots.isEmpty {
            let slot = orderedSlots[index % orderedSlots.count]
            placementTopics.append(
                MustContainRule(
                    day: slot.0,
                    meal: slot.1,
                    topic: included
                )
            )
        }

        var solverPlacements: [MP5MustContainRule] = []
        for placement in placementTopics {
            guard let candidate = await resolveCompactCandidate(
                named: placement.topic,
                smartSearch: smartSearch
            ) else {
                throw MP5SolverFailure.infeasible(
                    constraint: "structural placement '\(placement.topic)' did not resolve to a catalogue food"
                )
            }
            solverPlacements.append(
                MP5MustContainRule(
                    day: placement.day,
                    meal: placement.meal,
                    foodID: candidate.id
                )
            )
        }
        try Task.checkCancellation()
        let assembly = try await MP5PlannerAdapter(
            container: container
        ).solve(
            profile: profile,
            daysAndMeals: daysAndMeals,
            prompts: prompts ?? [],
            interpretedPrompts: interpretedPrompts,
            exclusions: hardExclusions,
            placements: solverPlacements,
            mealTimings: mealTimings,
            onLog: onLog
        )
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.endStage("deterministic_assembly")
            await PlannerTelemetry.shared.beginStage("narration")
        }
        let narration = await MP6MealPlanNarrator.narrate(
            facts: assembly.narrationFacts,
            onLog: onLog
        )
        try Task.checkCancellation()
        var narratedDays = assembly.preview.days
        for narratedTitle in narration.titles {
            guard let dayIndex = narratedDays.firstIndex(where: {
                $0.dayIndex == narratedTitle.day
            }),
            narratedDays[dayIndex].meals.indices.contains(
                narratedTitle.slotIndex
            ) else {
                continue
            }
            narratedDays[dayIndex].meals[
                narratedTitle.slotIndex
            ].descriptiveTitle = narratedTitle.title
        }
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.endStage("narration")
        }
        let preview = MealPlanPreview(
            startDate: assembly.preview.startDate,
            prompt: assembly.preview.prompt,
            days: narratedDays,
            minAgeMonths: assembly.preview.minAgeMonths,
            interpretationCaveat: interpretationCaveat
        )

        emitLog("✅ Final Meal Plan Preview Prepared. Clearing intermediate progress.", onLog: onLog)
        job.intermediateResultData = nil
        try ctx.save()
        if PlannerTelemetry.isEnabled {
            let telemetrySummary = await PlannerTelemetry.shared.summary()
            emitLog(telemetrySummary, onLog: onLog)
        }
        return preview
        } catch {
            if PlannerTelemetry.isEnabled {
                let telemetrySummary = await PlannerTelemetry.shared.summary()
                emitLog(telemetrySummary, onLog: onLog)
            }
            throw error
        }
    }
    
    public func savePlan(from preview: MealPlanPreview, for profileID: PersistentIdentifier, onLog: (@Sendable (String) -> Void)?) async throws -> MealPlan {
        let ctx = ModelContext(self.container)
        guard let profile = ctx.model(for: profileID) as? Profile else {
            throw NSError(domain: "MealPlannerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile not found."])
        }
        let newPlan = MealPlan(name: "AI Plan \(Date().formatted(date: .numeric, time: .omitted))", profile: profile)
        var planDays: [MealPlanDay] = []
        for previewDay in preview.days {
            try Task.checkCancellation()
            let day = MealPlanDay(dayIndex: previewDay.dayIndex)
            var planMeals: [MealPlanMeal] = []
            for previewMeal in previewDay.meals {
                try Task.checkCancellation()
                let meal = MealPlanMeal(mealName: previewMeal.name)
                meal.descriptiveAIName = previewMeal.descriptiveTitle
                var entries: [MealPlanEntry] = []
                for previewItem in previewMeal.items {
                    let itemName = previewItem.name
                    let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate<FoodItem> { item in
                        item.name == itemName && !item.isUserAdded
                    })
                    if let foodItem = (try? ctx.fetch(descriptor))?.first {
                        let newEntry = MealPlanEntry(food: foodItem, grams: previewItem.grams, meal: meal)
                        entries.append(newEntry)
                    }
                }
                meal.entries = entries
                planMeals.append(meal)
            }
            day.meals = planMeals
            planDays.append(day)
        }
        newPlan.days = planDays
        ctx.insert(newPlan)
        try ctx.save()
        onLog?("✅ Successfully saved MealPlan from preview.")
        return newPlan
    }

    private func aiInterpretUserPrompts(
        prompts: [String],
        includedFoods: [String],
        excludedFoods: [String],
        daysAndMeals: [Int: [String]],
        smartSearch: SmartFoodSearch3, // Updated Type
        onLog: (@Sendable (String) -> Void)?
    ) async -> InterpretedPrompts {
        guard !prompts.isEmpty else { return InterpretedPrompts() }
        onLog?("  -> Interpreting user prompts with AI one-by-one...")
        
        var interpreted = InterpretedPrompts()
        
        for prompt in prompts {
            let session = LanguageModelSession(instructions: Instructions {
                """
                           CRITICAL RULES
                           1) Choose exactly ONE category that best fits the prompt.
                           2) Prioritize numericalGoal or frequencyRequest when applicable. Otherwise use structuralRequest; use qualitativeGoal only if nothing else fits.
                           3) frequencyRequest rules:
                              - "daily"  -> n must be 0.
                              - "per_n_days" -> n is an integer number of days (e.g., every 2 days => n=2).
                              - "once"   -> n must be 0.
                              - Only set "meal" when the prompt clearly mentions a specific meal (breakfast/lunch/dinner or synonyms). Otherwise set "meal" to "any".
                           4) Map time-of-day synonyms to meals:
                              - morning/breakfast/for breakfast => "Breakfast"
                              - noon/lunchtime/for lunch        => "Lunch"
                              - evening/dinnertime/for dinner   => "Dinner"
                           5) If the prompt mentions specific days (e.g., “on Day 1”, “on Monday”, “weekends”), prefer structuralRequest and encode the constraint in natural language (do NOT invent new JSON fields).
                           6) If the prompt uses negation (“no”, “avoid”, “without”, “exclude”), use structuralRequest that begins with “Exclude …”.

                           EXAMPLES (General)
                           - "I want to have no more than 50 grams of fats per day"
                             => { "numericalGoal": { "nutrient": "fat", "constraint": "lessThan", "value": 50 } }
                           - "add a dessert to every lunch"
                             => { "structuralRequest": "Add a dessert to every lunch" }
                           - "I would like to eat foods rich in iron"
                             => { "qualitativeGoal": "Prioritize foods rich in iron" }
                           - "twice a week have salmon for dinner"
                             => { "frequencyRequest": { "topic": "salmon", "frequency": "per_n_days", "n": 3, "meal": "Dinner" } }
                           - "every other day eat yogurt in the morning"
                             => { "frequencyRequest": { "topic": "yogurt", "frequency": "per_n_days", "n": 2, "meal": "Breakfast" } }
                           - "no beef on weekends"
                             => { "structuralRequest": "Exclude beef on weekends" }
                           - "No alcohol consumption"
                             => { "structuralRequest": "Exclude alcohol on all days" }
                           - "avoid tuna except on Mondays"
                             => { "structuralRequest": "Exclude tuna on all days except Monday" }
                           - "replace white bread with whole grain bread"
                             => { "structuralRequest": "Replace white bread with whole grain bread" }
                           - "only chicken for dinner on Day 1"
                             => { "structuralRequest": "On Day 1, include only chicken at Dinner" }
                           - "skip pork at lunch"
                             => { "structuralRequest": "Exclude pork at Lunch" }
                           - "limit bacon to at most once every 3 days"
                             => { "frequencyRequest": { "topic": "bacon", "frequency": "per_n_days", "n": 3, "meal": "any" } }
                           - "have eggs once"
                             => { "frequencyRequest": { "topic": "eggs", "frequency": "once", "n": 0, "meal": "any" } }
                           - "I want low sodium overall"
                             => { "qualitativeGoal": "Prefer low sodium choices" }
                """
            })
            if PlannerTelemetry.isEnabled {
                await PlannerTelemetry.shared.noteSession(site: "aiInterpretUserPrompts")
            }
            
            let promptForAI = """
            You are an expert prompt analyzer. Analyze ONLY the SINGLE user prompt below and return an object that fits ONE (and only one) of these categories:
            
            - numericalGoal: { "nutrient": "<string>", "constraint": "lessThan|greaterThan|equalTo|range", "value": <number or [min,max]> }
            - frequencyRequest: { "topic": "<food or concept>", "frequency": "daily|per_n_days|once", "n": <int>, "meal": "Breakfast|Lunch|Dinner|any" }
            - structuralRequest: "<short imperative sentence describing what to add/remove/limit/replace, possibly with day/weekday constraints>"
            - qualitativeGoal: "<concise preference if nothing else fits>"
            
            Now, analyze ONLY the following user prompt:
            
            USER PROMPT: "\(prompt)"
            """

            var telemetryRespondStartedAt: UInt64?
            var telemetryRespondRecorded = false
            do {
                try Task.checkCancellation()
                if PlannerTelemetry.isEnabled {
                    telemetryRespondStartedAt = DispatchTime.now().uptimeNanoseconds
                }
                let response = try await session.respond(to: promptForAI, generating: AIInterpretedPrompt.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy))
                if let startedAt = telemetryRespondStartedAt {
                    await PlannerTelemetry.shared.noteRespond(
                        site: "aiInterpretUserPrompts",
                        ok: true,
                        ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                    )
                    telemetryRespondRecorded = true
                }
                try Task.checkCancellation()
                await processSingleAIInterpretation(
                    response.content,
                    into: &interpreted,
                    daysAndMeals: daysAndMeals,
                    excludedFoods: excludedFoods,
                    smartSearch: smartSearch,
                    onLog: onLog
                )
                try Task.checkCancellation()
            } catch {
                if let startedAt = telemetryRespondStartedAt, !telemetryRespondRecorded {
                    await PlannerTelemetry.shared.noteRespond(
                        site: "aiInterpretUserPrompts",
                        ok: false,
                        ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                    )
                }
                onLog?("    - ⚠️ AI interpretation for prompt '\(prompt)' failed: \(error.localizedDescription). Treating as qualitative goal.")
                interpreted.qualitativeGoals.append(prompt)
            }
        }
        
        return interpreted
    }
    
    private func extractBreakfastRecurringTopic(from text: String) -> String? {
        let l = text.lowercased()
        let patterns = [
            #"(?:eat|include|have)\s+(?:different\s+types\s+of\s+)?([a-zA-Z][a-zA-Z\s]+?)\s+(?:every\s+)?morning"#,
            #"(?:eat|include|have)\s+(?:different\s+types\s+of\s+)?([a-zA-Z][a-zA-Z\s]+?)\s+for\s+breakfast"#
        ]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(l.startIndex..<l.endIndex, in: l)
                if let m = r.firstMatch(in: l, range: range), m.numberOfRanges >= 2,
                   let gr = Range(m.range(at: 1), in: l) {
                    var raw = String(l[gr]).trimmingCharacters(in: .whitespaces)
                    let trailingStops = [" in the", " at the", " the", " in", " at", " for", " of"]
                    for stop in trailingStops {
                        if raw.hasSuffix(stop) {
                            raw.removeSubrange(raw.index(raw.endIndex, offsetBy: -stop.count)..<raw.endIndex)
                            raw = raw.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    var tokens = raw.split(separator: " ").map(String.init)
                    let stopwords: Set<String> = ["in","the","at","for","of"]
                    tokens = tokens.filter { !stopwords.contains($0) }
                    if tokens.isEmpty { continue }
                    let head: String
                    if tokens.count >= 2 {
                        head = tokens.suffix(2).joined(separator: " ")
                    } else {
                        head = tokens.last!
                    }
                    let cleaned = head.capitalized
                    return cleaned
                }
            }
        }
        return nil
    }
    private func isPureSchedulingInstruction(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^(breakfast|lunch|dinner)\s+should\s+occur\s+at\s+\w+"#,
            #"^(have\s+)?(breakfast|lunch|dinner)\s+at\s+\w+"#,
            #"^(schedule|timing|time)\s+for\s+(breakfast|lunch|dinner)\b"#
        ]
        for p in patterns {
            if t.range(of: p, options: .regularExpression) != nil { return true }
        }
        return false
    }
    
    private func processSingleAIInterpretation(
        _ aiResponse: AIInterpretedPrompt,
        into interpreted: inout InterpretedPrompts,
        daysAndMeals: [Int: [String]],
        excludedFoods: [String],
        smartSearch: SmartFoodSearch3, // Updated Type
        onLog: (@Sendable (String) -> Void)?
    ) async {
        func shouldDropMetaInstruction(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t.isEmpty { return false }
            let patterns: [String] = [
                #"^no other (menu|menus|options|cuisines?)$"#,
                #"^no other menu options$"#,
                #"^no other (menu\s+options|cuisine\s+options)$"#,
                #".*\bno other (menu|menus|menu\s+options|cuisine|cuisines|options)\b.*"#,
                #"^do not include other (menu|menus|cuisines?)$"#,
                #"^avoid other (menu|menus|cuisines?)$"#,
                #"^(keep|stick)\s+to\s+(this|the)\s+(menu|cuisine)$"#,
                #"^exclusively\s+(this|the)\s+(menu|cuisine)$"#,
                #"^(only|just)\s+(italian|this|the)\s+(menu|cuisine)$"#,
                #"^only\s+italian(\s+menu)?$"#
            ]
            for p in patterns {
                if t.range(of: p, options: .regularExpression) != nil { return true }
            }
            return false
        }
        
        if let aiNumericalGoal = aiResponse.numericalGoal {
            let nutrientRaw = aiNumericalGoal.nutrient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let constraintRaw = aiNumericalGoal.constraint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            guard let nutrient = MacronutrientType(map: nutrientRaw) else {
                onLog?("  -> Unknown nutrient '\(nutrientRaw)'; skipping numerical goal.")
                return
            }
            
            let constraint: Constraint
            switch constraintRaw {
            case "lessthan", "less_than", "max", "<", "lte", "≤":
                constraint = .lessThan
            case "morethan", "greaterthan", "greater_than", "min", ">", "gte", "≥":
                constraint = .moreThan
            case "equalto", "equals", "equal", "=", "exactly":
                constraint = .exactly
            case "range":
                onLog?("  -> 'range' constraint not supported; treating as qualitative preference instead.")
                interpreted.qualitativeGoals.append("Keep \(nutrient.rawValue) in a moderate range")
                return
            default:
                onLog?("  -> Unknown constraint '\(aiNumericalGoal.constraint)'; defaulting to 'exactly'.")
                constraint = .exactly
            }

            interpreted.numericalGoals.append(.init(nutrient: nutrient, constraint: constraint, value: aiNumericalGoal.value))
            return
        }
        
        if var fr = aiResponse.frequencyRequest {
            let mealNormalized: String = {
                if let meal = fr.meal, !meal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return meal }
                return "any"
            }()
            let f = fr.frequency.lowercased()
            let nNormalized: Int = {
                if f == "daily" || f == "once" { return 0 }
                if f == "per_n_days" && fr.n <= 0 { return 1 }
                return fr.n
            }()
            if shouldDropMetaInstruction(fr.topic) {
                onLog?("  -> Skipping meta directive in frequency request: '\(fr.topic)'")
                return
            }
            if await !isConcreteFoodName(fr.topic, smartSearch: smartSearch) {
                interpreted.qualitativeGoals.append("Prefer \(fr.topic)")
                return
            }

            let sortedDays = daysAndMeals.keys.sorted()
            var daysToInclude: [Int] = []
            switch fr.frequency {
            case "per_n_days":
                guard nNormalized > 0, let first = sortedDays.first else { return }
                var d = first
                while let last = sortedDays.last, d <= last { daysToInclude.append(d); d += nNormalized }
            case "daily": daysToInclude = sortedDays
            case "once": if let first = sortedDays.first { daysToInclude = [first] }
            default: return
            }
            
            for day in daysToInclude {
                let mealTarget = mealNormalized
                if mealTarget.caseInsensitiveCompare("any") != .orderedSame,
                   let dayMeals = daysAndMeals[day],
                   let actual = dayMeals.first(where: { $0.caseInsensitiveCompare(mealTarget) == .orderedSame }) {
                    interpreted.structuralRequests.append("On Day \(day), the \(actual) meal must contain \(fr.topic).")
                } else {
                    interpreted.structuralRequests.append("On Day \(day), one meal must contain \(fr.topic).")
                }
            }
            return
        }
        
        if var sr = aiResponse.structuralRequest {
            if isPureSchedulingInstruction(sr) {
                onLog?("  -> Skipping scheduling directive: '\(sr)'")
                return
            }
            if let topic = extractBreakfastRecurringTopic(from: sr) {
                let sortedDays = daysAndMeals.keys.sorted()
                for day in sortedDays {
                    if let dayMeals = daysAndMeals[day], let _ = dayMeals.first(where: { $0.caseInsensitiveCompare("Breakfast") == .orderedSame }) {
                        interpreted.structuralRequests.append("On Day \(day), include \(topic) at Breakfast")
                    } else {
                        interpreted.structuralRequests.append("On Day \(day), one meal must contain \(topic)")
                    }
                }
                return
            }
            if shouldDropMetaInstruction(sr) {
                onLog?("  -> Skipping meta directive: '\(sr)'")
                return
            }
            if let topic = sr.split(separator: " ").last.map(String.init),
               sr.lowercased().contains("must contain"),
               await !isConcreteFoodName(topic, smartSearch: smartSearch) {
                interpreted.qualitativeGoals.append("Prefer \(topic)")
                return
            }
            interpreted.structuralRequests.append(sr)
            return
        }
        
        if let qualitativeGoal = aiResponse.qualitativeGoal {
            if shouldDropMetaInstruction(qualitativeGoal) {
                onLog?("  -> Skipping meta directive: '\(qualitativeGoal)'")
                return
            }
            interpreted.qualitativeGoals.append(qualitativeGoal)
        }
    }
    
    private func isConcreteFoodName(_ name: String, smartSearch: SmartFoodSearch3) async -> Bool {
        let ids = await smartSearch.searchFoodsAI(
            query: name,
            limit: 3,
            context: "Validating if '\(name)' is a concrete, standalone food item."
        )
        return !ids.isEmpty
    }
    
    private func hardExclusionTerms(from structural: [String]) -> [String] {
        guard !structural.isEmpty else { return [] }
        var out = Set<String>()
        let patterns: [String] = [
            #"exclude\s+([a-zA-Z][a-zA-Z\s]+?)\s+on\s+all\s+days"#,
            #"exclude\s+([a-zA-Z][a-zA-Z\s]+?)\s+completely"#,
            #"no\s+([a-zA-Z][a-zA-Z\s]+?)\s*(?:\.|$)"#
        ]
        for s in structural {
            let l = s.lowercased()
            for p in patterns {
                if let r = try? NSRegularExpression(pattern: p) {
                    let range = NSRange(l.startIndex..<l.endIndex, in: l)
                    if let m = r.firstMatch(in: l, range: range), m.numberOfRanges >= 2,
                       let nameRange = Range(m.range(at: 1), in: l) {
                        let name = String(l[nameRange]).trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { out.insert(name.capitalized) }
                    }
                }
            }
        }
        return Array(out)
    }

    @MainActor
    private func makePlannerExclusions(
        extractedTerms: [String],
        structuralRequests: [String],
        smartSearch: SmartFoodSearch3,
        context: ModelContext
    ) async -> PlannerConceptExclusions {
        var orderedTerms = extractedTerms
        orderedTerms.append(contentsOf: hardExclusionTerms(from: structuralRequests))
        orderedTerms.append("Alcohol")

        var seenTerms = Set<String>()
        orderedTerms = orderedTerms.filter { term in
            let normalized = AyurvedaRules.modifierTokens(term)
                .joined(separator: " ")
            return !normalized.isEmpty && seenTerms.insert(normalized).inserted
        }

        var concepts = Set<String>()
        var explicitFoodIDs = Set<UUID>()
        var exactTerms = Set<String>()
        for term in orderedTerms {
            let normalized = AyurvedaRules.modifierTokens(term)
                .joined(separator: " ")
            exactTerms.insert(normalized)
            if let concept = FoodConcepts.shared.conceptID(for: term) {
                concepts.insert(concept)
            } else if let food = await resolveCompactCandidate(
                named: term,
                smartSearch: smartSearch
            ) {
                explicitFoodIDs.insert(food.id)
            }
        }

        let seededFoodIDs = Set(
            ((try? context.fetch(FetchDescriptor<AyurvedaProfile>())) ?? [])
                .map(\.foodId)
        )
        return PlannerConceptExclusions(
            concepts: concepts,
            explicitFoodIDs: explicitFoodIDs,
            exactTerms: exactTerms,
            seededFoodIDs: seededFoodIDs,
            promptTerms: orderedTerms
        )
    }

    @MainActor
    private func resolveCompactCandidate(
        named name: String,
        smartSearch: SmartFoodSearch3
    ) async -> CompactFoodItem? {
        let ontologyAliases = FoodConcepts.shared.resolutionAliases
        let queries = PlannerDeterministicFoodResolver.queries(
            for: name,
            ontologyAliases: ontologyAliases
        )
        var candidatesByID: [UUID: CompactFoodItem] = [:]
        for query in queries {
            for candidate in await smartSearch.searchCompact(
                query: query,
                limit: 120
            ) {
                candidatesByID[candidate.id] = candidate
            }
        }
        let scorerCandidates = candidatesByID.values.map {
            PlannerResolutionCandidate(
                id: $0.id,
                name: $0.name,
                isRecipe: $0.isRecipe,
                tier: .estimated
            )
        }
        guard let decision = PlannerDeterministicFoodResolver.resolve(
            concept: name,
            ontologyAliases: ontologyAliases,
            candidates: scorerCandidates
        ) else {
            return nil
        }
        return candidatesByID[decision.candidate.id]
    }
    
    private func buildMustContainRules(
        structuralRequests: [String],
        daysAndMeals: [Int: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) -> [MustContainRule] {
        guard !structuralRequests.isEmpty else { return [] }
        let validDays = Set(daysAndMeals.keys)
        var out: [MustContainRule] = []
        
        var mealMaps: [Int: [String: String]] = [:]
        for (day, meals) in daysAndMeals {
            var m: [String: String] = [:]
            for name in meals { m[name.lowercased()] = name }
            mealMaps[day] = m
        }
        
        let p1 = #"on\s+day\s+([1-7])\s*,?\s*include\s+([a-zA-Z][a-zA-Z\s]+?)\s+at\s+([a-zA-Z][a-zA-Z\s]+)"#
        let p2 = #"on\s+day\s+([1-7])\s*,?\s*the\s+([a-zA-Z][a-zA-Z\s]+)\s+meal\s+must\s+contain\s+([a-zA-Z][a-zA-Z\s]+)"#
        let p3 = #"on\s+day\s+([1-7])\s*,?\s*one\s+meal\s+must\s+contain\s+([a-zA-Z][a-zA-Z\s]+)"#
        
        for raw in structuralRequests {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            func addRule(dayStr: String, mealStr: String?, topicStr: String) {
                guard let day = Int(dayStr), validDays.contains(day) else { return }
                let topic = topicStr.trimmingCharacters(in: .whitespaces).capitalized
                let meal: String? = {
                    guard let ms = mealStr?.trimmingCharacters(in: .whitespacesAndNewlines), !ms.isEmpty else { return nil }
                    let ci = ms.lowercased()
                    if let mapped = mealMaps[day]?[ci] { return mapped }
                    if ci.contains("breakfast") { return mealMaps[day]?["breakfast"] }
                    if ci.contains("lunch") { return mealMaps[day]?["lunch"] }
                    if ci.contains("dinner") { return mealMaps[day]?["dinner"] }
                    return nil
                }()
                out.append(MustContainRule(day: day, meal: meal, topic: topic))
            }
            
            if let r = try? NSRegularExpression(pattern: p1, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                if let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 4,
                   let g1 = Range(m.range(at: 1), in: s),
                   let g2 = Range(m.range(at: 2), in: s),
                   let g3 = Range(m.range(at: 3), in: s) {
                    addRule(dayStr: String(s[g1]), mealStr: String(s[g3]), topicStr: String(s[g2]))
                    continue
                }
            }
            if let r = try? NSRegularExpression(pattern: p2, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                if let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 4,
                   let g1 = Range(m.range(at: 1), in: s),
                   let g2 = Range(m.range(at: 2), in: s),
                   let g3 = Range(m.range(at: 3), in: s) {
                    addRule(dayStr: String(s[g1]), mealStr: String(s[g2]), topicStr: String(s[g3]))
                    continue
                }
            }
            if let r = try? NSRegularExpression(pattern: p3, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                if let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 3,
                   let g1 = Range(m.range(at: 1), in: s),
                   let g2 = Range(m.range(at: 2), in: s) {
                    addRule(dayStr: String(s[g1]), mealStr: nil, topicStr: String(s[g2]))
                    continue
                }
            }
        }
        
        if !out.isEmpty {
            onLog?("  -> Built \(out.count) must-contain rule(s): \(out)")
        }
        return out
    }
    
    @MainActor
    private func adjustResolvedDayForGoals(
        dayIndex: Int,
        meals: [MealPlanPreviewMeal],
        goals: [NumericalGoal],
        unresolvedComponentCount: Int,
        context: ModelContext,
        onLog: (@Sendable (String) -> Void)?
    ) -> [MealPlanPreviewMeal] {
        if unresolvedComponentCount > 0 {
            onLog?(
                "⚠️ MP2 nutrition truth: Day \(dayIndex) excludes "
                    + "\(unresolvedComponentCount) unresolved component(s) from goal math."
            )
        }
        guard !goals.isEmpty else { return meals }

        var foodsByName: [String: FoodItem] = [:]
        var missingFoodNames = Set<String>()
        var macroItems: [PlannerResolvedMacroItem] = []
        var unavailableNutritionCount = 0

        for (mealIndex, meal) in meals.enumerated() {
            for (itemIndex, item) in meal.items.enumerated() {
                guard item.grams > 0 else {
                    unavailableNutritionCount += 1
                    continue
                }

                let nameKey = item.name.lowercased()
                let food: FoodItem?
                if let cached = foodsByName[nameKey] {
                    food = cached
                } else if missingFoodNames.contains(nameKey) {
                    food = nil
                } else {
                    let itemName = item.name
                    let descriptor = FetchDescriptor<FoodItem>(
                        predicate: #Predicate { $0.name == itemName }
                    )
                    let fetched = (try? context.fetch(descriptor))?.first
                    if let fetched {
                        foodsByName[nameKey] = fetched
                    } else {
                        missingFoodNames.insert(nameKey)
                    }
                    food = fetched
                }

                guard let food else {
                    unavailableNutritionCount += 1
                    continue
                }
                let referenceWeight = food.referenceWeightG
                let macros = FoodItem.aggregatedNutrition(for: food).macros
                guard referenceWeight > 0,
                      let protein = macros?.protein?.value,
                      let fat = macros?.fat?.value,
                      let carbohydrates = macros?.carbohydrates?.value else {
                    unavailableNutritionCount += 1
                    continue
                }

                macroItems.append(
                    PlannerResolvedMacroItem(
                        mealIndex: mealIndex,
                        itemIndex: itemIndex,
                        name: item.name,
                        grams: item.grams,
                        caloriesPerGram: food.calories(for: 1),
                        referenceWeightGrams: referenceWeight,
                        proteinPerReference: protein,
                        fatPerReference: fat,
                        carbohydratesPerReference: carbohydrates
                    )
                )
            }
        }

        if unavailableNutritionCount > 0 {
            onLog?(
                "⚠️ MP2 nutrition truth: Day \(dayIndex) excludes "
                    + "\(unavailableNutritionCount) resolved item(s) without complete "
                    + "FoodItem macros from goal math."
            )
        }

        let targets = goals.map { goal -> PlannerMacroTarget in
            let nutrient: PlannerMacroNutrient
            switch goal.nutrient {
            case .protein:
                nutrient = .protein
            case .fat:
                nutrient = .fat
            case .carbohydrates:
                nutrient = .carbohydrates
            }

            let constraint: PlannerMacroConstraint
            switch goal.constraint {
            case .exactly:
                constraint = .exactly
            case .lessThan:
                constraint = .lessThan
            case .moreThan:
                constraint = .moreThan
            }
            return PlannerMacroTarget(
                nutrient: nutrient,
                constraint: constraint,
                value: goal.value
            )
        }
        let result = PlannerMacroGoalAdjuster.adjust(
            items: macroItems,
            targets: targets,
            unresolvedComponentCount: unresolvedComponentCount
        )

        onLog?(
            "    - Day \(dayIndex) PRE resolved totals: Protein "
                + "\(Int(result.before.protein))g • Fat \(Int(result.before.fat))g "
                + "• Carbs \(Int(result.before.carbohydrates))g"
        )
        onLog?(
            "    - Day \(dayIndex) POST resolved totals: Protein "
                + "\(Int(result.after.protein))g • Fat \(Int(result.after.fat))g "
                + "• Carbs \(Int(result.after.carbohydrates))g"
        )

        var adjustedMeals = meals
        for item in result.items {
            guard adjustedMeals.indices.contains(item.mealIndex),
                  adjustedMeals[item.mealIndex].items.indices.contains(item.itemIndex) else {
                continue
            }
            let original = adjustedMeals[item.mealIndex].items[item.itemIndex]
            adjustedMeals[item.mealIndex].items[item.itemIndex] = MealPlanPreviewItem(
                id: original.id,
                name: original.name,
                grams: item.grams,
                kcal: item.caloriesPerGram * item.grams
            )
        }
        return adjustedMeals
    }
    
    @MainActor
    private func resolveFoodConcept(
        smartSearch: SmartFoodSearch3, // Updated Type
        conceptName: String,
        mealContext: ConceptualMeal,
        relevantPrompts: [String],
        exclusions: PlannerConceptExclusions = .none,
        onLog: (@Sendable (String) -> Void)?
    ) async -> ResolvedFoodInfo? {
        onLog?("    - Resolving '\(conceptName)' in context of '\(mealContext.descriptiveTitle)'...")
        let ctx = ModelContext(self.container)
        guard !AyurvedaRecommendationGate.nameIsExcluded(conceptName, context: ctx) else {
            emitLog("🚫 AyurvedaGate: dropped excluded generated ingredient '\(conceptName)'", onLog: onLog)
            return nil
        }

        let ontologyAliases = FoodConcepts.shared.resolutionAliases
        let queries = PlannerDeterministicFoodResolver.queries(
            for: conceptName,
            ontologyAliases: ontologyAliases
        )
        guard !queries.isEmpty else {
            onLog?("    - ⚠️ Empty deterministic query for '\(conceptName)'.")
            return nil
        }

        var candidatesByID: [UUID: CompactFoodItem] = [:]
        for query in queries {
            let searchCandidates = await smartSearch.searchCompact(
                query: query,
                limit: 120
            )
            for candidate in searchCandidates {
                candidatesByID[candidate.id] = candidate
            }
        }
        onLog?(
            "    - Deterministic queries \(queries) produced "
                + "\(candidatesByID.count) unique candidates."
        )

        guard !candidatesByID.isEmpty else {
            onLog?("    - ⚠️ No candidates found for '\(conceptName)'.")
            return nil
        }

        let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
        let beforeExclusionCount = candidatesByID.count
        candidatesByID = candidatesByID.filter {
            !excludedFoodIds.contains($0.key)
        }
        emitLog(
            "🚫 AyurvedaGate: AyurvedaGate active, "
                + "\(beforeExclusionCount - candidatesByID.count) candidates filtered",
            onLog: onLog
        )
        guard !candidatesByID.isEmpty else { return nil }

        let beforeConceptExclusionCount = candidatesByID.count
        let conceptFiltered = exclusions.filtering(Array(candidatesByID.values))
        candidatesByID = Dictionary(
            uniqueKeysWithValues: conceptFiltered.map { ($0.id, $0) }
        )
        emitLog(
            "🚫 FoodConcepts: \(beforeConceptExclusionCount - candidatesByID.count) "
                + "candidates excluded by canonical membership.",
            onLog: onLog
        )
        guard !candidatesByID.isEmpty else { return nil }

        let candidateFoodIDs = Array(candidatesByID.keys)
        let directProfileIDs: Set<UUID> = {
            let descriptor = FetchDescriptor<AyurvedaProfile>(
                predicate: #Predicate { candidateFoodIDs.contains($0.foodId) }
            )
            return Set((try? ctx.fetch(descriptor))?.map(\.foodId) ?? [])
        }()
        let linksByFoodID: [UUID: String] = {
            let descriptor = FetchDescriptor<AyurvedaLink>(
                predicate: #Predicate { candidateFoodIDs.contains($0.foodId) }
            )
            let links = (try? ctx.fetch(descriptor)) ?? []
            return Dictionary(
                uniqueKeysWithValues: links.map { ($0.foodId, $0.tier) }
            )
        }()

        let scorerCandidates = candidatesByID.values.map { candidate in
            let tier: PlannerResolutionTier
            if directProfileIDs.contains(candidate.id) {
                tier = .classical
            } else if let linkTier = linksByFoodID[candidate.id] {
                tier = linkTier == "derived" ? .derived : .classical
            } else {
                tier = .estimated
            }
            return PlannerResolutionCandidate(
                id: candidate.id,
                name: candidate.name,
                isRecipe: candidate.isRecipe,
                tier: tier
            )
        }

        guard let decision = PlannerDeterministicFoodResolver.resolve(
            concept: conceptName,
            ontologyAliases: ontologyAliases,
            candidates: scorerCandidates
        ) else {
            onLog?(
                "    - ⚠️ Deterministic score below "
                    + "\(PlannerDeterministicFoodResolver.minimumScore) for "
                    + "'\(conceptName)'; leaving unresolved."
            )
            return nil
        }

        let chosenID = decision.candidate.id
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.id == chosenID }
        )
        guard let chosen = (try? ctx.fetch(descriptor))?.first else {
            onLog?("    - ⚠️ Could not materialize deterministic candidate \(chosenID).")
            return nil
        }
        onLog?(
            "    - Deterministic choice '\(chosen.name)' score "
                + "\(String(format: "%.1f", decision.score)); tier "
                + "\(decision.candidate.tier.rawValue); extras "
                + "\(decision.extraTokens)."
        )
        return ResolvedFoodInfo(
            persistentID: chosen.persistentModelID,
            resolvedName: chosen.name
        )
    }
    
    @MainActor
        private func polishConceptualPlan(
            plan: AIConceptualPlanResponse,
            profile: Profile,
            daysAndMeals: [Int: [String]],
            rules: [MustContainRule],
            excludedFoods: [String],
            foodPalette: [String],
            exclusions: PlannerConceptExclusions,
            smartSearch: SmartFoodSearch3,
            onLog: (@Sendable (String) -> Void)?
        ) async -> AIConceptualPlanResponse {
            var polishedPlan = plan
            onLog?("✨ Polishing conceptual plan (Rules, Trimming & AI Portion Control)...")
            
            // --- Start Helper Functions (scoped to polishing) ---
            var namesToResolve = Set(foodPalette)
            for day in polishedPlan.days {
                for meal in day.meals {
                    namesToResolve.formUnion(meal.components.map(\.name))
                }
            }
            var excludedResolvedNames = Set<String>()
            for name in namesToResolve.sorted() {
                let normalized = AyurvedaRules.modifierTokens(name)
                    .joined(separator: " ")
                if exclusions.excludesUnresolvedName(name) {
                    excludedResolvedNames.insert(normalized)
                } else if let candidate = await resolveCompactCandidate(
                    named: name,
                    smartSearch: smartSearch
                ), exclusions.excludes(candidate) {
                    excludedResolvedNames.insert(normalized)
                }
            }

            func isExcluded(_ name: String) -> Bool {
                excludedResolvedNames.contains(
                    AyurvedaRules.modifierTokens(name).joined(separator: " ")
                )
            }
            
            func isProtein(_ n: String) -> Bool {
                let keys = ["chicken", "pork", "beef", "turkey", "salmon", "tuna", "fish", "lamb", "loin", "breast", "steak", "ham", "shrimp", "egg", "tofu", "tempeh", "lentil", "bean", "seitan"]
                return keys.contains { n.lowercased().contains($0) }
            }
            
            func coreProteinKey(_ name: String) -> String {
                let keys = ["chicken", "turkey", "salmon", "tuna", "fish", "shrimp", "pork", "beef", "lamb", "egg", "tofu", "tempeh", "lentil", "bean", "seitan"]
                for k in keys { if name.lowercased().contains(k) { return k } }
                return name.lowercased()
            }
            
            func isSalad(_ n: String) -> Bool { let l = n.lowercased(); return l.contains("salad") || l.contains("greens") }
            func isFruit(_ n: String) -> Bool { let l = n.lowercased(); return l.contains("fruit") || l.contains("berry") || l.contains("melon") || l.contains("apple") || l.contains("banana") }
            let gateContext = ModelContext(self.container)
            
            // --- Prepare Side Candidates ---
            var sideCandidates: [String] = {
                var candidates: [String] = []
                let paletteSides = foodPalette.filter { isSalad($0) || isFruit($0) }
                var seen = Set<String>()
                for side in paletteSides {
                    if seen.insert(side.lowercased()).inserted && !isExcluded(side)
                        && !AyurvedaRecommendationGate.nameIsExcluded(side, context: gateContext) {
                        candidates.append(side)
                    }
                }
                return candidates
            }()
            
            if sideCandidates.isEmpty {
                let ctx = ModelContext(self.container)
                let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
                let descriptor = FetchDescriptor<FoodItem>()
                if let all = try? ctx.fetch(descriptor) {
                    for f in all {
                        if (isSalad(f.name) || isFruit(f.name)) && !isExcluded(f.name)
                            && !exclusions.excludes(
                                foodID: f.id,
                                allergens: Set((f.allergens ?? []).map(\.rawValue))
                            )
                            && !excludedFoodIds.contains(f.id) {
                            sideCandidates.append(f.name)
                        }
                    }
                }
            }
            
            // --- Prepare Rules Lookup ---
            var seenSignatures: [String: Set<String>] = [:]
            var usedDinnerProteins = Set<String>()
            
            var protectedByDayMeal: [Int: [String: Set<String>]] = [:]
            for r in rules {
                let keyMeal = (r.meal?.lowercased()) ?? "*"
                var meals = protectedByDayMeal[r.day] ?? [:]
                var set = meals[keyMeal] ?? Set()
                set.insert(r.topic.lowercased())
                meals[keyMeal] = set
                protectedByDayMeal[r.day] = meals
            }
            
            let orderedDayIndices = polishedPlan.days.indices.sorted(by: { polishedPlan.days[$0].day < polishedPlan.days[$1].day })
            
            // --- Iterate Days & Meals (Structural Polish) ---
            for dayIndex in orderedDayIndices {
                let dayNumber = polishedPlan.days[dayIndex].day
                var dayHasSaladOrFruit = false
                
                for mealIndex in 0..<polishedPlan.days[dayIndex].meals.count {
                    var meal = polishedPlan.days[dayIndex].meals[mealIndex]
                    
                    // --- Rule 1: Purge Excluded Foods ---
                    let beforeCount = meal.components.count
                    meal.components.removeAll { isExcluded($0.name) }
                    if meal.components.count < beforeCount {
                        onLog?("🧹 Day \(dayNumber) • \(meal.name): Removed \(beforeCount - meal.components.count) excluded component(s).")
                    }
                    if meal.components.isEmpty {
                        meal.components.append(ConceptualComponent(name: "Mixed Greens", grams: 80))
                    }
                    
                    // --- Rule 2: Enforce Must-Contain Rules ---
                    let relevantRules = rules.filter { $0.day == dayNumber }
                    for rule in relevantRules {
                        let mealMatches = (rule.meal == nil) || (rule.meal?.caseInsensitiveCompare(meal.name) == .orderedSame)
                        if mealMatches && !meal.components.contains(where: { $0.name.range(of: rule.topic, options: .caseInsensitive) != nil }) {
                            if let proteinIdx = meal.components.firstIndex(where: { isProtein($0.name) }) {
                                let old = meal.components[proteinIdx].name
                                meal.components[proteinIdx] = ConceptualComponent(name: rule.topic, grams: 120)
                                onLog?("✅ Enforced: Day \(dayNumber) • \(meal.name) now has '\(rule.topic)' (replaced '\(old)').")
                            } else {
                                meal.components.append(ConceptualComponent(name: rule.topic, grams: 120))
                                onLog?("✅ Enforced: Day \(dayNumber) • \(meal.name) now has '\(rule.topic)' (added).")
                            }
                        }
                    }
                    
                    // --- Rule 3: Diversify Dinner & Enforce Single Main Course ---
                    var proteinIndices = meal.components.indices.filter { isProtein(meal.components[$0].name) }
                    
                    // 3a. Avoid repeating the same main protein at dinner across the week
                    if meal.name.caseInsensitiveCompare("Dinner") == .orderedSame {
                        if let mainProteinIdx = proteinIndices.first {
                            let currentKey = coreProteinKey(meal.components[mainProteinIdx].name)
                            if usedDinnerProteins.contains(currentKey) {
                                let isProtectedByRule = protectedByDayMeal[dayNumber]?[meal.name.lowercased()]?.contains(where: { currentKey.contains($0) }) ?? false
                                if !isProtectedByRule {
                                    let replacementOptions = foodPalette.filter { isProtein($0) && !isExcluded($0) }
                                    if let replacement = replacementOptions.first(where: { !usedDinnerProteins.contains(coreProteinKey($0)) }) {
                                        let oldName = meal.components[mainProteinIdx].name
                                        meal.components[mainProteinIdx].name = replacement
                                        onLog?("🔁 Diversified Dinner on Day \(dayNumber): replaced '\(oldName)' with '\(replacement)'.")
                                        usedDinnerProteins.insert(coreProteinKey(replacement))
                                    }
                                }
                            } else {
                                usedDinnerProteins.insert(currentKey)
                            }
                        }
                    }
                    
                    // 3b. Ensure only one main protein per meal (unless explicitly requested)
                    proteinIndices = meal.components.indices.filter { isProtein(meal.components[$0].name) }
                    if proteinIndices.count > 1 {
                        for extraIdx in proteinIndices.dropFirst().reversed() {
                            let old = meal.components[extraIdx].name
                            if let replacement = sideCandidates.randomElement() {
                                meal.components[extraIdx] = ConceptualComponent(name: replacement, grams: 100)
                                onLog?("✅ Single Main: Day \(dayNumber) • \(meal.name) replaced extra protein '\(old)' with '\(replacement)'.")
                            } else {
                                meal.components.remove(at: extraIdx)
                            }
                        }
                    }
                    
                    // --- Rule 4: Inter-day Variety Check (Signature) ---
                    let signature = mealSignature(meal)
                    if seenSignatures[meal.name, default: []].contains(signature) {
                        onLog?("‼️ Duplicate meal signature detected for \(meal.name) on Day \(dayNumber). Attempting to vary.")
                        var varied = false
                        // Try to vary a side component first
                        if let sideIdx = meal.components.firstIndex(where: { !isProtein($0.name) }) {
                            if let newSide = sideCandidates.first(where: { !meal.components.map({$0.name}).contains($0) }) {
                                let oldSide = meal.components[sideIdx].name
                                meal.components[sideIdx].name = newSide
                                onLog?("🔀 Varied side in Day \(dayNumber) • \(meal.name): '\(oldSide)' → '\(newSide)'.")
                                varied = true
                            }
                        }
                        // If no side could be varied, try the main
                        if !varied, let mainIdx = meal.components.firstIndex(where: { isProtein($0.name) }) {
                            let currentMain = meal.components[mainIdx].name
                            let variants = await aiGenerateVariants(for: currentMain, count: 2, mealName: meal.name, excludedFoods: excludedFoods, onLog: onLog)
                            if let replacement = variants.first(where: { $0.lowercased() != currentMain.lowercased() }) {
                                meal.components[mainIdx].name = replacement
                                onLog?("🔀 Varied main in Day \(dayNumber) • \(meal.name): '\(currentMain)' → '\(replacement)'.")
                            }
                        }
                    }
                    seenSignatures[meal.name, default: []].insert(mealSignature(meal))
                    
                    // --- Rule 5: Component Limits (Context-Aware) ---
                    let cuisine = inferCuisineFromMeal(meal: meal)
                    let maxCount = maxComponents(for: cuisine)
                    if meal.components.count > maxCount {
                        let originalCount = meal.components.count
                        meal.components = trimComponents(
                            components: meal.components,
                            maxCount: maxCount,
                            cuisine: cuisine,
                            onLog: onLog
                        )
                        onLog?("✂️ Trimmed components for Day \(dayNumber) • \(meal.name) from \(originalCount) to \(meal.components.count) (Cuisine: \(cuisine)).")
                    }
                    
                    // NOTE: Old heuristic clamping removed from here.
                    
                    // --- Update State & Final Meal ---
                    polishedPlan.days[dayIndex].meals[mealIndex] = meal
                    if meal.components.contains(where: { isSalad($0.name) || isFruit($0.name) }) {
                        dayHasSaladOrFruit = true
                    }
                }
                
                // --- Rule 7: Sprinkle Salads/Fruits (Day-level check) ---
                if !dayHasSaladOrFruit {
                    if let lunchIndex = polishedPlan.days[dayIndex].meals.firstIndex(where: { $0.name.caseInsensitiveCompare("Lunch") == .orderedSame }),
                       let pick = sideCandidates.randomElement() {
                        polishedPlan.days[dayIndex].meals[lunchIndex].components.append(ConceptualComponent(name: pick, grams: isFruit(pick) ? 150 : 120))
                        onLog?("🥗 Sprinkled '\(pick)' into Day \(dayNumber) Lunch.")
                    }
                }
            }
            
            // --- Rule 6: Portion Clamping (Global AI Batch Pass) ---
            // Извикваме новия метод върху целия план наведнъж
            polishedPlan = await aiApplyPortionClamping(plan: polishedPlan, profile: profile, onLog: onLog)
            
            return polishedPlan
        }
    
    // **NEW**: Helper for `polishConceptualPlan` to infer cuisine
    private func inferCuisineFromMeal(meal: ConceptualMeal) -> String {
        let title = meal.descriptiveTitle.lowercased()
        let componentNames = meal.components.map { $0.name.lowercased() }.joined(separator: " ")
        let combinedText = title + " " + componentNames
        
        if combinedText.contains("ayurvedic") || combinedText.contains("indian") || combinedText.contains("thali") || combinedText.contains("curry") {
            return "Indian/Ayurvedic"
        }
        if combinedText.contains("slovak") || combinedText.contains("banica") {
            return "Slovak"
        }
        if combinedText.contains("italian") || combinedText.contains("pasta") || combinedText.contains("risotto") {
            return "Italian"
        }
        if combinedText.contains("mexican") || combinedText.contains("taco") || combinedText.contains("burrito") {
            return "Mexican"
        }
        if combinedText.contains("chinese") || combinedText.contains("wok") || combinedText.contains("dim sum") {
            return "Chinese"
        }
        if combinedText.contains("japanese") || combinedText.contains("sushi") || combinedText.contains("ramen") {
            return "Japanese"
        }
        return "Generic"
    }
    
    // **NEW**: Helper for `polishConceptualPlan` to get max components
    private func maxComponents(for cuisine: String) -> Int {
        switch cuisine {
        case "Indian/Ayurvedic", "Slovak":
            return 8 // Allow more components for these cuisines
        case "Mexican", "Chinese", "Japanese":
            return 6
        default:
            return 5 // Default for "Generic", "Italian", etc.
        }
    }
    
    // **NEW**: Helper for `polishConceptualPlan` to identify essential ingredients like spices
    private func isEssentialIngredient(name: String, cuisine: String) -> Bool {
        guard cuisine == "Indian/Ayurvedic" else {
            return false // This logic currently only applies to Indian/Ayurvedic food
        }
        let lowercasedName = name.lowercased()
        let spicesAndHerbs: Set<String> = [
            "turmeric", "cumin", "coriander", "cardamom", "clove", "cinnamon", "fenugreek",
            "mustard seed", "fennel seed", "asafoetida", "hing", "ginger", "garlic", "chili",
            "curry leaves", "tamarind", "ashwagandha", "amla", "sesame", "black pepper"
        ]
        
        return spicesAndHerbs.contains { lowercasedName.contains($0) }
    }
    
    // **NEW**: Helper for `polishConceptualPlan` for intelligent trimming
    private func trimComponents(
        components: [ConceptualComponent],
        maxCount: Int,
        cuisine: String,
        onLog: (@Sendable (String) -> Void)?
    ) -> [ConceptualComponent] {
        guard components.count > maxCount else { return components }
        
        var essential: [ConceptualComponent] = []
        var nonEssential: [ConceptualComponent] = []
        
        for component in components {
            if isEssentialIngredient(name: component.name, cuisine: cuisine) {
                essential.append(component)
            } else {
                nonEssential.append(component)
            }
        }
        
        var finalComponents = essential
        let remainingSlots = maxCount - finalComponents.count
        
        if remainingSlots > 0 {
            // Sort non-essential by grams descending to keep the "main" parts
            nonEssential.sort { $0.grams > $1.grams }
            finalComponents.append(contentsOf: nonEssential.prefix(remainingSlots))
        } else {
            // This case happens if there are more essential ingredients than allowed slots
            onLog?("  - NOTE: More essential ingredients than available slots. Trimming essentials.")
            finalComponents = Array(finalComponents.prefix(maxCount))
        }
        
        return finalComponents
    }
    
    private func debugDumpConceptualPlan(
        _ plan: AIConceptualPlanResponse,
        title: String,
        onLog: (@Sendable (String) -> Void)?
    ) {
        onLog?("──────── \(title) ────────")
        onLog?("Plan: \(plan.planName) • minAge=\(plan.minAgeMonths)mo • days=\(plan.days.count)")
        for d in plan.days.sorted(by: { $0.day < $1.day }) {
            onLog?("  Day \(d.day):")
            for m in d.meals {
                onLog?("    • \(m.name) — '\(m.descriptiveTitle)' (\(m.components.count) items)")
                for c in m.components {
                    onLog?("        - \(c.name) : \(Int(c.grams)) g")
                }
                onLog?("      • signature: \(mealSignature(m))")
            }
        }
        onLog?("────────────────────────────")
    }
    
    @MainActor
    private func fetchFoodNames(for ids: [PersistentIdentifier]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let ctx = ModelContext(self.container)
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.persistentModelID) })
        let items = (try? ctx.fetch(descriptor)) ?? []
        return items.map { $0.name }
    }
    
    @MainActor private func fetchFoodItem(by id: PersistentIdentifier) -> FoodItem? { let ctx = ModelContext(self.container); return ctx.model(for: id) as? FoodItem }
    private func logInterpretedGoals(_ interpreted: InterpretedPrompts, onLog: (@Sendable (String) -> Void)?) { for goal in interpreted.numericalGoals { onLog?("  -> Interpreted numerical goal: \(goal.nutrient.rawValue) \(goal.constraint) \(goal.value)g") }; for goal in interpreted.qualitativeGoals { onLog?("  -> Interpreted qualitative goal: \(goal)") }; for request in interpreted.structuralRequests { onLog?("  -> Interpreted structural request: \(request)") } }
    private func estimatedDailyCalories(for p: Profile) -> Double { let ageY = Calendar.current.dateComponents([.year], from: p.birthday, to: .now).year ?? 30; let w = max(20, p.weight); let h = max(120, p.height); let base = (p.gender.lowercased() == "female") ? (10*w + 6.25*h - 5*Double(ageY) - 161) : (10*w + 6.25*h - 5*Double(ageY) + 5); let tdee = base * 1.2; return max(1400, tdee.rounded()) }
    private func logPreview(_ days: [MealPlanPreviewDay]) { for day in days { print("  -> Day \(day.dayIndex):"); for meal in day.meals { let title = meal.descriptiveTitle ?? meal.name; print("    - Meal: \(meal.name) ('\(title)') (\(meal.items.count) items, \(Int(meal.kcalTotal)) kcal)"); for item in meal.items { print("      - \(item.name), \(Int(item.grams))g, \(Int(item.kcal)) kcal") } } } }
    
    private func mealSignature(_ meal: ConceptualMeal) -> String {
        let names = meal.components.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return names.sorted().joined(separator: "|")
    }
    
    @MainActor
    private func aiGenerateVariantIdeas(
        for baseFood: String,
        count: Int,
        context: String,
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        let session = LanguageModelSession(instructions: Instructions {
            """
            You are a creative culinary assistant. Your task is to generate distinct, realistic variations of a given base food.
            RULES:
            - Generate exactly the requested number of variations.
            - Each variation must be a full, plausible dish name.
            - The variations should be diverse (change fillings, preparation style, or key ingredients).
            - Do not include explanations or bullets; return only the list of names.
            - Ensure the variants are appropriate for the provided meal context (e.g., breakfast, lunch, dinner).
            - **CRITICAL**: Do NOT invent hybrid names by combining the headword with generic dish types unless they are real, well-known dishes. Focus on authentic variations.
            """
        })
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.noteSession(site: "aiGenerateVariantIdeas")
        }
        let prompt = """
        Generate \(count) distinct variations of the dish "\(baseFood)" suitable for a \(context) meal.
        """
        var telemetryRespondStartedAt: UInt64?
        var telemetryRespondRecorded = false
        do {
            try Task.checkCancellation()
            if PlannerTelemetry.isEnabled {
                telemetryRespondStartedAt = DispatchTime.now().uptimeNanoseconds
            }
            let response = try await session.respond(
                to: prompt,
                generating: AIVariantListResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            if let startedAt = telemetryRespondStartedAt {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiGenerateVariantIdeas",
                    ok: true,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
                telemetryRespondRecorded = true
            }
            try Task.checkCancellation()
            var seen = Set<String>()
            let variants = response.content.variants.compactMap { variant -> String? in
                let cleaned = variant.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return nil }
                return seen.insert(cleaned.lowercased()).inserted ? cleaned : nil
            }
            try Task.checkCancellation()
            onLog?("  -> Generated \(variants.count) variant ideas for '\(baseFood)': \(variants)")
            return variants
        } catch {
            if let startedAt = telemetryRespondStartedAt, !telemetryRespondRecorded {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiGenerateVariantIdeas",
                    ok: false,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
            }
            onLog?("  -> ⚠️ AI variant idea generation failed for '\(baseFood)': \(error.localizedDescription)")
            return []
        }
    }
    
    @MainActor
    private func validateAndSelectBestVariants(
        variantIdeas: [String],
        baseFood: String,
        count: Int,
        smartSearch: SmartFoodSearch3, // Updated Type
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        guard !variantIdeas.isEmpty else { return [] }
        var validatedVariants: [String] = []
        let ctx = ModelContext(self.container)
        let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
        
        for idea in variantIdeas {
            if AyurvedaRecommendationGate.nameIsExcluded(idea, context: ctx) {
                emitLog("🚫 AyurvedaGate: dropped excluded generated ingredient '\(idea)'", onLog: onLog)
                continue
            }
            if let existing = try? ctx.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name == idea }))
                .first(where: { !excludedFoodIds.contains($0.id) }) {
                validatedVariants.append(existing.name)
                onLog?("    - ✅ Validated variant by exact match: '\(existing.name)'")
                continue
            }
            
            let tokenizedWords = FoodItem.makeTokens(from: baseFood)
            let ids = await smartSearch.searchFoodsAI(
                query: idea,
                limit: 5,
                context: "Validating variants for \(baseFood)",
                requiredHeadwords: tokenizedWords
            )
            
            if let bestCandidateID = ids.first, let foodItem = fetchFoodItem(by: bestCandidateID),
               !excludedFoodIds.contains(foodItem.id) {
                validatedVariants.append(foodItem.name)
                onLog?("    - ✅ Validated variant by smart search: '\(idea)' -> '\(foodItem.name)'")
            } else {
                onLog?("    - ⚠️ Could not validate variant idea '\(idea)' against the database. It will be created if needed.")
                validatedVariants.append(idea)
            }
        }
        
        var finalSelection: [String] = []
        var seen = Set<String>()
        for variant in validatedVariants {
            if seen.insert(variant.lowercased()).inserted {
                finalSelection.append(variant)
            }
        }
        
        return Array(finalSelection.prefix(count))
    }
    
    @MainActor
    private func aiGenerateVariants(
        for baseDish: String,
        count: Int,
        mealName: String?,
        excludedFoods: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        let cleanCount = max(1, min(count, 7))
        let exclusions = excludedFoods.isEmpty ? "none" : excludedFoods.joined(separator: ", ")
        let meal = mealName ?? "Meal"
        
        let instructions = Instructions {
            """
            You are a culinary planner. Generate realistic, distinct variants of a base dish for a specific meal across different days.
            Rules:
            - Output exactly N full dish names (no bullets, no numbering, no extra prose).
            - Variants must be plausible and diverse (change method, cut, garnish OR style), not just repeat the same words.
            - **CRITICAL**: Do NOT invent hybrid names by combining the headword with generic dish types (e.g., do not create 'Pizza' or 'Risotto' variants unless they are real, well-known dishes). Focus on authentic variations.
            - Respect exclusions/banned ingredients.
            - Avoid returning the base dish name unchanged.
            - Keep names concise; avoid listing long topping lists.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.noteSession(site: "aiGenerateVariants")
        }
        let prompt = """
        BASE DISH: \(baseDish)
        MEAL: \(meal)
        EXCLUDED INGREDIENTS: \(exclusions)
        N: \(cleanCount)
        
        Respond with exactly N variant names as an array according to the provided schema.
        """
        
        var telemetryRespondStartedAt: UInt64?
        var telemetryRespondRecorded = false
        do {
            try Task.checkCancellation()
            if PlannerTelemetry.isEnabled {
                telemetryRespondStartedAt = DispatchTime.now().uptimeNanoseconds
            }
            let resp = try await session.respond(
                to: prompt,
                generating: AIVariantListResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content
            if let startedAt = telemetryRespondStartedAt {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiGenerateVariants",
                    ok: true,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
                telemetryRespondRecorded = true
            }
            try Task.checkCancellation()
            func normalize(_ s: String) -> String {
                return s
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "[\n\t]+", with: " ", options: .regularExpression)
            }
            let baseNorm = baseDish.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var uniq: [String] = []
            var seen = Set<String>()
            for v in resp.variants {
                try Task.checkCancellation()
                let k = normalize(v)
                guard !k.isEmpty else { continue }
                let lc = k.lowercased()
                if lc == baseNorm { continue }
                if seen.insert(lc).inserted { uniq.append(k) }
            }
            try Task.checkCancellation()
            if uniq.count < cleanCount {
                let methods = ["grilled","baked","roasted","steamed","pan-seared","air-fried","poached"]
                let cutsOrForms = ["slices","cubes","fillet","strips","whole","chips","roast"]
                let lightAdds = ["with herbs","with vegetables","with yogurt","with cheese","with tomato","with greens","with spices"]
                
                var i = 0
                while uniq.count < cleanCount && i < 40 {
                    try Task.checkCancellation()
                    let method = methods[i % methods.count]
                    let form = cutsOrForms[(i / methods.count) % cutsOrForms.count]
                    let add = lightAdds[(i / (methods.count * cutsOrForms.count)) % lightAdds.count]
                    let candidate = "\(baseDish) (\(method) \(form)) \(add)"
                    let lc = candidate.lowercased()
                    if lc != baseNorm && !seen.contains(lc) {
                        uniq.append(candidate)
                        seen.insert(lc)
                    }
                    i += 1
                }
            }
            
            if uniq.count < cleanCount {
                var padded = uniq
                while padded.count < cleanCount {
                    try Task.checkCancellation()
                    let candidate = "\(baseDish) (variant \(padded.count + 1))"
                    if !seen.contains(candidate.lowercased()) {
                        padded.append(candidate)
                        seen.insert(candidate.lowercased())
                    }
                }
                onLog?("    - Not enough distinct AI variants for '\(baseDish)'. Added generic placeholders.")
                return padded
            }
            try Task.checkCancellation()
            return Array(uniq.prefix(cleanCount))
        } catch {
            if let startedAt = telemetryRespondStartedAt, !telemetryRespondRecorded {
                await PlannerTelemetry.shared.noteRespond(
                    site: "aiGenerateVariants",
                    ok: false,
                    ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                )
            }
            onLog?("    - ⚠️ Variant generation failed for \(baseDish): \(error.localizedDescription). Using generic labels.")
            return (0..<cleanCount).map { "\(baseDish) (variant \($0+1))" }
        }
    }
    
    private struct MustContainRule: Equatable, Hashable {
        let day: Int
        let meal: String?
        let topic: String
    }
    
    private func parseMustContainRules(_ requests: [String]) -> [MustContainRule] {
        var rules: [MustContainRule] = []
        let rx1 = try! NSRegularExpression(pattern: #"On Day (\d+), the ([A-Za-z]+) meal must contain ([^\.]+)\."#)
        let rx2 = try! NSRegularExpression(pattern: #"On Day (\d+), one meal must contain ([^\.]+)\."#)
        for s in requests {
            if let m = rx1.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let day = Int((s as NSString).substring(with: m.range(at: 1))) ?? 0
                let meal = (s as NSString).substring(with: m.range(at: 2))
                let topic = (s as NSString).substring(with: m.range(at: 3))
                rules.append(.init(day: day, meal: meal, topic: topic))
            } else if let m = rx2.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let day = Int((s as NSString).substring(with: m.range(at: 1))) ?? 0
                let topic = (s as NSString).substring(with: m.range(at: 2))
                rules.append(.init(day: day, meal: nil, topic: topic))
            }
        }
        return rules
    }
    
    private func determineDemographic(for profile: Profile) -> String {
        let age = profile.age
        let ageInMonths = profile.ageInMonths
        let gender = profile.gender.lowercased()
        
        if ageInMonths <= 6 { return Demographic.babies0_6m }
        if ageInMonths <= 12 { return Demographic.babies7_12m }
        
        switch age {
        case 1...3:
            return Demographic.children1_3y
        case 4...8:
            return Demographic.children4_8y
        case 9...13:
            return Demographic.children9_13y
        case 14...18:
            return gender == "female" ? Demographic.adolescentFemales14_18y : Demographic.adolescentMales14_18y
        case 19...50:
            return gender == "female" ? Demographic.adultWomen19_50y : Demographic.adultMen19_50y
        case 51...:
            return gender == "female" ? Demographic.adultWomen51plusY : Demographic.adultMen51plusY
        default:
            // Fallback за възраст над 18, ако друга логика не успее
            return gender == "female" ? Demographic.adultWomen19_50y : Demographic.adultMen19_50y
        }
    }
    
}



fileprivate func isMetaDirective(_ text: String) -> Bool {
    let t = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    if t.isEmpty { return false }
    let patterns: [String] = [
        #"^no other (menu|menus|options|cuisines?)$"#,
        #"^no other menu options$"#,
        #"^no other (menu\s+options|cuisine\s+options)$"#,
        #"^do not include other (menu|menus|cuisines?)$"#,
        #"^avoid other (menu|menus|cuisines?)$"#,
        #"^(keep|stick)\s+to\s+(this|the)\s+(menu|cuisine)$"#,
        #"^exclusively\s+(this|the)\s+(menu|cuisine)$"#,
        #"^(only|just)\s+(italian|this|the)\s+(menu|cuisine)$"#,
        #"^only\s+italian(\s+menu)?$"#,
        #".*\bno other (menu|menus|menu\s+options|cuisine|cuisines|options)\b.*"#,

    ]
    for p in patterns {
        if t.range(of: p, options: .regularExpression) != nil { return true }
    }
    return false
}

fileprivate func filterMetaDirectives(_ items: [String]) -> [String] {
    items.filter { !isMetaDirective($0) }
}


@available(iOS 26.0, *)
extension USDAWeeklyMealPlanner {
    
    @available(iOS 26.0, *)
        @MainActor
        private func aiBatchAssignFoodPortions(
            names: [String],
            onLog: (@Sendable (String) -> Void)?
        ) async -> [String: AIFoodPortionKind] {
            guard !names.isEmpty else { return [:] }
            
            let uniqueNames = Array(Set(names)).sorted()
            
            let session = LanguageModelSession(instructions: Instructions {
                """
                You are a nutritional data assistant. Assign a portion-control rule to each food item.
                
                PORTION TYPES:
                1. **Protein**: Meat, fish, eggs, tofu, seitan.
                2. **Starchy Carb**: Rice, pasta, bread, potatoes, corn, oats, beans/lentils.
                3. **Fat/Oil**: Pure fats like Butter, Olive Oil, Ghee, Coconut Oil.
                4. **Spice/Herb**: Dry spices, dry herbs, salt, pepper, baking powder.
                5. **Sauce/Dressing**: Ketchup, Mayo, Mustard, Salsa, Soy Sauce, Vinegar.
                6. **Sweetener**: Honey, Maple Syrup, Sugar, Agave, Molasses.
                7. **Composite Dish**: A full meal item like "Lasagna", "Pizza Slice", "Burrito".
                8. **Veg**: Raw/cooked vegetables (Spinach, Carrot, Tomato).
                9. **Salad**: Leafy greens mixes.
                10. **Dairy**: Milk (Drink), Cheese/Yogurt (Solid).
                
                Return a JSON map of Name -> Portion Type.
                """
            })
            if PlannerTelemetry.isEnabled {
                await PlannerTelemetry.shared.noteSession(site: "aiBatchAssignFoodPortions")
            }
            
            let prompt = """
            Assign portion types to these foods:
            \(uniqueNames.map { "- \($0)" }.joined(separator: "\n"))
            """
            
            var telemetryRespondStartedAt: UInt64?
            var telemetryRespondRecorded = false
            do {
                try Task.checkCancellation()
                if PlannerTelemetry.isEnabled {
                    telemetryRespondStartedAt = DispatchTime.now().uptimeNanoseconds
                }
                let response = try await session.respond(
                    to: prompt,
                    generating: AIBatchFoodPortionAssignments.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(sampling: .greedy)
                )
                if let startedAt = telemetryRespondStartedAt {
                    await PlannerTelemetry.shared.noteRespond(
                        site: "aiBatchAssignFoodPortions",
                        ok: true,
                        ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                    )
                    telemetryRespondRecorded = true
                }
                
                var map: [String: AIFoodPortionKind] = [:]
                for item in response.content.assignments {
                    map[item.foodName.lowercased()] = item.kind
                }
                
                // Fallback
                for name in uniqueNames {
                    if map[name.lowercased()] == nil { map[name.lowercased()] = .other }
                }
                return map
                
            } catch {
                if let startedAt = telemetryRespondStartedAt, !telemetryRespondRecorded {
                    await PlannerTelemetry.shared.noteRespond(
                        site: "aiBatchAssignFoodPortions",
                        ok: false,
                        ms: Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
                    )
                }
                onLog?("⚠️ AI portion assignment failed. Defaults applied.")
                return [:]
            }
        }
    
    @available(iOS 26.0, *)
        @MainActor
        private func aiApplyPortionClamping(
            plan: AIConceptualPlanResponse,
            profile: Profile,
            onLog: (@Sendable (String) -> Void)?
        ) async -> AIConceptualPlanResponse {
            var newPlan = plan
            
            // 1. Събиране на имената
            var allFoodNames = Set<String>()
            for day in newPlan.days {
                for meal in day.meals {
                    for component in meal.components {
                        allFoodNames.insert(component.name)
                    }
                }
            }
            
            // 2. Правила за порции
            let portionKindByName = await aiBatchAssignFoodPortions(names: Array(allFoodNames), onLog: onLog)
            
            // 3. Helpers
            func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, x)) }
            func round5(_ x: Double) -> Double { (x / 5.0).rounded() * 5.0 }
            
            let proteinMax = 180.0
            let starchHi = 180.0
            
            // 4. Обхождане и обновяване
            for d in 0..<newPlan.days.count {
                for m in 0..<newPlan.days[d].meals.count {
                    for c in 0..<newPlan.days[d].meals[m].components.count {
                        let component = newPlan.days[d].meals[m].components[c]
                        let key = component.name.lowercased()
                        let portionKind = portionKindByName[key] ?? .other
                        
                        var g = component.grams
                        
                        switch portionKind {
                        case .protein:
                            g = clamp(g, 90.0, proteinMax)
                            
                        case .starchyCarb:
                            g = clamp(g, 90.0, starchHi)
                            
                        case .dairyDrink:
                            g = clamp(g, 200.0, 300.0)
                            
                        case .cheeseOrYogurt:
                            if key.contains("yogurt") || key.contains("skyr") || key.contains("quark") {
                                g = clamp(g, 120.0, 200.0)
                            } else {
                                g = clamp(g, 30.0, 60.0)
                            }
                            
                        case .nutOrSeed:
                            g = clamp(g, 15.0, 40.0)
                            
                        case .fruit:
                            g = clamp(g, 100.0, 180.0)
                            
                        case .salad:
                            g = clamp(g, 60.0, 150.0)
                            
                        case .veg:
                            g = clamp(g, 100.0, 250.0)
                            
                        case .soup:
                            g = clamp(g, 250.0, 400.0)
                            
                        case .fatOrOil:
                            g = clamp(g, 5.0, 15.0)
                            
                        case .sauceOrDressing:
                            g = clamp(g, 15.0, 40.0)
                            
                        case .spiceOrHerb:
                            if key.contains("fresh") || key.contains("leaves") {
                                g = clamp(g, 5.0, 20.0) // пресни билки
                            } else {
                                g = clamp(g, 0.5, 3.0)  // сухи подправки
                            }

                        case .sweetener: // <-- ТУК Е ПРОМЯНАТА (Замества sweetenerOrCondiment)
                            // Мед, кленов сироп, захар.
                            // Малко по-щедро от олиото, но все пак ограничено.
                            g = clamp(g, 5.0, 25.0)
                            
                        case .compositeDish:
                            g = clamp(g, 250.0, 450.0)
                            
                        case .other:
                            g = clamp(g, 50.0, 200.0)
                        }
                        
                        // Закръгляме, но за сухите подправки запазваме прецизност
                        if portionKind == .spiceOrHerb && g < 5.0 {
                            newPlan.days[d].meals[m].components[c].grams = (g * 2).rounded() / 2
                        } else {
                            newPlan.days[d].meals[m].components[c].grams = round5(g)
                        }
                    }
                }
            }
            
            onLog?("✅ Applied AI-based portion clamping.")
            return newPlan
        }
}
