import Foundation

struct BarcodeFoodMatchCandidate: Sendable {
    let id: UUID
    let name: String
    /// Relevance supplied by the existing food search, in the 0...1 range.
    let searchRelevance: Double
}

struct BarcodeFoodMatchDecision: Sendable {
    let foodID: UUID
    let confidence: Double
    let score: Double
    let margin: Double
    let matchedTokens: [String]
}

/// Conservative name matcher for packaged products. It deliberately returns
/// nil when the local candidates are ambiguous instead of silently selecting
/// the first search result.
enum BarcodeFoodMatchScorer {
    private struct NameAnalysis {
        let identity: [String]
        let modifiers: Set<String>
        let forms: Set<String>
        let searchable: [String]
    }

    private struct ScoredCandidate {
        let candidate: BarcodeFoodMatchCandidate
        let analysis: NameAnalysis
        let score: Double
        let matchedTokens: [String]
    }

    private static let aliases: [String: String] = [
        "yoghurt": "yogurt", "yoghurts": "yogurt", "yogourt": "yogurt",
        "yogourts": "yogurt", "biscuits": "biscuit", "cookies": "cookie",
        "crisps": "crisp", "chips": "chip", "beverages": "beverage",
        "drinks": "drink", "juices": "juice", "sauces": "sauce",
        "cereals": "cereal", "noodles": "noodle", "pastas": "pasta",
        "spaghetti": "spaghetti", "chocolates": "chocolate",
        "candies": "candy", "sweets": "sweet", "tomatoes": "tomato",
        "potatoes": "potato", "berries": "berry", "bananas": "banana",
        "mayonnaise": "mayo", "mayonnaises": "mayo", "ketchups": "ketchup",
        "mueslis": "muesli", "granolas": "granola", "oats": "oat",
        "decaffeinated": "decaf", "non-fat": "nonfat", "low-fat": "lowfat",

        // Russian/Ukrainian labels commonly present in the OFF catalogue.
        "молоко": "milk", "молочный": "milk", "молочная": "milk",
        "кефир": "yogurt", "сыр": "cheese", "сырный": "cheese",
        "сырном": "cheese", "творог": "cheese", "сливки": "cream",
        "хлеб": "bread", "булочка": "bread", "яблоко": "apple",
        "яблочный": "apple", "апельсин": "orange", "апельсиновый": "orange",
        "томат": "tomato", "картофель": "potato", "картопля": "potato",
        "курица": "chicken", "курицей": "chicken", "куриный": "chicken",
        "курячим": "chicken", "свинина": "pork", "свиной": "pork",
        "говядина": "beef", "индейка": "turkey", "рыба": "fish",
        "рибні": "fish", "фасоль": "bean", "горох": "pea",
        "чечевица": "lentil", "рис": "rice", "яйцо": "egg",
        "мука": "flour", "сахар": "sugar", "соль": "salt",
        "печенье": "cookie", "вафля": "wafer", "майонез": "mayo",
        "соус": "sauce", "суп": "soup", "кофе": "coffee",
        "пиво": "beer", "сосиска": "sausage", "ветчина": "ham",
        "мороженое": "icecream",
        "копченый": "smoked", "копченая": "smoked", "консервы": "canned",

        // Frequent Western-European label vocabulary.
        "jus": "juice", "pomme": "apple", "lait": "milk",
        "yaourt": "yogurt", "fromage": "cheese", "pain": "bread",
        "poulet": "chicken", "porc": "pork", "boeuf": "beef",
        "poisson": "fish", "zumo": "juice", "jugo": "juice",
        "leche": "milk", "yogur": "yogurt", "queso": "cheese",
        "pan": "bread", "manzana": "apple", "naranja": "orange",
        "patata": "potato", "pollo": "chicken", "cerdo": "pork",
        "pescado": "fish", "frijol": "bean", "harina": "flour",
        "azucar": "sugar", "galleta": "cookie", "aceite": "oil",
        "cerveza": "beer", "milch": "milk", "joghurt": "yogurt",
        "kase": "cheese", "brot": "bread", "saft": "juice",
        "apfel": "apple", "kartoffel": "potato", "hahnchen": "chicken",
        "schwein": "pork", "rind": "beef", "fisch": "fish",
        "bohne": "bean", "mehl": "flour", "zucker": "sugar",
        "salz": "salt", "schokolade": "chocolate", "keks": "cookie",
        "bier": "beer", "wein": "wine", "wasser": "water",
        "latte": "milk", "formaggio": "cheese", "pane": "bread",
        "succo": "juice", "mela": "apple", "arancia": "orange",
        "pomodoro": "tomato", "maiale": "pork", "pesce": "fish",
        "riso": "rice", "fagiolo": "bean", "farina": "flour",
        "zucchero": "sugar", "cioccolato": "chocolate", "biscotto": "cookie",
        "olio": "oil", "birra": "beer", "acqua": "water"
    ]

    private static let noise: Set<String> = [
        "and", "or", "with", "without", "from", "the", "this", "that",
        "for", "of", "in", "on", "to", "a", "an", "plus", "no",
        "style", "type", "made", "brand", "new", "original", "classic",
        "premium", "quality", "delicious", "tasty", "natural", "organic",
        "bio", "eco", "authentic", "traditional", "selected", "selection",
        "finest", "special", "value", "family", "size", "small", "medium",
        "large", "mini", "maxi", "pack", "packs", "packet", "bottle",
        "bottled", "jar", "box", "pouch", "serving", "portion", "piece",
        "pieces", "count", "ct", "gram", "grams", "kilogram", "kilograms",
        "milligram", "milligrams", "liter", "liters", "litre", "litres",
        "milliliter", "milliliters", "millilitre", "millilitres", "ounce",
        "ounces", "pound", "pounds", "fl", "oz", "lb", "lbs", "kg",
        "mg", "ml", "cl", "product", "food", "prepared", "commercial",
        "commercially", "ready", "regular", "nfs", "ns", "unspecified", "unknown",
        "fluid", "only", "broiler", "broilers", "fryer", "fryers",
        "классик",
        "de", "des", "du", "la", "le", "les", "au", "aux", "avec",
        "et", "pour", "en", "del", "della", "di", "el", "los", "las"
    ]

    private static let modifierTokens: Set<String> = [
        "raw", "cooked", "boiled", "fried", "baked", "roasted", "grilled",
        "canned", "frozen", "dried", "fresh", "salted", "unsalted",
        "sweetened", "unsweetened", "whole", "skim", "nonfat", "lowfat",
        "reducedfat", "sugarfree", "smoked", "pickled", "peeled",
        "unpeeled", "skinless", "boneless", "ground", "minced", "lean",
        "diet", "light", "decaf", "caffeinated", "fortified", "instant",
        "concentrated", "concentrate", "virgin", "extravirgin"
    ]

    private static let formAliases: [String: String] = [
        "juice": "juice", "nectar": "juice", "drink": "beverage",
        "beverage": "beverage", "cola": "soda", "soda": "soda",
        "lemonade": "soda", "milk": "milk", "yogurt": "yogurt",
        "cheese": "cheese", "butter": "butter", "oil": "oil",
        "sauce": "sauce", "ketchup": "sauce", "mayo": "sauce",
        "dressing": "sauce", "seasoning": "seasoning", "spice": "seasoning",
        "cereal": "cereal", "granola": "cereal", "muesli": "cereal",
        "oatmeal": "cereal", "bread": "bread", "bun": "bread",
        "roll": "bread", "tortilla": "bread", "pita": "bread",
        "pasta": "pasta", "spaghetti": "pasta", "macaroni": "pasta",
        "noodle": "pasta", "cookie": "cookie", "biscuit": "cookie",
        "cracker": "cracker", "chip": "chip", "crisp": "chip",
        "soup": "soup", "broth": "soup", "stock": "soup",
        "chocolate": "chocolate", "cocoa": "chocolate", "candy": "candy",
        "sweet": "candy", "gum": "candy", "cake": "cake",
        "muffin": "cake", "pastry": "cake", "donut": "cake",
        "doughnut": "cake", "bar": "bar", "jam": "jam",
        "marmalade": "jam", "jelly": "jam", "spread": "spread",
        "flour": "flour", "puree": "puree", "powder": "powder",
        "coffee": "coffee", "tea": "tea", "beer": "beer", "wine": "wine",
        "water": "water", "icecream": "icecream", "cream": "cream",
        "sausage": "processedmeat", "ham": "processedmeat",
        "bacon": "processedmeat", "croissant": "pastry", "wafer": "wafer",
        "pizza": "pizza", "burger": "burger", "sandwich": "sandwich"
    ]

    private static let beverageForms: Set<String> = [
        "beverage", "juice", "soda", "milk", "water", "coffee", "tea"
    ]

    static func queryVariants(for productName: String) -> [String] {
        let analysis = analyze(productName)
        guard !analysis.searchable.isEmpty else { return [] }

        var result: [String] = []
        func append(_ tokens: ArraySlice<String>) {
            let value = tokens.joined(separator: " ")
            guard !value.isEmpty, !result.contains(value) else { return }
            result.append(value)
        }
        func append(_ tokens: [String]) {
            append(tokens[...])
        }

        append(analysis.searchable)

        let identity = analysis.identity
        if let formIndex = identity.indices.last(where: {
            formAliases[identity[$0]] != nil
        }) {
            let lower = max(identity.startIndex, formIndex - 2)
            let upper = min(identity.endIndex, formIndex + 2)
            append(identity[lower..<upper])
        }

        if identity.count >= 2 {
            append(identity.dropFirst())
        }
        append(identity)
        return Array(result.prefix(4))
    }

    static func select(
        productName: String,
        candidates: [BarcodeFoodMatchCandidate]
    ) -> BarcodeFoodMatchDecision? {
        let product = analyze(productName)
        guard !product.identity.isEmpty else { return nil }

        let scored = candidates.compactMap { candidate -> ScoredCandidate? in
            let candidateAnalysis = analyze(candidate.name)
            guard !candidateAnalysis.identity.isEmpty else { return nil }
            let productSet = Set(product.identity)
            let candidateSet = Set(candidateAnalysis.identity)
            let matched = productSet.intersection(candidateSet).sorted()
            guard !matched.isEmpty else { return nil }

            let intersection = Double(matched.count)
            let candidateCoverage = intersection / Double(candidateSet.count)
            let productCoverage = intersection / Double(productSet.count)
            let dice = (2 * intersection) / Double(productSet.count + candidateSet.count)

            var score = 0.42 * candidateCoverage
                + 0.25 * dice
                + 0.15 * productCoverage

            if productSet == candidateSet {
                score += 0.06
            }
            if containsSequence(product.identity, candidateAnalysis.identity) {
                score += candidateAnalysis.identity.count == 1 ? 0.04 : 0.08
            } else if containsSequence(candidateAnalysis.identity, product.identity) {
                score += product.identity.count == 1 ? 0.03 : 0.06
            }

            switch formRelationship(product.forms, candidateAnalysis.forms) {
            case .matching:
                score += 0.10
            case .conflicting:
                score -= 0.28
            case .notApplicable:
                break
            }

            let modifierMatches = product.modifiers.intersection(
                candidateAnalysis.modifiers
            ).count
            score += min(0.08, Double(modifierMatches) * 0.04)
            if modifiersConflict(product.modifiers, candidateAnalysis.modifiers) {
                score -= 0.18
            }

            score += 0.06 * min(1, max(0, candidate.searchRelevance))
            score = min(1, max(0, score))
            return ScoredCandidate(
                candidate: candidate,
                analysis: candidateAnalysis,
                score: score,
                matchedTokens: matched
            )
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.candidate.searchRelevance != $1.candidate.searchRelevance {
                return $0.candidate.searchRelevance > $1.candidate.searchRelevance
            }
            return $0.candidate.id.uuidString < $1.candidate.id.uuidString
        }

        guard let best = scored.first, best.score >= 0.64 else { return nil }

        let bestSignature = Set(best.analysis.identity)
        let runnerUp = scored.dropFirst().first {
            Set($0.analysis.identity) != bestSignature
        }
        let margin = runnerUp.map { best.score - $0.score } ?? best.score
        let requiredMargin = best.score >= 0.86 && best.matchedTokens.count >= 2
            ? 0.025
            : 0.055
        guard runnerUp == nil || margin >= requiredMargin else { return nil }

        let confidence = min(0.99, best.score + min(0.06, max(0, margin) * 0.30))
        return BarcodeFoodMatchDecision(
            foodID: best.candidate.id,
            confidence: confidence,
            score: best.score,
            margin: margin,
            matchedTokens: best.matchedTokens
        )
    }

    private enum FormRelationship {
        case matching
        case conflicting
        case notApplicable
    }

    private static func formRelationship(
        _ product: Set<String>,
        _ candidate: Set<String>
    ) -> FormRelationship {
        guard !product.isEmpty else { return .notApplicable }
        guard !candidate.isEmpty else { return .conflicting }
        if !product.intersection(candidate).isEmpty { return .matching }
        if product.contains("beverage"), !candidate.intersection(beverageForms).isEmpty {
            return .matching
        }
        if candidate.contains("beverage"), !product.intersection(beverageForms).isEmpty {
            return .matching
        }
        return .conflicting
    }

    private static func modifiersConflict(
        _ product: Set<String>,
        _ candidate: Set<String>
    ) -> Bool {
        let groups: [[Set<String>]] = [
            [Set(["raw"]), Set(["cooked", "boiled", "fried", "baked", "roasted", "grilled"])],
            [Set(["sweetened"]), Set(["unsweetened", "sugarfree"])],
            [Set(["salted"]), Set(["unsalted"])],
            [Set(["whole"]), Set(["skim", "nonfat", "lowfat", "reducedfat"])],
            [Set(["decaf"]), Set(["caffeinated"])],
            [Set(["dried"]), Set(["fresh", "frozen"])]
        ]
        for alternatives in groups {
            guard let productSide = alternatives.firstIndex(where: {
                !product.intersection($0).isEmpty
            }), let candidateSide = alternatives.firstIndex(where: {
                !candidate.intersection($0).isEmpty
            }) else {
                continue
            }
            if productSide != candidateSide { return true }
        }
        return false
    }

    private static func analyze(_ value: String) -> NameAnalysis {
        let tokens = lexicalTokens(value)
        var pairedModifierIndexes: Set<Int> = []
        var modifiers: Set<String> = []

        if tokens.count >= 2 {
            for index in 0..<(tokens.count - 1) {
                let pair = (tokens[index], tokens[index + 1])
                let modifier: String?
                switch pair {
                case ("fat", "free"): modifier = "nonfat"
                case ("low", "fat"): modifier = "lowfat"
                case ("reduced", "fat"): modifier = "reducedfat"
                case ("sugar", "free"), ("no", "sugar"): modifier = "sugarfree"
                case ("extra", "virgin"): modifier = "extravirgin"
                case ("ice", "cream"): modifier = nil
                default: modifier = nil
                }
                if let modifier {
                    modifiers.insert(modifier)
                    pairedModifierIndexes.insert(index)
                    pairedModifierIndexes.insert(index + 1)
                }
            }
        }
        modifiers.formUnion(tokens.filter { modifierTokens.contains($0) })

        var searchable: [String] = []
        var identity: [String] = []
        for (index, token) in tokens.enumerated() {
            guard !noise.contains(token) else { continue }
            if pairedModifierIndexes.contains(index) {
                continue
            }
            searchable.append(token)
            if !modifierTokens.contains(token) {
                identity.append(token)
            }
        }

        let allSet = Set(tokens)
        if (allSet.contains("cola") || allSet.contains("soda")) {
            identity.removeAll { ["soft", "drink", "beverage", "carbonated"].contains($0) }
        } else if allSet.contains("juice") || allSet.contains("nectar") {
            identity.removeAll { ["drink", "beverage"].contains($0) }
        }
        if identity.count > 1 {
            identity.removeAll { $0 == "meat" }
        }

        var forms = Set(tokens.compactMap { formAliases[$0] })
        if allSet.contains("ice"), allSet.contains("cream") {
            forms.insert("icecream")
        }
        return NameAnalysis(
            identity: unique(identity),
            modifiers: modifiers,
            forms: forms,
            searchable: unique(searchable)
        )
    }

    private static func lexicalTokens(_ value: String) -> [String] {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return folded
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap { raw -> String? in
                var token = String(raw)
                guard token.count > 1, !token.contains(where: \.isNumber) else {
                    return nil
                }
                token = aliases[token] ?? token
                if token.count > 4, token.hasSuffix("ies") {
                    token = String(token.dropLast(3)) + "y"
                } else if token.count > 4,
                          ["ches", "shes", "xes", "zes"].contains(where: token.hasSuffix) {
                    token = String(token.dropLast(2))
                } else if token.count > 3,
                          token.hasSuffix("s"),
                          !token.hasSuffix("ss"),
                          !token.hasSuffix("us"),
                          !token.hasSuffix("is") {
                    token.removeLast()
                }
                return aliases[token] ?? token
            }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func containsSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        if needle.count == 1 { return haystack.contains(needle[0]) }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}
