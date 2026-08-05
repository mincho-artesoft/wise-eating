import Foundation
import SwiftData

@MainActor
enum YogaSeeder {
    struct Result {
        let asanaCount: Int
        let sequenceCount: Int
    }

    private struct ValidatedSeed {
        let asanas: [YogaAsanaDTO]
        let sequences: [YogaSequenceDTO]
    }

    static func bundleSeedVersion() throws -> Int {
        6
    }

    static func isInstalled(context: ModelContext) throws -> Bool {
        let cataloguedExercises = try context.fetch(
            FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.catalogNumber != nil }
            )
        )
        let installedAsanas = cataloguedExercises.filter {
            guard let number = $0.catalogNumber else { return false }
            return (800_000...800_907).contains(number) && $0.family != nil
        }
        let namesAreComposed = installedAsanas.allSatisfy {
            $0.name == YogaExerciseNaming.displayName(
                title: $0.name,
                sanskrit: $0.sanskrit
            )
        }
        let installedDurations = installedAsanas.compactMap(\.durationSeconds)
        let durationsAreExactSeconds = installedDurations.count == installedAsanas.count
            && installedDurations.min() == 5
            && installedDurations.max() == 1_800
        let installedSequences = try context.fetch(FetchDescriptor<YogaSequence>())
        let sequenceDurationsAreSeconds = installedSequences.allSatisfy {
            $0.durationSeconds >= 15 * 60
        }
        return installedAsanas.count == 908
            && namesAreComposed
            && durationsAreExactSeconds
            && installedSequences.count == 4_419
            && sequenceDurationsAreSeconds
    }

    static func run(context: ModelContext) throws -> Result {
        let seed = try loadAndValidate()
        let asanaCatalogNumbers = Set(seed.asanas.map(\.catalogNumber))

        let cataloguedExercises = try context.fetch(
            FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.catalogNumber != nil }
            )
        )
        let existingAsanas = cataloguedExercises.filter {
            guard let catalogNumber = $0.catalogNumber else { return false }
            return asanaCatalogNumbers.contains(catalogNumber)
        }
        var asanasByCatalogNumber = try uniqueModels(
            existingAsanas,
            catalogNumber: { $0.catalogNumber },
            label: "asana"
        )

        let existingSequences = try context.fetch(FetchDescriptor<YogaSequence>())
        var sequencesByCatalogNumber = try uniqueModels(
            existingSequences,
            catalogNumber: { $0.catalogNumber },
            label: "sequence"
        )

        try context.transaction {
            for dto in seed.asanas {
                let model: ExerciseItem
                if let existing = asanasByCatalogNumber[dto.catalogNumber] {
                    guard existing.id == dto.id else {
                        throw YogaSeedError.invalidData(
                            "Asana \(dto.catalogNumber) has a non-canonical UUID"
                        )
                    }
                    model = existing
                } else {
                    model = ExerciseItem(
                        id: dto.id,
                        catalogNumber: dto.catalogNumber,
                        name: YogaExerciseNaming.displayName(
                            title: dto.title,
                            sanskrit: dto.sanskrit
                        ),
                        muscleGroups: dto.muscleGroups
                    )
                    context.insert(model)
                    asanasByCatalogNumber[dto.catalogNumber] = model
                }
                apply(dto, to: model)
            }

            for dto in seed.sequences {
                let posesData = try JSONEncoder().encode(dto.poses)

                if let existing = sequencesByCatalogNumber[dto.catalogNumber] {
                    guard existing.id == dto.id else {
                        throw YogaSeedError.invalidData(
                            "Sequence \(dto.catalogNumber) has a non-canonical UUID"
                        )
                    }
                    existing.update(from: dto, posesData: posesData)
                } else {
                    let sequence = YogaSequence(
                        id: dto.id,
                        catalogNumber: dto.catalogNumber,
                        title: dto.title,
                        intent: dto.intent,
                        level: dto.level,
                        durationSeconds: dto.durationMinutes * 60,
                        season: dto.season,
                        school: dto.school,
                        sequenceNote: dto.note,
                        doshaEffect: dto.doshaEffect,
                        doshaProvenance: dto.doshaProvenance,
                        estimatedSeconds: dto.estimatedSeconds,
                        posesData: posesData
                    )
                    context.insert(sequence)
                    sequencesByCatalogNumber[dto.catalogNumber] = sequence
                }
            }
        }

        if context.hasChanges {
            try context.save()
        }

        let persistedAsanaCount = try context.fetch(
            FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.catalogNumber != nil }
            )
        ).reduce(into: 0) { count, item in
            if let number = item.catalogNumber,
               asanaCatalogNumbers.contains(number) {
                count += 1
            }
        }
        let persistedSequenceCount = try context.fetchCount(
            FetchDescriptor<YogaSequence>()
        )

        guard persistedAsanaCount == seed.asanas.count,
              persistedSequenceCount == seed.sequences.count else {
            throw YogaSeedError.invalidData(
                "Persisted yoga counts differ: asanas=\(persistedAsanaCount), "
                    + "sequences=\(persistedSequenceCount)"
            )
        }

        print(
            "   ✅ Yoga seed complete: \(persistedAsanaCount) asanas, "
                + "\(persistedSequenceCount) sequences."
        )
        return Result(
            asanaCount: persistedAsanaCount,
            sequenceCount: persistedSequenceCount
        )
    }

    private static func apply(_ dto: YogaAsanaDTO, to model: ExerciseItem) {
        model.catalogNumber = dto.catalogNumber
        model.name = YogaExerciseNaming.displayName(
            title: dto.title,
            sanskrit: dto.sanskrit
        )
        model.sanskrit = dto.sanskrit
        model.slug = dto.slug
        model.family = dto.family
        model.level = dto.level
        model.breath = dto.breath
        model.drishti = dto.drishti
        model.contraindications = dto.contraindications
        model.dosha = dto.dosha
        model.doshaProvenance = dto.doshaProvenance
        model.exerciseDescription = dto.desc
        model.metValue = dto.metValue
        model.muscleGroups = dto.muscleGroups
        model.minimalAgeMonths = dto.minimalAgeMonths
        model.assetImageName = dto.assetImageName
        model.isUserAdded = false
        model.isWorkout = false
        model.durationSeconds = dto.durationSeconds
        model.refreshSearchMetadata()
    }

    private static func loadAndValidate() throws -> ValidatedSeed {
        let asanas: [YogaAsanaDTO] = try decodeResource(
            "asanas",
            as: [YogaAsanaDTO].self
        )
        let sequences: [YogaSequenceDTO] = try decodeResource(
            "sequences",
            as: [YogaSequenceDTO].self
        )
        guard asanas.count == 908 else {
            throw YogaSeedError.invalidData(
                "Expected 908 asanas, found \(asanas.count)"
            )
        }
        guard sequences.count == 4_419 else {
            throw YogaSeedError.invalidData(
                "Expected 4419 sequences, found \(sequences.count)"
            )
        }

        _ = try uniqueValues(asanas.map(\.id), label: "asana id")
        let asanaCatalogNumbers = try uniqueValues(
            asanas.map(\.catalogNumber),
            label: "asana catalogNumber"
        )
        let sequenceIDs = try uniqueValues(
            sequences.map(\.id),
            label: "sequence id"
        )
        _ = try uniqueValues(
            sequences.map(\.catalogNumber),
            label: "sequence catalogNumber"
        )
        guard asanaCatalogNumbers == Set(800_000...800_907),
              sequenceIDs.count == 4_419 else {
            throw YogaSeedError.invalidData("Yoga UUID catalogues are incomplete")
        }

        try validateAsanas(asanas)
        try validateSequences(
            sequences,
            asanaIDsByCatalogNumber: Dictionary(
                uniqueKeysWithValues: asanas.map { ($0.catalogNumber, $0.id) }
            )
        )
        printSearchSmokeTests(asanas)

        return ValidatedSeed(
            asanas: asanas,
            sequences: sequences
        )
    }

    private static func validateAsanas(_ rows: [YogaAsanaDTO]) throws {
        _ = try uniqueValues(rows.map(\.title), label: "asana title")
        _ = try uniqueValues(rows.map(\.sanskrit), label: "Sanskrit name")
        _ = try uniqueValues(rows.map(\.slug), label: "asana slug")
        _ = try uniqueValues(
            rows.map(\.assetImageName),
            label: "asana image filename"
        )

        let expectedHistogram: [AsanaFamily: Int] = [
            .backbend: 156,
            .forwardBend: 119,
            .hipOpener: 114,
            .standing: 95,
            .standingBalance: 72,
            .inversion: 57,
            .seated: 57,
            .twist: 55,
            .armBalance: 43,
            .core: 42,
            .restorative: 36,
            .pranayama: 14,
            .meditation: 13,
            .supine: 10,
            .bandhaAndMudra: 9,
            .suryaNamaskar: 9,
            .kriya: 6,
            .prone: 1,
        ]
        let histogram = Dictionary(grouping: rows, by: \.family).mapValues(\.count)
        guard histogram == expectedHistogram else {
            throw YogaSeedError.invalidData(
                "Asana family histogram differs from the approved catalogue"
            )
        }

        let expectedLevels = [1: 370, 2: 259, 3: 279]
        let levels = Dictionary(grouping: rows, by: \.level).mapValues(\.count)
        guard levels == expectedLevels else {
            throw YogaSeedError.invalidData(
                "Asana level histogram differs from the approved catalogue"
            )
        }

        guard Set(rows.map(\.breath)) == Set(YogaBreath.allCases),
              Set(rows.map(\.drishti)) == Set(YogaDrishti.allCases) else {
            throw YogaSeedError.invalidData(
                "Breath or drishti enum options differ from the approved catalogue"
            )
        }

        for row in rows {
            guard !row.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row.doshaProvenance == "modern-synthesis",
                  [row.dosha.vata, row.dosha.pitta, row.dosha.kapha]
                    .allSatisfy({ (-2...2).contains($0) }) else {
                throw YogaSeedError.invalidData(
                    "Invalid approved metadata for asana \(row.catalogNumber)"
                )
            }
        }

        let histogramText = AsanaFamily.allCases
            .compactMap { family in
                histogram[family].map { "\(family.rawValue)=\($0)" }
            }
            .joined(separator: ", ")
        print("   Yoga Gate 1: decoded 908 asanas; \(histogramText)")
    }

    private static func validateSequences(
        _ rows: [YogaSequenceDTO],
        asanaIDsByCatalogNumber: [Int: UUID]
    ) throws {
        var dangling = 0
        for row in rows {
            guard row.doshaProvenance == "modern-synthesis",
                  (1...3).contains(row.level),
                  !row.poses.isEmpty else {
                throw YogaSeedError.invalidData(
                    "Invalid sequence metadata for \(row.catalogNumber)"
                )
            }
            let calculatedSeconds = row.poses.reduce(0) {
                $0 + $1.totalSeconds
            }
            guard calculatedSeconds == row.estimatedSeconds else {
                throw YogaSeedError.invalidData(
                    "Sequence \(row.catalogNumber) estimatedSeconds mismatch: "
                        + "\(row.estimatedSeconds) != \(calculatedSeconds)"
                )
            }
            dangling += row.poses.lazy.filter {
                asanaIDsByCatalogNumber[$0.catalogNumber] != $0.id
            }.count
        }
        guard dangling == 0 else {
            throw YogaSeedError.invalidData(
                "Sequence catalogue has \(dangling) dangling pose references"
            )
        }

        for duration in [15, 90] {
            guard let sample = rows.first(where: { $0.durationMinutes == duration }) else {
                throw YogaSeedError.invalidData(
                    "Missing \(duration)-minute sequence sample"
                )
            }
            let statedSeconds = duration * 60
            let difference = abs(sample.estimatedSeconds - statedSeconds)
            guard Double(difference) / Double(statedSeconds) <= 0.15 else {
                throw YogaSeedError.invalidData(
                    "Sequence \(sample.catalogNumber) is not near its stated duration"
                )
            }
            print(
                "   Yoga Gate 2 sample: \(duration) min, "
                    + "\(sample.estimatedSeconds) calculated seconds"
            )
        }
        print("   Yoga Gate 2: decoded 4419 sequences; 0 dangling poses")
    }

    private static func printSearchSmokeTests(_ rows: [YogaAsanaDTO]) {
        for query in ["adho mukha", "backbend", "pranayama", "warrior"] {
            let normalizedQuery = query.foldedSearchKey
            let results = rows.filter { row in
                [row.title, row.sanskrit, row.family.rawValue]
                    .joined(separator: " ")
                    .foldedSearchKey
                    .contains(normalizedQuery)
            }
            .prefix(5)
            .map(\.title)
            .joined(separator: ", ")
            print("   Yoga Gate 5 '\(query)': \(results)")
        }
    }

    private static func decodeResource<T: Decodable>(
        _ name: String,
        as type: T.Type
    ) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw YogaSeedError.missingResource("\(name).json")
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private static func uniqueValues<T: Hashable>(
        _ values: [T],
        label: String
    ) throws -> Set<T> {
        let unique = Set(values)
        guard unique.count == values.count else {
            throw YogaSeedError.invalidData("Duplicate \(label)")
        }
        return unique
    }

    private static func uniqueModels<T>(
        _ models: [T],
        catalogNumber: (T) -> Int?,
        label: String
    ) throws -> [Int: T] {
        var result: [Int: T] = [:]
        for model in models {
            guard let number = catalogNumber(model) else { continue }
            guard result.updateValue(model, forKey: number) == nil else {
                throw YogaSeedError.invalidData(
                    "Duplicate persisted \(label) catalog number \(number)"
                )
            }
        }
        return result
    }
}

private enum YogaSeedError: LocalizedError {
    case missingResource(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let filename):
            return "Missing yoga seed resource: \(filename)"
        case .invalidData(let message):
            return message
        }
    }
}
