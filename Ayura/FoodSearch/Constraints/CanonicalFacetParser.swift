import Foundation

struct AyurvedaFacetConstraint: Hashable, Sendable {
    /// Keys within one constraint are alternatives; separate constraints compose with AND.
    let acceptedKeys: Set<String>

    init(_ acceptedKeys: Set<String>) {
        self.acceptedKeys = acceptedKeys
    }
}

struct AyurvedaFacetParseResult: Sendable {
    let remainingQuery: String
    let constraints: [AyurvedaFacetConstraint]

    static func passthrough(_ query: String) -> Self {
        Self(remainingQuery: query, constraints: [])
    }
}

enum CanonicalFacetParser {
    private static let doshas = ["vata", "pitta", "kapha"]
    private static let rasaValues = [
        "sweet",
        "sour",
        "salty",
        "pungent",
        "bitter",
        "astringent",
    ]
    private static let vipakaValues = ["sweet", "sour", "pungent"]
    private static let gunaValues = [
        "dense",
        "dry",
        "heavy",
        "light",
        "liquid",
        "oily",
        "penetrating",
        "rough",
        "sharp",
        "slimy",
        "smooth",
        "soft",
    ]
    private static let seasonValues = [
        "grishma",
        "hemanta",
        "sharad",
        "shishira",
        "varsha",
        "vasanta",
    ]
    private static let fastSignals = [
        "cool",
        "warm",
        "heat",
        "virya:",
        "neutral virya",
        "virya neutral",
        "rasa",
        "taste",
        "vipaka",
        "post-digestive",
        "post digestive",
        "guna",
        "quality",
        "pacif",
        "balanc",
        "calm",
        "good for",
        "aggravat",
        "avoid for",
        "agni",
        "digest",
        "summer",
        "winter",
        "spring",
        "autumn",
        "fall",
        "monsoon",
        "rainy",
        "grishma",
        "hemanta",
        "sharad",
        "shishira",
        "varsha",
        "vasanta",
        "ritu:",
        "season:",
        "concept:",
        "ushna",
        "sheeta",
        "deepana",
    ]

    static func parse(
        _ query: String,
        synonyms: [String: String] = [:]
    ) -> AyurvedaFacetParseResult {
        let lowerQuery = query.lowercased()
        guard fastSignals.contains(where: lowerQuery.contains) else {
            return .passthrough(query)
        }

        var working = expandFacetSynonyms(in: lowerQuery, synonyms: synonyms)
        var constraints: [AyurvedaFacetConstraint] = []
        var seen = Set<Set<String>>()

        func add(_ keys: Set<String>) {
            guard !keys.isEmpty, seen.insert(keys).inserted else { return }
            constraints.append(AyurvedaFacetConstraint(keys))
        }

        func consume(_ pattern: String, keys: Set<String>) {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                return
            }
            let range = NSRange(working.startIndex..., in: working)
            guard regex.firstMatch(in: working, range: range) != nil else { return }
            add(keys)
            working = regex.stringByReplacingMatches(
                in: working,
                range: range,
                withTemplate: " "
            )
        }

        func remove(_ pattern: String) {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                return
            }
            let range = NSRange(working.startIndex..., in: working)
            working = regex.stringByReplacingMatches(
                in: working,
                range: range,
                withTemplate: " "
            )
        }

        consumeExplicitFacets(in: &working, add: add)

        consume(#"\bneutral[- ]virya\b|\bvirya[- ]neutral\b"#, keys: ["virya:neutral"])
        consume(#"\bcooling(?:[- ]foods?)?\b"#, keys: ["virya:cooling"])
        consume(#"\b(?:warming|heating)(?:[- ]foods?)?\b"#, keys: ["virya:heating"])

        for value in rasaValues {
            consume(
                #"\b\#(value)[- ]+(?:rasa|taste)\b|\b(?:rasa|taste)[- :]+\#(value)\b"#,
                keys: ["rasa:\(value)"]
            )
        }
        for value in vipakaValues {
            consume(
                #"\b\#(value)[- ]+(?:vipaka|post[- ]digestive)\b|\b(?:vipaka|post[- ]digestive)[- :]+\#(value)\b"#,
                keys: ["vipaka:\(value)"]
            )
        }
        for value in gunaValues {
            consume(
                #"\b\#(value)[- ]+(?:gunas?|quality|qualities)\b|\b(?:gunas?|quality|qualities)[- :]+\#(value)\b"#,
                keys: ["guna:\(value)"]
            )
        }

        for dosha in doshas {
            consume(
                #"\b(?:balances?|calms?|pacif(?:y|ies)|good[- ]for)[- ]+\#(dosha)\b|\b\#(dosha)[- ]+(?:balancing|calming|pacifying)\b"#,
                keys: ["pacifies:\(dosha)"]
            )
            consume(
                #"\b(?:aggravates?|avoid[- ]for)[- ]+\#(dosha)\b|\b\#(dosha)[- ]+aggravating\b"#,
                keys: ["aggravates:\(dosha)"]
            )
        }

        consume(#"\bkindles?[- ]+agni\b"#, keys: ["agni:kindles"])
        consume(#"\bdampens?[- ]+agni\b"#, keys: ["agni:dampens"])
        consume(#"\bfor[- ]+digestion\b|\bdigestive[- ]+foods?\b"#, keys: ["concept:digestion"])
        consume(#"\b(?:light|easy)[- ]+to[- ]+digest\b"#, keys: ["digestibility:light"])
        consume(#"\b(?:heavy|hard)[- ]+to[- ]+digest\b"#, keys: ["digestibility:heavy"])

        consume(#"\bsummer(?:[- ]foods?)?\b"#, keys: ["season:grishma"])
        consume(
            #"\bwinter(?:[- ]foods?)?\b"#,
            keys: ["season:hemanta", "season:shishira"]
        )
        consume(#"\bspring(?:[- ]foods?)?\b"#, keys: ["season:vasanta"])
        consume(#"\b(?:autumn|fall)(?:[- ]foods?)?\b"#, keys: ["season:sharad"])
        consume(
            #"\b(?:monsoon|rainy)(?:[- ]season)?(?:[- ]foods?)?\b"#,
            keys: ["season:varsha"]
        )
        for season in seasonValues {
            consume(#"\b\#(season)(?:[- ]ritu)?\b"#, keys: ["season:\(season)"])
        }

        guard !constraints.isEmpty else {
            return .passthrough(query)
        }
        return AyurvedaFacetParseResult(
            remainingQuery: collapseWhitespace(working),
            constraints: constraints
        )
    }

    private static func consumeExplicitFacets(
        in query: inout String,
        add: (Set<String>) -> Void
    ) {
        let pattern = #"\b(virya|rasa|vipaka|gunas?|pacifies|aggravates|agni|digestibility|season|ritu|concept):([a-z0-9-]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let original = query
        let range = NSRange(original.startIndex..., in: original)
        let matches = regex.matches(in: original, range: range)
        var acceptedRanges: [NSRange] = []

        for match in matches {
            guard let kindRange = Range(match.range(at: 1), in: original),
                  let valueRange = Range(match.range(at: 2), in: original) else {
                continue
            }
            var kind = String(original[kindRange])
            let value = String(original[valueRange])
            if kind == "ritu" { kind = "season" }
            if kind == "gunas" { kind = "guna" }
            let key = "\(kind):\(value)"
            guard isKnownExplicitFacet(kind: kind, value: value) else { continue }
            add([key])
            acceptedRanges.append(match.range)
        }

        for range in acceptedRanges.reversed() {
            guard let swiftRange = Range(range, in: query) else { continue }
            query.replaceSubrange(swiftRange, with: " ")
        }
    }

    private static func isKnownExplicitFacet(
        kind: String,
        value: String
    ) -> Bool {
        switch kind {
        case "virya":
            return ["cooling", "heating", "neutral"].contains(value)
        case "rasa":
            return rasaValues.contains(value)
        case "vipaka":
            return vipakaValues.contains(value)
        case "guna":
            return gunaValues.contains(value)
        case "pacifies", "aggravates":
            return doshas.contains(value)
        case "agni":
            return ["kindles", "dampens"].contains(value)
        case "digestibility":
            return ["light", "heavy"].contains(value)
        case "season":
            return seasonValues.contains(value)
        case "concept":
            return value == "digestion"
        default:
            return false
        }
    }

    private static func expandFacetSynonyms(
        in query: String,
        synonyms: [String: String]
    ) -> String {
        var result = query
        for synonym in ["ushna", "sheeta", "deepana"] {
            guard let replacement = synonyms[synonym],
                  let regex = try? NSRegularExpression(
                    pattern: #"\b\#(NSRegularExpression.escapedPattern(for: synonym))\b"#
                  ) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement.lowercased()
            )
        }
        return result
    }

    private static func collapseWhitespace(_ query: String) -> String {
        query
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
