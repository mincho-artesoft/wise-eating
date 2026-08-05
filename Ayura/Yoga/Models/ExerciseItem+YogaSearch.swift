import Foundation

enum YogaWorkoutAyurvedaMath {
    static func aggregate(
        _ values: [(dosha: YogaDosha, durationSeconds: Double)]
    ) -> YogaDosha? {
        guard !values.isEmpty else { return nil }

        let weightedValues = values.map {
            (dosha: $0.dosha, weight: max($0.durationSeconds, 1))
        }
        let totalWeight = weightedValues.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        func weightedValue(_ keyPath: KeyPath<YogaDosha, Int>) -> Int {
            let value = weightedValues.reduce(0.0) { result, value in
                result + Double(value.dosha[keyPath: keyPath]) * value.weight
            } / totalWeight
            return min(2, max(-2, Int(value.rounded())))
        }

        return YogaDosha(
            vata: weightedValue(\.vata),
            pitta: weightedValue(\.pitta),
            kapha: weightedValue(\.kapha)
        )
    }
}

extension ExerciseItem {
    var resolvedYogaDosha: YogaDosha? {
        if let dosha {
            return dosha
        }

        guard isWorkout, let exercises else { return nil }
        let values = exercises.compactMap { link -> (YogaDosha, Double)? in
            guard let dosha = link.exercise?.dosha else { return nil }
            return (dosha, link.durationSeconds)
        }
        return YogaWorkoutAyurvedaMath.aggregate(values)
    }
}

enum ExerciseAyurvedaSearch {
    struct ParsedQuery: Sendable {
        let lexicalQuery: String
        let constraints: [AyurvedaFacetConstraint]
    }

    static func parse(_ query: String) -> ParsedQuery {
        let parsed = CanonicalFacetParser.parse(query)
        guard !parsed.constraints.isEmpty else {
            return ParsedQuery(lexicalQuery: query, constraints: [])
        }

        let genericTerms: Set<String> = [
            "asana", "asanas", "exercise", "exercises", "pose", "poses", "yoga"
        ]
        let lexicalQuery = parsed.remainingQuery
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
            .filter { !genericTerms.contains($0) }
            .joined(separator: " ")

        return ParsedQuery(
            lexicalQuery: lexicalQuery,
            constraints: parsed.constraints
        )
    }

    static func score(
        item: ExerciseItem,
        filters: AyurvedaSearchFilters,
        constraints: [AyurvedaFacetConstraint]
    ) -> Int {
        guard let dosha = item.resolvedYogaDosha else {
            return filters.isActive || !constraints.isEmpty ? -30 : 0
        }

        var score = 0
        for kind in AyurvedaSearchDosha.allCases {
            guard let preference = filters.preference(for: kind) else { continue }
            score += preferenceScore(value(kind, in: dosha), preference: preference)
        }

        for constraint in constraints {
            let scores = constraint.acceptedKeys.compactMap { key -> Int? in
                let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let kind = AyurvedaSearchDosha(rawValue: parts[1]) else {
                    return nil
                }
                let preference: AyurvedaDoshaPreference
                switch parts[0] {
                case "pacifies": preference = .pacifies
                case "aggravates": preference = .aggravates
                default: return nil
                }
                return preferenceScore(value(kind, in: dosha), preference: preference)
            }
            if let best = scores.max() {
                score += best
            }
        }
        return score
    }

    private static func value(
        _ kind: AyurvedaSearchDosha,
        in dosha: YogaDosha
    ) -> Int {
        switch kind {
        case .vata: return dosha.vata
        case .pitta: return dosha.pitta
        case .kapha: return dosha.kapha
        }
    }

    private static func preferenceScore(
        _ value: Int,
        preference: AyurvedaDoshaPreference
    ) -> Int {
        switch preference {
        case .pacifies:
            if value < 0 { return 120 + abs(value) * 10 }
            if value == 0 { return 15 }
            return -120 - value * 10
        case .neutral:
            return value == 0 ? 130 : 20 - abs(value) * 40
        case .aggravates:
            if value > 0 { return 120 + value * 10 }
            if value == 0 { return 15 }
            return -120 - abs(value) * 10
        }
    }
}
