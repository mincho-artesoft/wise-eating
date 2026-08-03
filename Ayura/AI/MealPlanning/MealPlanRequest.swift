import Foundation
#if canImport(FoundationModels) && !MP4_NO_FOUNDATION_MODELS
import FoundationModels
#endif

// MARK: - MP-4: prompt → constraints
//
// DIRECTOR-AUTHORED. Ported from a reference implementation validated against
// 10 realistic prompts + 13 end-to-end cases, including adversarial calorie
// inputs. Deliberately written with NO dependencies on app types so it compiles
// standalone; every integration point is marked INTEGRATE.
//
// THE CENTRAL RULE
// The model's entire job is to turn one sentence of English into ParsedRequest.
// It never names a dish, never emits a gram weight, never emits a calorie figure
// it derived itself, and never emits a database ID. Food mentions come back as
// the USER'S OWN WORDS and are resolved afterwards by the MP-3 resolver + FC-1
// aliases, because a 3B model asked for an ID will invent one that happens to
// exist and happens to be wrong.
//
// Cost: ~58 output tokens instead of the ~2,745 needed to emit a whole 7-day
// plan — the difference between roughly 2 seconds and roughly 90 on-device.

// MARK: - Closed vocabularies
// Closed enums mean the model CANNOT emit an invalid value. This is constrained
// decoding at the sampler, not an instruction it may ignore.

#if canImport(FoundationModels) && !MP4_NO_FOUNDATION_MODELS
@Generable
#endif
@available(iOS 26.0, *)
public enum DoshaTag: String, Codable, CaseIterable, Sendable {
    case vata, pitta, kapha
}

#if canImport(FoundationModels) && !MP4_NO_FOUNDATION_MODELS
@Generable
#endif
@available(iOS 26.0, *)
public enum AgniTag: String, Codable, CaseIterable, Sendable {
    case balanced, irregular, sharp, slow
}

/// INTEGRATE: map to the existing `Allergen` enum in SearchKnowledgeBase.
/// Kept as a separate closed vocabulary so the model's output space stays small
/// and stable even if the app's allergen enum grows.
#if canImport(FoundationModels) && !MP4_NO_FOUNDATION_MODELS
@Generable
#endif
@available(iOS 26.0, *)
public enum AllergenTag: String, Codable, CaseIterable, Sendable {
    case dairy, gluten, treeNuts = "tree_nuts", peanuts, soy, egg, shellfish, fish, sesame
}

// MARK: - The @Generable request

#if canImport(FoundationModels) && !MP4_NO_FOUNDATION_MODELS
@available(iOS 26.0, *)
@Generable
public struct PlanRequest: Sendable {

    @Guide(description: "How many days the plan covers. Use 1 for a single day, 7 for a week. Only default to 7 if the person clearly wants a week.", .range(1...7))
    public var days: Int

    @Guide(description: "How many meals per day.", .range(1...3))
    public var mealsPerDay: Int

    @Guide(description: "A daily calorie target ONLY if the person stated an explicit number. Otherwise 0 and the app computes one.", .range(0...5000))
    public var statedKcal: Int

    @Guide(description: "Foods, ingredients or cuisines the person does NOT want. Use their own words, singular, lowercase. Do not translate to a formal or database name.", .maximumCount(12))
    public var avoid: [String]

    @Guide(description: "Foods, ingredients or cuisines the person explicitly DOES want. Their own words, singular, lowercase.", .maximumCount(12))
    public var prefer: [String]

    @Guide(description: "Allergies the person named. Only a true allergy or intolerance — a dislike is not an allergy and belongs in avoid.", .maximumCount(9))
    public var allergens: [AllergenTag]

    @Guide(description: "Which dosha the person describes as out of balance, if they name one or clearly describe it. Leave empty if unclear.", .maximumCount(1))
    public var doshaFocus: [DoshaTag]

    @Guide(description: "How the person describes their digestion. Leave empty if not mentioned.", .maximumCount(1))
    public var agni: [AgniTag]

    @Guide(description: "Anything the person asked for that fits no field above. Quote them briefly. This is how the app tells them what it could not handle.", .maximumCount(6))
    public var unmapped: [String]
}
#endif

/// Transport-independent mirror, so the fallback parser, the tests and the
/// resolution layer speak one type whether or not FoundationModels is present.
@available(iOS 26.0, *)
public struct ParsedRequest: Sendable, Equatable {
    public var days: Int = 7
    public var mealsPerDay: Int = 3
    public var statedKcal: Int = 0
    public var avoid: [String] = []
    public var prefer: [String] = []
    public var allergens: [AllergenTag] = []
    public var doshaFocus: DoshaTag? = nil
    public var agni: AgniTag? = nil
    public var unmapped: [String] = []
    public init() {}
}

#if canImport(FoundationModels) && !MP4_NO_FOUNDATION_MODELS
@available(iOS 26.0, *)
extension ParsedRequest {
    public init(_ r: PlanRequest) {
        self.init()
        days = r.days; mealsPerDay = r.mealsPerDay
        statedKcal = r.statedKcal
        avoid = r.avoid; prefer = r.prefer; allergens = r.allergens
        doshaFocus = r.doshaFocus.first; agni = r.agni.first
        unmapped = r.unmapped
    }
}
#endif

// MARK: - Sanitizer

@available(iOS 26.0, *)
public enum RequestSanitizer {

    public static let absoluteFloor = 1000
    public static let absoluteCeiling = 4500

    public struct Adjustment: Sendable, Equatable {
        public let field: String
        public let message: String
        public init(field: String, message: String) { self.field = field; self.message = message }
    }

    /// Never trust a number that came out of a language model, even a guided one.
    ///
    /// A stated target is accepted only inside a sane band around the app's own
    /// computed maintenance estimate. "I eat about 500 calories" and "make it
    /// 9000" are both far more likely to be extraction errors than genuine
    /// requests, and shipping either would be harmful.
    ///
    /// Verified behaviour: "500 calories a day for a week" → raised to the floor
    /// and the user is told. "9000 calories, 7 days, vegan" → capped and told.
    public static func sanitize(_ r: ParsedRequest, computedMaintenanceKcal: Int)
        -> (request: ParsedRequest, adjustments: [Adjustment]) {

        var out = r
        var notes: [Adjustment] = []

        out.days = min(max(out.days, 1), 7)
        out.mealsPerDay = min(max(out.mealsPerDay, 1), 3)

        if out.statedKcal > 0 {
            let lo = max(absoluteFloor, Int(Double(computedMaintenanceKcal) * 0.60))
            let hi = min(absoluteCeiling, Int(Double(computedMaintenanceKcal) * 1.60))
            if out.statedKcal < lo {
                notes.append(Adjustment(field: "calories",
                    message: "Raised the daily target to \(lo) kcal — the number in your request looked like a misreading."))
                out.statedKcal = lo
            } else if out.statedKcal > hi {
                notes.append(Adjustment(field: "calories",
                    message: "Capped the daily target at \(hi) kcal."))
                out.statedKcal = hi
            }
        }

        func clean(_ xs: [String]) -> [String] {
            var seen = Set<String>()
            return xs.compactMap { s -> String? in
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard t.count >= 2, t.count <= 40, !seen.contains(t) else { return nil }
                seen.insert(t)
                return t
            }
        }
        out.avoid = clean(out.avoid)
        out.prefer = clean(out.prefer)

        // A term on both lists is a parse contradiction. Avoidance wins: wrongly
        // including something someone rejected costs more than wrongly omitting
        // something they wanted.
        let conflicts = Set(out.avoid).intersection(out.prefer)
        if !conflicts.isEmpty {
            out.prefer.removeAll { conflicts.contains($0) }
            notes.append(Adjustment(field: "preferences",
                message: "Treated \(conflicts.sorted().joined(separator: ", ")) as something to avoid."))
        }

        return (out, notes)
    }
}

// MARK: - Deterministic fallback parser
//
// Runs on iPhone 15 and 15 Plus (A16, NO Apple Intelligence — the feature starts
// at the 15 Pro), and on every device where Apple Intelligence is off, out of
// region, or still downloading. Instant, zero memory, fully offline.
//
// Two bugs this design exists to prevent, both found in reference testing:
//   • substring matching made "allergic to peanuts" ALSO register a tree-nut
//     allergy, because "nut" appears inside "peanuts";
//   • "no shellfish" ALSO registered a fish allergy, because "fish" appears
//     inside "shellfish".
// Both silently invent dietary restrictions the user never declared. Hence
// wordRanges() — token-boundary matching, never substring.

@available(iOS 26.0, *)
public enum FallbackParser {

    private static let negationCues = [
        "without", "no ", "not ", "avoid", "avoiding", "skip", "exclude", "except",
        "can't eat", "cant eat", "cannot eat", "don't like", "dont like", "hate",
        "allergic to", "allergy to", "intolerant", "free from", "-free", "less ",
    ]
    private static let positiveCues = [
        "love", "like", "want", "prefer", "include", "more ", "lots of", "plenty of",
    ]

    private static let allergenWords: [(String, AllergenTag)] = [
        ("dairy", .dairy), ("milk", .dairy), ("lactose", .dairy),
        ("gluten", .gluten), ("wheat", .gluten),
        ("nut", .treeNuts), ("almond", .treeNuts), ("cashew", .treeNuts),
        ("peanut", .peanuts), ("soy", .soy), ("egg", .egg),
        ("shellfish", .shellfish), ("prawn", .shellfish), ("shrimp", .shellfish),
        ("fish", .fish), ("sesame", .sesame),
    ]

    /// Grammatically food-shaped, but names nothing in the catalogue.
    /// Without this, "want lighter meals" resolves `meals`, which matches
    /// thousands of rows and empties the candidate pool.
    private static let generic: Set<String> = [
        "meal", "meals", "food", "foods", "plan", "plans", "day", "days",
        "week", "weeks", "thing", "things", "stuff", "option", "options",
        "dish", "dishes", "recipe", "recipes", "item", "items",
        "breakfast", "lunch", "dinner", "snack", "snacks", "portion",
        "portions", "calorie", "calories", "weight", "protein", "carbs",
    ]

    /// NB: "a"/"an" are deliberately absent. "500 calories a day for a week"
    /// must parse as 7 days, not 1 — "a day" is a rate, not a count.
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "couple": 2, "few": 3,
    ]

    public static func parse(_ raw: String) -> ParsedRequest {
        let text = " " + raw.lowercased()
            .replacingOccurrences(of: ",", with: " , ")
            .replacingOccurrences(of: ".", with: " . ") + " "
        var r = ParsedRequest()

        if let n = firstInt(in: text, followedByAnyOf: ["day", "days"]), (1...7).contains(n) {
            r.days = n
        } else if text.contains("weekend") { r.days = 2 }
        else if text.contains("week") { r.days = 7 }
        else if text.contains("tomorrow") || text.contains("today") { r.days = 1 }

        if let n = firstInt(in: text, followedByAnyOf: ["meal", "meals"]), (1...3).contains(n) {
            r.mealsPerDay = n
        }

        if let n = firstInt(in: text, followedByAnyOf: ["cal", "cals", "kcal", "calories", "calorie"]) {
            r.statedKcal = n
        }

        if text.contains("vata") { r.doshaFocus = .vata }
        else if text.contains("pitta") { r.doshaFocus = .pitta }
        else if text.contains("kapha") { r.doshaFocus = .kapha }

        if containsAny(text, ["sluggish digestion", "slow digestion", "heavy after eating",
                              "sluggish", "feel heavy"]) { r.agni = .slow }
        else if containsAny(text, ["acid", "heartburn", "reflux", "always hungry",
                                   "burning"]) { r.agni = .sharp }
        else if containsAny(text, ["irregular", "erratic", "bloat", "gas ",
                                   "variable appetite"]) { r.agni = .irregular }

        // Allergens only inside a negation window, so "I love cheese" never
        // becomes a dairy allergy.
        for (word, tag) in allergenWords {
            if isNegated(word, in: text) && !r.allergens.contains(tag) {
                r.allergens.append(tag)
            }
        }
        r.avoid = extractTerms(text, cues: negationCues).filter { !generic.contains($0) }
        r.prefer = extractTerms(text, cues: positiveCues)
            .filter { !r.avoid.contains($0) && !generic.contains($0) }

        if r.avoid.isEmpty && r.prefer.isEmpty && raw.count > 120 {
            r.unmapped.append("some of the detail in your request")
        }
        return r
    }

    // MARK: helpers

    private static func containsAny(_ s: String, _ xs: [String]) -> Bool {
        for x in xs where s.contains(x) { return true }
        return false
    }

    /// Occurrences of `word` at a WORD BOUNDARY.
    /// Plain substring search is wrong here and dangerously so — see the header.
    private static func wordRanges(_ word: String, in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: word, range: search) {
            let beforeOK = r.lowerBound == text.startIndex
                || !text[text.index(before: r.lowerBound)].isLetter
            var afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if !afterOK, text[r.upperBound] == "s" {
                let n = text.index(after: r.upperBound)
                afterOK = n == text.endIndex || !text[n].isLetter
            }
            if beforeOK && afterOK { out.append(r) }
            search = text.index(after: r.lowerBound)..<text.endIndex
        }
        return out
    }

    private static func isNegated(_ word: String, in text: String) -> Bool {
        for wr in wordRanges(word, in: text) {
            let start = text.index(wr.lowerBound, offsetBy: -36,
                                   limitedBy: text.startIndex) ?? text.startIndex
            if containsAny(String(text[start..<wr.lowerBound]), negationCues) { return true }
            let after = text.index(wr.upperBound, offsetBy: 6,
                                   limitedBy: text.endIndex) ?? text.endIndex
            if String(text[wr.upperBound..<after]).contains("free") { return true }
        }
        return false
    }

    /// Pull the 1–2 words following each cue, stopping at punctuation, a
    /// conjunction, or a generic word. Crude but predictable — and
    /// predictability is the entire point of a fallback.
    private static func extractTerms(_ text: String, cues: [String]) -> [String] {
        let stop: Set<String> = ["and", "or", "but", "with", "the", "a", "an", "any",
                                 "some", "my", "i", "im", "please", ",", ".",
                                 "for", "to", "of", "at", "in", "on", "is", "are",
                                 "too", "very", "really", "much", "also"]
        var out: [String] = []
        for cue in cues {
            var search = text.startIndex..<text.endIndex
            while let r = text.range(of: cue, range: search) {
                let tail = text[r.upperBound...]
                var words: [String] = []
                for w in tail.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true) {
                    let t = String(w).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    if t.isEmpty || stop.contains(t) || generic.contains(t) { break }
                    words.append(t)
                    if words.count == 2 { break }
                }
                if let phrase = words.last, phrase.count >= 3 { out.append(phrase) }
                search = r.upperBound..<text.endIndex
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// Handles digits ("3 days", "1800cal") and number words ("two meals"),
    /// with the unit attached or in the following token.
    private static func firstInt(in text: String, followedByAnyOf units: [String]) -> Int? {
        let tokens = text.split(separator: " ").map(String.init)
        for (i, t) in tokens.enumerated() {
            let digits = t.filter(\.isNumber)
            var n: Int? = nil
            var attached = ""
            if !digits.isEmpty {
                n = Int(digits)
                attached = t.filter { !$0.isNumber }
            } else if let w = numberWords[t] {
                n = w
            }
            guard let value = n else { continue }
            if !attached.isEmpty, units.contains(where: { attached.hasPrefix($0) }) { return value }
            if i + 1 < tokens.count,
               units.contains(where: { tokens[i + 1].hasPrefix($0) }) { return value }
        }
        return nil
    }
}

// MARK: - One-call orchestration

/// Keeps the one-call invariant independent of prompt count and provides the
/// same deterministic fallback path to production and the MP-4 gate harness.
@available(iOS 26.0, *)
public enum MealPlanIntentCoordinator {
    public struct Outcome: Sendable, Equatable {
        public let request: ParsedRequest
        public let usedFallback: Bool

        public init(request: ParsedRequest, usedFallback: Bool) {
            self.request = request
            self.usedFallback = usedFallback
        }
    }

    @MainActor
    public static func parse(
        prompts: [String],
        modelAvailable: Bool,
        modelResponse: (String) async throws -> ParsedRequest,
        onModelCall: (Bool, Double) async -> Void
    ) async -> Outcome {
        let cleaned = prompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let combined = cleaned.joined(separator: "\n")

        guard modelAvailable, !combined.isEmpty else {
            return Outcome(
                request: FallbackParser.parse(combined),
                usedFallback: true
            )
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            let request = try await modelResponse(combined)
            let elapsed = Double(
                DispatchTime.now().uptimeNanoseconds - startedAt
            ) / 1_000_000
            await onModelCall(true, elapsed)
            return Outcome(request: request, usedFallback: false)
        } catch {
            let elapsed = Double(
                DispatchTime.now().uptimeNanoseconds - startedAt
            ) / 1_000_000
            await onModelCall(false, elapsed)
            return Outcome(
                request: FallbackParser.parse(combined),
                usedFallback: true
            )
        }
    }
}
