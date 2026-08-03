// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/Ayura/Ayura/AI/ReceptGeneration/AIRecipeGenerator.swift ====
import Foundation
import SwiftData
import FoundationModels

// MARK: - Main Recipe Generator Class

@available(iOS 26.0, *)
@MainActor
class AIRecipeGenerator {
    private let globalTaskManager = GlobalTaskManager.shared
    
    // MARK: Logging
    private func emitLog(_ message: String, onLog: (@Sendable (String) -> Void)?) {
        onLog?(message)
    }
    
    // Compact JSON pretty-printer for logging model outputs
    private func logJSON<T: Encodable>(_ value: T, label: String, onLog: (@Sendable (String) -> Void)?) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let data = try enc.encode(value)
            var s = String(data: data, encoding: .utf8) ?? "<encoding failed>"
            if s.count > 1200 {
                s = String(s.prefix(1200)) + " …(truncated)"
            }
            emitLog("\(label): \(s)", onLog: onLog)
        } catch {
            emitLog("\(label): <failed to encode JSON: \(error.localizedDescription)>", onLog: onLog)
        }
    }
    
    private func logDivider(_ title: String? = nil, onLog: (@Sendable (String) -> Void)?) {
        let bar = String(repeating: "─", count: 48)
        emitLog("┌\(bar)", onLog: onLog)
        if let t = title { emitLog("│ \(t)", onLog: onLog) }
        emitLog("└\(bar)", onLog: onLog)
    }
    
    // --- START OF CHANGE ---
    private func formatConceptualRecipe(_ r: AIRecipeResponse, title: String) -> String {
        var s: [String] = []
        s.append("RECIPE: \(title)")
        s.append("Prep time (active): \(r.prepTimeMinutes) min")
        s.append("")
        s.append("Ingredients (conceptual, 2–4 servings):")
        if r.ingredients.isEmpty {
            s.append("  – none")
        } else {
            for (i, ing) in r.ingredients.enumerated() {
                s.append(String(format: "  %2d) %@ – %.0f g", i+1, ing.name, ing.grams))
            }
        }
        s.append("")
        s.append("Description:")
        s.append(r.description)
        return s.joined(separator: "\n")
    }
    // --- END OF CHANGE ---
    
    private func formatFinalRecipe(
        name: String,
        description: String,
        prepTime: Int,
        resolved: [ResolvedIngredient],
        nameByID: [Int: String]
    ) -> String {
        var s: [String] = []
        s.append("FINAL RECIPE: \(name)")
        s.append("Prep time (active): \(prepTime) min")
        s.append("")
        s.append("Ingredients (resolved):")
        if resolved.isEmpty {
            s.append("  – none")
        } else {
            let sorted = resolved.sorted { $0.grams > $1.grams }
            for (i, r) in sorted.enumerated() {
                let nm = nameByID[r.foodItemID] ?? "Item #\(r.foodItemID)"
                s.append(String(format: "  %2d) %@ – %.0f g  [id: %d]", i+1, nm, r.grams, r.foodItemID))
            }
        }
        s.append("")
        s.append("Description:")
        s.append(description)
        return s.joined(separator: "\n")
    }
    
    // MARK: Dependencies
    private let container: ModelContainer
    
    init(container: ModelContainer) {
        self.container = container
        emitLog("init(container:) – ModelContainer injected and stored.", onLog: nil)
    }
    
    // --- START OF CHANGE: crash-safe saveProgress (RecipeGenerationProgress) ---
    @MainActor
    private func saveProgress(
        jobID: PersistentIdentifier,
        progress: RecipeGenerationProgress,
        onLog: (@Sendable (String) -> Void)?
    ) async {
        if Task.isCancelled {
            emitLog("⏹️ [Progress] Task cancelled; skip recipe progress save.", onLog: onLog)
            return
        }
        
        do {
            // fresh контекст за писане
            let writeCtx = ModelContext(self.container)
            
            // ре-фетч по persistentModelID (НЕ context.model(for:))
            let fd = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.persistentModelID == jobID })
            guard let job = try writeCtx.fetch(fd).first else {
                emitLog("⚠️ [Progress] Job \(jobID) not found (deleted?); skip.", onLog: onLog)
                return
            }
            
            // последна проверка преди сетъра — пресича race с изтриване
            try Task.checkCancellation()
            
            job.intermediateResultData = try JSONEncoder().encode(progress)
            try writeCtx.save()
            
            emitLog("💾 [Progress] Прогресът за генериране на рецепта е запазен.", onLog: onLog)
        } catch is CancellationError {
            emitLog("⏹️ [Progress] Cancelled mid-save; skipping recipe progress.", onLog: onLog)
        } catch {
            emitLog("❌ [Progress] Неуспешен запис на прогреса: \(error.localizedDescription)", onLog: onLog)
        }
    }
    // --- END OF CHANGE ---
    
    
    // MARK: Recipe-level context profile (derived — no hardcoding of dish names)
    private struct RecipeContextProfile {
        let recipeName: String
        let isColdOrNoCook: Bool
        let preferRawProduce: Bool
        let disallowCookedForms: Bool
        let rationale: String
    }
    
    /// Infer simple, robust context signals from the conceptual response and name — without hardcoding any dish.
    private func inferRecipeContext(from r: AIRecipeResponse, recipeName: String) -> RecipeContextProfile {
        // Signals from description
        let desc = r.description.lowercased()
        let cookVerbs: Set<String> = [
            "bake","boil","simmer","stew","grill","griddle","roast","fry","deep-fry","pan-fry",
            "saute","sauté","broil","poach","steam","blanch","sear","braise","pressure-cook","air-fry"
        ]
        let coldSignals: Set<String> = [
            "serve cold","chill","chilled","cold soup","no-cook","uncooked","combine and serve","stir and serve"
        ]
        let hasCookingVerb = cookVerbs.contains { desc.contains($0) }
        let hasColdSignal   = coldSignals.contains { desc.contains($0) }
        
        let isNoCook = hasColdSignal && !hasCookingVerb
        let preferRaw = isNoCook // if it's a no-cook/cold style, prefer raw variants

        let rationale = "isNoCook=\(isNoCook) (coldSignal=\(hasColdSignal), cookingVerb=\(hasCookingVerb))"
        return RecipeContextProfile(
            recipeName: recipeName,
            isColdOrNoCook: isNoCook,
            preferRawProduce: preferRaw,
            disallowCookedForms: isNoCook, // forbid cooked forms when dish is no-cook
            rationale: rationale
        )
    }
    
    private static let baseInstructions = Instructions {
        """
        You are a helpful culinary assistant that creates recipes.
        
        REQUIRED OUTPUT SHAPE:
        - Return ONLY the JSON object that matches the provided schema. No prose, no code fences.
        
        DESCRIPTION FIELD RULES (STRICT):
        - The "description" string must have:
          1) One short summary line, prefixed exactly with: "Summary: "
             • 1–2 concise sentences max; plain text only.
          2) A blank line.
          3) A numbered, step-by-step procedure with the exact format:
             "1) ...\n2) ...\n3) ..."
             • 5–12 steps total, each step a short, imperative sentence.
             • Plain text only (no Markdown, bullets, or headings).
        
        INGREDIENTS & PREP TIME:
        - List common, simple ingredients with realistic gram amounts for 2–4 servings.
        - "prepTimeMinutes" is an integer in [5, 240], covering active prep only (washing, chopping, preheating).
        
        NAMING:
        - Use generic ingredient names (e.g., "Chicken Breast" instead of branded/overly specific variants).
        """
    }
    
    private lazy var sharedSession = LanguageModelSession(instructions: Self.baseInstructions)
    
    /// Trim the shared session transcript by removing the last `count` entries while keeping the older history.
    /// If the transcript has fewer than `count` entries, this resets it to empty.
    private func trimSharedSessionRemovingLast(_ count: Int, onLog: (@Sendable (String) -> Void)?) {
        // Current FoundationModels Transcript API doesn't expose an `entries` collection we can slice here.
        // Fallback: safely reset the session to clear recent turns while keeping instructions stable.
        sharedSession = LanguageModelSession(instructions: Self.baseInstructions)
        emitLog("🧹 Reset sharedSession transcript (cleared recent turns).", onLog: onLog)
    }
    
    // MARK: Step 1 – Conceptual generation (names + grams + prep time)
    private func generateConceptualRecipe(
        for recipeName: String,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> AIRecipeResponse {
        emitLog("🚀 generateConceptualRecipe(for: '\(recipeName)') – START", onLog: onLog)
        
        emitLog("LanguageModelSession prepared with strict instructions.", onLog: onLog)
        
        let prompt = "Generate a recipe for \(recipeName)."
        emitLog("LLM#1 prompt → \(prompt)", onLog: onLog)
        try Task.checkCancellation()
        
        func isValidDescriptionWithIntro(_ text: String) -> Bool {
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
        try Task.checkCancellation()
        
        do {
            let options = GenerationOptions(
                sampling: .greedy
            )
            emitLog("Options: sampling=.greedy, includeSchemaInPrompt=true", onLog: onLog)
            try Task.checkCancellation()
            
            // Attempt #1
            emitLog("LLM#1 request (conceptual recipe)…", onLog: onLog)
            var response = try await sharedSession.respond(
                to: prompt,
                generating: AIRecipeResponse.self,
                includeSchemaInPrompt: true,
                options: options
            )
            logJSON(response.content, label: "LLM#1 output (AIRecipeResponse)", onLog: onLog)
            try Task.checkCancellation()
            
            // Format guard, one strict retry if needed
            if !isValidDescriptionWithIntro(response.content.description) {
                emitLog("ℹ️ Description format validation failed → strict re-generation (LLM#1b)…", onLog: onLog)
                
                let fixPrompt = """
                Regenerate the SAME recipe for \(recipeName).
                The JSON must match the schema. Enforce this "description" format exactly:
                Summary: <1–2 concise sentences>
                
                1) ...
                2) ...
                3) ...
                (5–12 steps total, plain text only)
                Keep ingredients realistic in grams for 2–4 servings and provide a valid prepTimeMinutes in [5, 240].
                """
                
                emitLog("LLM#1b prompt → \(fixPrompt)", onLog: onLog)
                response = try await sharedSession.respond(
                    to: fixPrompt,
                    generating: AIRecipeResponse.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                logJSON(response.content, label: "LLM#1b output (AIRecipeResponse)", onLog: onLog)
            }
            try Task.checkCancellation()
            
            emitLog("✅ Conceptual recipe generated.", onLog: onLog)
            emitLog("   • Prep time (active): \(response.content.prepTimeMinutes) min", onLog: onLog)
            emitLog("   • Ingredients count: \(response.content.ingredients.count)", onLog: onLog)
            let preview = String(response.content.description.prefix(140))
            emitLog("   • Description (preview): \(preview)\(response.content.description.count > 140 ? "..." : "")", onLog: onLog)
            try Task.checkCancellation()
            
            // Full conceptual printout (for visibility)
            logDivider("Conceptual Recipe (Full Printout)", onLog: onLog)
            emitLog("\n" + formatConceptualRecipe(response.content, title: recipeName), onLog: onLog)
            logDivider(onLog: onLog)
            try Task.checkCancellation()
            
            // After generating a conceptual recipe (and any retry), drop the last 2 turns to cap growth
            trimSharedSessionRemovingLast(2, onLog: onLog)
            emitLog("🏁 generateConceptualRecipe – END", onLog: onLog)
            return response.content
            
        } catch {
            emitLog("❌ Conceptual generation failed: \(error.localizedDescription)", onLog: onLog)
            emitLog("🏁 generateConceptualRecipe – END (ERROR)", onLog: onLog)
            throw error
        }
    }
    
    // MARK: Step 2 – Resolve conceptual ingredients to FoodItems (DTO)
    // --- START OF CHANGE: Modify generateAndResolveRecipeDTO ---
    func generateAndResolveRecipeDTO(
        for recipeName: String,
        jobID: PersistentIdentifier, // Add jobID parameter
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> ResolvedRecipeResponseDTO {
        emitLog("🚀 generateAndResolveRecipeDTO(for: '\(recipeName)') – START", onLog: onLog)
        try Task.checkCancellation()
        
        let ctx = ModelContext(self.container)
        guard let job = ctx.model(for: jobID) as? AIGenerationJob else {
            throw NSError(domain: "RecipeGenerator", code: 404, userInfo: [NSLocalizedDescriptionKey: "AIGenerationJob not found."])
        }
        guard !AyurvedaRecommendationGate.nameIsExcluded(recipeName, context: ctx) else {
            emitLog("🚫 AyurvedaGate: dropped excluded generated recipe '\(recipeName)'", onLog: onLog)
            throw NSError(domain: "AyurvedaRecommendationGate", code: 1, userInfo: [NSLocalizedDescriptionKey: "This food is not available for recommendations."])
        }
        
        var progress: RecipeGenerationProgress
        if let data = job.intermediateResultData, let loaded = try? JSONDecoder().decode(RecipeGenerationProgress.self, from: data) {
            progress = loaded
            emitLog("🔄 Продължаване на генерирането на рецепта.", onLog: onLog)
        } else {
            progress = RecipeGenerationProgress()
            emitLog("  -> Не е намерен съществуващ прогрес. Започва се отначало.", onLog: onLog)
        }
        try Task.checkCancellation()
        
        // --- Checkpoint 1: Conceptual generation ---
        let conceptual: AIRecipeResponse
        if let cached = progress.conceptualRecipe {
            conceptual = cached
            emitLog("  -> ✅ Checkpoint 1: Използване на кеширана концептуална рецепта.", onLog: onLog)
        } else {
            emitLog("Step 1/3: Conceptual generation…", onLog: onLog)
            conceptual = try await generateConceptualRecipe(for: recipeName, onLog: onLog)
            progress.conceptualRecipe = conceptual
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
            emitLog("✅ Conceptual ready and saved.", onLog: onLog)
        }
        try Task.checkCancellation()
        
        // Derive per-recipe context from the conceptual result (no hardcoded dish/ingredients)
        let recipeCtx = inferRecipeContext(from: conceptual, recipeName: recipeName)
        emitLog("RecipeContext: \(recipeCtx.rationale)", onLog: onLog)
        try Task.checkCancellation()
        
        // --- Checkpoint 2: Smart ingredient resolution ---
        let smart: SmartResolutionResult
        if let cached = progress.smartResolutionResult {
            smart = cached
            emitLog("  -> ✅ Checkpoint 2: Използване на кеширани резолвнати съставки.", onLog: onLog)
        } else {
            emitLog("Step 2/3: Smart ingredient resolution for \(conceptual.ingredients.count) item(s)…", onLog: onLog)
            let smartTuple = try await resolveIngredientsSmartly(
                recipeName: recipeName,
                conceptual: conceptual,
                recipeContext: recipeCtx,
                onLog: onLog
            )
            smart = SmartResolutionResult(
                resolved: smartTuple.resolved,
                replacements: smartTuple.replacements.map { .init(from: $0.from, to: $0.to) },
                generatedNames: smartTuple.generatedNames,
                nameByID: smartTuple.nameByID,
                unresolved: smartTuple.unresolved
            )
            progress.smartResolutionResult = smart
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
            emitLog("✅ Smart resolving completed and saved.", onLog: onLog)
        }
        try Task.checkCancellation()
        
        if !smart.unresolved.isEmpty {
            emitLog("   • Unresolved (skipped): \(smart.unresolved.joined(separator: ", "))", onLog: onLog)
        }
        if !smart.replacements.isEmpty {
            let pairs = smart.replacements.map { "‘\($0.from)’→‘\($0.to)’" }.joined(separator: ", ")
            emitLog("   • Name replacements: \(pairs)", onLog: onLog)
        }
        if !smart.generatedNames.isEmpty {
            emitLog("   • Generated new items: \(smart.generatedNames.joined(separator: ", "))", onLog: onLog)
        }
        try Task.checkCancellation()

        let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
        let allowedResolved = smart.resolved.filter { !excludedFoodIds.contains($0.foodItemID) }
        emitLog("🚫 AyurvedaGate: AyurvedaGate active, \(smart.resolved.count - allowedResolved.count) candidates filtered", onLog: onLog)
        
        // --- Step 3: Description reconciliation (fast, no checkpoint needed) ---
        emitLog("Step 3/3: Description reconciliation (if needed)…", onLog: onLog)
        var finalDescription = conceptual.description
        if !smart.replacements.isEmpty || !smart.generatedNames.isEmpty || allowedResolved.count != smart.resolved.count {
            let finalNamesWithGrams: [(String, Double)] = allowedResolved
                .compactMap { rid in
                    guard let name = smart.nameByID[rid.foodItemID] else { return nil }
                    return (name, rid.grams)
                }
            finalDescription = try await regenerateDescriptionToMatchIngredients(
                original: conceptual.description,
                recipeName: recipeName,
                finalIngredients: finalNamesWithGrams,
                onLog: onLog
            )
            emitLog("📝 Description was regenerated to reflect final ingredient names.", onLog: onLog)
        } else {
            emitLog("📝 Description regeneration skipped (no replacements/new items).", onLog: onLog)
        }
        try Task.checkCancellation()
        
        let clampedPrep = max(5, min(240, conceptual.prepTimeMinutes))
        let dto = ResolvedRecipeResponseDTO(
            description: finalDescription,
            prepTimeMinutes: clampedPrep,
            ingredients: allowedResolved.sorted { $0.grams > $1.grams }
        )
        try Task.checkCancellation()
        
        // --- Final printout and cleanup ---
        logDivider("FINAL RECIPE (Printout Before Return)", onLog: onLog)
        let finalPrint = formatFinalRecipe(
            name: recipeName,
            description: dto.description,
            prepTime: dto.prepTimeMinutes,
            resolved: dto.ingredients,
            nameByID: smart.nameByID
        )
        emitLog("\n" + finalPrint, onLog: onLog)
        logDivider(onLog: onLog)
        try Task.checkCancellation()
        
        emitLog("✅ Генерирането на рецепта завърши. Изчистване на междинния прогрес.", onLog: onLog)
        job.intermediateResultData = nil
        try ctx.save()
        
        emitLog("📤 Returning DTO (description + \(dto.ingredients.count) resolved ingredient(s)).", onLog: onLog)
        emitLog("🏁 generateAndResolveRecipeDTO – END", onLog: onLog)
        return dto
    }
    // --- END OF CHANGE ---
    
    // MARK: Convenience – Generate, then materialize to [FoodItem]
    /// Generates, resolves, and returns an in-memory result with [FoodItem].
    func generateAndResolveRecipe(
        for recipeName: String,
        jobID: PersistentIdentifier, // Propagate jobID
        onLog: (@Sendable (String) -> Void)?,
        in context: ModelContext
    ) async throws -> ResolvedRecipeResponse {
        emitLog("🚀 generateAndResolveRecipe(for: '\(recipeName)') – START", onLog: onLog)
        let dto = try await generateAndResolveRecipeDTO(for: recipeName, jobID: jobID, onLog: onLog)
        emitLog("Materializing DTO into in-memory ResolvedRecipeResponse…", onLog: onLog)
        let result = AIRecipeGenerator.materialize(dto, in: context, onLog: onLog)
        emitLog("🏁 generateAndResolveRecipe – END", onLog: onLog)
        return result
    }
    
    // MARK: - Materialization helper
    /// Convert DTO → in-memory model with actual `FoodItem` instances.
    @MainActor
    static func materialize(
        _ dto: ResolvedRecipeResponseDTO,
        in context: ModelContext,
        onLog: (@Sendable (String) -> Void)? = nil
    ) -> ResolvedRecipeResponse {
        let ids = dto.ingredients.map { $0.foodItemID }
        let desc = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.id) })
        let fetchedItems = (try? context.fetch(desc)) ?? []
        let itemMap = Dictionary(uniqueKeysWithValues: fetchedItems.map { ($0.id, $0) })
        
        var items: [FoodItem] = []
        var grams: [FoodItem: Double] = [:]
        var missing = 0
        
        for entry in dto.ingredients {
            if let fi = itemMap[entry.foodItemID] {
                items.append(fi)
                grams[fi, default: 0.0] += entry.grams
            } else {
                missing += 1
            }
        }
        
        if missing > 0 {
            let msg = "Materialize: \(missing) ingredient(s) missing in current ModelContext."
            let line = "🧭 [AIRecipeGenerator] \(msg)"
            onLog?(line)
            print(line)
        }
        
        let summary = "Materialized \(items.count) FoodItem(s) (\(missing) missing)."
        let line = "🧭 [AIRecipeGenerator] \(summary)"
        onLog?(line)
        print(line)
        
        return ResolvedRecipeResponse(
            description: dto.description,
            prepTimeMinutes: dto.prepTimeMinutes,
            ingredients: items,
            gramsByItem: grams
        )
    }
    
    private func filterCandidates(
        _ candidates: [FoodItemCandidate],
        banned: [String],
        requiredHeadwords: [String],
        original: AIRecipeIngredient,
        recipeContext: RecipeContextProfile,
        otherIngredients: [String]
    ) -> [FoodItemCandidate] {
        guard !candidates.isEmpty else { return [] }
        
        let dynamicBans = banned + [
            "baby food","infant","toddler","gerber",
            "stage 1","stage 2","stage 3",
            "dog food","cat food","pet food"
        ]
        let conceptIDs = Set(
            dynamicBans.compactMap { FoodConcepts.shared.conceptID(for: $0) }
        )
        let candidateIDs = Set(candidates.map(\.id))
        var blockedIDs = Set<Int>()
        for conceptID in conceptIDs {
            blockedIDs.formUnion(
                FoodConcepts.shared.members(of: conceptID).map(Int.init)
            )
        }
        let allowedIDs = candidateIDs.subtracting(blockedIDs)
        let guardTokenGroups = dynamicBans.compactMap { value -> Set<String>? in
            guard FoodConcepts.shared.conceptID(for: value) == nil else {
                return nil
            }
            let tokens = Set(AyurvedaRules.modifierTokens(value))
            return tokens.isEmpty ? nil : tokens
        }
        
        return candidates.filter { c in
            guard allowedIDs.contains(c.id) else { return false }
            let candidateTokens = Set(AyurvedaRules.modifierTokens(c.name))
            if guardTokenGroups.contains(where: { $0.isSubset(of: candidateTokens) }) {
                return false
            }
            
            return passesStrictGuards(
                originalName: original.name,
                candidateName: c.name,
                recipeContext: recipeContext,
                otherIngredients: otherIngredients,
                requiredHeadwords: requiredHeadwords
            )
        }
    }
    
    
    // MARK: - Smart ingredient resolution pipeline
    @MainActor
    private func resolveIngredientsSmartly(
        recipeName: String,
        conceptual: AIRecipeResponse,
        recipeContext: RecipeContextProfile,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> (
        resolved: [ResolvedIngredient],
        replacements: [(from: String, to: String)],
        generatedNames: [String],
        nameByID: [Int: String],
        unresolved: [String]
    ) {
        emitLog("🔎 resolveIngredientsSmartly – START (\(conceptual.ingredients.count) conceptual ingredient(s))", onLog: onLog)

        let gateContext = ModelContext(self.container)
        let allowedIngredients = conceptual.ingredients.filter { ingredient in
            let excluded = AyurvedaRecommendationGate.nameIsExcluded(ingredient.name, context: gateContext)
            if excluded { emitLog("🚫 AyurvedaGate: dropped excluded generated ingredient '\(ingredient.name)'", onLog: onLog) }
            return !excluded
        }
        emitLog("🚫 AyurvedaGate: AyurvedaGate active, \(conceptual.ingredients.count - allowedIngredients.count) candidates filtered", onLog: onLog)
        
        // ПРОМЯНА: Използваме SmartFoodSearch3
        let smartSearch = SmartFoodSearch3(container: self.container)
        // Зареждаме данните предварително, за да не се бави при първата заявка в цикъла
        smartSearch.loadData()
        
        try Task.checkCancellation()
        
        let otherNames = Set(allowedIngredients.map { $0.name })
        try Task.checkCancellation()
        
        var outResolved: [ResolvedIngredient] = []
        var outRepl: [(from: String, to: String)] = []
        var nameByID: [Int: String] = [:]
        var unresolvedConceptualNames: [String] = []
        try Task.checkCancellation()
        
        // PHASE 1: Паралелна резолюция на налични съставки
        emitLog("--- Starting PARALLEL resolution for existing items ---", onLog: onLog)
        
        let ingredientResolutionTask = Task<Void, Error> {
            try await withThrowingTaskGroup(
                of: (ResolvedIngredient?, (String, String)?, (Int, String)?, String?).self
            ) { group in
                for ing in allowedIngredients {
                    group.addTask { [weak self] in
                        guard let self else { return (nil, nil, nil, ing.name) }
                        
                        await self.emitLog("   🔎 '\(ing.name)' – parallel resolution START", onLog: onLog)
                        
                        let otherIngredientsForContext = Array(otherNames.subtracting([ing.name]))
                        
                        var (queries, banned, requiredHeads) = try await self.ingredientSmartQueries(
                            for: ing.name,
                            recipeName: recipeName,
                            recipeContext: recipeContext,
                            otherIngredients: otherIngredientsForContext,
                            onLog: onLog
                        )
                        
                        var candIDs: [PersistentIdentifier] = []
                        var seen = Set<PersistentIdentifier>()
                        
                        let contextString = "Finding ingredient '\(ing.name)' for recipe '\(recipeName)'."
                        queries.append(ing.name)
                        
                        // Изпълняваме заявките последователно
                        outer: for q in queries {
                            // ПРОМЯНА: Извикваме новия метод в SmartFoodSearch3
                            let ids = await smartSearch.searchFoodsAI(
                                query: q,
                                limit: 20,
                                context: contextString,
                                requiredHeadwords: requiredHeads
                            )
                            for id in ids where !seen.contains(id) {
                                seen.insert(id)
                                candIDs.append(id)
                            }
                        }
                        
                        if candIDs.isEmpty {
                            await self.emitLog("  \(ing.name)     • No candidates found. Marking for sequential creation.", onLog: onLog)
                            return (nil, nil, nil, ing.name)
                        }
                        
                        let candItems = await self.fetchFoodCandidates(for: candIDs, onLog: onLog)
                        
                        let filteredCandItems = await self.filterCandidates(
                            candItems,
                            banned: banned,
                            requiredHeadwords: requiredHeads,
                            original: ing,
                            recipeContext: recipeContext,
                            otherIngredients: otherIngredientsForContext
                        )
                        
                        if filteredCandItems.count < candItems.count {
                            await self.emitLog("   '\(ing.name)' • Programmatic filter removed \(candItems.count - filteredCandItems.count) candidate(s).", onLog: onLog)
                        }
                        
                        if filteredCandItems.isEmpty {
                            await self.emitLog("  '\(ing.name)'     • All candidates were removed by the programmatic filter. Marking for creation.", onLog: onLog)
                            return (nil, nil, nil, ing.name)
                        }
                        
                        let candidateNamesForLog = filteredCandItems.map { "'\($0.name)'" }
                        await self.emitLog("  '\(ing.name)'     • Final candidates for AI choice: [\(candidateNamesForLog.joined(separator: ", "))]", onLog: onLog)
                        
                        let pickIdx = try await self.chooseBestIngredientCandidate(
                            originalName: ing.name,
                            candidateNames: filteredCandItems.map { $0.name },
                            recipeName: recipeName,
                            recipeContext: recipeContext,
                            otherIngredients: otherIngredientsForContext,
                            requiredHeadwords: requiredHeads,
                            onLog: onLog
                        )
                        
                        if pickIdx < 0 || !filteredCandItems.indices.contains(pickIdx) {
                            await self.emitLog("  \(ing.name)     • AI pick is invalid or none chosen. Marking for sequential creation.", onLog: onLog)
                            return (nil, nil, nil, ing.name)
                        }
                        
                        let chosen = filteredCandItems[pickIdx]
                        let repl: (String, String)? = (ing.name.caseInsensitiveCompare(chosen.name) == .orderedSame) ? nil : (ing.name, chosen.name)
                        
                        await self.emitLog("   ✅ '\(ing.name)' → RESOLVED TO '\(chosen.name)' [\(chosen.id)]", onLog: onLog)
                        return (ResolvedIngredient(foodItemID: chosen.id, grams: ing.grams), repl, (chosen.id, chosen.name), nil)
                    }
                }
                
                for try await (maybeRes, maybeRepl, maybePair, maybeUnres) in group {
                    if let r = maybeRes { outResolved.append(r) }
                    if let rr = maybeRepl { outRepl.append(rr) }
                    if let p = maybePair { nameByID[p.0] = p.1 }
                    if let u = maybeUnres { unresolvedConceptualNames.append(u) }
                }
            }
        }
        
        await globalTaskManager.addTask(ingredientResolutionTask)
        try await ingredientResolutionTask.value
        try Task.checkCancellation()
        
        
        var outGenerated: [String] = []
        
        // PHASE 2: Секвенциално създаване на липсващи
        if !unresolvedConceptualNames.isEmpty {
            emitLog("--- Starting SEQUENTIAL creation for \(unresolvedConceptualNames.count) missing item(s) ---", onLog: onLog)
            for name in unresolvedConceptualNames {
                try Task.checkCancellation()
                
                guard let conceptualIngredient = conceptual.ingredients.first(where: { $0.name == name }) else { continue }
                
                emitLog("   🛠️ createMissingIngredient for '\(name)'...", onLog: onLog)
                if let created = try await self.createMissingIngredient(named: name, grams: conceptualIngredient.grams, onLog: onLog) {
                    emitLog("   ✅ '\(name)' → CREATED NEW '\(created.name)' [\(created.id)]", onLog: onLog)
                    outResolved.append(ResolvedIngredient(foodItemID: created.id, grams: conceptualIngredient.grams))
                    outGenerated.append(created.name)
                    nameByID[created.id] = created.name
                    
                    if name.caseInsensitiveCompare(created.name) != .orderedSame {
                        outRepl.append((from: name, to: created.name))
                    }
                } else {
                    emitLog("   ⚠️ '\(name)': creation failed; marking as ultimately unresolved.", onLog: onLog)
                }
            }
            emitLog("--- Finished SEQUENTIAL creation ---", onLog: onLog)
        }
        try Task.checkCancellation()
        
        // Merge на дубликати
        var mergedByID: [Int: Double] = [:]
        for r in outResolved { mergedByID[r.foodItemID, default: 0.0] += r.grams }
        let merged: [ResolvedIngredient] = mergedByID.map { ResolvedIngredient(foodItemID: $0.key, grams: $0.value) }
        try Task.checkCancellation()
        
        emitLog("Resolution process finished.", onLog: onLog)
        emitLog("   • Resolved unique item IDs: \(merged.count)", onLog: onLog)
        if !outRepl.isEmpty {
            let pairs = outRepl.map { "‘\($0.from)’→‘\($0.to)’" }.joined(separator: ", ")
            emitLog("   • Replacements applied: \(pairs)", onLog: onLog)
        }
        if !outGenerated.isEmpty {
            emitLog("   • Newly generated items: \(outGenerated.joined(separator: ", "))", onLog: onLog)
        }
        
        let finalUnresolved = unresolvedConceptualNames.filter { name in
            !outRepl.contains(where: { $0.from == name }) && !outGenerated.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        }
        if !finalUnresolved.isEmpty {
            emitLog("   • Ultimately unresolved conceptual names: \(finalUnresolved.joined(separator: ", "))", onLog: onLog)
        }
        
        emitLog("🔎 resolveIngredientsSmartly – END", onLog: onLog)
        return (
            resolved: merged,
            replacements: outRepl,
            generatedNames: outGenerated,
            nameByID: nameByID,
            unresolved: finalUnresolved
        )
    }
    
    @MainActor
    private func ingredientSmartQueries(
        for rawName: String,
        recipeName: String,
        recipeContext: RecipeContextProfile,
        otherIngredients: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> (queries: [String], banned: [String], requiredHeadwords: [String]) {
        emitLog("ingredientSmartQueries(\"\(rawName)\") – START", onLog: onLog)
        
        // 1) Варианти + avoid от AINamingVariants
        let (variantQueries, variantBans) = try await generateUSDANameVariants(
            for: rawName,
            recipeName: recipeName,
            recipeContext: recipeContext,
            otherIngredients: otherIngredients,
            onLog: onLog
        )
        
        // 2) Кратки ключови думи + синоними (AIShortKeywords)
        let ctx = otherIngredients.isEmpty ? "n/a" : otherIngredients.joined(separator: ", ")
        emitLog("  • Recipe context: \(recipeContext.rationale)", onLog: onLog)
        emitLog("  • Context → recipe: '\(recipeName)', other: \(ctx)", onLog: onLog)
        
        var finalQueries = variantQueries
        var bannedSet = Set(variantBans.map { $0.lowercased() })
        var dynamicHeadwords = [String]()
        
        do {
            let instructions = Instructions {
                """
                Extract compact search tokens: 2–4 priority keywords (headword first), up to 6 banned tokens, and up to 3 headword synonyms.
                Keep tokens short (1–2 words each). No brands.
                """
            }
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            CONCEPT: "\(rawName)"
            RECIPE: "\(recipeName)"
            OTHER INGREDIENTS: \(ctx)
            """
            emitLog("  • LLM#KW prompt → \(prompt)", onLog: onLog)
            try Task.checkCancellation()
            
            let resp = try await session.respond(
                to: prompt,
                generating: AIShortKeywords.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content
            logJSON(resp, label: "  • LLM#KW output (AIShortKeywords)", onLog: onLog)
            try Task.checkCancellation()
            
            // Headword = първият priority keyword; добавяме и headwordSynonyms (динамични).
            let kw = resp.priorityKeywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if let head = kw.first { dynamicHeadwords.append(head) }
            dynamicHeadwords.append(contentsOf: resp.headwordSynonyms)
            try Task.checkCancellation()
            
            // Подобряване на заявки (както досега)
            if !kw.isEmpty {
                let top3 = Array(kw.prefix(3))
                if top3.count == 3 { finalQueries.append(top3.joined(separator: " ")) }
                if top3.count >= 2 { finalQueries.append(top3.prefix(2).joined(separator: " ")) }
                finalQueries.append(top3[0])
            }
            bannedSet.formUnion(resp.bannedKeywords.map { $0.lowercased() })
        } catch {
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            if error is CancellationError {
                throw error
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
            
            emitLog("  • LLM#KW enrichment skipped: \(error.localizedDescription)", onLog: onLog)
        }
        
        // Fallback за headwords, ако LLM не даде – първи токен от името/самото име.
        if dynamicHeadwords.isEmpty {
            if let t0 = tokens(rawName).first { dynamicHeadwords.append(t0) }
            else { dynamicHeadwords.append(normalize(rawName)) }
        }
        
        finalQueries = finalQueries.dedupCaseInsensitive()
        let bans = Array(bannedSet)
        let requiredHeads = Array(Set(dynamicHeadwords.map { $0.lowercased() })).filter { !$0.isEmpty }
        
        emitLog("  • queries(final): \(finalQueries)", onLog: onLog)
        emitLog("  • banned(final): \(bans)", onLog: onLog)
        emitLog("  • requiredHeadwords(final): \(requiredHeads)", onLog: onLog)
        emitLog("ingredientSmartQueries – END", onLog: onLog)
        return (finalQueries, bans, requiredHeads)
    }
    
    
    @MainActor
    private func generateUSDANameVariants(
        for rawName: String,
        recipeName: String,
        recipeContext: RecipeContextProfile,
        otherIngredients: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> (queries: [String], banned: [String]) {
        let ctx = otherIngredients.isEmpty ? "n/a" : otherIngredients.joined(separator: ", ")
        let instructions = Instructions {
                """
                You generate USDA-like naming variants for a single ingredient. Keep outputs short and generic. No brands.
                - preferForms: realistic names that match USDA catalog entries for the concept.
                - avoidForms: clearly wrong or composite foods that would pollute search results; include dairy/fats like butter if unrelated to the headword; avoid brand-like or flavored variants; avoid 'with X' composites.
                - cookedKeywords/rawKeywords: one-word tokens that indicate state; these help the caller filter according to preparation context.
                """
        }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
            INGREDIENT: "\(rawName)"
            RECIPE: "\(recipeName)"
            OTHER INGREDIENTS: \(ctx)
            PREPARATION CONTEXT: \(recipeContext.isColdOrNoCook ? "no-cook/cold dish; prefer raw forms" : "cooking allowed; raw/cooked both acceptable")
            TASK: Produce USDA-style naming variants for this single ingredient.
            """
        do {
            emitLog("  • LLM#Variants prompt → \(prompt)", onLog: onLog)
            try Task.checkCancellation()
            
            let v = try await session.respond(
                to: prompt,
                generating: AINamingVariants.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content
            logJSON(v, label: "  • LLM#Variants output (AINamingVariants)", onLog: onLog)
            try Task.checkCancellation()
            
            var queries: [String] = []
            queries.append(rawName)
            try Task.checkCancellation()
            
            if !v.canonicalName.isEmpty { queries.append(v.canonicalName) }
            queries.append(contentsOf: v.preferForms.prefix(6))
            if recipeContext.disallowCookedForms {
                queries.append(contentsOf: v.rawKeywords.prefix(3))
            }
            try Task.checkCancellation()
            
            var banned: [String] = []
            banned.append(contentsOf: v.avoidForms.prefix(8))
            if recipeContext.disallowCookedForms {
                banned.append(contentsOf: v.cookedKeywords.prefix(8))
            }
            try Task.checkCancellation()
            
            // Always exclude infant/pet foods
            banned.append(contentsOf: ["baby food","infant","toddler","gerber","stage 1","stage 2","stage 3","dog food","cat food","pet food"])
            
            // Dedupe + sanitize
            queries = queries.uniqued(caseInsensitive: true).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let bannedFinal = Array(Set(banned.map { $0.lowercased() }))
            try Task.checkCancellation()
            
            emitLog("  • Variants → queries(final): \(queries)", onLog: onLog)
            emitLog("  • Variants → banned(final): \(bannedFinal)", onLog: onLog)
            return (queries, bannedFinal)
        } catch {
            // --- НАЧАЛО НА ПРОМЯНАТА ---
            // Ако грешката е прекратяване на задача, я препредаваме нагоре, вместо да я "поглъщаме".
            if error is CancellationError {
                throw error
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
            
            emitLog("  • Variants generation failed (\(error.localizedDescription)) → fallback to heuristic.", onLog: onLog)
            
            // ПРОМЯНА: Използваме FoodItem.makeTokens вместо SmartFoodSearch.tokenize
            let toks = FoodItem.makeTokens(from: rawName)
            
            var queries = [rawName]
            if let head = toks.first { queries.append(head) }
            queries = queries.uniqued(caseInsensitive: true)
            let banned = ["baby food","infant","toddler","gerber","stage 1","stage 2","stage 3","dog food","cat food","pet food"]
            return (queries, banned)
        }
    }
    
    @MainActor
    private func chooseBestIngredientCandidate(
        originalName: String,
        candidateNames: [String],
        recipeName: String,
        recipeContext: RecipeContextProfile,
        otherIngredients: [String],
        requiredHeadwords: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> Int {
        emitLog("chooseBestIngredientCandidate(\"\(originalName)\") – START", onLog: onLog)
        
        if candidateNames.isEmpty {
            emitLog("  • No candidates at all. Returning -1.", onLog: onLog)
            return -1
        }
        try Task.checkCancellation()
        
        let heads = requiredHeadwords.isEmpty
        ? (tokens(originalName).first.map { [$0] } ?? [normalize(originalName)])
        : requiredHeadwords
        let headStr = heads.joined(separator: " | ")
        let forbidden = (compositeIndicators + sweetFlavoringIndicators + withJoiners).joined(separator: ", ")
        try Task.checkCancellation()
        
        let otherBlock = otherIngredients.isEmpty ? "OTHER INGREDIENTS: (none)" :
        """
        OTHER INGREDIENTS:
        - \(otherIngredients.joined(separator: "\n- "))
        """
        
        let choosePrompt = """
        You must pick ONE candidate index for the target ingredient OR -1 if none is valid.
        
        RECIPE: \(recipeName)
        TARGET: "\(originalName)"
        PREPARATION: \(recipeContext.isColdOrNoCook ? "no-cook/cold; avoid cooked variants" : "cooking allowed")
        HEADWORDS (must appear in the chosen name): \(headStr)
        FORBIDDEN INDICATORS (reject if present): \(forbidden)
        \(otherBlock)
        
        CANDIDATES:
        \(candidateNames.enumerated().map { "\($0). \($1)" }.joined(separator: "\n"))
        
        HARD RULES (MANDATORY):
        1) The chosen name MUST contain at least one HEADWORD literally (substring match is ok).
        2) Reject composite dishes (dip/spread/salad/casserole/burger/bread/wrap/sandwich/marinade/seasoning/mix/blend/sauce/dressing/syrup/jam/jelly/cereal/bar).
        3) If dish is savory (garlic/cucumber/onion/dill/pepper/salt in other ingredients), REJECT sweetened/flavored/fruit variants.
        4) If PREPARATION says no-cook/cold, REJECT cooked forms (cooked/boiled/grilled/roasted/fried/baked/steamed).
        5) If no candidate satisfies ALL rules, you MUST answer { "bestIndex": -1, "reason": "..." }.
        
        Respond ONLY as JSON: { "bestIndex": <int>, "reason": "<short>" }.
        """
        
        let chooseSession = LanguageModelSession()
        emitLog("  • LLM#Pick prompt with \(candidateNames.count) candidate(s).", onLog: onLog)
        try Task.checkCancellation()
        
        let res = try await chooseSession.respond(
            to: choosePrompt,
            generating: AIIngredientCandidatePick.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(sampling: .greedy)
        )
        try Task.checkCancellation()
        
        logJSON(res.content, label: "  • LLM#Pick output (AIIngredientCandidatePick)", onLog: onLog)
        
        let pick = res.content.bestIndex
        guard candidateNames.indices.contains(pick) else {
            emitLog("  • LLM returned invalid index → -1", onLog: onLog)
            return -1
        }
        
        let chosenName = candidateNames[pick]
        try Task.checkCancellation()
        
        // Пост-валидация с динамичните headwords (твърди гардове).
        let valid = passesStrictGuards(
            originalName: originalName,
            candidateName: chosenName,
            recipeContext: recipeContext,
            otherIngredients: otherIngredients,
            requiredHeadwords: heads
        )
        
        if !valid {
            emitLog("  • Post-validate failed for '\(chosenName)' → returning -1", onLog: onLog)
            return -1
        }
        
        emitLog("chooseBestIngredientCandidate – END (index \(pick))", onLog: onLog)
        return pick
    }
    
    
    @MainActor
    private func createMissingIngredient(
        named name: String,
        grams: Double,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> FoodItemCandidate? {
        emitLog("createMissingIngredient('\(name)', \(grams) g) – START", onLog: onLog)
        
        // Use one ModelContext for the entire operation to ensure consistency.
        let ctx = ModelContext(self.container)
        guard !AyurvedaRecommendationGate.nameIsExcluded(name, context: ctx) else {
            emitLog("🚫 AyurvedaGate: dropped excluded generated ingredient '\(name)'", onLog: onLog)
            return nil
        }
        let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
        try Task.checkCancellation()
        
        // Check 1: By original name (fast path)
        let exactPredicate = #Predicate<FoodItem> { $0.name == name }
        if let existing = try ctx.fetch(FetchDescriptor(predicate: exactPredicate)).first(where: { !excludedFoodIds.contains($0.id) }) {
            emitLog("  • Found existing by exact name: '\(existing.name)' [\(existing.id)] – reuse", onLog: onLog)
            return FoodItemCandidate(id: existing.id, name: existing.name)
        }
        try Task.checkCancellation()
        
        // Generate DTO via AI (slow operation, outside transaction) + RETRY
        emitLog("  • Generating details via AIFoodDetailGenerator… (input name='\(name)')", onLog: onLog)
        let gen = AIFoodDetailGenerator(container: ctx.container)
        try Task.checkCancellation()
        
        // Option A (throwing retry - stops on failure after N attempts):
        var dto = try await gen.generateDetailsRetrying(
            for: name,
            ctx: ctx,
            onLog: onLog,
            attempts: 5,        // adjust as needed
            baseBackoffMs: 700  // starting backoff
        )
        try Task.checkCancellation()
        
        // Option B (silent - returns nil after N attempts):
        /*
         guard var dto = await gen.generateDetailsOrNil(
         for: name,
         ctx: ctx,
         onLog: onLog,
         attempts: 5,
         baseBackoffMs: 700
         ) else {
         emitLog("  • ❌ AIFoodDetailGenerator failed after retries → returning nil", onLog: onLog)
         return nil
         }
         */
        
        let finalName = dto.name.isEmpty ? name : dto.name
        dto.name = finalName
        emitLog("  • AIFoodDetailGenerator output name: '\(finalName)'", onLog: onLog)
        guard !AyurvedaRecommendationGate.nameIsExcluded(finalName, context: ctx) else {
            emitLog("🚫 AyurvedaGate: dropped excluded generated ingredient '\(finalName)'", onLog: onLog)
            return nil
        }
        try Task.checkCancellation()
        
        // Check 2: By final name from DTO
        let finalPredicate = #Predicate<FoodItem> { $0.name == finalName }
        if let existing = try ctx.fetch(FetchDescriptor(predicate: finalPredicate)).first(where: { !excludedFoodIds.contains($0.id) }) {
            emitLog("  • Found existing by final name after DTO generation: '\(existing.name)' [\(existing.id)] – reuse", onLog: onLog)
            return FoodItemCandidate(id: existing.id, name: existing.name)
        }
        try Task.checkCancellation()
        
        // --- ATOMIC CREATION BLOCK ---
        do {
            var idDescriptor = FetchDescriptor<FoodItem>()
            idDescriptor.sortBy = [SortDescriptor(\.id, order: .reverse)]
            idDescriptor.fetchLimit = 1
            let maxId = (try ctx.fetch(idDescriptor).first?.id) ?? 0
            dto.id = maxId + 1
            try Task.checkCancellation()
            
            let model = dto.model()
            model.isUserAdded = false
            model.isRecipe = false
            try Task.checkCancellation()
            
            ctx.insert(model)
            try ctx.save()
            
            SearchIndexStore.shared.updateItem(model, context: ctx)
            emitLog("  • New FoodItem persisted: '\(model.name)' [ID: \(model.id)]", onLog: onLog)
            emitLog("createMissingIngredient – END (created)", onLog: onLog)
            return FoodItemCandidate(id: model.id, name: model.name)
        } catch {
            emitLog("  • ❌ Failed to save new FoodItem: \(error.localizedDescription)", onLog: onLog)
            
            if let existing = try ctx.fetch(FetchDescriptor(predicate: finalPredicate)).first(where: { !excludedFoodIds.contains($0.id) }) {
                emitLog("  • Found existing item after save failed (likely race condition): '\(existing.name)' [\(existing.id)] – reuse", onLog: onLog)
                return FoodItemCandidate(id: existing.id, name: existing.name)
            }
            
            emitLog("createMissingIngredient – END (error)", onLog: onLog)
            throw error
        }
    }
    
    
    @MainActor
    private func persistFoodItemDTO(
        _ dto: FoodItemDTO,
        in ctx: ModelContext,
        onLog: (@Sendable (String) -> Void)?
    ) throws -> FoodItem {
        
        // If the DTO comes with an empty name, there's nothing to materialize here.
        precondition(!dto.name.isEmpty, "persistFoodItemDTO: DTO.name must not be empty")
        try Task.checkCancellation()
        
        // 0) Duplicate by exact name
        do {
            let exact = FetchDescriptor<FoodItem>(
                predicate: #Predicate<FoodItem> { $0.name == dto.name }
            )
            if let existing = try ctx.fetch(exact).first {
                emitLog("  • Reusing existing FoodItem by name '\(existing.name)' [\(existing.id)]", onLog: onLog)
                return existing
            }
        } catch {
            emitLog("  • Exact-name check failed inside persistFoodItemDTO: \(error.localizedDescription)", onLog: onLog)
        }
        try Task.checkCancellation()
        
        // 1) Build model from DTO
        let model = dto.model()
        model.isUserAdded = false
        model.isRecipe   = false
        try Task.checkCancellation()
        
        // 2) Insert (without save - the caller will save)
        ctx.insert(model)
        emitLog("  • Materialized & inserted FoodItem from DTO: '\(model.name)' [\(model.id)]", onLog: onLog)
        
        return model
    }
    
    @MainActor
    private func regenerateDescriptionToMatchIngredients(
        original: String,
        recipeName: String,
        finalIngredients: [(name: String, grams: Double)],
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> String {
        emitLog("regenerateDescriptionToMatchIngredients – START", onLog: onLog)
        
        let ingLines = finalIngredients.map { "- \($0.name) – \(Int($0.grams)) g" }.joined(separator: "\n")
        emitLog("  • Final ingredient list for reconciliation:\n\(ingLines)", onLog: onLog)
        
        let prompt = """
        You must output a single plain-text string with:
        1) One line: "Summary: <1–2 short sentences>"
        2) A blank line
        3) Numbered steps in the exact format:
           1) ...
           2) ...
           3) ...
           (5–12 steps total, imperative, no Markdown)
        
        TASK:
        Regenerate ONLY the description for the recipe "\(recipeName)" so that it aligns with the EXACT ingredient list below.
        Do not list ingredients in the steps verbatim as a list; just ensure the steps naturally use them.
        Keep the style concise and realistic for a home cook.
        
        FINAL INGREDIENTS:
        \(ingLines)
        
        PREVIOUS DESCRIPTION (for style reference only, do not copy blindly):
        \(original)
        """
        try Task.checkCancellation()
        
        let session = LanguageModelSession(instructions: Instructions { "Return ONLY the description string in the exact required format." })
        emitLog("  • LLM#DescReconcile prompt prepared.", onLog: onLog)
        try Task.checkCancellation()
        let res = try await session.respond(
            to: prompt,
            generating: String.self,
            includeSchemaInPrompt: false,
            options: GenerationOptions(sampling: .greedy)
        )
        try Task.checkCancellation()
        
        let preview = String(res.content.prefix(200))
        emitLog("  • LLM#DescReconcile output (preview 200 chars): \(preview)\(res.content.count > 200 ? "…" : "")", onLog: onLog)
        emitLog("regenerateDescriptionToMatchIngredients – END", onLog: onLog)
        return res.content
    }
    
    @MainActor
    private func fetchFoodCandidates(
        for ids: [PersistentIdentifier],
        onLog: (@Sendable (String) -> Void)?
    ) -> [FoodItemCandidate] {
        emitLog("fetchFoodCandidates – START (\(ids.count) id(s))", onLog: nil)
        guard !ids.isEmpty else {
            emitLog("fetchFoodCandidates – END (empty)", onLog: nil)
            return []
        }
        let ctx = ModelContext(self.container)
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.persistentModelID) })
        let fetched = (try? ctx.fetch(descriptor)) ?? []
        let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
        let allowed = fetched.filter { !excludedFoodIds.contains($0.id) }
        emitLog("🚫 AyurvedaGate: AyurvedaGate active, \(fetched.count - allowed.count) candidates filtered", onLog: onLog)
        let result = allowed.map { FoodItemCandidate(id: $0.id, name: $0.name) }
        emitLog("fetchFoodCandidates – END (fetched \(result.count))", onLog: nil)
        return result
    }
    
    @MainActor
    private func fetchFoodItem(by id: PersistentIdentifier) -> FoodItem? {
        emitLog("fetchFoodItem(by:) – id=\(id)", onLog: nil)
        let ctx = ModelContext(self.container)
        let model = ctx.model(for: id) as? FoodItem
        if let model {
            emitLog("fetchFoodItem – hit: \(model.name) [\(model.id)]", onLog: nil)
        } else {
            emitLog("fetchFoodItem – miss", onLog: nil)
        }
        return model
    }
    
    // --- HELPERS (без хардкод синоними) ---
    
    private func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func tokens(_ s: String) -> [String] {
        FoodItem.makeTokens(from: s.lowercased())
    }
    
    // Индикатори за композитни изделия и овкусени варианти (не са синоними).
    private let compositeIndicators: [String] = [
        "dip","spread","salad","casserole","burger","bread","wrap","sandwich","marinade",
        "seasoning","mix","blend","sauce","dressing","syrup","jam","jelly","cereal","bar"
    ]
    
    private let sweetFlavoringIndicators: [String] = [
        "sweet","sweetened","flavored","flavoured","vanilla","chocolate","strawberry","blueberry",
        "raspberry","peach","banana","honey","maple","caramel","berry","fruit","fruity"
    ]
    
    private let withJoiners: [String] = [" with ", " and ", " in ", " w/ "]
    
    // Строга пост-валидация на кандидат спрямо ДИНАМИЧНИ headwords.
    private func passesStrictGuards(
        originalName: String,
        candidateName: String,
        recipeContext: RecipeContextProfile,
        otherIngredients: [String],
        requiredHeadwords: [String]
    ) -> Bool {
        let name = normalize(candidateName)
        
        // 1) Задължително присъствие на поне един динамичен headword.
        let reqHeads = requiredHeadwords.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !reqHeads.isEmpty else { return false }
        guard reqHeads.contains(where: { name.contains($0) }) else { return false }
        
        // 2) Отхвърляне на композити/изделия.
        if compositeIndicators.contains(where: { name.contains($0) }) { return false }
        
        // 3) Савъри контекст → забрана за сладки/овкусени варианти.
        let savoryHints = otherIngredients.joined(separator: " ").lowercased()
        let looksSavory = ["garlic","cucumber","onion","dill","pepper","salt"]
            .contains(where: { savoryHints.contains($0) })
        if looksSavory {
            if sweetFlavoringIndicators.contains(where: { name.contains($0) }) { return false }
        }
        
        // 4) При no-cook/cold → режем готвени ключови думи.
        if recipeContext.disallowCookedForms {
            let cooked = ["cooked","boiled","grilled","roasted","fried","baked","steamed"]
            if cooked.contains(where: { name.contains($0) }) { return false }
        }
        
        // 5) Избягваме конструкции, подсказващи композит.
        if withJoiners.contains(where: { name.contains($0) }) { return false }
        
        return true
    }
    
}
