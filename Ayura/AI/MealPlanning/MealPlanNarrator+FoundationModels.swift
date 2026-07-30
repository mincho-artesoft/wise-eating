import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
private struct MP6GeneratedNarrationTitle {
    @Guide(description: "The supplied one-based day index.")
    let day: Int
    @Guide(description: "The supplied zero-based meal-slot index for that day.")
    let slotIndex: Int
    @Guide(description: "A concise, readable descriptive title grounded only in the supplied meal facts.")
    let title: String
}

@available(iOS 26.0, *)
@Generable
private struct MP6GeneratedNarrationResponse {
    @Guide(description: "Exactly one title for every supplied day and slot pair, with no omissions, duplicates, or extra entries.")
    let titles: [MP6GeneratedNarrationTitle]
}

enum MP6MealPlanNarrator {
    static let wallClockBudgetNanoseconds: UInt64 = 8_000_000_000

    @MainActor
    static func narrate(
        facts: [MP6NarrationFact],
        onLog: (@Sendable (String) -> Void)?
    ) async -> MP6NarrationOutcome {
        guard #available(iOS 26.0, *) else {
            return MP6NarrationOutcome(
                titles: MP6TemplateNarrator.narrate(facts),
                usedTemplate: true,
                fallbackReason: "Foundation Models requires iOS 26"
            )
        }
        let modelAvailable: Bool
        switch SystemLanguageModel.default.availability {
        case .available:
            modelAvailable = true
        case .unavailable:
            modelAvailable = false
        @unknown default:
            modelAvailable = false
        }

        let outcome = await MP6NarrationCoordinator.narrate(
            facts: facts,
            modelAvailable: modelAvailable,
            wallClockBudgetNanoseconds: wallClockBudgetNanoseconds,
            modelResponse: { suppliedFacts in
                try await generateTitles(for: suppliedFacts)
            }
        )
        if outcome.usedTemplate {
            onLog?(
                "📝 MP-6 template narration used: "
                    + (outcome.fallbackReason ?? "unspecified reason")
            )
        } else {
            onLog?(
                "📝 MP-6 batched narration completed for "
                    + "\(outcome.titles.count) meals."
            )
        }
        return outcome
    }

    @available(iOS 26.0, *)
    private static func generateTitles(
        for facts: [MP6NarrationFact]
    ) async throws -> [MP6NarratedTitle] {
        let instructions = Instructions {
            """
            You write concise descriptive meal titles from finished, validated
            meal-plan facts. The catalogue choices and quantities are final.

            Rules:
            - Return exactly one title for every supplied (day, slotIndex) pair.
            - Preserve each supplied day and slotIndex exactly.
            - Never invent, replace, recommend, or omit a food.
            - Never invent a weight, calorie, protein, taste, thermal, agni, or
              other figure or property. Use only facts explicitly supplied.
            - Never state or imply that a food treats, cures, prevents, or
              manages a disease or medical condition.
            - Ayurvedic context is traditional guidance, not medical fact. If
              referenced, use the register "Traditionally considered".
            - The content remains qualityState aiDraft pending expert review.
            - Keep each title natural, non-marketing, and under 80 characters.
            """
        }
        let session = LanguageModelSession(instructions: instructions)
        if PlannerTelemetry.isEnabled {
            await PlannerTelemetry.shared.noteSession(
                site: "mealPlanNarration"
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(facts)
        guard let factsJSON = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let prompt = """
        Write the complete title batch for these finished meal facts:
        \(factsJSON)
        """
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            let response = try await session.respond(
                to: prompt,
                generating: MP6GeneratedNarrationResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            if PlannerTelemetry.isEnabled {
                await PlannerTelemetry.shared.noteRespond(
                    site: "mealPlanNarration",
                    ok: true,
                    ms: elapsedMilliseconds(since: startedAt)
                )
            }
            return response.content.titles.map {
                MP6NarratedTitle(
                    day: $0.day,
                    slotIndex: $0.slotIndex,
                    title: $0.title
                )
            }
        } catch {
            if PlannerTelemetry.isEnabled {
                await PlannerTelemetry.shared.noteRespond(
                    site: "mealPlanNarration",
                    ok: false,
                    ms: elapsedMilliseconds(since: startedAt)
                )
            }
            throw error
        }
    }

    private static func elapsedMilliseconds(since startedAt: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
    }
}
