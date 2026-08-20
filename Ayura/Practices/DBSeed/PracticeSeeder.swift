import Foundation
import SwiftData

@MainActor
enum PracticeSeeder {
    struct Result {
        let practiceCount: Int
        let cueCount: Int
        let unresolvedSeatReferences: Int
        let timingMode: String
    }

    private struct ValidatedSeed {
        let rows: [PracticeSeedDTO]
        let timingMode: String
    }

    static func bundleSeedVersion() throws -> Int {
        guard PracticeAudioAssetResolver.mappedDefaultResourceCount == 36 else {
            throw PracticeSeedError.invalidData(
                "Expected 36 unique default ambience mappings, found "
                    + "\(PracticeAudioAssetResolver.mappedDefaultResourceCount)"
            )
        }
        guard PracticeAudioAssetResolver.recordedNarrationPracticeCount == 60,
              PracticeAudioAssetResolver.recordedNarrationCueCount == 601 else {
            throw PracticeSeedError.invalidData(
                "Expected recorded narration for 60 practices and 601 cues, found "
                    + "\(PracticeAudioAssetResolver.recordedNarrationPracticeCount) practices "
                    + "and \(PracticeAudioAssetResolver.recordedNarrationCueCount) cues"
            )
        }
        return 2
    }

    static func isInstalled(context: ModelContext) throws -> Bool {
        let practices = try context.fetch(FetchDescriptor<Practice>())
        let cueCount = practices.reduce(0) { $0 + $1.script.count }
        return practices.count == 60 && cueCount == 601
    }

    static func run(context: ModelContext) throws -> Result {
        let seed = try loadAndValidate()
        let exerciseIDs = Set(
            try context.fetch(FetchDescriptor<ExerciseItem>()).map(\.id)
        )
        let unresolved = seed.rows.compactMap { row -> UUID? in
            guard let seatID = row.seatAsanaId else { return nil }
            return exerciseIDs.contains(seatID) ? nil : seatID
        }
        guard unresolved.isEmpty else {
            throw PracticeSeedError.invalidData(
                "Unresolved seatAsanaId references: "
                    + unresolved.map(\.uuidString).joined(separator: ", ")
            )
        }

        let existing = try context.fetch(FetchDescriptor<Practice>())
        let favoriteIDs = Set(existing.filter(\.isFavorite).map(\.id))
        try context.transaction {
            for practice in existing {
                context.delete(practice)
            }

            for row in seed.rows {
                let practice = Practice(
                    id: row.id,
                    catalogNumber: row.catalogNumber,
                    slug: row.slug,
                    kind: row.kind,
                    title: row.title,
                    sanskrit: row.sanskrit,
                    practiceDescription: row.desc,
                    technique: row.technique,
                    sourceTradition: row.sourceTradition,
                    seatAsanaID: row.seatAsanaId,
                    seatFlexible: row.seatFlexible,
                    posture: row.posture,
                    eyes: row.eyes,
                    durationSeconds: row.durationSeconds,
                    durationOptions: row.durationOptions,
                    goals: row.goals,
                    themes: row.themes,
                    level: row.level,
                    minimalAgeMonths: row.minimalAgeMonths,
                    contraindications: row.contraindications,
                    isFavorite: favoriteIDs.contains(row.id),
                    doshaVata: row.dosha.vata,
                    doshaPitta: row.dosha.pitta,
                    doshaKapha: row.dosha.kapha,
                    doshaProvenance: row.doshaProvenance,
                    guna: row.guna,
                    timeOfDay: row.timeOfDay,
                    season: row.season,
                    agni: row.agni,
                    sceneImageName: row.sceneImageName,
                    narrationAudioAssetName: row.narration.audioAssetName,
                    ttsVoiceHint: row.narration.ttsVoiceHint,
                    wordsPerMinute: row.narration.wordsPerMinute,
                    ambienceTrackID: row.ambience.trackId,
                    ambienceLoops: row.ambience.loop,
                    ambienceVolume: row.ambience.defaultVolume,
                    timingMode: seed.timingMode
                )
                context.insert(practice)

                let cues = row.script.enumerated().map { index, cue in
                    PracticeCue(
                        id: "\(row.id.uuidString.lowercased()):\(index)",
                        ordinal: index,
                        atSeconds: cue.atSeconds,
                        text: cue.text,
                        holdSeconds: cue.hold,
                        practice: practice
                    )
                }
                practice.script = cues
                cues.forEach(context.insert)
            }
        }

        if context.hasChanges { try context.save() }

        let persisted = try context.fetch(FetchDescriptor<Practice>())
        let persistedCueCount = persisted.reduce(0) { $0 + $1.script.count }
        guard persisted.count == seed.rows.count,
              persistedCueCount == 601 else {
            throw PracticeSeedError.invalidData(
                "Persisted practice counts differ: practices=\(persisted.count), "
                    + "cues=\(persistedCueCount)"
            )
        }

        return Result(
            practiceCount: persisted.count,
            cueCount: persistedCueCount,
            unresolvedSeatReferences: unresolved.count,
            timingMode: seed.timingMode
        )
    }

    private static func loadAndValidate() throws -> ValidatedSeed {
        guard let url = resourceURL(
            name: "practices",
            extension: "json",
            subdirectory: "Practices/Data"
        ) else {
            throw PracticeSeedError.missingResource("practices.json")
        }

        let data = try Data(contentsOf: url)
        var rows = try JSONDecoder().decode([PracticeSeedDTO].self, from: data)
        let timingMode = try applyMeasuredTimingIfPresent(to: &rows)

        guard rows.count == 60 else {
            throw PracticeSeedError.invalidData(
                "Expected 60 practices, found \(rows.count)"
            )
        }
        let cueCount = rows.reduce(0) { $0 + $1.script.count }
        guard cueCount == 601 else {
            throw PracticeSeedError.invalidData(
                "Expected 601 cues, found \(cueCount)"
            )
        }
        let assignedAmbienceResources = Set(rows.compactMap {
            PracticeAudioAssetResolver.defaultResourceName(
                for: $0.ambience.trackId,
                catalogNumber: $0.catalogNumber
            )
        })
        guard assignedAmbienceResources
                == PracticeAudioAssetResolver.mappedDefaultResourceNames else {
            throw PracticeSeedError.invalidData(
                "Not every bundled ambience resource is assigned to a practice"
            )
        }
        let missingAmbienceResources = assignedAmbienceResources.filter {
            PracticeAudioAssetResolver.ambienceURL(resourceName: $0) == nil
        }
        guard missingAmbienceResources.isEmpty else {
            throw PracticeSeedError.missingResource(
                "Missing ambience files: "
                    + missingAmbienceResources.sorted().joined(separator: ", ")
            )
        }
        let incompleteNarration = rows.compactMap { row in
            PracticeAudioAssetResolver.hasCompleteRecordedNarration(
                practiceSlug: row.slug,
                cueCount: row.script.count
            ) ? nil : row.slug
        }
        guard incompleteNarration.isEmpty else {
            throw PracticeSeedError.missingResource(
                "Incomplete recorded narration: "
                    + incompleteNarration.sorted().joined(separator: ", ")
            )
        }
        try requireUnique(rows.map(\.id), label: "practice id")
        try requireUnique(rows.map(\.catalogNumber), label: "catalogNumber")
        try requireUnique(rows.map(\.slug), label: "slug")
        guard Set(rows.map(\.catalogNumber)) == Set(810_000...810_059) else {
            throw PracticeSeedError.invalidData(
                "Practice catalog numbers must be exactly 810000...810059"
            )
        }

        for row in rows {
            try validate(row)
        }
        return ValidatedSeed(rows: rows, timingMode: timingMode)
    }

    private static func validate(_ row: PracticeSeedDTO) throws {
        guard row.durationSeconds > 0 else {
            throw PracticeSeedError.invalidData(
                "\(row.slug): durationSeconds must be greater than zero"
            )
        }
        guard (0...1).contains(row.ambience.defaultVolume) else {
            throw PracticeSeedError.invalidData(
                "\(row.slug): ambience volume must be within 0...1"
            )
        }
        guard row.narration.wordsPerMinute > 0 else {
            throw PracticeSeedError.invalidData(
                "\(row.slug): wordsPerMinute must be greater than zero"
            )
        }
        guard !row.script.isEmpty else {
            throw PracticeSeedError.invalidData("\(row.slug): script is empty")
        }
        let cueTimes = row.script.map(\.atSeconds)
        guard cueTimes == cueTimes.sorted() else {
            throw PracticeSeedError.invalidData(
                "\(row.slug): cues are not sorted by atSeconds"
            )
        }
        guard cueTimes.allSatisfy({ $0 >= 0 && $0 <= Double(row.durationSeconds) }) else {
            throw PracticeSeedError.invalidData(
                "\(row.slug): cue falls outside total duration"
            )
        }
        guard row.script.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.hold >= 0 }) else {
            throw PracticeSeedError.invalidData(
                "\(row.slug): cue text is empty or hold is negative"
            )
        }
    }

    /// Narration production can add this optional manifest later. With no
    /// manifest in the bundle, authored JSON timings remain the source.
    private static func applyMeasuredTimingIfPresent(
        to rows: inout [PracticeSeedDTO]
    ) throws -> String {
        guard let url = resourceURL(
            name: "practice_timing_manifest",
            extension: "json",
            subdirectory: "Practices/Data"
        ) else {
            return "authored"
        }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(PracticeTimingManifest.self, from: data)
        let timingBySlug = Dictionary(
            uniqueKeysWithValues: manifest.practices.map { ($0.slug, $0) }
        )

        for index in rows.indices {
            guard let measured = timingBySlug[rows[index].slug] else { continue }
            guard measured.cueAtSeconds.count == rows[index].script.count else {
                throw PracticeSeedError.invalidData(
                    "\(rows[index].slug): measured cue count differs from script"
                )
            }
            rows[index].durationSeconds = measured.durationSeconds
            for cueIndex in rows[index].script.indices {
                rows[index].script[cueIndex].atSeconds = measured.cueAtSeconds[cueIndex]
            }
        }
        return "measured"
    }

    private static func resourceURL(
        name: String,
        extension fileExtension: String,
        subdirectory: String
    ) -> URL? {
        if let nested = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) {
            return nested
        }
        if let root = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension
        ) {
            return root
        }
        return Bundle.main.urls(
            forResourcesWithExtension: fileExtension,
            subdirectory: nil
        )?.first { $0.deletingPathExtension().lastPathComponent == name }
    }

    private static func requireUnique<T: Hashable>(
        _ values: [T],
        label: String
    ) throws {
        guard Set(values).count == values.count else {
            throw PracticeSeedError.invalidData("Duplicate \(label)")
        }
    }
}

private struct PracticeSeedDTO: Codable {
    let id: UUID
    let catalogNumber: Int
    let slug: String
    let kind: String
    let title: String
    let sanskrit: String?
    let desc: String
    let technique: String
    let sourceTradition: String
    let seatAsanaId: UUID?
    let seatFlexible: Bool
    let posture: String
    let eyes: String
    var durationSeconds: Int
    let durationOptions: [Int]
    let goals: [String]
    let themes: [String]
    let level: Int
    let minimalAgeMonths: Int
    let contraindications: [String]
    let dosha: PracticeDoshaDTO
    let doshaProvenance: String
    let guna: String
    let timeOfDay: [String]
    let season: [String]
    let agni: String
    var script: [PracticeCueDTO]
    let narration: PracticeNarrationDTO
    let ambience: PracticeAmbienceDTO
    let sceneImageName: String?
}

private struct PracticeDoshaDTO: Codable {
    let vata: Int
    let pitta: Int
    let kapha: Int
}

private struct PracticeCueDTO: Codable {
    var atSeconds: Double
    let text: String
    let hold: Double
}

private struct PracticeNarrationDTO: Codable {
    let audioAssetName: String?
    let ttsVoiceHint: String
    let wordsPerMinute: Int
}

private struct PracticeAmbienceDTO: Codable {
    let trackId: String
    let loop: Bool
    let defaultVolume: Double
}

private struct PracticeTimingManifest: Codable {
    let practices: [PracticeMeasuredTiming]
}

private struct PracticeMeasuredTiming: Codable {
    let slug: String
    let durationSeconds: Int
    let cueAtSeconds: [Double]
}

enum PracticeSeedError: LocalizedError {
    case missingResource(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "Missing practice seed resource: \(name)"
        case .invalidData(let message):
            "Invalid practice seed: \(message)"
        }
    }
}
