// ==== FILE: AIMenuGenerator.swift ====
import Foundation
import SwiftData
import FoundationModels

@available(iOS 26.0, *)
@MainActor
final class AIMenuGenerator {

    // MARK: Dependencies
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Константи/настройки за имена

    /// Разрешен набор за изходното име (1 дума)
    private let allowedEnglish: [String] = [
        "Breakfast", "Brunch", "Lunch", "Snack", "Dinner"
    ]

    /// Синоними/ключови думи → канонично име от allowedEnglish
    private let synonymMap: [String: String] = [
        // EN
        "breakfast": "Breakfast", "break fast": "Breakfast", "morning": "Breakfast",
        "brunch": "Brunch", "late breakfast": "Brunch",
        "lunch": "Lunch", "noon": "Lunch", "midday": "Lunch",
        "snack": "Snack", "bite": "Snack", "light bite": "Snack",
        "dinner": "Dinner", "supper": "Dinner", "evening": "Dinner", "night": "Dinner",

        // BG → EN canonical
        "закуска": "Breakfast",
        "бранч": "Brunch",
        "обяд": "Lunch",
        "снак": "Snack", "лека закуска": "Snack",
        "вечеря": "Dinner", "вечерен": "Dinner", "нощна закуска": "Snack"
    ]

    // MARK: - Лог помощници

    private func emitLog(_ message: String, onLog: (@Sendable (String) -> Void)?) {
        onLog?(message)
    }

    // MARK: - Текстови помощници

    private func ensureSummaryHasName(_ description: String, menuName: String) -> String {
        var lines = description.components(separatedBy: .newlines)
        guard let first = lines.first else {
            return "Summary: \(menuName)\n\n" + description
        }
        let trimmedFirst = first.trimmingCharacters(in: .whitespaces)
        if trimmedFirst.lowercased().hasPrefix("summary:") {
            if !trimmedFirst.localizedCaseInsensitiveContains(menuName) {
                let rest = trimmedFirst.dropFirst("Summary:".count).trimmingCharacters(in: .whitespaces)
                lines[0] = rest.isEmpty ? "Summary: \(menuName)" : "Summary: \(menuName) – \(rest)"
            }
            return lines.joined(separator: "\n")
        } else {
            return "Summary: \(menuName)\n\n" + description
        }
    }

    private func budgetedJoin(_ items: [String], maxChars: Int) -> String {
        var acc: [String] = []
        var used = 0
        for s in items {
            let add = s.count + (acc.isEmpty ? 0 : 2)
            if used + add > maxChars { break }
            acc.append(s)
            used += add
        }
        var joined = acc.joined(separator: ", ")
        if joined.isEmpty { return joined }
        if items.count > acc.count { joined += "…" }
        return joined
    }

    private func firstOneOrTwoWords(_ s: String) -> String {
        let words = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .split { $0.isWhitespace }
            .map(String.init)
        if words.isEmpty { return "" }
        if words.count == 1 { return words[0] }
        return words[0] + " " + words[1]
    }

    // MARK: - Канонизация на имената към разрешения набор

    private func pickFromPrompts(_ prompts: [String]) -> String? {
        let joined = prompts.joined(separator: " ").lowercased()
        if joined.contains("brunch") || joined.contains("бранч") { return "Brunch" }
        if joined.contains("breakfast") || joined.contains("morning") || joined.contains("закуска") { return "Breakfast" }
        if joined.contains("lunch") || joined.contains("noon") || joined.contains("midday") || joined.contains("обяд") { return "Lunch" }
        if joined.contains("snack") || joined.contains("снак") || joined.contains("лека закуска") || joined.contains("afternoon") { return "Snack" }
        if joined.contains("dinner") || joined.contains("supper") || joined.contains("evening") || joined.contains("вечеря") { return "Dinner" }
        return nil
    }

    private func canonicalizeName(_ raw: String, prompts: [String]) -> String {
        if let fromPrompts = pickFromPrompts(prompts) {
            return fromPrompts
        }
        let lower = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .lowercased()
        if let exact = allowedEnglish.first(where: { $0.lowercased() == lower }) {
            return exact
        }
        if let mapped = synonymMap[lower] {
            return mapped
        }
        for (key, val) in synonymMap {
            if lower.contains(key) {
                return val
            }
        }
        return "Lunch"
    }

    private func sanitizeAndClampToAllowed(_ s: String, prompts: [String]) -> String {
        let cand = canonicalizeName(firstOneOrTwoWords(s), prompts: prompts)
        return allowedEnglish.contains(cand) ? cand : "Lunch"
    }

    // MARK: - Инструкции / промптове

    private func nameInstructions() -> Instructions {
        Instructions {
            """
            You output a concise menu name (1–2 words) ONLY from this fixed set:
            - Breakfast, Brunch, Lunch, Snack, Dinner

            Rules:
            - Choose the single best label based on the hints.
            - Keep it to EXACTLY one of the allowed words (case as given).
            - If unclear → "Lunch".
            - Return ONLY valid JSON for AIMenuNameOnly, e.g.: {"menuName":"Lunch"}
            """
        }
    }

    private func nameUserPrompt(prompts: [String]) -> String {
        if prompts.isEmpty {
            return """
            Choose ONE name from: Breakfast, Brunch, Lunch, Snack, Dinner.
            No extra text, emojis, or quotes.
            If unclear → "Lunch".
            Return JSON { "menuName": "…" }.
            """
        } else {
            let p = budgetedJoin(prompts, maxChars: 300)
            return """
            Choose ONE name from: Breakfast, Brunch, Lunch, Snack, Dinner,
            based on these hints: \(p)
            No extra text, emojis, or quotes.
            If unclear → "Lunch".
            Return JSON { "menuName": "…" }.
            """
        }
    }

    // Строги инструкции за описанието (идентични по дух с AIRecipeGenerator)
    private func detailsInstructions() -> Instructions {
        Instructions {
            """
            You write brief menu descriptions. Return ONLY valid JSON for AIMenuDetailsOnly.

            DESCRIPTION FIELD RULES (STRICT):
            - The "description" string must have:
              1) One short summary line, prefixed exactly with: "Summary: "
                 • 1–2 concise sentences max; plain text only.
              2) A blank line.
              3) A numbered, step-by-step procedure with the exact format:
                 "1) ...\\n2) ...\\n3) ..."
                 • 5–12 steps total, each step a short, imperative sentence.
                 • Plain text only (no Markdown, bullets, or headings).

            PREP TIME:
            - "prepTimeMinutes" is an integer in [10, 360], covering active prep only.

            LANGUAGE:
            - Match the user's language if obvious; else Bulgarian.
            """
        }
    }

    private func isValidDescriptionWithIntro(_ text: String) -> Bool {
        let parts = text.components(separatedBy: "\n\n")
        guard parts.count >= 2 else { return false }

        let summaryBlock = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let stepsBlock = parts.dropFirst().joined(separator: "\n\n")

        guard summaryBlock.hasPrefix("Summary: "),
              summaryBlock.count > "Summary: ".count else { return false }

        let rawStepLines = stepsBlock.split(separator: "\n", omittingEmptySubsequences: true)
        guard rawStepLines.count >= 5, rawStepLines.count <= 12 else { return false }

        for (idx, raw) in rawStepLines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let expected = "\(idx + 1))"
            if !line.hasPrefix(expected) { return false }
            if line.count <= expected.count + 1 { return false }
        }
        return true
    }

    private func ultraCompactNamePrompt(prompts: [String]) -> String {
        if prompts.isEmpty {
            return #"Return {"menuName":"Lunch"}"#
        } else {
            let p = budgetedJoin(prompts, maxChars: 200)
            return #"From hints (\#(p)) return ONLY one of {"menuName":"Breakfast"|"Brunch"|"Lunch"|"Snack"|"Dinner"}. If unclear → "Lunch"."#
        }
    }

    private func ultraCompactDetailsPrompt(menuName: String, prompts: [String]) -> String {
        let p = prompts.isEmpty ? "" : " (" + budgetedJoin(prompts, maxChars: 160) + ")"
        return """
        Return {"description":"Summary: \(menuName)\\n\\n1) …\\n2) …","prepTimeMinutes":30}\(p.isEmpty ? "" : " // consider: \(p)")
        """
    }

    // MARK: - Превю → ResolvedIngredient

    private func resolvePreviewItemsToResolvedIngredients(
        _ items: [MealPlanPreviewItem],
        onLog: (@Sendable (String) -> Void)?
    ) async -> [ResolvedIngredient] {
        guard !items.isEmpty else { return [] }
        let ctx = ModelContext(self.container)
        var out: [ResolvedIngredient] = []

        for it in items {
            let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate<FoodItem> {
                $0.name == it.name && !$0.isUserAdded
            })
            
            do {
                try Task.checkCancellation()
                if let food = try ctx.fetch(descriptor).first {
                    out.append(ResolvedIngredient(foodItemID: food.id, grams: it.grams))
                } else {
                    onLog?("    - ⚠️ Can't resolve '\(it.name)' to FoodItem; skipping.")
                }
            } catch {
                onLog?("    - ⚠️ Fetch error for '\(it.name)': \(error.localizedDescription)")
            }
        }
        return out
    }

    // --- START OF CHANGE (Decorated Name) ---
    /// Инструкции за украсяване: изисква включен каноничен слот + 1–2 тематични думи, без емоджита/брендове.
    private func decoratedNameInstructions() -> Instructions {
        Instructions {
            """
            Create a short, decorated display name for a meal.

            HARD RULES:
            - 3–6 words, plain text only (no emojis, no brands).
            - MUST include one of the exact canonical slots: Breakfast, Brunch, Lunch, Snack, Dinner.
            - Prefer putting the canonical slot first, then an en dash or hyphen, then 2–4 words.
            - Incorporate 1–2 cues: key ingredients, cuisine, or attributes (e.g., High-Protein, Mediterranean, Fresh).
            - Keep it natural and readable. Avoid long lists.

            LANGUAGE:
            - Match the user's language if obvious; else Bulgarian.

            Return ONLY JSON: {"displayName":"…"}
            """
        }
    }

    /// Взимаме топ съставките по грамове за подсказка към украсяването.
    private func topIngredientHints(_ items: [MealPlanPreviewItem], max: Int = 4) -> [String] {
        let top = items.sorted { $0.grams > $1.grams }.prefix(max)
        return top.map { $0.name }
    }

    /// Генерира “украшено” име, **съдържащо** каноничния слот.
    private func regenerateDecoratedMenuName(
        canonicalSlot: String,
        items: [MealPlanPreviewItem],
        prompts: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> String {
        let ing = topIngredientHints(items).joined(separator: ", ")
        let hints = budgetedJoin(prompts, maxChars: 200)

        let session = LanguageModelSession(instructions: decoratedNameInstructions())
        let prompt = """
        Canonical slot: \(canonicalSlot)
        Key ingredients: \(ing.isEmpty ? "n/a" : ing)
        Hints: \(hints)

        Produce a decorated display name (3–6 words) that includes "\(canonicalSlot)" and reads nicely.
        Prefer format: "<\(canonicalSlot)> – <2–4 words>".
        """
        emitLog("LLM decorated-name prompt → \(prompt)", onLog: onLog)

        do {
            let resp = try await session.respond(
                to: prompt,
                generating: AIMenuDecoratedNameOnly.self,
                includeSchemaInPrompt: false,
                options: GenerationOptions(sampling: .greedy)
            ).content
            var pretty = resp.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")

            // Гаранция: съдържа каноничния слот. Ако липсва – префиксваме.
            if !pretty.localizedCaseInsensitiveContains(canonicalSlot) {
                pretty = "\(canonicalSlot) – \(pretty)"
            }

            // Къс клип (без да чупим думи): ~48 символа
            if pretty.count > 64 {
                if let idx = pretty.index(pretty.startIndex, offsetBy: 64, limitedBy: pretty.endIndex) {
                    let clipped = String(pretty[..<idx])
                    // опит да не режем по средата на дума
                    if let lastSpace = clipped.lastIndex(of: " ") {
                        pretty = String(clipped[..<lastSpace])
                    } else {
                        pretty = clipped
                    }
                }
            }

            emitLog("✅ Decorated name → \(pretty)", onLog: onLog)
            return pretty
        } catch {
            emitLog("⚠️ Decorated-name generation failed: \(error.localizedDescription). Fallback to canonical.", onLog: onLog)
            return canonicalSlot
        }
    }

    func generateMenuDetails(
        jobID: PersistentIdentifier,
        for profile: Profile,
        prompts: [String]?,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> ResolvedRecipeResponseDTO {

        let promptsSafe = (prompts ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        emitLog("🚀 generateMenuDetails(for: \(profile.name), prompts: \(promptsSafe)) – START", onLog: onLog)
        try Task.checkCancellation()

        // === ЕТАП 1: Канонично име ===
        let nameSession = LanguageModelSession(instructions: nameInstructions())
        let namePrompt  = nameUserPrompt(prompts: promptsSafe)
        emitLog("LLM name-prompt → \(namePrompt)", onLog: onLog)
        try Task.checkCancellation()

        var canonicalSlot: String = "Lunch"
        do {
            let nameResp = try await nameSession.respond(
                to: namePrompt,
                generating: AIMenuNameOnly.self,
                includeSchemaInPrompt: false,
                options: GenerationOptions(sampling: .greedy)
            ).content
            canonicalSlot = sanitizeAndClampToAllowed(nameResp.menuName, prompts: promptsSafe)
            emitLog("✅ Етап 1: Канонично име → \(canonicalSlot)", onLog: onLog)
        } catch {
            if let fromPrompts = pickFromPrompts(promptsSafe) {
                canonicalSlot = fromPrompts
                emitLog("⚠️ Етап 1 се провали, използва се от подсказките → \(canonicalSlot)", onLog: onLog)
            } else {
                emitLog("⚠️ Етап 1 се провали (\(error)). Използва се 'Lunch'.", onLog: onLog)
                canonicalSlot = "Lunch"
            }
        }
        try Task.checkCancellation()

        // === ЕТАП 2: Съставки от планера ===
        emitLog("🚀 Етап 2: Генериране на съставки чрез USDAWeeklyMealPlanner за '\(canonicalSlot)'...", onLog: onLog)
        let planner = USDAWeeklyMealPlanner(container: self.container)
        try Task.checkCancellation()
        let generatedPreview: MealPlanPreview
        do {
            generatedPreview = try await planner.fillPlanDetails(
                jobID: jobID,
                profileID: profile.persistentModelID,
                daysAndMeals: [1: [canonicalSlot]],
                prompts: promptsSafe,
                mealTimings: nil,
                onLog: onLog
            )
            emitLog("✅ Етап 2: Съставките са генерирани.", onLog: onLog)
        } catch {
            emitLog("❌ Етап 2: Провал: \(error.localizedDescription).", onLog: onLog)
            throw error
        }
        try Task.checkCancellation()

        let previewItems = generatedPreview.days.first?.meals.first?.items ?? []
        if previewItems.isEmpty {
            emitLog("⚠️ Етап 2: Няма съставки.", onLog: onLog)
        } else {
            let ingredientList = previewItems
                .map { "- \($0.name) (\(Int(($0.grams).rounded()))g)" }
                .joined(separator: "\n")
            emitLog("   - Съставки:\n\(ingredientList)", onLog: onLog)
        }
        try Task.checkCancellation()

        // === ЕТАП 2.5: Украсяване на името (дисплейно име) ===
        let decoratedName = await regenerateDecoratedMenuName(
            canonicalSlot: canonicalSlot,
            items: previewItems,
            prompts: promptsSafe,
            onLog: onLog
        )
        try Task.checkCancellation()

        // === ЕТАП 3: Описание + време (строго валидирано) ===
        emitLog("🚀 Етап 3: Генериране на описание и време…", onLog: onLog)

        let detailsSession = LanguageModelSession(instructions: detailsInstructions())
        let ingredientListForPrompt = previewItems
            .map { "\($0.name) (\(Int(($0.grams).rounded())) g)" }
            .joined(separator: ", ")

        let detailsPrompt = """
        Generate a description and total active prep time for the following menu.
        The description MUST be in the required format: a line starting with "Summary: ", a blank line, and then numbered steps "1) ...", 5–12 steps.

        Menu Name: \(decoratedName)
        Ingredients: \(ingredientListForPrompt.isEmpty ? "n/a" : ingredientListForPrompt)
        User Prompts (for context): \(budgetedJoin(promptsSafe, maxChars: 300))

        Return ONLY the JSON for AIMenuDetailsOnly.
        """
        emitLog("LLM details-prompt → \(detailsPrompt)", onLog: onLog)

        var descriptionOut: String = "Summary: \(decoratedName)\n\n1) Prepare ingredients.\n2) Assemble the meal.\n3) Serve.\n4) Enjoy.\n5) Clean up."
        var minutesOut: Int = 25
        try Task.checkCancellation()

        do {
            var resp = try await detailsSession.respond(
                to: detailsPrompt,
                generating: AIMenuDetailsOnly.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content

            var fixedDesc = ensureSummaryHasName(resp.description, menuName: decoratedName)
            if !isValidDescriptionWithIntro(fixedDesc) {
                emitLog("ℹ️ Description форматът не мина → строг re-generation…", onLog: onLog)

                let fixPrompt = """
                Regenerate the SAME menu description for "\(decoratedName)".
                The JSON must match the schema. Enforce this "description" format exactly:
                Summary: <1–2 concise sentences>

                1) ...
                2) ...
                3) ...
                (5–12 steps total, plain text only)
                Keep "prepTimeMinutes" within [10, 360] and reflect the ingredients: \(ingredientListForPrompt.isEmpty ? "n/a" : ingredientListForPrompt).
                """
                resp = try await detailsSession.respond(
                    to: fixPrompt,
                    generating: AIMenuDetailsOnly.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(sampling: .greedy)
                ).content
                fixedDesc = ensureSummaryHasName(resp.description, menuName: decoratedName)
            }
            try Task.checkCancellation()

            if !isValidDescriptionWithIntro(fixedDesc) {
                emitLog("⚠️ И вторият опит не покри формàта. Използвам fallback шаблон.", onLog: onLog)
            } else {
                descriptionOut = fixedDesc
            }

            minutesOut = max(10, min(360, resp.prepTimeMinutes))
            emitLog("✅ Етап 3: Детайлите са генерирани → време: \(minutesOut) мин", onLog: onLog)
        } catch {
            emitLog("❌ Етап 3 се провали (\(error.localizedDescription)). Използват се стойности по подразбиране.", onLog: onLog)
        }
        try Task.checkCancellation()

        // === ЕТАП 4: Резолвваме съставките и връщаме DTO ===
        let resolvedIngredients = await resolvePreviewItemsToResolvedIngredients(previewItems, onLog: onLog)
        try Task.checkCancellation()

        let dto = ResolvedRecipeResponseDTO(
            name: decoratedName, // <<< връщаме УКРАСЕНОТО име
            description: descriptionOut,
            prepTimeMinutes: minutesOut,
            ingredients: resolvedIngredients
        )

        emitLog("🏁 generateMenuDetails – КРАЙ (ingredients: \(resolvedIngredients.count), name: \(decoratedName))", onLog: onLog)
        return dto
    }
}
