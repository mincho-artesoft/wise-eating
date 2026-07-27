import Foundation

struct MP6NarrationFact: Codable, Equatable, Hashable, Sendable {
    let day: Int
    let slotIndex: Int
    let slotName: String
    let dishNames: [String]
    let kcal: Double
    let proteinGrams: Double
    let tastes: [String]
    let thermalCharacter: String
    let agni: String

    var key: MP6NarrationKey {
        MP6NarrationKey(day: day, slotIndex: slotIndex)
    }
}

struct MP6NarrationKey: Codable, Equatable, Hashable, Sendable {
    let day: Int
    let slotIndex: Int
}

struct MP6NarratedTitle: Codable, Equatable, Sendable {
    let day: Int
    let slotIndex: Int
    let title: String

    var key: MP6NarrationKey {
        MP6NarrationKey(day: day, slotIndex: slotIndex)
    }
}

struct MP6NarrationOutcome: Equatable, Sendable {
    let titles: [MP6NarratedTitle]
    let usedTemplate: Bool
    let fallbackReason: String?
}

enum MP6TemplateNarrator {
    static let frameCount = 5

    static func narrate(_ facts: [MP6NarrationFact]) -> [MP6NarratedTitle] {
        facts.map { fact in
            MP6NarratedTitle(
                day: fact.day,
                slotIndex: fact.slotIndex,
                title: title(for: fact)
            )
        }
    }

    static func frameIndex(for fact: MP6NarrationFact) -> Int {
        let dayOffset = max(0, fact.day - 1) % frameCount
        let slotOffset = max(0, fact.slotIndex) % frameCount
        return (dayOffset * 3 + slotOffset) % frameCount
    }

    static func title(for fact: MP6NarrationFact) -> String {
        let dishes = readableList(
            uniqueNonempty(fact.dishNames),
            empty: fact.slotName
        )
        let kcal = String(
            format: "%.0f",
            locale: Locale(identifier: "en_US_POSIX"),
            fact.kcal
        )
        let protein = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            fact.proteinGrams
        )
        let tastes = uniqueNonempty(fact.tastes).sorted()
        let singleTaste = tastes.count == 1 ? tastes[0] : nil
        let multipleTastes = tastes.count > 1
            ? readableList(tastes, empty: "")
            : nil
        let singleTasteSuffix = singleTaste.map {
            ", with \($0) as its recorded taste"
        } ?? ""
        let tasteSentence: String
        switch frameIndex(for: fact) {
        case 0:
            tasteSentence = multipleTastes.map {
                " Recorded tastes: \($0)."
            } ?? ""
        case 1:
            tasteSentence = multipleTastes.map {
                " Its recorded tastes are \($0)."
            } ?? ""
        case 2:
            tasteSentence = multipleTastes.map {
                " Taste record: \($0)."
            } ?? ""
        case 3:
            tasteSentence = multipleTastes.map {
                " The recorded tastes are \($0)."
            } ?? ""
        default:
            tasteSentence = multipleTastes.map {
                " Recorded taste set: \($0)."
            } ?? ""
        }
        let guidance = traditionalGuidance(
            thermalCharacter: fact.thermalCharacter,
            agni: fact.agni
        )
        let mainSentence: String
        switch frameIndex(for: fact) {
        case 0:
            mainSentence = "\(dishes) — \(kcal) kcal and \(protein) g protein"
                + "\(singleTasteSuffix)."
        case 1:
            mainSentence = "\(dishes): \(kcal) kcal, \(protein) g protein"
                + "\(singleTasteSuffix)."
        case 2:
            let slot = displayTerm(fact.slotName, empty: "meal").lowercased()
            mainSentence = "At \(kcal) kcal and \(protein) g protein, this "
                + "\(slot) includes \(dishes)\(singleTasteSuffix)."
        case 3:
            mainSentence = "\(protein) g protein and \(kcal) kcal come from "
                + "\(dishes)\(singleTasteSuffix)."
        default:
            let slot = displayTerm(fact.slotName, empty: "This meal")
            mainSentence = "\(slot) includes \(dishes), totaling \(kcal) kcal "
                + "and \(protein) g protein\(singleTasteSuffix)."
        }
        return mainSentence + tasteSentence + guidance
    }

    private static func uniqueNonempty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }

    private static func readableList(
        _ values: [String],
        empty fallback: String
    ) -> String {
        switch values.count {
        case 0:
            return fallback
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            return values.dropLast().joined(separator: ", ")
                + ", and \(values.last ?? fallback)"
        }
    }

    private static func displayTerm(
        _ raw: String,
        empty fallback: String
    ) -> String {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        return value.isEmpty ? fallback : value
    }

    private static func traditionalGuidance(
        thermalCharacter: String,
        agni: String
    ) -> String {
        let thermal = displayTerm(
            thermalCharacter,
            empty: "unrecorded"
        ).lowercased()
        let agni = displayTerm(agni, empty: "balanced").lowercased()
        let hasThermal = !["mixed", "unrecorded"].contains(thermal)
        let hasAgni = agni != "balanced"

        switch (hasThermal, hasAgni) {
        case (true, true):
            return " Traditionally considered \(thermal); "
                + "agni context: \(agni)."
        case (true, false):
            return " Traditionally considered \(thermal)."
        case (false, true):
            return " Traditional agni context: \(agni)."
        case (false, false):
            return ""
        }
    }
}

enum MP6NarrationCoordinator {
    typealias ModelResponse = @Sendable (
        [MP6NarrationFact]
    ) async throws -> [MP6NarratedTitle]

    private enum Attempt: Sendable {
        case response([MP6NarratedTitle])
        case failed
        case timedOut
    }

    static func narrate(
        facts: [MP6NarrationFact],
        modelAvailable: Bool,
        wallClockBudgetNanoseconds: UInt64 = 8_000_000_000,
        modelResponse: @escaping ModelResponse
    ) async -> MP6NarrationOutcome {
        let templates = MP6TemplateNarrator.narrate(facts)
        guard !facts.isEmpty else {
            return MP6NarrationOutcome(
                titles: [],
                usedTemplate: true,
                fallbackReason: "empty plan"
            )
        }
        guard modelAvailable else {
            return MP6NarrationOutcome(
                titles: templates,
                usedTemplate: true,
                fallbackReason: "model unavailable"
            )
        }

        let attempt = await withTaskGroup(of: Attempt.self) { group in
            group.addTask {
                do {
                    return .response(try await modelResponse(facts))
                } catch {
                    return .failed
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(
                        nanoseconds: wallClockBudgetNanoseconds
                    )
                    return .timedOut
                } catch {
                    return .failed
                }
            }
            let first = await group.next() ?? .failed
            group.cancelAll()
            return first
        }

        switch attempt {
        case .response(let generated):
            guard let ordered = validated(generated, for: facts) else {
                return MP6NarrationOutcome(
                    titles: templates,
                    usedTemplate: true,
                    fallbackReason: "title count or index mismatch"
                )
            }
            return MP6NarrationOutcome(
                titles: ordered,
                usedTemplate: false,
                fallbackReason: nil
            )
        case .failed:
            return MP6NarrationOutcome(
                titles: templates,
                usedTemplate: true,
                fallbackReason: "model response failed"
            )
        case .timedOut:
            return MP6NarrationOutcome(
                titles: templates,
                usedTemplate: true,
                fallbackReason: "narration exceeded wall-clock budget"
            )
        }
    }

    private static func validated(
        _ generated: [MP6NarratedTitle],
        for facts: [MP6NarrationFact]
    ) -> [MP6NarratedTitle]? {
        guard generated.count == facts.count else { return nil }
        let expectedKeys = Set(facts.map(\.key))
        let generatedKeys = Set(generated.map(\.key))
        guard generatedKeys.count == generated.count,
              generatedKeys == expectedKeys
        else {
            return nil
        }
        let byKey = Dictionary(
            uniqueKeysWithValues: generated.map { ($0.key, $0) }
        )
        let ordered = facts.compactMap { byKey[$0.key] }
        guard ordered.count == facts.count,
              ordered.allSatisfy({
                  !$0.title.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty
              })
        else {
            return nil
        }
        return ordered
    }
}
