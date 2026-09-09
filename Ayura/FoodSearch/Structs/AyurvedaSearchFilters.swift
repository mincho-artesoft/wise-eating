import Foundation

enum AyurvedaSearchDosha: String, CaseIterable, Identifiable, Sendable {
    case vata
    case pitta
    case kapha

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

enum AyurvedaDoshaPreference: String, CaseIterable, Identifiable, Sendable {
    case pacifies
    case neutral
    case aggravates

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pacifies: return "Pacifies"
        case .neutral: return "Neutral"
        case .aggravates: return "Aggravates"
        }
    }
}

struct AyurvedaSearchFilters: Equatable, Sendable {
    var vata: AyurvedaDoshaPreference?
    var pitta: AyurvedaDoshaPreference?
    var kapha: AyurvedaDoshaPreference?
    var rasa: Set<String> = []
    var virya: String?
    var gunas: Set<String> = []
    var easyOnDigestion = false

    static let empty = AyurvedaSearchFilters()

    var isActive: Bool {
        vata != nil
            || pitta != nil
            || kapha != nil
            || !rasa.isEmpty
            || virya != nil
            || !gunas.isEmpty
            || easyOnDigestion
    }

    var activeCount: Int {
        [vata, pitta, kapha].compactMap { $0 }.count
            + rasa.count
            + (virya == nil ? 0 : 1)
            + gunas.count
            + (easyOnDigestion ? 1 : 0)
    }

    func preference(for dosha: AyurvedaSearchDosha) -> AyurvedaDoshaPreference? {
        switch dosha {
        case .vata: return vata
        case .pitta: return pitta
        case .kapha: return kapha
        }
    }

    mutating func set(
        _ preference: AyurvedaDoshaPreference?,
        for dosha: AyurvedaSearchDosha
    ) {
        switch dosha {
        case .vata: vata = preference
        case .pitta: pitta = preference
        case .kapha: kapha = preference
        }
    }

    mutating func cyclePreference(for dosha: AyurvedaSearchDosha) {
        let nextPreference: AyurvedaDoshaPreference?
        switch preference(for: dosha) {
        case nil:
            nextPreference = .pacifies
        case .pacifies:
            nextPreference = .neutral
        case .neutral:
            nextPreference = .aggravates
        case .aggravates:
            nextPreference = nil
        }
        set(nextPreference, for: dosha)
    }
}

struct AyurvedaSearchTemporalContext: Sendable {
    let season: String
    let period: String

    static func current(
        date: Date = .now,
        calendar: Calendar = .current
    ) -> Self {
        let month = calendar.component(.month, from: date)
        let hour = calendar.component(.hour, from: date)

        let season: String
        switch month {
        case 1, 2: season = "shishira"
        case 3, 4: season = "vasanta"
        case 5, 6: season = "grishma"
        case 7, 8: season = "varsha"
        case 9, 10: season = "sharad"
        default: season = "hemanta"
        }

        let period: String
        switch hour {
        case 5..<11: period = "morning"
        case 11..<15: period = "midday"
        case 15..<21: period = "evening"
        default: period = "night"
        }

        return Self(season: season, period: period)
    }
}

enum AyurvedaSearchRanker {
    /// Rasa, virya and the lower-priority facets are true facets for profiled
    /// foods. Dosha preferences deliberately never reject a result.
    static func matches(
        _ metadata: AyurvedaCanonicalSearchMetadata,
        filters: AyurvedaSearchFilters
    ) -> Bool {
        if !filters.rasa.isEmpty {
            let values = Set(metadata.rasa.map(AyurvedaFacet.normalize))
            if values.isDisjoint(with: filters.rasa) {
                return false
            }
        }
        if let virya = filters.virya,
           AyurvedaFacet.normalize(metadata.virya ?? "") != virya {
            return false
        }
        if !filters.gunas.isEmpty {
            let values = Set(metadata.gunas.map(AyurvedaFacet.normalize))
            if values.isDisjoint(with: filters.gunas) {
                return false
            }
        }
        if filters.easyOnDigestion {
            let isEasy = (metadata.digestibility ?? 0) >= 4
                || (metadata.agniEffect ?? 0) > 0
            if !isEasy {
                return false
            }
        }
        return true
    }

    /// Explicit text facets keep unprofiled results visible. For a profiled
    /// result, all non-dosha constraints remain hard facets.
    static func matches(
        _ metadata: AyurvedaCanonicalSearchMetadata,
        constraints: [AyurvedaFacetConstraint]
    ) -> Bool {
        for constraint in constraints {
            let hardKeys = constraint.acceptedKeys.filter {
                !$0.hasPrefix("pacifies:") && !$0.hasPrefix("aggravates:")
            }
            if !hardKeys.isEmpty && metadata.facets.isDisjoint(with: hardKeys) {
                return false
            }
        }
        return true
    }

    static func score(
        _ metadata: AyurvedaCanonicalSearchMetadata,
        filters: AyurvedaSearchFilters,
        constraints: [AyurvedaFacetConstraint],
        temporalContext: AyurvedaSearchTemporalContext,
        constitutionTarget: AyurvedaDoshaDistribution? = nil
    ) -> Double {
        var score = 0.0

        // Context is intentionally a quiet boost rather than a user-facing
        // exclusion. It only breaks otherwise similar search results.
        if metadata.seasons.contains(temporalContext.season) {
            score += 8
        }
        if metadata.timeOfDay.contains(temporalContext.period) {
            score += 6
        }

        // A constitution/current check-in changes ordering only. It never
        // participates in `matches`, so an unfavorable fit cannot hide food.
        if let constitutionTarget, metadata.sourceTier != "estimated" {
            score += constitutionTarget.doshaFit(
                vata: metadata.doshaVata,
                pitta: metadata.doshaPitta,
                kapha: metadata.doshaKapha
            ) * 24
        }

        for dosha in AyurvedaSearchDosha.allCases {
            guard let preference = filters.preference(for: dosha) else { continue }
            score += doshaScore(
                value(for: dosha, in: metadata),
                preference: preference
            )
        }

        if !filters.rasa.isEmpty { score += 12 }
        if filters.virya != nil { score += 8 }
        if !filters.gunas.isEmpty { score += 8 }
        if filters.easyOnDigestion { score += 10 }

        for constraint in constraints {
            let doshaScores = constraint.acceptedKeys.compactMap {
                parsedDoshaScore(key: $0, metadata: metadata)
            }
            if let best = doshaScores.max() {
                score += best
            } else if !metadata.facets.isDisjoint(with: constraint.acceptedKeys) {
                score += 8
            }
        }

        return score
    }

    private static func value(
        for dosha: AyurvedaSearchDosha,
        in metadata: AyurvedaCanonicalSearchMetadata
    ) -> Int {
        switch dosha {
        case .vata: return metadata.doshaVata
        case .pitta: return metadata.doshaPitta
        case .kapha: return metadata.doshaKapha
        }
    }

    private static func doshaScore(
        _ value: Int,
        preference: AyurvedaDoshaPreference
    ) -> Double {
        switch preference {
        case .pacifies:
            return Double(-value) * 24
        case .neutral:
            return 24 - Double(abs(value)) * 12
        case .aggravates:
            return Double(value) * 24
        }
    }

    private static func parsedDoshaScore(
        key: String,
        metadata: AyurvedaCanonicalSearchMetadata
    ) -> Double? {
        guard let facet = AyurvedaFacet(key: key),
              let dosha = AyurvedaSearchDosha(rawValue: facet.value) else {
            return nil
        }
        let preference: AyurvedaDoshaPreference
        switch facet.kind {
        case .pacifies: preference = .pacifies
        case .aggravates: preference = .aggravates
        default: return nil
        }
        return doshaScore(value(for: dosha, in: metadata), preference: preference)
    }
}
