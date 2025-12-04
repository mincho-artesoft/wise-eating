import Foundation
@preconcurrency import NaturalLanguage

// One shared embedding (not actor-isolated)
private let smartFoodSearchEmbedding: NLEmbedding? =
    NLEmbedding.wordEmbedding(for: .english)

struct SemanticEntry {
    enum Kind {
        case nutrient(NutrientType)
        case allergen(Allergen)
        case diet(DietType)
        case op(Tokenizer.OpToken)
    }

    let phrase: String      // e.g. "vitamin c"
    let kind: Kind          // e.g. .nutrient(.vitaminC)
    let vector: [Double]    // embedding vector
}

final class SemanticLexicon {
    /// Not main-actor isolated: read-only after init, safe for background use.
    @MainActor static let shared = SemanticLexicon()

    private(set) var entries: [SemanticEntry] = []

    private init() {
        guard let embedding = smartFoodSearchEmbedding else { return }
        let kb = SearchKnowledgeBase.shared

        func add(_ phrase: String, _ kind: SemanticEntry.Kind) {
            // normalize to lowercase, as Tokenizer does
            let normalized = phrase.lowercased()
            guard let vec = embedding.vector(for: normalized) else { return }
            entries.append(SemanticEntry(
                phrase: normalized,
                kind: kind,
                vector: vec
            ))
        }

        // --- Nutrients ---
        for (phrase, nutrient) in kb.nutrientMap {
            add(phrase, .nutrient(nutrient))
        }

        // --- Allergens (generic AllergenType level) ---
        for (phrase, allergenType) in kb.allergenMap {
            add(phrase, .allergen(allergenType))
        }

        // --- Diets ---
        // Direct diet phrases mapped to DietType enum
        for (phrase, dietType) in kb.dietMap {
            add(phrase, .diet(dietType))
        }

        // Synonyms that resolve to DietType via their canonical string
        for (synonym, canonicalName) in kb.dietSynonyms {
            if let t = DietType.from(string: canonicalName) {
                add(synonym, .diet(t))
            }
        }

        // --- Operators: phrase → OpToken ---

        func opToken(from token: String) -> Tokenizer.OpToken? {
            switch token {
            case "_op_lt_":  return .lt
            case "_op_lte_": return .lte
            case "_op_gt_":  return .gt
            case "_op_gte_": return .gte
            case "_op_eq_":  return .eq
            case "_op_neq_": return .neq
            default:         return nil
            }
        }

        // Phrase operators like "less than or equal to", "at least", etc.
        for (pattern, tokenString) in kb.operatorPhraseMap {
            if let op = opToken(from: tokenString) {
                add(pattern, .op(op))
            }
        }

        // Comparative adjectives like "less", "more", "high"
        for (word, tokenString) in kb.comparativeAdjectives {
            if let op = opToken(from: tokenString) {
                add(word, .op(op))
            }
        }

        // NOTE: strictOperatorMap ("<=", ">=") usually has no embedding vectors,
        // so we skip them.
    }

    func bestMatch(for phrase: String, minCosine: Double = 0.6) -> SemanticEntry? {
        guard let embedding = smartFoodSearchEmbedding,
              let q = embedding.vector(for: phrase.lowercased()) else { return nil }

        func cosine(_ a: [Double], _ b: [Double]) -> Double {
            var dot = 0.0, na = 0.0, nb = 0.0
            let count = min(a.count, b.count)
            for i in 0..<count {
                let av = a[i], bv = b[i]
                dot += av * bv
                na  += av * av
                nb  += bv * bv
            }
            if na == 0 || nb == 0 { return -1 }
            return dot / (sqrt(na) * sqrt(nb))
        }

        var best: SemanticEntry?
        var bestScore = minCosine

        for entry in entries {
            let c = cosine(q, entry.vector)
            if c > bestScore {
                bestScore = c
                best = entry
            }
        }
        return best
    }
}
