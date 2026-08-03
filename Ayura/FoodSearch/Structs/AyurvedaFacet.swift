import Foundation

enum AyurvedaFacetKind: String, CaseIterable, Sendable {
    case virya
    case rasa
    case vipaka
    case guna
    case pacifies
    case aggravates
    case agni
    case digestibility
    case season
    case time
    case category
    case concept
}

struct AyurvedaFacet: Hashable, Sendable {
    let kind: AyurvedaFacetKind
    let value: String

    var key: String {
        "\(kind.rawValue):\(value)"
    }

    init?(kind: AyurvedaFacetKind, value: String) {
        let normalized = Self.normalize(value)
        guard !normalized.isEmpty else { return nil }
        self.kind = kind
        self.value = normalized
    }

    init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let kind = AyurvedaFacetKind(rawValue: parts[0]) else {
            return nil
        }
        self.init(kind: kind, value: parts[1])
    }

    static func canonicalKeys(from profile: AyurvedaProfile) -> Set<String> {
        guard isCanonicalSeedProfile(profile) else { return [] }
        return searchKeys(from: profile)
    }

    /// Search facets for both bundled profiles and records created in the editor.
    static func searchKeys(from profile: AyurvedaProfile) -> Set<String> {
        searchKeys(
            category: profile.category,
            doshaVata: profile.doshaVata,
            doshaPitta: profile.doshaPitta,
            doshaKapha: profile.doshaKapha,
            rasa: profile.rasa,
            virya: profile.virya,
            vipaka: profile.vipaka,
            gunas: profile.gunas,
            agniEffect: profile.agniEffect,
            digestibility: profile.digestibility,
            seasons: profile.seasons,
            timeOfDay: profile.timeOfDay
        )
    }

    static func canonicalMapFromBundledSeed(
        bundle: Bundle = .main
    ) throws -> [Int: Set<String>] {
        try canonicalSearchMapFromBundledSeed(bundle: bundle).mapValues {
            $0.facets
        }
    }

    static func canonicalSearchMapFromBundledSeed(
        bundle: Bundle = .main
    ) throws -> [Int: AyurvedaCanonicalSearchMetadata] {
        guard let url = bundle.url(
            forResource: "ayurveda_seed",
            withExtension: "json.gz"
        ) else {
            throw AyurvedaFacetSeedError.missingBundle
        }

        let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
        let plain = try ZlibGzip.decompress(data: compressed)
        let seed = try JSONDecoder().decode(
            AyurvedaFacetSeedDocument.self,
            from: plain
        )
        guard seed.dravyas.count == 704,
              seed.recipes.count == 1_511,
              seed.links.count == 2_336 else {
            throw AyurvedaFacetSeedError.invalidCounts
        }

        let profiles = seed.dravyas + seed.recipes
        let profilesByID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.id, $0) }
        )
        var result: [Int: AyurvedaCanonicalSearchMetadata] = [:]

        for profile in profiles {
            guard profile.isCanonical else { continue }
            guard profile.safety.enforcedMinAgeMonths >= 0,
                  profile.safety.enforcedMinAgeMonths <= profile.safety.minAgeMonths,
                  ["authored", "legacyImport"].contains(profile.safety.ageProvenance)
            else {
                throw AyurvedaFacetSeedError.invalidAgeMetadata(profile.id)
            }
            result[profile.foodId] = AyurvedaCanonicalSearchMetadata(
                profile: profile,
                enforcedMinAgeMonths: profile.edible
                    ? profile.safety.enforcedMinAgeMonths
                    : nil,
                sourceTier: nil
            )
        }

        // USDA links extend the searchable coverage beyond the direct canonical
        // rows. Direct profiles always win when an ID appears in both sets.
        for link in seed.links {
            guard result[link.fdcId]?.sourceTier != nil || result[link.fdcId] == nil,
                  let profile = profilesByID[link.dravyaId] else {
                continue
            }
            result[link.fdcId] = AyurvedaCanonicalSearchMetadata(
                profile: profile,
                enforcedMinAgeMonths: profile.edible
                    ? profile.safety.enforcedMinAgeMonths
                    : nil,
                sourceTier: link.tier
            )
        }
        return result
    }

    static func searchKeys(
        category: String,
        doshaVata: Int,
        doshaPitta: Int,
        doshaKapha: Int,
        rasa: [String],
        virya: String?,
        vipaka: String?,
        gunas: [String],
        agniEffect: Int?,
        digestibility: Int?,
        seasons: [String],
        timeOfDay: [String]
    ) -> Set<String> {
        var facets = Set<String>()

        if let virya {
            insert(.virya, virya, into: &facets)
        }
        for value in rasa {
            insert(.rasa, value, into: &facets)
        }
        if let vipaka {
            insert(.vipaka, vipaka, into: &facets)
        }
        for value in gunas {
            insert(.guna, value, into: &facets)
        }

        insertDosha(
            value: doshaVata,
            dosha: "vata",
            into: &facets
        )
        insertDosha(
            value: doshaPitta,
            dosha: "pitta",
            into: &facets
        )
        insertDosha(
            value: doshaKapha,
            dosha: "kapha",
            into: &facets
        )

        if let agni = agniEffect {
            if agni > 0 {
                insert(.agni, "kindles", into: &facets)
            } else if agni < 0 {
                insert(.agni, "dampens", into: &facets)
            }
        }

        if let digestibility {
            if digestibility >= 4 {
                insert(.digestibility, "light", into: &facets)
            } else if digestibility <= 2 {
                insert(.digestibility, "heavy", into: &facets)
            }
        }

        for season in seasons {
            insert(.season, season, into: &facets)
        }
        for period in timeOfDay {
            insert(.time, period, into: &facets)
        }

        let normalizedCategory = normalize(category)
        if !normalizedCategory.isEmpty {
            insert(.category, normalizedCategory, into: &facets)
            insert(.concept, normalizedCategory, into: &facets)
        }

        if (agniEffect ?? 0) > 0 || (digestibility ?? 0) >= 4 {
            insert(.concept, "digestion", into: &facets)
        }

        return facets
    }

    static func isCanonicalSeedProfile(_ profile: AyurvedaProfile) -> Bool {
        switch profile.kind {
        case "dravya":
            return profile.id.hasPrefix("dravya.")
        case "recipe":
            return profile.id.hasPrefix("recipe.")
        default:
            return false
        }
    }

    static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(
                of: "-+",
                with: "-",
                options: .regularExpression
            )
    }

    private static func insertDosha(
        value: Int,
        dosha: String,
        into facets: inout Set<String>
    ) {
        if value < 0 {
            insert(.pacifies, dosha, into: &facets)
        } else if value > 0 {
            insert(.aggravates, dosha, into: &facets)
        }
    }

    private static func insert(
        _ kind: AyurvedaFacetKind,
        _ value: String,
        into facets: inout Set<String>
    ) {
        if let facet = AyurvedaFacet(kind: kind, value: value) {
            facets.insert(facet.key)
        }
    }
}

private enum AyurvedaFacetSeedError: LocalizedError {
    case missingBundle
    case invalidCounts
    case invalidAgeMetadata(String)

    var errorDescription: String? {
        switch self {
        case .missingBundle:
            return "ayurveda_seed.json.gz is missing from the app bundle"
        case .invalidCounts:
            return "the Ayurveda facet seed must contain 704 dravyas and 1,511 recipes"
        case .invalidAgeMetadata(let profileID):
            return "the Ayurveda seed has invalid age metadata for \(profileID)"
        }
    }
}

private struct AyurvedaFacetSeedDocument: Decodable {
    let dravyas: [AyurvedaFacetSeedProfile]
    let recipes: [AyurvedaFacetSeedProfile]
    let links: [AyurvedaFacetSeedLink]
}

private struct AyurvedaFacetSeedProfile: Decodable {
    struct Dosha: Decodable {
        let vata: Int
        let pitta: Int
        let kapha: Int
    }

    struct Safety: Decodable {
        let minAgeMonths: Int
        let enforcedMinAgeMonths: Int
        let ageProvenance: String
        let ageSource: String?
    }

    struct Confidence: Decodable {
        let ayur: Double
    }

    let id: String
    let name: String
    let category: String
    let edible: Bool
    let dosha: Dosha
    let seasons: [String]
    let timeOfDay: [String]
    let foodId: Int
    let rasa: [String]?
    let virya: String?
    let vipaka: String?
    let gunas: [String]?
    let prabhava: String?
    let agniEffect: Int?
    let digestibility: Int?
    let contraindications: [String]?
    let confidence: Confidence
    let safety: Safety

    var isCanonical: Bool {
        id.hasPrefix("dravya.") || id.hasPrefix("recipe.")
    }
}

private struct AyurvedaFacetSeedLink: Decodable {
    let fdcId: Int
    let dravyaId: String
    let tier: String
}

struct AyurvedaCanonicalSearchMetadata: Codable, Hashable, Sendable {
    let facets: Set<String>
    let enforcedMinAgeMonths: Int?
    let sourceProfileName: String
    let sourceTier: String?
    let doshaVata: Int
    let doshaPitta: Int
    let doshaKapha: Int
    let rasa: [String]
    let virya: String?
    let vipaka: String?
    let gunas: [String]
    let agniEffect: Int?
    let digestibility: Int?
    let seasons: [String]
    let timeOfDay: [String]
    let category: String
    let edible: Bool
    let prabhava: String?
    let contraindications: [String]
    let confidenceAyur: Double

    var isInferred: Bool {
        sourceTier == "near" || sourceTier == "derived"
    }

    var sourceCaption: String? {
        switch sourceTier {
        case "near":
            return "Inferred from \(sourceProfileName) · near match"
        case "derived":
            return "Inferred from \(sourceProfileName)"
        case "exact":
            return "Linked to \(sourceProfileName)"
        default:
            return nil
        }
    }

    init(
        profile: AyurvedaProfile,
        enforcedMinAgeMonths: Int?,
        sourceTier: String? = nil
    ) {
        self.init(
            enforcedMinAgeMonths: enforcedMinAgeMonths,
            sourceProfileName: profile.name,
            sourceTier: sourceTier,
            doshaVata: profile.doshaVata,
            doshaPitta: profile.doshaPitta,
            doshaKapha: profile.doshaKapha,
            rasa: profile.rasa,
            virya: profile.virya,
            vipaka: profile.vipaka,
            gunas: profile.gunas,
            agniEffect: profile.agniEffect,
            digestibility: profile.digestibility,
            seasons: profile.seasons,
            timeOfDay: profile.timeOfDay,
            category: profile.category,
            edible: profile.edible,
            prabhava: profile.prabhava,
            contraindications: profile.contraindications,
            confidenceAyur: profile.confidenceAyur
        )
    }

    fileprivate init(
        profile: AyurvedaFacetSeedProfile,
        enforcedMinAgeMonths: Int?,
        sourceTier: String?
    ) {
        self.init(
            enforcedMinAgeMonths: enforcedMinAgeMonths,
            sourceProfileName: profile.name,
            sourceTier: sourceTier,
            doshaVata: profile.dosha.vata,
            doshaPitta: profile.dosha.pitta,
            doshaKapha: profile.dosha.kapha,
            rasa: profile.rasa ?? [],
            virya: profile.virya,
            vipaka: profile.vipaka,
            gunas: profile.gunas ?? [],
            agniEffect: profile.agniEffect,
            digestibility: profile.digestibility,
            seasons: profile.seasons,
            timeOfDay: profile.timeOfDay,
            category: profile.category,
            edible: profile.edible,
            prabhava: profile.prabhava,
            contraindications: profile.contraindications ?? [],
            confidenceAyur: profile.confidence.ayur
        )
    }

    private init(
        enforcedMinAgeMonths: Int?,
        sourceProfileName: String,
        sourceTier: String?,
        doshaVata: Int,
        doshaPitta: Int,
        doshaKapha: Int,
        rasa: [String],
        virya: String?,
        vipaka: String?,
        gunas: [String],
        agniEffect: Int?,
        digestibility: Int?,
        seasons: [String],
        timeOfDay: [String],
        category: String,
        edible: Bool,
        prabhava: String?,
        contraindications: [String],
        confidenceAyur: Double
    ) {
        self.enforcedMinAgeMonths = enforcedMinAgeMonths
        self.sourceProfileName = sourceProfileName
        self.sourceTier = sourceTier
        self.doshaVata = min(2, max(-2, doshaVata))
        self.doshaPitta = min(2, max(-2, doshaPitta))
        self.doshaKapha = min(2, max(-2, doshaKapha))
        self.rasa = rasa
        self.virya = virya
        self.vipaka = vipaka
        self.gunas = gunas
        self.agniEffect = agniEffect
        self.digestibility = digestibility
        self.seasons = seasons
        self.timeOfDay = timeOfDay
        self.category = category
        self.edible = edible
        self.prabhava = prabhava
        self.contraindications = contraindications
        self.confidenceAyur = confidenceAyur
        self.facets = AyurvedaFacet.searchKeys(
            category: category,
            doshaVata: doshaVata,
            doshaPitta: doshaPitta,
            doshaKapha: doshaKapha,
            rasa: rasa,
            virya: virya,
            vipaka: vipaka,
            gunas: gunas,
            agniEffect: agniEffect,
            digestibility: digestibility,
            seasons: seasons,
            timeOfDay: timeOfDay
        )
    }

    func applyingDerivedModifiers(to foodName: String) -> Self {
        guard sourceTier == "derived" else { return self }
        let modifiers = AyurvedaRules.shared.modifiers(forName: foodName)
        guard !modifiers.isEmpty else { return self }
        let adjusted = AyurvedaRules.adjustedVPK(
            base: (doshaVata, doshaPitta, doshaKapha),
            modifiers: modifiers
        )
        var adjustedGunas = gunas
        for modifier in modifiers {
            for guna in modifier.gunas where !adjustedGunas.contains(guna) {
                adjustedGunas.append(guna)
            }
        }
        return Self(
            enforcedMinAgeMonths: enforcedMinAgeMonths,
            sourceProfileName: sourceProfileName,
            sourceTier: sourceTier,
            doshaVata: adjusted.vata,
            doshaPitta: adjusted.pitta,
            doshaKapha: adjusted.kapha,
            rasa: rasa,
            virya: virya,
            vipaka: vipaka,
            gunas: adjustedGunas,
            agniEffect: agniEffect,
            digestibility: digestibility,
            seasons: seasons,
            timeOfDay: timeOfDay,
            category: category,
            edible: edible,
            prabhava: prabhava,
            contraindications: contraindications,
            confidenceAyur: max(confidenceAyur - 0.15, 0.1)
        )
    }
}
