import Foundation

protocol SelectableItem: Identifiable, Hashable {
    var name: String { get }
    var iconName: String? { get }
    var iconText: String? { get }
}

@main
struct YogaDecodeGate {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw GateError.usage
        }

        let decoder = JSONDecoder()
        let asanas = try decoder.decode(
            [YogaAsanaDTO].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let sequences = try decoder.decode(
            [YogaSequenceDTO].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        )
        guard asanas.count == 908, sequences.count == 4_419 else {
            throw GateError.invalidCounts(asanas.count, sequences.count)
        }

        let asanaIDs = Set(asanas.map(\.id))
        let dangling = sequences.flatMap(\.poses).filter {
            !asanaIDs.contains($0.id)
        }
        guard dangling.isEmpty else {
            throw GateError.dangling(dangling.count)
        }
        for sequence in sequences {
            let calculated = sequence.poses.reduce(0) {
                $0 + $1.totalSeconds
            }
            guard calculated == sequence.estimatedSeconds else {
                throw GateError.duration(sequence.catalogNumber)
            }
        }

        let histogram = Dictionary(grouping: asanas, by: \.family).mapValues(\.count)
        let histogramText = AsanaFamily.allCases.compactMap { family in
            histogram[family].map { "\(family.rawValue)=\($0)" }
        }.joined(separator: ", ")
        print("Gate 1: decoded \(asanas.count) asanas; \(histogramText)")
        print("Gate 2: decoded \(sequences.count) sequences; 0 dangling poses")

        for duration in [15, 90] {
            guard let sample = sequences.first(where: {
                $0.durationMinutes == duration
            }) else {
                throw GateError.missingDuration(duration)
            }
            print(
                "Duration sample \(duration) min: "
                    + "\(sample.estimatedSeconds) calculated seconds"
            )
        }

        for query in ["adho mukha", "backbend", "pranayama", "warrior"] {
            let normalized = query.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            let results = asanas.filter { row in
                [row.title, row.sanskrit, row.family.rawValue]
                    .joined(separator: " ")
                    .folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                    .contains(normalized)
            }.prefix(5).map(\.title).joined(separator: ", ")
            print("Gate 5 '\(query)': \(results)")
        }
    }
}

private enum GateError: Error {
    case usage
    case invalidCounts(Int, Int)
    case dangling(Int)
    case duration(Int)
    case missingDuration(Int)
}
