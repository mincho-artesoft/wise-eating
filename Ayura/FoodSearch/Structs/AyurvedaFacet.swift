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
            seasons: profile.seasons
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
        guard seed.dravyas.count == 714, seed.recipes.count == 1_500 else {
            throw AyurvedaFacetSeedError.invalidCounts
        }

        return try (seed.dravyas + seed.recipes).reduce(into: [:]) {
            result,
            profile in
            guard profile.isCanonical else { return }
            guard profile.safety.enforcedMinAgeMonths >= 0,
                  profile.safety.enforcedMinAgeMonths <= profile.safety.minAgeMonths,
                  ["authored", "legacyImport"].contains(profile.safety.ageProvenance)
            else {
                throw AyurvedaFacetSeedError.invalidAgeMetadata(profile.id)
            }
            let facets = searchKeys(
                category: profile.category,
                doshaVata: profile.dosha.vata,
                doshaPitta: profile.dosha.pitta,
                doshaKapha: profile.dosha.kapha,
                rasa: profile.rasa ?? [],
                virya: profile.virya,
                vipaka: profile.vipaka,
                gunas: profile.gunas ?? [],
                agniEffect: profile.agniEffect,
                digestibility: profile.digestibility,
                seasons: profile.seasons
            )
            guard !facets.isEmpty else { return }
            result[profile.foodId] = AyurvedaCanonicalSearchMetadata(
                facets: facets,
                enforcedMinAgeMonths: profile.safety.enforcedMinAgeMonths
            )
        }
    }

    private static func searchKeys(
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
        seasons: [String]
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
            return "the Ayurveda facet seed must contain 714 dravyas and 1,500 recipes"
        case .invalidAgeMetadata(let profileID):
            return "the Ayurveda seed has invalid age metadata for \(profileID)"
        }
    }
}

private struct AyurvedaFacetSeedDocument: Decodable {
    let dravyas: [AyurvedaFacetSeedProfile]
    let recipes: [AyurvedaFacetSeedProfile]
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
    }

    let id: String
    let category: String
    let dosha: Dosha
    let seasons: [String]
    let foodId: Int
    let rasa: [String]?
    let virya: String?
    let vipaka: String?
    let gunas: [String]?
    let agniEffect: Int?
    let digestibility: Int?
    let safety: Safety

    var isCanonical: Bool {
        id.hasPrefix("dravya.") || id.hasPrefix("recipe.")
    }
}

struct AyurvedaCanonicalSearchMetadata: Sendable {
    let facets: Set<String>
    let enforcedMinAgeMonths: Int?
}
