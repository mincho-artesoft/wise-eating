import SwiftData
import Foundation
import FoundationModels

@available(iOS 26.0, *)
public final class USDAWeeklyMealPlanner: Sendable {
    private let globalTaskManager = GlobalTaskManager.shared
    private let container: ModelContainer
    public init(container: ModelContainer) {
        self.container = container
    }
    
    private func splitIntoAtomicPrompts(_ prompts: [String]) -> [String] {
        var atoms: [String] = []
        let seps = CharacterSet.newlines.union(CharacterSet(charactersIn: ";|"))
        for p in prompts {
            for raw in p.components(separatedBy: seps) {
                var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                line = line.replacingOccurrences(of: #"^\s*([\-–—•\*]+)\s*"#,
                                                 with: "",
                                                 options: .regularExpression)
                if line.hasSuffix(".") { line.removeLast() }
                if !line.isEmpty { atoms.append(line) }
            }
        }
        var seen = Set<String>()
        return atoms.filter { seen.insert($0.lowercased()).inserted }
    }
    
    
    @MainActor
    private func aiSplitIntoAtomicPrompts(
        _ prompts: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        guard !prompts.isEmpty else { return [] }
        
        @MainActor
        func aiSplitSinglePrompt(_ single: String) async -> [String] {
            let instructions = Instructions {
                """
                You split messy, compound diet requests into atomic, standalone directives.
                RULES:
                - Each unit MUST express exactly one requirement (frequency, inclusion/exclusion, replacement, meal-time).
                - Preserve negations (“no”, “avoid”, “without”) and numeric patterns (“once every 3 days”, “daily”).
                - Map time-of-day to meals: morning→Breakfast, noon→Lunch, evening→Dinner.
                - If a line has multiple 'and/;/-/•' parts, split into multiple units.
                - Keep wording concise; do not add new constraints; keep the user's intent.
                - Return at most 16 units.
                """
            }
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            Split the following user text into atomic directives:
            
            \(single)
            """
            
            do {
                try Task.checkCancellation()
                let resp = try await session.respond(
                    to: prompt,
                    generating: AIAtomicPromptsResponse.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(sampling: .greedy)
                )
                try Task.checkCancellation()
                var atoms = resp.content.directives
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                atoms = atoms.map { s in
                    var x = s
                    if x.hasSuffix(".") { x.removeLast() }
                    if let first = x.first { x.replaceSubrange(x.startIndex...x.startIndex, with: String(first).uppercased()) }
                    return x
                }
                try Task.checkCancellation()
                var seen = Set<String>()
                atoms = atoms.filter { seen.insert($0.lowercased()).inserted }
                atoms = Array(atoms.prefix(16))
                try Task.checkCancellation()
                
                return filterMetaDirectives(atoms)
            } catch {
                onLog?("    - ⚠️ Atomic split via AI failed for prompt: '\(single)'. Falling back to heuristic.")
                return filterMetaDirectives(splitIntoAtomicPrompts([single]))
            }
        }
        
        var all: [String] = []
        for raw in prompts {
            let perPrompt = await aiSplitSinglePrompt(raw)
            all.append(contentsOf: perPrompt)
        }
        var seen = Set<String>()
        let deduped = all.filter { seen.insert($0.lowercased()).inserted }
        let finalAtoms = Array(deduped.prefix(16))
        if !finalAtoms.isEmpty { onLog?("   -> Atomic prompts (AI): \(finalAtoms)") }
        return finalAtoms
    }
    
    @MainActor
    private func aiExtractRequestedFoods(from prompts: [String], onLog: (@Sendable (String) -> Void)?) async -> (included: [String], excluded: [String]) {
        
        guard !prompts.isEmpty else { return (included: [], excluded: []) }
        
        let session = LanguageModelSession(instructions: Instructions {
            """
            You extract and categorize food names from user prompts.
            - From the user's prompts, create two lists:
              1. `includedFoods`: Concrete food names explicitly asked to be INCLUDED.
              2. `excludedFoods`: Concrete food names explicitly asked to be EXCLUDED or AVOIDED.
            - Ignore frequencies, meals, numbers, and nutrition goals for this task.
            - Normalize all names to simple USDA-like forms without portions.
            """
        })
        
        let prompt = """
        Extract both included and excluded food names the user mentioned.
        
        PROMPTS:
        \(prompts.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(to: prompt, generating: AIFoodExtractionResponse.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy))
            try Task.checkCancellation()
            var seenIncluded = Set<String>()
            let cleanedIncluded: [String] = resp.content.includedFoods.compactMap { raw in
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let key = name.lowercased()
                guard !seenIncluded.contains(key) else { return nil }
                seenIncluded.insert(key)
                return name
            }
            try Task.checkCancellation()
            var seenExcluded = Set<String>()
            let cleanedExcluded: [String] = resp.content.excludedFoods.compactMap { raw in
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let key = name.lowercased()
                guard !seenExcluded.contains(key) else { return nil }
                seenExcluded.insert(key)
                return name
            }
            try Task.checkCancellation()
            let includedLower = Set(cleanedIncluded.map { $0.lowercased() })
            let prunedExcluded: [String] = cleanedExcluded.filter { !includedLower.contains($0.lowercased()) }
            let dropped = cleanedExcluded.filter { includedLower.contains($0.lowercased()) }
            
            try Task.checkCancellation()
            
            if !cleanedIncluded.isEmpty { onLog?("  -> Requested foods to include: \(cleanedIncluded)") }
            if !prunedExcluded.isEmpty { onLog?("  -> Requested foods to exclude: \(prunedExcluded)") }
            if !dropped.isEmpty {
                onLog?("  -> Note: removed from global excludes due to simultaneous inclusion: \(dropped)")
            }
            
            try Task.checkCancellation()
            
            return (included: cleanedIncluded, excluded: prunedExcluded)
            
        } catch {
            onLog?("    - ⚠️ Food-name extraction failed: \(error.localizedDescription). Falling back to heuristic.")
        }
        
        let includedResults = [String]()
        let excludedResults = [String]()
        
        if !includedResults.isEmpty { onLog?("  -> Included foods (heuristic): \(includedResults)") }
        if !excludedResults.isEmpty { onLog?("  -> Excluded foods (heuristic): \(excludedResults)") }
        return (included: includedResults, excluded: excludedResults)
    }
    
    @MainActor
    private func aiFixAtomsAndFoods(
        originalPrompts: [String],
        atoms: [String],
        included: [String],
        excluded: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> (directives: [String], included: [String], excluded: [String]) {
        guard !originalPrompts.isEmpty else { return (atoms, included, excluded) }
        
        let instructions = Instructions {
            """
            You reconcile a list of atomic diet directives with the user's raw prompts and the extracted food lists.
            GOALS:
            - Preserve the user's explicit foods EXACTLY as written in the raw prompts unless they are clear plural or casing variants. Do NOT replace or substitute them with different foods.
            - If a food is negated in any raw prompt (using terms like 'no', 'avoid', or 'without'), ensure it appears in the excludedFoods list unless it is also explicitly required for specific meals or days.
            - If a food is explicitly requested positively in any raw prompt, ensure it appears in includedFoods.
            - Correct any mistaken substitutions in `directives` so they align with the actual foods from the raw prompts.
            - Keep directives concise and limited to a maximum of 16 total. Omit meta or vague items.
            OUTPUT STRICTLY the JSON schema fields: fixedDirectives, includedFoods, excludedFoods. No extra text.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        RAW_PROMPTS:\n\(originalPrompts.map { "- \($0)" }.joined(separator: "\n"))
        
        CURRENT_ATOMIC_DIRECTIVES:\n\(atoms.map { "- \($0)" }.joined(separator: "\n"))
        
        CURRENT_INCLUDED_FOODS:\n\(included)
        CURRENT_EXCLUDED_FOODS:\n\(excluded)
        """
        
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(
                to: prompt,
                generating: AIAtomsAndFoodsFixResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            try Task.checkCancellation()
            var dirs = resp.content.fixedDirectives
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            dirs = dirs.map { s in
                var x = s
                if x.hasSuffix(".") { x.removeLast() }
                if let first = x.first { x.replaceSubrange(x.startIndex...x.startIndex, with: String(first).uppercased()) }
                return x
            }
            try Task.checkCancellation()
            var seen = Set<String>()
            dirs = dirs.filter { seen.insert($0.lowercased()).inserted }
            dirs = Array(dirs.prefix(16))
            try Task.checkCancellation()
            func cleanFoods(_ arr: [String]) -> [String] {
                var out: [String] = []
                var s = Set<String>()
                for r in arr {
                    let n = r.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !n.isEmpty else { continue }
                    let k = n.lowercased()
                    if s.insert(k).inserted { out.append(n) }
                }
                return out
            }
            try Task.checkCancellation()
            let inc = cleanFoods(resp.content.includedFoods)
            let exc0 = cleanFoods(resp.content.excludedFoods)
            let incSet = Set(inc.map { $0.lowercased() })
            let exc = exc0.filter { !incSet.contains($0.lowercased()) }
            try Task.checkCancellation()
            if !dirs.isEmpty { onLog?("   -> Atomic prompts (fixed): \(dirs)") }
            if !inc.isEmpty { onLog?("   -> Included foods (fixed): \(inc)") }
            if !exc.isEmpty { onLog?("   -> Excluded foods (fixed): \(exc)") }
            
            return (dirs, inc, exc)
        } catch {
            onLog?("    - ⚠️ Post-fix AI pass failed: \(error.localizedDescription). Keeping previous atoms/foods.")
            return (atoms, included, excluded)
        }
    }
    
    private func emitLog(_ message: String, onLog: (@Sendable (String) -> Void)?) {
        onLog?(message)
    }
    
    private func makeDietMap(in ctx: ModelContext) throws -> [String: Diet] {
        let persistedDiets = try ctx.fetch(FetchDescriptor<Diet>())
        return Dictionary(uniqueKeysWithValues: persistedDiets.map {
            ($0.name._normKey, $0)
        })
    }
    
    @MainActor
    private func createMissingIngredient(
        named name: String,
        grams: Double,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> FoodItemCandidate? {
        emitLog("createMissingIngredient('\(name)', \(grams) g) – START", onLog: onLog)
        
        let ctx = ModelContext(self.container)
        
        let exactPredicate = #Predicate<FoodItem> { $0.name == name }
        if let existing = try ctx.fetch(FetchDescriptor(predicate: exactPredicate)).first {
            emitLog("  • Found existing by exact name: '\(existing.name)' [\(existing.id)] – reuse", onLog: onLog)
            return FoodItemCandidate(id: existing.id, name: existing.name)
        }
        
        emitLog("  • Generating details via AIFoodDetailGenerator… (input name='\(name)')", onLog: onLog)
        let gen = AIFoodDetailGenerator(container: ctx.container)
        
        var dto = try await gen.generateDetailsRetrying(
            for: name,
            ctx: ctx,
            onLog: onLog,
            attempts: 5,
            baseBackoffMs: 700
        )
        
        let finalName = dto.name.isEmpty ? name : dto.name
        dto.name = finalName
        emitLog("  • AIFoodDetailGenerator output name: '\(finalName)'", onLog: onLog)
        
        let finalPredicate = #Predicate<FoodItem> { $0.name == finalName }
        if let existing = try ctx.fetch(FetchDescriptor(predicate: finalPredicate)).first {
            emitLog("  • Found existing by final name after DTO generation: '\(existing.name)' [\(existing.id)] – reuse", onLog: onLog)
            return FoodItemCandidate(id: existing.id, name: existing.name)
        }
        
        do {
            try Task.checkCancellation()
            var idDescriptor = FetchDescriptor<FoodItem>()
            idDescriptor.sortBy = [SortDescriptor(\.id, order: .reverse)]
            idDescriptor.fetchLimit = 1
            let maxId = (try ctx.fetch(idDescriptor).first?.id) ?? 0
            dto.id = maxId + 1
            try Task.checkCancellation()
            let dietMap = try makeDietMap(in: ctx)
            let model = dto.model(dietMap: dietMap)
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
            
            if let existing = try ctx.fetch(FetchDescriptor(predicate: finalPredicate)).first {
                emitLog("  • Found existing item after save failed (likely race condition): '\(existing.name)' [\(existing.id)] – reuse", onLog: onLog)
                return FoodItemCandidate(id: existing.id, name: existing.name)
            }
            
            emitLog("createMissingIngredient – END (error)", onLog: onLog)
            throw error
        }
    }
    
    
    @MainActor
    private func resolveAndCreateItemsForMeal(
        _ conceptualMeal: ConceptualMeal,
        relevantPrompts: [String],
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async -> [MealPlanPreviewItem] {
        let components = conceptualMeal.components
        guard !components.isEmpty else { return [] }
        
        enum FoodResolutionResult: Sendable {
            case resolved(info: ResolvedFoodInfo, component: ConceptualComponent)
            case unresolved(component: ConceptualComponent)
        }
        
        let resolutionGroupTask = Task<[FoodResolutionResult], Never> {
            await withTaskGroup(of: FoodResolutionResult.self, returning: [FoodResolutionResult].self) { group in
                for component in components {
                    group.addTask { [weak self] in
                        guard let self else { return .unresolved(component: component) }
                        
                        if let resolvedInfo = await self.resolveFoodConcept(
                            smartSearch: smartSearch,
                            conceptName: component.name,
                            mealContext: conceptualMeal,
                            relevantPrompts: relevantPrompts,
                            onLog: onLog
                        ) {
                            return .resolved(info: resolvedInfo, component: component)
                        } else {
                            return .unresolved(component: component)
                        }
                    }
                }
                
                var results: [FoodResolutionResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
        }
        
        await globalTaskManager.addTask(resolutionGroupTask)
        let resolutionResults = await resolutionGroupTask.value
        
        
        var resolvedItems: [MealPlanPreviewItem] = []
        var unresolvedComponents: [ConceptualComponent] = []
        
        let ctx = ModelContext(self.container)
        for result in resolutionResults {
            switch result {
            case .resolved(let info, let component):
                if let foodItem = ctx.model(for: info.persistentID) as? FoodItem {
                    let gramsValue = component.grams > 0 ? component.grams : 100.0
                    let previewItem = MealPlanPreviewItem(
                        name: info.resolvedName,
                        grams: gramsValue,
                        kcal: foodItem.calories(for: gramsValue)
                    )
                    resolvedItems.append(previewItem)
                } else {
                    unresolvedComponents.append(component)
                }
            case .unresolved(let component):
                unresolvedComponents.append(component)
            }
        }
        
        if !unresolvedComponents.isEmpty {
            emitLog("--- Meal '\(conceptualMeal.name)': Starting SEQUENTIAL creation for \(unresolvedComponents.count) missing item(s) ---", onLog: onLog)
            for component in unresolvedComponents {
                do {
                    try Task.checkCancellation()
                    if let newFoodCandidate = try await self.createMissingIngredient(named: component.name, grams: component.grams, onLog: onLog) {
                        let foodID = newFoodCandidate.id
                        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == foodID })
                        if let newlyCreatedItem = (try? ctx.fetch(descriptor))?.first {
                            let gramsValue = component.grams > 0 ? component.grams : 100.0
                            let previewItem = MealPlanPreviewItem(
                                name: newlyCreatedItem.name,
                                grams: gramsValue,
                                kcal: newlyCreatedItem.calories(for: gramsValue)
                            )
                            resolvedItems.append(previewItem)
                            emitLog("   ✅ '\(component.name)' -> CREATED & RESOLVED to '\(newlyCreatedItem.name)'", onLog: onLog)
                        }
                    }
                } catch {
                    emitLog("   - ⚠️ Error during creation of '\(component.name)': \(error.localizedDescription). Skipping.", onLog: onLog)
                }
            }
            emitLog("--- Finished SEQUENTIAL creation ---", onLog: onLog)
        }
        
        return resolvedItems
    }
    
    /**
     * NEW FUNCTION
     * Validates if the generated plan's structure matches the user's request.
     */
    private func isPlanStructureValid(
        plan: AIConceptualPlanResponse,
        expectedDaysAndMeals: [Int: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) -> Bool {
        let planDays = Set(plan.days.map { $0.day })
        let expectedDays = Set(expectedDaysAndMeals.keys)
        
        if planDays != expectedDays {
            onLog?("  - structural validation FAIL: Day mismatch. Expected \(expectedDays.sorted()), got \(planDays.sorted()).")
            return false
        }
        
        for day in plan.days {
            guard let expectedMeals = expectedDaysAndMeals[day.day] else {
                onLog?("  - structural validation FAIL: Day \(day.day) was generated but not requested.")
                return false
            }
            
            let planMeals = day.meals.map { $0.name.lowercased() }
            let expectedMealsLower = expectedMeals.map { $0.lowercased() }
            
            if Set(planMeals) != Set(expectedMealsLower) {
                onLog?("  - structural validation FAIL: Day \(day.day) meal mismatch. Expected \(expectedMeals), got \(day.meals.map { $0.name }).")
                return false
            }
            
            for meal in day.meals {
                if meal.components.isEmpty {
                    onLog?("  - structural validation FAIL: Day \(day.day), Meal '\(meal.name)' has no components.")
                    return false
                }
            }
        }
        
        return true
    }
    
    @MainActor
    private func saveProgress(
        jobID: PersistentIdentifier,
        progress: MealPlanGenerationProgress,
        onLog: (@Sendable (String) -> Void)?
    ) async {
        // ако задачата е отменена – не записваме
        if Task.isCancelled {
            emitLog("⏹️ [Progress] Task cancelled; skip meal plan progress save.", onLog: onLog)
            return
        }

        do {
            // fresh контекст за писане (избягва сблъсък с UI/mainContext)
            let writeCtx = ModelContext(self.container)

            // важно: ре-фетч по persistentModelID (НЕ context.model(for:))
            let fd = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.persistentModelID == jobID })
            guard let job = try writeCtx.fetch(fd).first else {
                emitLog("⚠️ [Progress] Could not find job with ID \(jobID) to save progress (deleted?).", onLog: onLog)
                return
            }

            // последна проверка за отмяна точно преди сетъра
            try Task.checkCancellation()

            let data = try JSONEncoder().encode(progress)
            job.intermediateResultData = data
            try writeCtx.save()

            emitLog("💾 [Progress] Meal plan progress saved.", onLog: onLog)
        } catch is CancellationError {
            emitLog("⏹️ [Progress] Cancelled mid-save; skipping meal plan progress.", onLog: onLog)
        } catch {
            emitLog("❌ [Progress] Failed to save progress: \(error.localizedDescription)", onLog: onLog)
        }
    }

    
    @MainActor
    public func fillPlanDetails(
        jobID: PersistentIdentifier,
        profileID: PersistentIdentifier,
        daysAndMeals: [Int: [String]],
        prompts: [String]?,
        mealTimings: [String: Date]?,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> MealPlanPreview {
        
        // --- START OF CHANGE (2/3): Load or initialize progress ---
        let ctx = ModelContext(self.container)
        guard let job = ctx.model(for: jobID) as? AIGenerationJob else {
            throw NSError(domain: "MealPlannerError", code: 404, userInfo: [NSLocalizedDescriptionKey: "AIGenerationJob not found."])
        }
        
        var progress: MealPlanGenerationProgress
        if let data = job.intermediateResultData, let loadedProgress = try? JSONDecoder().decode(MealPlanGenerationProgress.self, from: data) {
            progress = loadedProgress
            emitLog("🔄 Resuming meal plan generation.", onLog: onLog)
        } else {
            progress = MealPlanGenerationProgress()
            emitLog("  -> No existing progress found. Starting from scratch.", onLog: onLog)
        }
        
        guard let profile = ctx.model(for: profileID) as? Profile else {
            throw NSError(domain: "MealPlannerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile not found."])
        }
        try Task.checkCancellation()
        // --- END OF CHANGE (2/3) ---
        
        let smartSearch = SmartFoodSearch(container: self.container)
        try Task.checkCancellation()
        
        // --- Checkpoint 1: Interpretation ---
        let atomicPrompts: [String]
        var includedFoods: [String]
        let excludedFoods: [String]
        var interpretedPrompts: InterpretedPrompts
        
        if let cached = progress.interpretedPrompts, let atoms = progress.atomicPrompts, let incl = progress.includedFoods, let excl = progress.excludedFoods {
            atomicPrompts = atoms
            includedFoods = incl
            excludedFoods = excl
            interpretedPrompts = cached
            emitLog("  -> ✅ Checkpoint 1: Using cached interpretation results.", onLog: onLog)
        } else {
            let atomicPromptsRaw = await aiSplitIntoAtomicPrompts(prompts ?? [], onLog: onLog)
            try Task.checkCancellation()
            
            emitLog("Atomic prompts (raw) → \(atomicPromptsRaw)", onLog: onLog)
            let (includedFoods0, excludedFoods0) = await aiExtractRequestedFoods(from: atomicPromptsRaw, onLog: onLog)
            try Task.checkCancellation()
            
            let fix = await aiFixAtomsAndFoods(originalPrompts: prompts ?? [], atoms: atomicPromptsRaw, included: includedFoods0, excluded: excludedFoods0, onLog: onLog)
            emitLog("Inputs after aiFixAtomsAndFoods → directives=\(fix.directives), included=\(fix.included), excluded=\(fix.excluded)", onLog: onLog)
            try Task.checkCancellation()
            
            atomicPrompts = fix.directives
            includedFoods = fix.included
            excludedFoods = fix.excluded
            interpretedPrompts = await aiInterpretUserPrompts(prompts: atomicPrompts, includedFoods: includedFoods, excludedFoods: excludedFoods, daysAndMeals: daysAndMeals, smartSearch: smartSearch, onLog: onLog)
            try Task.checkCancellation()
            
            progress.atomicPrompts = atomicPrompts
            progress.includedFoods = includedFoods
            progress.excludedFoods = excludedFoods
            progress.interpretedPrompts = interpretedPrompts
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
            emitLog("  -> ✅ Checkpoint 1: Interpretation complete and saved.", onLog: onLog)
        }
        
        logInterpretedGoals(interpretedPrompts, onLog: onLog)
        try Task.checkCancellation()
        
        // --- Checkpoint 2: Context & Palettes ---
        var contextTags: [(kind: String, tag: String)]
        var foodPalettesByContext: [(kind: String, tag: String, foods: [String], associatedCuisine: String?)]
        
        if let cachedTags = progress.contextTags, let cachedPalettes = progress.foodPalettesByContext {
            contextTags = cachedTags
            foodPalettesByContext = cachedPalettes
            emitLog("  -> ✅ Checkpoint 2: Using cached context tags and palettes.", onLog: onLog)
        } else {
            let (headwords, cuisines) = await aiInferContextTags(structural: interpretedPrompts.structuralRequests, qualitative: interpretedPrompts.qualitativeGoals, included: includedFoods, onLog: onLog)
            try Task.checkCancellation()
            
            contextTags = headwords.map { (kind: "headword", tag: $0) } + cuisines.map { (kind: "cuisine", tag: $0) }
            
            emitLog("Specialize pass — incoming structural=\(interpretedPrompts.structuralRequests) | included=\(includedFoods)", onLog: onLog)
            await specializeStructuralRequestsWithHeadwords(
                profile: profile,
                structuralRequests: &interpretedPrompts.structuralRequests,
                includedFoods: &includedFoods,
                contextTags: &contextTags,
                headwords: headwords,
                cuisines: cuisines,
                onLog: onLog
            )
            try Task.checkCancellation()
            emitLog("Specialize pass — result structural=\(interpretedPrompts.structuralRequests) | included=\(includedFoods) | contextTags=\(contextTags.map{ "\($0.kind):\($0.tag)" })", onLog: onLog)
            
            foodPalettesByContext = []
            for t in contextTags {
                try Task.checkCancellation()
                if t.kind == "cuisine" {
                    let sub = try await aiGenerateFoodPaletteForCuisine(profile: profile, cuisineTag: t.tag, onLog: onLog)
                    if !sub.isEmpty {
                        foodPalettesByContext.append((kind: t.kind, tag: t.tag, foods: Array(sub.shuffled().prefix(25)), associatedCuisine: nil))
                    }
                } else if t.kind == "headword" {
                    let (sub, inferredCuisine) = try await aiGenerateFoodPaletteForHeadword(profile: profile, headword: t.tag, includeHeadword: true, onLog: onLog)
                    if !sub.isEmpty {
                        foodPalettesByContext.append((kind: t.kind, tag: t.tag, foods: Array(sub.shuffled().prefix(25)), associatedCuisine: inferredCuisine))
                    }
                }
            }
            
            progress.contextTags = contextTags
            progress.foodPalettesByContext = foodPalettesByContext
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
            emitLog("  -> ✅ Checkpoint 2: Context and palettes generated and saved.", onLog: onLog)
        }
        
        let hardExcludes = deriveHardExcludes(from: interpretedPrompts.structuralRequests)
        try Task.checkCancellation()
        
        // --- Checkpoint 3: Conceptual Plan ---
        var conceptualPlan: AIConceptualPlanResponse
        
        if let cachedPlan = progress.conceptualPlan {
            conceptualPlan = cachedPlan
            emitLog("  -> ✅ Checkpoint 3: Using cached conceptual plan.", onLog: onLog)
        } else {
            let cuisineTagCSV = contextTags.filter { $0.kind == "cuisine" }.map { $0.tag }.joined(separator: ", ")
            
            var rules = parseMustContainRules(interpretedPrompts.structuralRequests)
            let allPromptText = (atomicPrompts + interpretedPrompts.structuralRequests).joined(separator: " ").lowercased()
            let wantsDifferentTypes = allPromptText.contains("different type") || allPromptText.contains("different kind") || allPromptText.contains("variet")
            var specificVariantPlacements: [String] = []
            
            if wantsDifferentTypes {
                let originalIncluded = includedFoods // Operate on the list before it gets pruned
                for baseFood in originalIncluded {
                    try Task.checkCancellation()
                    
                    let relevantRules = rules.filter { $0.topic.caseInsensitiveCompare(baseFood) == .orderedSame }
                    if relevantRules.isEmpty { continue }
                    
                    let count = relevantRules.count
                    let context = relevantRules.first?.meal ?? "any meal"
                    onLog?("  -> User requested \(count) different types of '\(baseFood)'. Generating variants...")
                    
                    let variantIdeas = await aiGenerateVariantIdeas(for: baseFood, count: count * 2, context: context, onLog: onLog)
                    
                    try Task.checkCancellation()
                    
                    let validatedVariants = await validateAndSelectBestVariants(
                        variantIdeas: variantIdeas,
                        baseFood: baseFood,
                        count: count,
                        smartSearch: smartSearch,
                        onLog: onLog
                    )
                    try Task.checkCancellation()
                    
                    if !validatedVariants.isEmpty {
                        var rulesToRemove = Set<MustContainRule>()
                        for (i, rule) in relevantRules.enumerated() {
                            try Task.checkCancellation()
                            
                            let variant = validatedVariants.indices.contains(i) ? validatedVariants[i] : "\(baseFood) variant \(i+1)"
                            // Add a new, specific structural request
                            let newRuleText = "On Day \(rule.day), the \(rule.meal ?? "any meal") MUST contain exactly: '\(variant)'."
                            specificVariantPlacements.append(newRuleText)
                            rulesToRemove.insert(rule)
                        }
                        // Remove the old generic rules
                        rules.removeAll(where: { rulesToRemove.contains($0) })
                        
                        try Task.checkCancellation()
                        
                        // Also remove the original, generic structural request text to prevent confusion
                        interpretedPrompts.structuralRequests.removeAll(where: { request in
                            rulesToRemove.contains(where: { rule in
                                request.localizedCaseInsensitiveContains("day \(rule.day)") &&
                                request.localizedCaseInsensitiveContains(rule.topic) &&
                                (rule.meal == nil || request.localizedCaseInsensitiveContains(rule.meal!))
                            })
                        })
                        try Task.checkCancellation()
                        
                        includedFoods.removeAll { $0.caseInsensitiveCompare(baseFood) == .orderedSame }
                        if let headwordIndex = contextTags.firstIndex(where: { $0.kind == "headword" && $0.tag.caseInsensitiveCompare(baseFood) == .orderedSame }) {
                            contextTags.remove(at: headwordIndex)
                            onLog?("   -> Removed generic headword '\(baseFood)' as it has been replaced by specific variants.")
                        }
                    }
                }
            }
            
            let structurallyPlacedFoods = Set(rules.map { $0.topic.lowercased() })
            let genericIncludedFoods = includedFoods.filter { !structurallyPlacedFoods.contains($0.lowercased()) }
            
            var retryCount = 0
            let maxRetries = 2
            while true {
                try Task.checkCancellation()
                conceptualPlan = try await generateFullPlanWithAI(
                    profile: profile, daysAndMeals: daysAndMeals, interpretedPrompts: interpretedPrompts,
                    foodPalettesByContext: foodPalettesByContext, includedFoods: genericIncludedFoods,
                    specificVariantPlacements: specificVariantPlacements, excludedFoods: hardExcludes,
                    cuisineTag: cuisineTagCSV, onLog: onLog
                )
                try Task.checkCancellation()
                
                conceptualPlan = normalizeMealsToRequestedOrder(plan: conceptualPlan, daysAndMeals: daysAndMeals, onLog: onLog)
                try Task.checkCancellation()
                
                if isPlanStructureValid(plan: conceptualPlan, expectedDaysAndMeals: daysAndMeals, onLog: onLog) {
                    onLog?("✅ Initial plan structure is valid after normalization.")
                    break
                } else if retryCount < maxRetries {
                    retryCount += 1
                    onLog?("⚠️ Plan structure is invalid. Retrying generation (\(retryCount)/\(maxRetries))...")
                } else {
                    onLog?("⚠️ Plan structure remains invalid after \(maxRetries + 1) attempts. Proceeding with potentially flawed structure.")
                    break
                }
            }
            
            conceptualPlan = await polishConceptualPlan(
                plan: conceptualPlan, profile: profile, daysAndMeals: daysAndMeals, rules: rules,
                excludedFoods: hardExcludes, foodPalette: foodPalettesByContext.flatMap { $0.foods },
                smartSearch: smartSearch, onLog: onLog
            )
            try Task.checkCancellation()
            
            progress.conceptualPlan = conceptualPlan
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
            emitLog("  -> ✅ Checkpoint 4: Conceptual plan generated, polished, and saved.", onLog: onLog)
        }
        
        debugDumpConceptualPlan(conceptualPlan, title: "FINAL CONCEPTUAL PLAN", onLog: onLog)
        try Task.checkCancellation()
        
        // --- Checkpoint 5: Resolution ---
        if progress.resolvedItems == nil {
            progress.resolvedItems = [:]
        }
        
        var previewDays: [MealPlanPreviewDay] = []
        for conceptualDay in conceptualPlan.days.sorted(by: { $0.day < $1.day }) {
            try Task.checkCancellation()
            
            let adjustedDay = await validateAndAdjustDayForGoals(day: conceptualDay, goals: interpretedPrompts.numericalGoals, onLog: onLog)
            var previewMeals: [MealPlanPreviewMeal] = []
            
            for conceptualMeal in adjustedDay.meals {
                try Task.checkCancellation()
                if Task.isCancelled { break }
                
                let mealName = conceptualMeal.name
                let finalItems: [MealPlanPreviewItem]
                
                if let cachedItems = progress.resolvedItems?[conceptualDay.day]?[mealName]?.compactMap({ info in
                    let component = conceptualMeal.components.first(where: { $0.name.lowercased() == info.resolvedName.lowercased() || info.resolvedName.lowercased().contains($0.name.lowercased()) })
                    if let food = ctx.model(for: info.persistentID) as? FoodItem {
                        let grams = component?.grams ?? 100.0
                        return MealPlanPreviewItem(name: food.name, grams: grams, kcal: food.calories(for: grams))
                    }
                    return nil
                }) {
                    emitLog("  -> 🔄 Checkpoint 4: Using cached resolved items for Day \(conceptualDay.day) - '\(mealName)'.", onLog: onLog)
                    finalItems = rebalanceMealCalories(items: cachedItems, mealName: mealName, dailyCalTarget: estimatedDailyCalories(for: profile), onLog: onLog)
                } else {
                    let relevantPrompts = interpretedPrompts.structuralRequests.filter { prompt in
                        let lower = prompt.lowercased()
                        let mealKeywords = ["breakfast", "lunch", "dinner", "morning", "noon", "evening"]
                        
                        let hasDaySpecifier = lower.contains("day ")
                        let hasMealSpecifier = mealKeywords.contains { lower.contains($0) }
                        
                        if !hasDaySpecifier && !hasMealSpecifier {
                            return true
                        }
                        if !hasDaySpecifier && hasMealSpecifier {
                            return lower.contains(conceptualMeal.name.lowercased())
                        }
                        if hasDaySpecifier && !hasMealSpecifier {
                            return lower.contains("day \(conceptualDay.day)")
                        }
                        if hasDaySpecifier && hasMealSpecifier {
                            return lower.contains("day \(conceptualDay.day)") && lower.contains(conceptualMeal.name.lowercased())
                        }
                        return false
                        
                    } + interpretedPrompts.qualitativeGoals
                    let resolvedItems = await resolveAndCreateItemsForMeal(conceptualMeal, relevantPrompts: relevantPrompts, smartSearch: smartSearch, onLog: onLog)
                    try Task.checkCancellation()
                    
                    finalItems = rebalanceMealCalories(items: resolvedItems, mealName: conceptualMeal.name, dailyCalTarget: estimatedDailyCalories(for: profile), onLog: onLog)
                    try Task.checkCancellation()
                    
                    var dayDict = progress.resolvedItems?[conceptualDay.day, default: [:]]
                    dayDict![mealName] = finalItems.map { item in
                        let foodID = (try? ctx.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name == item.name })) )?.first?.persistentModelID
                        return ResolvedFoodInfo(persistentID: foodID!, resolvedName: item.name)
                    }
                    
                    progress.resolvedItems?[conceptualDay.day] = dayDict
                    await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
                    emitLog("  -> ✅ Checkpoint 4: Resolved and saved items for Day \(conceptualDay.day) - '\(mealName)'.", onLog: onLog)
                }
                
                let mealStartTime = mealTimings?.first { $0.key.lowercased() == conceptualMeal.name.lowercased() }?.value
                previewMeals.append(MealPlanPreviewMeal(name: conceptualMeal.name, descriptiveTitle: conceptualMeal.descriptiveTitle, items: finalItems, startTime: mealStartTime))
                try Task.checkCancellation()
            }
            previewDays.append(MealPlanPreviewDay(dayIndex: adjustedDay.day, meals: previewMeals))
            try Task.checkCancellation()
        }
        
        // --- Final Cleanup ---
        emitLog("✅ Final Meal Plan Preview Prepared. Clearing intermediate progress.", onLog: onLog)
        job.intermediateResultData = nil
        try ctx.save()
        
        return MealPlanPreview(startDate: Date(), prompt: conceptualPlan.planName, days: previewDays, minAgeMonths: conceptualPlan.minAgeMonths)
    }
    
    @inline(__always) private func roundTo5(_ x: Double) -> Double { (x / 5.0).rounded() * 5.0 }
    
    private func rebalanceDayCalories(
        meals: [MealPlanPreviewMeal],
        dailyCalTarget: Double,
        onLog: (@Sendable (String) -> Void)?
    ) -> [MealPlanPreviewMeal] {
        guard !meals.isEmpty, dailyCalTarget > 0 else { return meals }
        
        func isCondimentOrSweetener(_ n: String) -> Bool {
            let l = n.lowercased()
            let keys = [
                "honey","sugar","brown sugar","maple","agave","syrup","molasses","jam","jelly","preserves",
                "ketchup","mustard","mayo","mayonnaise","aioli","dressing","sauce","butter","ghee","cream",
                "whipped","coconut sugar","stevia","sweetener"
            ]
            return keys.contains { l.contains($0) }
        }
        func isBeverage(_ n: String) -> Bool {
            let l = n.lowercased(); return ["milk","kefir","yogurt drink","smoothie"].contains { l.contains($0) } && !l.contains("powder")
        }
        func isProtein(_ n: String) -> Bool {
            let keys = ["chicken","turkey","salmon","tuna","fish","shrimp","pork","beef","lamb","egg","eggs","tofu","tempeh","lentil","bean","chickpea"]
            let l = n.lowercased(); return keys.contains { l.contains($0) }
        }
        func isGrain(_ n: String) -> Bool {
            let keys = ["cereal","oat","oatmeal","rice","quinoa","pasta","noodle","bread","toast","couscous","potato"]
            let l = n.lowercased(); return keys.contains { l.contains($0) }
        }
        
        func minGrams(for name: String, current: Double) -> Double {
            let l = name.lowercased()
            if (l.contains("lemon") && (l.contains("wedge") || l.contains("slice"))) { return min(current, 20.0) }
            if isBeverage(name) { return 150.0 }
            if isProtein(name) { return 90.0 }
            if isGrain(name) { return 60.0 }
            return 40.0
        }
        
        func roundTo5(_ x: Double) -> Double { (x / 5.0).rounded() * 5.0 }
        
        let allTuples: [(mIdx: Int, iIdx: Int, item: MealPlanPreviewItem)] = meals.enumerated().flatMap { (mIdx, meal) in
            meal.items.enumerated().map { (iIdx, it) in (mIdx, iIdx, it) }
        }
        let initialTotal = allTuples.reduce(0.0) { $0 + $1.item.kcal }
        let cap = max(700.0, dailyCalTarget * 1.05)
        guard initialTotal > cap else { return meals }
        
        let locked = Set(allTuples.compactMap { (mIdx, iIdx, it) in
            (isCondimentOrSweetener(it.name) || it.grams < 50.0) ? "\(mIdx)#\(iIdx)" : nil
        })
        
        var adjustable: [(mIdx: Int, iIdx: Int, perGram: Double, grams: Double, name: String, kcal: Double)] = []
        var lockedCal = 0.0
        for (mIdx, iIdx, it) in allTuples {
            if locked.contains("\(mIdx)#\(iIdx)") {
                lockedCal += it.kcal
            } else {
                let perGram = it.grams > 0 ? (it.kcal / it.grams) : 0
                adjustable.append((mIdx, iIdx, perGram, it.grams, it.name, it.kcal))
            }
        }
        
        let currentAdjKcal = adjustable.reduce(0.0) { $0 + $1.kcal }
        let targetAdjKcal = max(0.0, cap - lockedCal)
        guard currentAdjKcal > 0 else {
            onLog?("⚖️ Day-level rebalance: nothing adjustable. Keeping meals as-is.")
            return meals
        }
        
        let scale = targetAdjKcal / currentAdjKcal
        var out = meals
        for a in adjustable {
            var newGrams = roundTo5(a.grams * scale)
            let minG = minGrams(for: a.name, current: a.grams)
            if newGrams < minG { newGrams = roundTo5(minG) }
            let newKcal = a.perGram * newGrams
            var items = out[a.mIdx].items
            items[a.iIdx] = MealPlanPreviewItem(name: items[a.iIdx].name, grams: newGrams, kcal: newKcal)
            out[a.mIdx] = MealPlanPreviewMeal(
                name: out[a.mIdx].name,
                descriptiveTitle: out[a.mIdx].descriptiveTitle,
                items: items,
                startTime: out[a.mIdx].startTime
            )
        }
        
        let newTotal = out.flatMap { $0.items }.reduce(0.0) { $0 + $1.kcal }
        onLog?("⚖️ Day-level rebalance: \(Int(initialTotal)) → \(Int(newTotal)) kcal (cap \(Int(cap))).")
        return out
    }
    
    @available(iOS 26.0, *)
    private func aiInferContextTags(
        structural: [String],
        qualitative: [String],
        included: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> (headwords: [String], cuisines: [String]) {
        let validCuisineTags = [
            "any", "American", "British & Irish", "French", "Italian", "Spanish & Portuguese (Iberian)",
            "Central & Eastern European", "Scandinavian / Nordic", "Mediterranean / Greek",
            "Middle Eastern / Levantine", "North African / Maghreb", "Sub-Saharan African",
            "Indian Subcontinent", "Chinese", "Japanese", "Korean", "Southeast Asian",
            "Central Asian", "Latin American / Caribbean", "Oceanian / Australasian",
            "Fusion / Global Contemporary", "ayurvedic", "vegetarian", "vegan", "gluten-free"
        ]
        
        let instructions = Instructions {
            """
            You are a highly precise culinary theme and keyword extractor. Your job is to identify and classify the most dominant culinary concepts from user requests.
            
            You will classify each theme into one of two `kind`s:
            - `kind: "cuisine"`: For a broad culinary tradition, dietary system, or style of eating.
            - `kind: "headword"`: For a specific, named dish or a single primary ingredient that is a central focus.
            
            **CRITICAL RULES FOR EXTRACTION AND CLASSIFICATION:**
            
            1.  **Preserve Detail**: If a culinary style has a specific sub-type, modifier, or focus (e.g., a diet for a specific condition, a regional variant), you MUST use the full, composite term in the tag. Do not discard these important details.
            2.  **Classification Logic**:
                - A specific, named dish or a single primary ingredient is **always** a `headword`.
                - A broad culinary tradition, dietary system, or style of eating is a `cuisine`.
            3.  **Mapping Unlisted Cuisines**: If a user's request implies a cuisine that is NOT on the `VALID CUISINE TAGS` list provided in the prompt, your task is twofold:
                - First, identify the most relevant broader category from that list for a `cuisine` tag.
                - Second, extract any specific named dishes from the user's request as `headword` tags.
            4.  **Focus on Dominant Themes**: Return only the 1-3 most important and relevant themes from the request. Do not extract every single food item mentioned.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        
        func truncateList(_ arr: [String], maxCount: Int, maxLen: Int) -> [String] {
            return arr.prefix(maxCount).map { $0.count > maxLen ? String($0.prefix(maxLen)) : $0 }
        }
        
        let structuralSlim = truncateList(structural, maxCount: 8, maxLen: 120)
        let qualitativeSlim = truncateList(qualitative, maxCount: 4, maxLen: 80)
        let includedSlim = truncateList(included, maxCount: 12, maxLen: 40)
        
        let promptSummary = """
        Analyze the following user requests to identify the main culinary themes according to the rules.
        VALID CUISINE TAGS for categorization reference: \(validCuisineTags.joined(separator: ", "))
        
        STRUCTURAL REQUESTS:
        \(structuralSlim.joined(separator: " | "))
        
        QUALITATIVE GOALS:
        \(qualitativeSlim.joined(separator: " | "))
        
        INCLUDED FOODS:
        \(includedSlim.joined(separator: " | "))
        """
        
        do {
            try Task.checkCancellation()
            
            let result = try await session.respond(
                to: promptSummary,
                generating: AIContextTagsResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            
            try Task.checkCancellation()
            
            var out: [(kind: String, tag: String)] = []
            var seen = Set<String>()
            
            for t in result.content.tags {
                try Task.checkCancellation()
                
                let kind = t.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                var tag = t.tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                guard !kind.isEmpty, !tag.isEmpty else { continue }
                
                tag = tag.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                
                if seen.insert("\(kind)#\(tag)").inserted {
                    out.append((kind, tag))
                }
            }
            
            let cuisines = out.filter { $0.kind == "cuisine" }
            let headwords = out.filter { $0.kind == "headword" }
            let finalTags = Array((cuisines + headwords).prefix(3))
            
            if !finalTags.isEmpty {
                onLog?("  -> Context tags inferred: " + finalTags.map { "\($0.kind):\($0.tag)" }.joined(separator: ", "))
                let heads = finalTags.filter { $0.kind == "headword" }.map { $0.tag }
                let cuisinesOnly = finalTags.filter { $0.kind == "cuisine" }.map { $0.tag }
                return (headwords: heads, cuisines: cuisinesOnly.isEmpty ? ["any"] : cuisinesOnly)
            } else {
                onLog?("  -> Context inference returned no valid tags; defaulting to cuisine:any")
                return (headwords: [], cuisines: ["any"])
            }
            
        } catch {
            onLog?("  -> AI context inference failed: \(error.localizedDescription). Using cuisine:any.")
            return (headwords: [], cuisines: ["any"])
        }
    }
    
    @available(iOS 26.0, *)
    private func aiGenerateVariantsOnly(for headword: String,
                                        onLog: (@Sendable (String) -> Void)?) async throws -> [String] {
        let session = LanguageModelSession(instructions: Instructions {
            """
            You generate distinct, popular variants for a given headword (dish name).
            RULES:
            - Return 4–7 standalone variant names.
            - Each name must be for a distinct, authentic, and recognized variant.
            - **CRITICAL**: Do NOT invent hybrid names by combining the headword with generic dish types unless they are real, well-known dishes. Focus on variations in filling, shape, or traditional preparation.
            - Do NOT include the original headword itself.
            - Keep names USDA-like and plausible.
            - Do not add portions or explanations.
            """
        })
        let prompt = "HEADWORD: \"\(headword)\"\nGenerate popular variants only."
        try Task.checkCancellation()
        
        let resp = try await session.respond(
            to: prompt,
            generating: AIHeadwordVariantsResponse.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 1024)
        )
        try Task.checkCancellation()
        
        var seen = Set<String>()
        onLog?("[Variants] Headword='\(headword)' → raw=\(resp.content.foodExamples)")
        return resp.content.foodExamples.compactMap { raw in
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { return nil }
            return seen.insert(v.lowercased()).inserted ? v : nil
        }
    }
    
    @available(iOS 26.0, *)
    private func specializeStructuralRequestsWithHeadwords(
        profile: Profile,
        structuralRequests: inout [String],
        includedFoods: inout [String],
        contextTags: inout [(kind: String, tag: String)],
        headwords: [String],
        cuisines: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async {
        emitLog("[Specialize] Heads=\(headwords) | cuisines=\(cuisines)", onLog: onLog)
        guard !headwords.isEmpty else { return }
        
        struct HeadwordAssets { let variants: [String]; let complements: [String] }
        var assets: [String: HeadwordAssets] = [:]
        
        for h in headwords {
            do {
                try Task.checkCancellation()
                
                let (foods, _) = try await aiGenerateFoodPaletteForHeadword(
                    profile: profile,
                    headword: h,
                    includeHeadword: false,
                    onLog: onLog
                )
                try Task.checkCancellation()
                
                let vars = try await aiGenerateVariantsOnly(for: h, onLog: onLog)
                try Task.checkCancellation()
                
                assets[h.lowercased()] = HeadwordAssets(variants: vars, complements: foods)
                try Task.checkCancellation()
                
                emitLog("[Specialize] Headword '\(h)' → variants=\(vars.count), complements=\(foods.count)", onLog: onLog)
            } catch {
                onLog?("  -> ⚠️ Could not prefetch complements/variants for headword '\(h)': \(error.localizedDescription)")
            }
        }
        guard !assets.isEmpty else { return }
        
        var cuisineAdds: [String] = []
        for c in cuisines {
            do {
                try Task.checkCancellation()
                let examples = try await aiGenerateFoodPaletteForCuisine(profile: profile, cuisineTag: c, onLog: onLog)
                try Task.checkCancellation()
                cuisineAdds.append(contentsOf: examples)
            } catch {
                onLog?("  -> ⚠️ Could not generate cuisine palette for '\(c)': \(error.localizedDescription)")
            }
        }
        if !cuisineAdds.isEmpty {
            var seen = Set(includedFoods.map { $0.lowercased() })
            for n in cuisineAdds { if seen.insert(n.lowercased()).inserted { includedFoods.append(n) } }
            emitLog("[Specialize] Enriched included foods with cuisineAdds (\(cuisineAdds.count))", onLog: onLog)
        }
        
        let pattern = #"^\s*On Day\s+(\d+),\s+include\s+(.+?)\s+at\s+(Breakfast|Lunch|Dinner)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        
        func chooseCombo(from arr: [String], avoiding set: Set<String>, count: Int) -> [String] {
            var picks: [String] = []
            var seen = set
            for n in arr.shuffled() {
                let k = n.lowercased()
                if seen.contains(k) { continue }
                seen.insert(k)
                picks.append(n)
                if picks.count == count { break }
            }
            return picks
        }
        
        var newRequests: [String] = []
        for sr in structuralRequests {
            let range = NSRange(sr.startIndex..<sr.endIndex, in: sr)
            if let m = regex.firstMatch(in: sr, options: [], range: range), m.numberOfRanges >= 4,
               let dayR = Range(m.range(at: 1), in: sr),
               let topicR = Range(m.range(at: 2), in: sr),
               let mealR = Range(m.range(at: 3), in: sr) {
                let day = String(sr[dayR])
                let topicRaw = String(sr[topicR]).trimmingCharacters(in: .whitespaces)
                let meal = String(sr[mealR])
                let key = topicRaw.lowercased()
                if let asset = assets[key] {
                    // NOTE: This logic is a fallback; the 'wantsDifferentTypes' flow is more robust for variety.
                    // This picks a random variant to avoid always using the same one.
                    let variant = asset.variants.randomElement() ?? topicRaw
                    let combo = chooseCombo(from: asset.complements, avoiding: [key, variant.lowercased()], count: 6)
                    let comboQuoted = combo.map { "\"\($0)\"" }.joined(separator: ", ")
                    let rewritten = "On Day \(day), include \(topicRaw) at \(meal) combined with some of \(comboQuoted)"
                    newRequests.append(rewritten)
                    onLog?("  -> Specialised: '\(sr)' → '\(rewritten)'")
                } else {
                    newRequests.append(sr)
                }
            } else {
                newRequests.append(sr)
            }
        }
        structuralRequests = newRequests
    }
    
    @available(iOS 26.0, *)
    private func aiGenerateFoodPaletteForCuisine(
        profile: Profile,
        cuisineTag: String,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> [String] {
        let session = LanguageModelSession(instructions: Instructions {
            """
            You generate culturally consistent food examples for a given cuisine/dietary system.
            - Input: a single lowercase cuisine tag (may be composite).
            - Output: USDA-like item names suitable for that cuisine/system.
            - Keep names standalone (no portions), realistic, varied.
            - Do not fabricate hybrid names by prefixing the tag to generic nouns.
            - No explanations; return only the schema.
            """
        })
        
        let prompt = """
        PROFILE:
        - Age months: \(profile.ageInMonths)
        
        CUISINE TAG: "\(cuisineTag)"
        Return foodExamples.
        """
        onLog?("Cuisine prompt: \(prompt)")
        try Task.checkCancellation()
        
        let resp = try await session.respond(
            to: prompt,
            generating: AIFoodPaletteResponse.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 2048)
        )
        try Task.checkCancellation()
        
        var seen = Set<String>()
        let out = resp.content.foodExamples.compactMap { n -> String? in
            let v = n.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { return nil }
            let key = v.lowercased()
            return seen.insert(key).inserted ? v : nil
        }
        try Task.checkCancellation()
        
        if !out.isEmpty { onLog?("  -> Palette(\(cuisineTag)) • \(out.count) items: \(out)") }
        return out
    }
    
    @available(iOS 26.0, *)
    private func aiGenerateFoodPaletteForHeadword(
        profile: Profile,
        headword: String,
        includeHeadword: Bool = false,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> (foods: [String], inferredCuisine: String) {
        let complementaryFoodSession = LanguageModelSession(instructions: Instructions {
            """
            You are a culinary expert specializing in traditional food pairings. Your task is to generate a list of items that would be served **alongside the HEADWORD to create a complete, authentic, and balanced meal**.
            
            **CRITICAL RULES:**
            1.  **Infer Cuisine:** First, you MUST infer the single, most specific, dominant cuisine for the HEADWORD.
            2.  **Generate a MEAL, not just a list:** The items you generate must be complementary. They should form a cohesive meal experience when eaten with the HEADWORD.
            3.  **Create Variety:** The list MUST include a mix of item types, such as:
                *   **Beverages**.
                *   **Light Sides**.
                *   **Condiments/Dairy**.
                *   Maybe a light soup if appropriate for the cuisine.
            4.  **Avoid Redundancy:** DO NOT suggest items that are nutritionally similar or redundant. For example, if the HEADWORD is a pastry, DO NOT suggest another heavy, starchy side. Prioritize freshness and contrast.
            5.  **Authenticity:** Items must be standalone food names, not raw ingredients. The pairings must be traditional for the inferred cuisine.
            6.  **Exclusions:** The HEADWORD itself MUST NOT be in the generated list.
            7.  **Output:** Return only the required schema containing the inferred cuisine and the list of 16-25 food items.
            """
        })
        
        let complementaryFoodPrompt = """
        PROFILE:
        - Age months: \(profile.ageInMonths)
        HEADWORD: "\(headword)"
        
        Return complementary items for this headword and the single cuisine you infer it belongs to.
        """
        onLog?("Complementary food prompt: \(complementaryFoodPrompt)")
        try Task.checkCancellation()
        
        let complementaryFoodResp = try await complementaryFoodSession.respond(
            to: complementaryFoodPrompt,
            generating: AIHeadwordPaletteResponse.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 2048)
        )
        try Task.checkCancellation()
        
        let headLower = headword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        try Task.checkCancellation()
        
        var out = complementaryFoodResp.content.foodExamples.compactMap { n -> String? in
            let v = n.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty, v.lowercased() != headLower else { return nil }
            return seen.insert(v.lowercased()).inserted ? v : nil
        }
        try Task.checkCancellation()
        
        if includeHeadword {
            out.insert(headword, at: 0)
            seen.insert(headLower)
            
            onLog?("Starting session to generate variants for headword: \(headword)")
            let variantsSession = LanguageModelSession(instructions: Instructions {
                """
                You are a culinary expert and food historian. Your task is to generate a list of popular and diverse variations of a given food item (the headword).
                
                These variations should be specific and distinct. They can be regional versions, variations with different fillings or ingredients, or different preparation styles.
                
                OUTPUT RULES:
                - Return 4-7 standalone item names.
                - **CRITICAL**: Do NOT invent hybrid names by combining the headword with generic dish types unless they are real, well-known dishes. Focus on variations in filling, shape, or traditional preparation.
                - Do NOT include the original headword itself in the results.
                - The items must be plausible USDA-like names.
                - Return only the schema with the food examples. The 'inferredCuisine' field can be the cuisine of the headword.
                """
            })
            
            let variantsPrompt = "HEADWORD: \"\(headword)\"\n\nGenerate popular variants for this headword."
            onLog?("Variants prompt: \(variantsPrompt)")
            
            do {
                try Task.checkCancellation()
                
                let variantsResp = try await variantsSession.respond(
                    to: variantsPrompt,
                    generating: AIHeadwordVariantsResponse.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 2048)
                )
                try Task.checkCancellation()
                
                let variants = variantsResp.content.foodExamples.compactMap { n -> String? in
                    let v = n.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !v.isEmpty else { return nil }
                    return seen.insert(v.lowercased()).inserted ? v : nil
                }
                try Task.checkCancellation()
                
                out.append(contentsOf: variants)
                onLog?("  -> Added \(variants.count) variants.")
                
            } catch {
                onLog?("Could not generate variants for headword '\(headword)': \(error.localizedDescription)")
            }
        }
        
        onLog?("[HeadwordPalette] headword='\(headword)' → items=\(out.count)")
        
        let inferredCuisine = complementaryFoodResp.content.inferredCuisine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        onLog?("  -> Palette(headword:\(headword)) • \(out.count) items (inferred cuisine='\(inferredCuisine)'): \(out)")
        
        return (out, inferredCuisine)
    }
    
    private func rebalanceMealCalories(
        items: [MealPlanPreviewItem],
        mealName: String,
        dailyCalTarget: Double,
        onLog: (@Sendable (String) -> Void)?
    ) -> [MealPlanPreviewItem] {
        guard !items.isEmpty, dailyCalTarget > 0 else { return items }
        
        let lowerName = mealName.lowercased()
        let split: [String: Double] = ["breakfast": 0.25, "lunch": 0.35, "dinner": 0.40]
        let ratio: Double = {
            if let r = split[lowerName] { return r }
            if lowerName.contains("breakfast") { return split["breakfast"]! }
            if lowerName.contains("lunch") { return split["lunch"]! }
            if lowerName.contains("dinner") { return split["dinner"]! }
            return 0.33
        }()
        
        func isCondimentOrSweetener(_ n: String) -> Bool {
            let l = n.lowercased()
            let keys = [
                "honey","sugar","brown sugar","maple","agave","syrup","molasses","jam","jelly","preserves",
                "ketchup","mustard","mayo","mayonnaise","aioli","dressing","sauce","butter","ghee","cream",
                "whipped","coconut sugar","stevia","sweetener"
            ]
            return keys.contains { l.contains($0) }
        }
        func isBeverage(_ n: String) -> Bool {
            let l = n.lowercased(); return ["milk","kefir","yogurt drink","smoothie"].contains { l.contains($0) } && !l.contains("powder")
        }
        func isProtein(_ n: String) -> Bool {
            let keys = ["chicken","turkey","salmon","tuna","fish","shrimp","pork","beef","lamb","egg","eggs","tofu","tempeh","lentil","bean","chickpea"]
            let l = n.lowercased(); return keys.contains { l.contains($0) }
        }
        func isGrain(_ n: String) -> Bool {
            let keys = ["cereal","oat","oatmeal","rice","quinoa","pasta","noodle","bread","toast","couscous","potato"]
            let l = n.lowercased(); return keys.contains { l.contains($0) }
        }
        func minGrams(for name: String, current: Double) -> Double {
            let l = name.lowercased()
            if (l.contains("lemon") && (l.contains("wedge") || l.contains("slice"))) { return min(current, 20.0) }
            if isBeverage(name) { return 150.0 }
            if isProtein(name) { return 90.0 }
            if isGrain(name) { return 60.0 }
            return 40.0
        }
        
        let initialTotal = items.reduce(0) { $0 + $1.kcal }
        let cap = max(300.0, dailyCalTarget * ratio * 1.05)
        guard initialTotal > cap else { return items }
        
        var mainItems = items.filter { !isCondimentOrSweetener($0.name) }
        if mainItems.count != items.count {
            let dropped = items.count - mainItems.count
            onLog?("⚖️ Removed \(dropped) condiment/sweetener item(s) before scaling \(mealName).")
        }
        
        var total = mainItems.reduce(0) { $0 + $1.kcal }
        if total <= cap { return mainItems }
        
        let lockThreshold = 50.0
        let lockedIdxs = Array(mainItems.enumerated().compactMap { (idx, it) in it.grams < lockThreshold ? idx : nil })
        let adjustableIdxs = Array(mainItems.indices.filter { !lockedIdxs.contains($0) })
        
        guard !adjustableIdxs.isEmpty else {
            let newTotal = mainItems.reduce(0) { $0 + $1.kcal }
            onLog?("⚖️ Calorie rebalance for \(mealName): \(Int(initialTotal)) → \(Int(newTotal)) kcal (cap \(Int(cap))).")
            return mainItems
        }
        
        let lockedCal = lockedIdxs.reduce(0.0) { $0 + mainItems[$1].kcal }
        let currentAdjKcal = adjustableIdxs.reduce(0.0) { $0 + mainItems[$1].kcal }
        let targetAdjKcal = max(0.0, cap - lockedCal)
        
        guard currentAdjKcal > 0 else {
            let newTotal = mainItems.reduce(0) { $0 + $1.kcal }
            onLog?("⚖️ Calorie rebalance for \(mealName): \(Int(initialTotal)) → \(Int(newTotal)) kcal (cap \(Int(cap))).")
            return mainItems
        }
        
        let scale = targetAdjKcal / currentAdjKcal
        
        var adjusted = mainItems
        for i in adjustableIdxs {
            let item = adjusted[i]
            let perGram = item.grams > 0 ? (item.kcal / item.grams) : 0
            var newGrams = roundTo5(item.grams * scale)
            let minG = minGrams(for: item.name, current: item.grams)
            if newGrams < minG { newGrams = roundTo5(minG) }
            let newKcal = perGram * newGrams
            adjusted[i] = MealPlanPreviewItem(name: item.name, grams: newGrams, kcal: newKcal)
        }
        
        let newTotal = adjusted.reduce(0) { $0 + $1.kcal }
        onLog?("⚖️ Calorie rebalance for \(mealName): \(Int(initialTotal)) → \(Int(newTotal)) kcal (cap \(Int(cap))).")
        return adjusted
    }
    
    public func savePlan(from preview: MealPlanPreview, for profileID: PersistentIdentifier, onLog: (@Sendable (String) -> Void)?) async throws -> MealPlan {
        let ctx = ModelContext(self.container)
        guard let profile = ctx.model(for: profileID) as? Profile else {
            throw NSError(domain: "MealPlannerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile not found."])
        }
        let newPlan = MealPlan(name: "AI Plan \(Date().formatted(date: .numeric, time: .omitted))", profile: profile)
        var planDays: [MealPlanDay] = []
        for previewDay in preview.days {
            try Task.checkCancellation()
            let day = MealPlanDay(dayIndex: previewDay.dayIndex)
            var planMeals: [MealPlanMeal] = []
            for previewMeal in previewDay.meals {
                try Task.checkCancellation()
                let meal = MealPlanMeal(mealName: previewMeal.name)
                meal.descriptiveAIName = previewMeal.descriptiveTitle
                var entries: [MealPlanEntry] = []
                for previewItem in previewMeal.items {
                    let itemName = previewItem.name
                    let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate<FoodItem> { item in
                        item.name == itemName && !item.isUserAdded
                    })
                    if let foodItem = (try? ctx.fetch(descriptor))?.first {
                        let newEntry = MealPlanEntry(food: foodItem, grams: previewItem.grams, meal: meal)
                        entries.append(newEntry)
                    }
                }
                meal.entries = entries
                planMeals.append(meal)
            }
            day.meals = planMeals
            planDays.append(day)
        }
        newPlan.days = planDays
        ctx.insert(newPlan)
        try ctx.save()
        onLog?("✅ Successfully saved MealPlan from preview.")
        return newPlan
    }
    
    @MainActor
    private func makePreviewItemSendably(
        component: ConceptualComponent,
        mealContext: ConceptualMeal,
        relevantPrompts: [String],
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async -> MealPlanPreviewItem? {
        let resolvedInfo = await self.resolveFoodConcept(
            smartSearch: smartSearch,
            conceptName: component.name,
            mealContext: mealContext,
            relevantPrompts: relevantPrompts,
            onLog: onLog
        )
        
        guard let info = resolvedInfo else {
            onLog?("    - ⚠️ No match for '\(component.name)'. Skipping.")
            return nil
        }
        
        let ctx = ModelContext(self.container)
        guard let food = ctx.model(for: info.persistentID) as? FoodItem else {
            onLog?("    - ⚠️ Could not materialize FoodItem with ID \(info.persistentID) for '\(component.name)'. Skipping.")
            return nil
        }
        
        let gramsValue = component.grams > 0 ? component.grams : 100.0
        return MealPlanPreviewItem(
            name: info.resolvedName,
            grams: gramsValue,
            kcal: food.calories(for: gramsValue)
        )
    }
    
    
    @MainActor
    private func aiInterpretUserPrompts(
        prompts: [String],
        includedFoods: [String],
        excludedFoods: [String],
        daysAndMeals: [Int: [String]],
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async -> InterpretedPrompts {
        guard !prompts.isEmpty else { return InterpretedPrompts() }
        onLog?("  -> Interpreting user prompts with AI one-by-one...")
        
        var interpreted = InterpretedPrompts()
        
        for prompt in prompts {
            let session = LanguageModelSession(instructions: Instructions {
                """
                           CRITICAL RULES
                           1) Choose exactly ONE category that best fits the prompt.
                           2) Prioritize numericalGoal or frequencyRequest when applicable. Otherwise use structuralRequest; use qualitativeGoal only if nothing else fits.
                           3) frequencyRequest rules:
                              - "daily"  -> n must be 0.
                              - "per_n_days" -> n is an integer number of days (e.g., every 2 days => n=2).
                              - "once"   -> n must be 0.
                              - Only set "meal" when the prompt clearly mentions a specific meal (breakfast/lunch/dinner or synonyms). Otherwise set "meal" to "any".
                           4) Map time-of-day synonyms to meals:
                              - morning/breakfast/for breakfast => "Breakfast"
                              - noon/lunchtime/for lunch        => "Lunch"
                              - evening/dinnertime/for dinner   => "Dinner"
                           5) If the prompt mentions specific days (e.g., “on Day 1”, “on Monday”, “weekends”), prefer structuralRequest and encode the constraint in natural language (do NOT invent new JSON fields).
                           6) If the prompt uses negation (“no”, “avoid”, “without”, “exclude”), use structuralRequest that begins with “Exclude …”.
                
                           EXAMPLES (General)
                           - "I want to have no more than 50 grams of fats per day"
                             => { "numericalGoal": { "nutrient": "fat", "constraint": "lessThan", "value": 50 } }
                           - "add a dessert to every lunch"
                             => { "structuralRequest": "Add a dessert to every lunch" }
                           - "I would like to eat foods rich in iron"
                             => { "qualitativeGoal": "Prioritize foods rich in iron" }
                           - "twice a week have salmon for dinner"
                             => { "frequencyRequest": { "topic": "salmon", "frequency": "per_n_days", "n": 3, "meal": "Dinner" } }
                           - "every other day eat yogurt in the morning"
                             => { "frequencyRequest": { "topic": "yogurt", "frequency": "per_n_days", "n": 2, "meal": "Breakfast" } }
                           - "no beef on weekends"
                             => { "structuralRequest": "Exclude beef on weekends" }
                           - "No alcohol consumption"
                             => { "structuralRequest": "Exclude alcohol on all days" }
                           - "avoid tuna except on Mondays"
                             => { "structuralRequest": "Exclude tuna on all days except Monday" }
                           - "replace white bread with whole grain bread"
                             => { "structuralRequest": "Replace white bread with whole grain bread" }
                           - "only chicken for dinner on Day 1"
                             => { "structuralRequest": "On Day 1, include only chicken at Dinner" }
                           - "skip pork at lunch"
                             => { "structuralRequest": "Exclude pork at Lunch" }
                           - "limit bacon to at most once every 3 days"
                             => { "frequencyRequest": { "topic": "bacon", "frequency": "per_n_days", "n": 3, "meal": "any" } }
                           - "have eggs once"
                             => { "frequencyRequest": { "topic": "eggs", "frequency": "once", "n": 0, "meal": "any" } }
                           - "I want low sodium overall"
                             => { "qualitativeGoal": "Prefer low sodium choices" }
                """
            })
            
            let promptForAI = """
            You are an expert prompt analyzer. Analyze ONLY the SINGLE user prompt below and return an object that fits ONE (and only one) of these categories:
            
            - numericalGoal: { "nutrient": "<string>", "constraint": "lessThan|greaterThan|equalTo|range", "value": <number or [min,max]> }
            - frequencyRequest: { "topic": "<food or concept>", "frequency": "daily|per_n_days|once", "n": <int>, "meal": "Breakfast|Lunch|Dinner|any" }
            - structuralRequest: "<short imperative sentence describing what to add/remove/limit/replace, possibly with day/weekday constraints>"
            - qualitativeGoal: "<concise preference if nothing else fits>"
            
            Now, analyze ONLY the following user prompt:
            
            USER PROMPT: "\(prompt)"
            """
            
            do {
                try Task.checkCancellation()
                let response = try await session.respond(to: promptForAI, generating: AIInterpretedPrompt.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy))
                try Task.checkCancellation()
                await processSingleAIInterpretation(
                    response.content,
                    into: &interpreted,
                    daysAndMeals: daysAndMeals,
                    excludedFoods: excludedFoods,
                    smartSearch: smartSearch,
                    onLog: onLog
                )
                try Task.checkCancellation()
            } catch {
                onLog?("    - ⚠️ AI interpretation for prompt '\(prompt)' failed: \(error.localizedDescription). Treating as qualitative goal.")
                interpreted.qualitativeGoals.append(prompt)
            }
        }
        
        return interpreted
    }
    
    private func extractBreakfastRecurringTopic(from text: String) -> String? {
        let l = text.lowercased()
        let patterns = [
            #"(?:eat|include|have)\s+(?:different\s+types\s+of\s+)?([a-zA-Z][a-zA-Z\s]+?)\s+(?:every\s+)?morning"#,
            #"(?:eat|include|have)\s+(?:different\s+types\s+of\s+)?([a-zA-Z][a-zA-Z\s]+?)\s+for\s+breakfast"#
        ]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(l.startIndex..<l.endIndex, in: l)
                if let m = r.firstMatch(in: l, range: range), m.numberOfRanges >= 2,
                   let gr = Range(m.range(at: 1), in: l) {
                    var raw = String(l[gr]).trimmingCharacters(in: .whitespaces)
                    let trailingStops = [" in the", " at the", " the", " in", " at", " for", " of"]
                    for stop in trailingStops {
                        if raw.hasSuffix(stop) {
                            raw.removeSubrange(raw.index(raw.endIndex, offsetBy: -stop.count)..<raw.endIndex)
                            raw = raw.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    var tokens = raw.split(separator: " ").map(String.init)
                    let stopwords: Set<String> = ["in","the","at","for","of"]
                    tokens = tokens.filter { !stopwords.contains($0) }
                    if tokens.isEmpty { continue }
                    let head: String
                    if tokens.count >= 2 {
                        head = tokens.suffix(2).joined(separator: " ")
                    } else {
                        head = tokens.last!
                    }
                    let cleaned = head.capitalized
                    return cleaned
                }
            }
        }
        return nil
    }
    private func isPureSchedulingInstruction(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^(breakfast|lunch|dinner)\s+should\s+occur\s+at\s+\w+"#,
            #"^(have\s+)?(breakfast|lunch|dinner)\s+at\s+\w+"#,
            #"^(schedule|timing|time)\s+for\s+(breakfast|lunch|dinner)\b"#
        ]
        for p in patterns {
            if t.range(of: p, options: .regularExpression) != nil { return true }
        }
        return false
    }
    
    private func processSingleAIInterpretation(
        _ aiResponse: AIInterpretedPrompt,
        into interpreted: inout InterpretedPrompts,
        daysAndMeals: [Int: [String]],
        excludedFoods: [String],
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async {
        func containsExcluded(_ text: String?) -> String? {
            guard let t = text?.lowercased(), !t.isEmpty else { return nil }
            for raw in excludedFoods {
                let ex = raw.lowercased()
                if ex.contains(" ") {
                    if t.contains(ex) { return raw }
                } else {
                    let pattern = "(^|\\W)\(NSRegularExpression.escapedPattern(for: ex))s?(\\W|$)"
                    if t.range(of: pattern, options: .regularExpression) != nil { return raw }
                }
            }
            return nil
        }
        
        func shouldDropMetaInstruction(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t.isEmpty { return false }
            let patterns: [String] = [
                #"^no other (menu|menus|options|cuisines?)$"#,
                #"^no other menu options$"#,
                #"^no other (menu\s+options|cuisine\s+options)$"#,
                #".*\bno other (menu|menus|menu\s+options|cuisine|cuisines|options)\b.*"#,
                #"^do not include other (menu|menus|cuisines?)$"#,
                #"^avoid other (menu|menus|cuisines?)$"#,
                #"^(keep|stick)\s+to\s+(this|the)\s+(menu|cuisine)$"#,
                #"^exclusively\s+(this|the)\s+(menu|cuisine)$"#,
                #"^(only|just)\s+(italian|this|the)\s+(menu|cuisine)$"#,
                #"^only\s+italian(\s+menu)?$"#
            ]
            for p in patterns {
                if t.range(of: p, options: .regularExpression) != nil { return true }
            }
            return false
        }
        
        if let aiNumericalGoal = aiResponse.numericalGoal {
            let nutrientRaw = aiNumericalGoal.nutrient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let constraintRaw = aiNumericalGoal.constraint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            guard let nutrient = MacronutrientType(map: nutrientRaw) else {
                onLog?("  -> Unknown nutrient '\(nutrientRaw)'; skipping numerical goal.")
                return
            }
            
            let constraint: Constraint
            switch constraintRaw {
            case "lessthan", "less_than", "max", "<", "lte", "≤":
                constraint = .lessThan
            case "morethan", "greaterthan", "greater_than", "min", ">", "gte", "≥":
                constraint = .moreThan
            case "equalto", "equals", "equal", "=", "exactly":
                constraint = .exactly
            case "range":
                onLog?("  -> 'range' constraint not supported; treating as qualitative preference instead.")
                interpreted.qualitativeGoals.append("Keep \(nutrient.rawValue) in a moderate range")
                return
            default:
                onLog?("  -> Unknown constraint '\(aiNumericalGoal.constraint)'; defaulting to 'exactly'.")
                constraint = .exactly
            }
            
            interpreted.numericalGoals.append(.init(nutrient: nutrient, constraint: constraint, value: aiNumericalGoal.value))
            return
        }
        
        if var fr = aiResponse.frequencyRequest {
            let mealNormalized: String = {
                if let meal = fr.meal, !meal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return meal }
                return "any"
            }()
            let f = fr.frequency.lowercased()
            let nNormalized: Int = {
                if f == "daily" || f == "once" { return 0 }
                if f == "per_n_days" && fr.n <= 0 { return 1 }
                return fr.n
            }()
            if shouldDropMetaInstruction(fr.topic) {
                onLog?("  -> Skipping meta directive in frequency request: '\(fr.topic)'")
                return
            }
            if let banned = containsExcluded(fr.topic) {
                onLog?("  -> ⚠️ Conflict: frequency request '\(fr.topic)' overlaps with a listed exclusion ('\(banned)'). Preferring the specific frequency for targeted meals and deferring conflict resolution to the global pass.")
            }
            if await !isConcreteFoodName(fr.topic, smartSearch: smartSearch) {
                interpreted.qualitativeGoals.append("Prefer \(fr.topic)")
                return
            }
            
            let sortedDays = daysAndMeals.keys.sorted()
            var daysToInclude: [Int] = []
            switch fr.frequency {
            case "per_n_days":
                guard nNormalized > 0, let first = sortedDays.first else { return }
                var d = first
                while let last = sortedDays.last, d <= last { daysToInclude.append(d); d += nNormalized }
            case "daily": daysToInclude = sortedDays
            case "once": if let first = sortedDays.first { daysToInclude = [first] }
            default: return
            }
            
            for day in daysToInclude {
                let mealTarget = mealNormalized
                if mealTarget.caseInsensitiveCompare("any") != .orderedSame,
                   let dayMeals = daysAndMeals[day],
                   let actual = dayMeals.first(where: { $0.caseInsensitiveCompare(mealTarget) == .orderedSame }) {
                    interpreted.structuralRequests.append("On Day \(day), the \(actual) meal must contain \(fr.topic).")
                } else {
                    interpreted.structuralRequests.append("On Day \(day), one meal must contain \(fr.topic).")
                }
            }
            return
        }
        
        if var sr = aiResponse.structuralRequest {
            if isPureSchedulingInstruction(sr) {
                onLog?("  -> Skipping scheduling directive: '\(sr)'")
                return
            }
            if let topic = extractBreakfastRecurringTopic(from: sr) {
                let sortedDays = daysAndMeals.keys.sorted()
                for day in sortedDays {
                    if let dayMeals = daysAndMeals[day], let _ = dayMeals.first(where: { $0.caseInsensitiveCompare("Breakfast") == .orderedSame }) {
                        interpreted.structuralRequests.append("On Day \(day), include \(topic) at Breakfast")
                    } else {
                        interpreted.structuralRequests.append("On Day \(day), one meal must contain \(topic)")
                    }
                }
                return
            }
            if shouldDropMetaInstruction(sr) {
                onLog?("  -> Skipping meta directive: '\(sr)'")
                return
            }
            if let banned = containsExcluded(sr), sr.lowercased().contains("must contain") {
                sr = "Exclude \(banned) on all days"
                interpreted.structuralRequests.append(sr)
                return
            }
            if let topic = sr.split(separator: " ").last.map(String.init),
               sr.lowercased().contains("must contain"),
               await !isConcreteFoodName(topic, smartSearch: smartSearch) {
                interpreted.qualitativeGoals.append("Prefer \(topic)")
                return
            }
            interpreted.structuralRequests.append(sr)
            return
        }
        
        if let qualitativeGoal = aiResponse.qualitativeGoal {
            if shouldDropMetaInstruction(qualitativeGoal) {
                onLog?("  -> Skipping meta directive: '\(qualitativeGoal)'")
                return
            }
            interpreted.qualitativeGoals.append(qualitativeGoal)
        }
    }
    
    private func isConcreteFoodName(_ name: String, smartSearch: SmartFoodSearch) async -> Bool {
        let tokenizedWords = FoodItem.makeTokens(from: name)
        
        let ids = await smartSearch.searchFoodsAI(
            query: name,
            limit: 3,
            context: "Validating if '\(name)' is a concrete, standalone food item.",
            requiredHeadwords: tokenizedWords
        )
        return !ids.isEmpty
    }
    
    private func deriveHardExcludes(from structural: [String]) -> [String] {
        guard !structural.isEmpty else { return [] }
        var out = Set<String>()
        let patterns: [String] = [
            #"exclude\s+([a-zA-Z][a-zA-Z\s]+?)\s+on\s+all\s+days"#,
            #"exclude\s+([a-zA-Z][a-zA-Z\s]+?)\s+completely"#,
            #"no\s+([a-zA-Z][a-zA-Z\s]+?)\s*(?:\.|$)"#
        ]
        for s in structural {
            let l = s.lowercased()
            for p in patterns {
                if let r = try? NSRegularExpression(pattern: p) {
                    let range = NSRange(l.startIndex..<l.endIndex, in: l)
                    if let m = r.firstMatch(in: l, range: range), m.numberOfRanges >= 2,
                       let nameRange = Range(m.range(at: 1), in: l) {
                        let name = String(l[nameRange]).trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { out.insert(name.capitalized) }
                    }
                }
            }
        }
        return Array(out)
    }
    
    @available(iOS 26.0, *)
    @MainActor
    private func generatePlanViaInterface(
        session: LanguageModelSession,
        prompt: String,
        daysAndMeals: [Int: [String]]
    ) async throws -> AIConceptualPlanResponse {
        let count = max(1, min(7, daysAndMeals.keys.count))
        let greedyOptions = GenerationOptions(sampling: .random(top: 50), temperature: 0.7)
        try Task.checkCancellation()
        switch count {
        case 1:
            let r = try await session.respond(to: prompt, generating: AIConceptualPlanResponse1D.self, includeSchemaInPrompt: false, options: greedyOptions)
            return AIConceptualPlanResponse(planName: r.content.planName, minAgeMonths: r.content.minAgeMonths, days: r.content.days)
        case 2:
            let r = try await session.respond(to: prompt, generating: AIConceptualPlanResponse2D.self, includeSchemaInPrompt: false, options: greedyOptions)
            return AIConceptualPlanResponse(planName: r.content.planName, minAgeMonths: r.content.minAgeMonths, days: r.content.days)
        case 3:
            let r = try await session.respond(to: prompt, generating: AIConceptualPlanResponse3D.self, includeSchemaInPrompt: false, options: greedyOptions)
            return AIConceptualPlanResponse(planName: r.content.planName, minAgeMonths: r.content.minAgeMonths, days: r.content.days)
        case 4:
            let r = try await session.respond(to: prompt, generating: AIConceptualPlanResponse4D.self, includeSchemaInPrompt: false, options: greedyOptions)
            return AIConceptualPlanResponse(planName: r.content.planName, minAgeMonths: r.content.minAgeMonths, days: r.content.days)
        case 5:
            let r = try await session.respond(to: prompt, generating: AIConceptualPlanResponse5D.self, includeSchemaInPrompt: false, options: greedyOptions)
            return AIConceptualPlanResponse(planName: r.content.planName, minAgeMonths: r.content.minAgeMonths, days: r.content.days)
        case 6:
            let r = try await session.respond(to: prompt, generating: AIConceptualPlanResponse6D.self, includeSchemaInPrompt: false, options: greedyOptions)
            return AIConceptualPlanResponse(planName: r.content.planName, minAgeMonths: r.content.minAgeMonths, days: r.content.days)
        default:
            let r = try await session.respond(to: prompt, generating: AIConceptualPlanResponse7D.self, includeSchemaInPrompt: false, options: greedyOptions)
            return AIConceptualPlanResponse(planName: r.content.planName, minAgeMonths: r.content.minAgeMonths, days: r.content.days)
        }
        
    }
    
    private func detectPreferredMealForIncludedFoods(
        structuralRequests: [String],
        daysAndMeals: [Int: [String]]
    ) -> String? {
        guard !structuralRequests.isEmpty else { return nil }
        let requestedMealsCI: [String: String] = {
            var map: [String: String] = [:]
            for arr in daysAndMeals.values {
                for m in arr { map[m.lowercased()] = m }
            }
            return map
        }()
        
        func mapSynonym(_ text: String) -> String? {
            let l = text.lowercased()
            if l.contains("morning")    { return requestedMealsCI["breakfast"] }
            if l.contains("noon") || l.contains("lunchtime") { return requestedMealsCI["lunch"] }
            if l.contains("evening") || l.contains("dinnertime") { return requestedMealsCI["dinner"] }
            return nil
        }
        
        for s in structuralRequests {
            let l = s.lowercased()
            if let hit = requestedMealsCI.first(where: { key, _ in l.contains(key) })?.value { return hit }
            if let syn = mapSynonym(l) { return syn }
        }
        return nil
    }
    
    @MainActor
    private func derivePerMealCuisineFocus(
        structuralRequests: [String],
        daysAndMeals: [Int: [String]],
        defaultTag: String
    ) async -> [String: String] {
        var mealNameSet = Set<String>()
        for meals in daysAndMeals.values { for m in meals { mealNameSet.insert(m) } }
        let mealNames = Array(mealNameSet)
        guard !mealNames.isEmpty else { return [:] }
        
        let structureBlock = mealNames.sorted().joined(separator: ", ")
        let requestsBlock = structuralRequests.isEmpty ? "(none)" : structuralRequests.joined(separator: "\n- ")
        let globalTag = defaultTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "any" : defaultTag.lowercased()
        
        let instructions = Instructions {
            """
            You are a culinary planner. Assign ONE cuisine tag per meal name from the plan structure.
            Rules:
            - Use short, lowercase cuisine tags.
            - If the meal should follow the global tag, use "any".
            - Do NOT invent or duplicate meals. Cover each meal exactly once.
            - Avoid cross-cuisine mixing within a meal.
            - Base decisions on the structural requests and typical cultural associations of named dishes.
            """
        }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        PLAN STRUCTURE — MEAL NAMES:
        \(structureBlock)
        
        GLOBAL CUISINE TAG (fallback if unspecified): \(globalTag)
        
        STRUCTURAL REQUESTS:
        - \(requestsBlock)
        
        TASK:
        Return a mapping from meal name → single cuisine tag as an array per the schema.
        """
        
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(
                to: prompt,
                generating: AIPerMealCuisineFocusResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content
            try Task.checkCancellation()
            var out: [String:String] = [:]
            let valid = Set(mealNames.map { $0.lowercased() })
            for pair in resp.focus {
                try Task.checkCancellation()
                let meal = pair.meal
                let cuisine = pair.cuisine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if valid.contains(meal.lowercased()), !cuisine.isEmpty {
                    out[meal] = cuisine
                }
            }
            try Task.checkCancellation()
            if globalTag != "any" {
                for m in mealNames where out[m] == nil { out[m] = globalTag }
            }
            return out
        } catch {
            var out: [String:String] = [:]
            if globalTag != "any" {
                for m in mealNames { out[m] = globalTag }
            }
            return out
        }
    }
    
    @MainActor
    private func aiGenerateFoodPalette(
        profile: Profile,
        cuisineTag: String,
        includedFoods: [String] = [],
        structuralRequests: [String] = [],
        mustContainRules: [MustContainRule] = [],
        relatedTopics: [String] = [],
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> [String] {
        onLog?("  -> Generating a dynamic food palette...")
        
        var focusSignals = Set<String>()
        for f in includedFoods { let v = f.trimmingCharacters(in: .whitespacesAndNewlines); if !v.isEmpty { focusSignals.insert(v) } }
        for r in mustContainRules { let v = r.topic.trimmingCharacters(in: .whitespacesAndNewlines); if !v.isEmpty { focusSignals.insert(v) } }
        for t in relatedTopics { let v = t.trimmingCharacters(in: .whitespacesAndNewlines); if !v.isEmpty { focusSignals.insert(v) } }
        
        let structuralBlock: String = {
            guard !structuralRequests.isEmpty else { return "(none)" }
            return structuralRequests.prefix(12).joined(separator: "\n- ")
        }()
        
        let userProfileSection = """
        --- USER PROFILE ---
        - Primary Goal: \(profile.goal?.title ?? "General Wellness")
        - Diets: \(profile.diets.isEmpty ? "None" : profile.diets.map { $0.name }.joined(separator: ", "))
        - Allergies (CRITICAL): \(profile.allergens.isEmpty ? "None" : profile.allergens.map { $0.rawValue }.joined(separator: ", "))
        """
        
        let focusTargetsLine = focusSignals.isEmpty ? "(none)" : focusSignals.joined(separator: ", ")
        
        let prompt = """
        \(userProfileSection)
        --- CONTEXT FROM USER PROMPTS (do not invent foods; use only as guidance) ---
        • Cuisine focus (HIGH): \(cuisineTag)
        • Focus targets (from user's own words: included foods, must‑contain, headwords): \(focusTargetsLine)
        • Structural/placement hints (for pairing ideas):
        - \(structuralBlock)
        """
        
        let session = LanguageModelSession(instructions: Instructions {
            """
            TASK:
              You are building a *palette* of concrete foods to feed a meal‑plan generator.
              Use BOTH the cuisine focus and the user's own focus targets to bias the list.
            
              Produce **25–30 distinct, USDA‑like food names** (single items or established dishes) that:
                • Are culturally consistent with the cuisine focus, AND
                • Include a balanced mix of:
                    – **Variants** of any explicitly requested foods only when the prompt implies variety (e.g., "different types/varieties/kinds").
                    – **Compatible pairings** that are commonly served with those foods within the cuisine (e.g., traditional drinks, dairy accompaniments, breads, salads, spreads, soups, or sweets). These must be *stand‑alone items*, not fabricated by prefixing the requested food name.
                • Strictly respect the user's diets/allergies.
            
              STRICT NAMING RULES (very important):
                • Use specific USDA‑style names.
                • **NEVER** fabricate hybrids by prepending or appending the focus target to a generic noun.
                • Only include the target term in the name if it is part of a well-established, authentic dish name in that cuisine.
                • Do **not** output pure spices/herbs/condiments as standalone items. They may appear within a dish name, but not alone.
                • Avoid duplicates and trivial morphological variants.
            """
        })
        try Task.checkCancellation()
        let options = GenerationOptions(sampling: .greedy)
        let response = try await session.respond(
            to: prompt,
            generating: AIFoodPaletteResponse.self,
            includeSchemaInPrompt: true,
            options: options
        )
        try Task.checkCancellation()
        let raw = response.content.foodExamples
        
        let validateSession = LanguageModelSession(instructions: Instructions {
            """
            ROLE: You validate candidate food names for a cuisine palette.
            RULES (critical):
            - Keep only established dishes or discrete foods that could appear as standalone items in a meal plan for the given cuisine.
            - Do NOT include pure spices/herbs/condiments as standalone items.
            - Do NOT include fabricated hybrids that merely attach a focus token (if any) to a generic class (e.g., "<focus> salad/pasta/risotto/bread/soup" etc.).
            - Preserve names exactly as provided; do not rewrite or translate.
            - Return 18–30 items.
            OUTPUT: `foodExamples` as an array of strings using only items from the input list.
            """
        })
        try Task.checkCancellation()
        let validationPrompt = """
        CUISINE: \(cuisineTag)
        FOCUS TARGETS (may be empty): \(focusTargetsLine)
        CANDIDATE ITEMS (choose a clean subset, no rewrites):
        \(raw.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        var validatedList: [String]
        do {
            try Task.checkCancellation()
            let validatedResp = try await validateSession.respond(
                to: validationPrompt,
                generating: AIFoodPaletteResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            try Task.checkCancellation()
            validatedList = validatedResp.content.foodExamples
            try Task.checkCancellation()
        } catch {
            onLog?("  -> ⚠️ Palette validation failed: \(error.localizedDescription). Using raw items.")
            validatedList = raw
        }
        
        var seen = Set<String>()
        var final: [String] = []
        
        let groundingContext = "Grounding food palette items for cuisine: \(cuisineTag). Focus: \(focusSignals.joined(separator: ", "))"
        
        for name in validatedList {
            try Task.checkCancellation()
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            let tokenizedWords = FoodItem.makeTokens(from: trimmed)
            try Task.checkCancellation()
            let ids = await smartSearch.searchFoodsAI(
                query: trimmed,
                limit: 1,
                context: groundingContext,
                requiredHeadwords: tokenizedWords
            )
            try Task.checkCancellation()
            if !ids.isEmpty { final.append(trimmed) }
            if final.count >= 30 { break }
        }
        
        if final.count < 12 {
            for name in raw where final.count < 30 {
                try Task.checkCancellation()
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                guard !seen.contains(key) else { continue }
                let tokenizedWords = FoodItem.makeTokens(from: trimmed)
                try Task.checkCancellation()
                let ids = await smartSearch.searchFoodsAI(
                    query: trimmed,
                    limit: 1,
                    context: groundingContext,
                    requiredHeadwords: tokenizedWords
                )
                try Task.checkCancellation()
                if !ids.isEmpty { seen.insert(key); final.append(trimmed) }
            }
        }
        
        onLog?("  -> Dynamic palette created with \(final.count) items.\n🔎 LLM build prompt:\n\(prompt)\n🔎 LLM validation accepted \(validatedList.count) candidate(s).\n\(final)")
        return final
    }
    
    @MainActor
    private func remapDuplicateDays(
        _ plan: AIConceptualPlanResponse,
        requested: [Int: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) -> AIConceptualPlanResponse {
        var out = plan
        let requestedDays = requested.keys.sorted()
        guard !requestedDays.isEmpty else { return out }
        
        let currentDays = out.days.map { $0.day }
        if Set(currentDays) == Set(requestedDays), currentDays.count == requestedDays.count {
            return out
        }
        
        var idx = 0
        for i in 0..<out.days.count where idx < requestedDays.count {
            let meals = out.days[i].meals
            out.days[i] = ConceptualDay(day: requestedDays[idx], meals: meals)
            idx += 1
        }
        onLog?("🔧 Remapped duplicate/invalid day indices to requested set: \(requestedDays)")
        return out
    }
    
    /// Helper function to identify topics that are exclusively requested for breakfast.
    private func findBreakfastOnlyTopics(from requests: [String]) -> [String] {
        var topicMealMap: [String: Set<String>] = [:]
        
        let pattern = #"\b(?:include|contain|have)\s+([^,.\n]+?)\s+at\s+(Breakfast|Lunch|Dinner)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        
        for req in requests {
            let nsRange = NSRange(req.startIndex..<req.endIndex, in: req)
            regex.enumerateMatches(in: req, options: [], range: nsRange) { match, _, _ in
                guard let match = match, match.numberOfRanges == 3 else { return }
                
                guard let topicRange = Range(match.range(at: 1), in: req),
                      let mealRange = Range(match.range(at: 2), in: req) else { return }
                
                // Extract and clean the topic, removing "different types of" etc.
                var topic = String(req[topicRange]).trimmingCharacters(in: .whitespaces)
                if let range = topic.range(of: #"(?:different\s+types\s+of|different\s+kinds\s+of|a\s+|an\s+)\s+"#, options: .regularExpression) {
                    topic.removeSubrange(range)
                }
                
                let meal = String(req[mealRange]).lowercased()
                
                if !topic.isEmpty {
                    topicMealMap[topic.lowercased(), default: []].insert(meal)
                }
            }
        }
        
        return topicMealMap.compactMap { (topic, meals) in
            // Return topic if it ONLY appears in the context of breakfast
            return meals == ["breakfast"] ? topic : nil
        }
    }
    
    
    @MainActor
    private func generateFullPlanWithAI(
        profile: Profile,
        daysAndMeals: [Int: [String]],
        interpretedPrompts: InterpretedPrompts,
        foodPalettesByContext: [(kind: String, tag: String, foods: [String], associatedCuisine: String?)],
        includedFoods: [String],
        specificVariantPlacements: [String],
        excludedFoods: [String],
        cuisineTag: String,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> AIConceptualPlanResponse {
        // ... (кодът за alcoholKeywords и excludedFoodsAugmented остава същият) ...
        let alcoholKeywords: [String] = [
            "alcohol","beer","wine","vodka","whiskey","whisky","rum","gin","tequila","brandy",
            "liqueur","liquor","cider","sake","soju","rakia","rakija","ouzo","vermouth","champagne",
            "prosecco","cava","mead","port","sherry","cocktail","spritzer","aperitif","digestif",
            "ale","lager","stout","ipa","pilsner","hard seltzer"
        ]
        let excludedFoodsAugmented: [String] = {
            var seen = Set<String>()
            var list: [String] = []
            for x in (excludedFoods + alcoholKeywords) {
                let key = x.lowercased()
                if seen.insert(key).inserted { list.append(x) }
            }
            return list
        }()
        if excludedFoodsAugmented.count != excludedFoods.count {
            onLog?("  -> Alcohol ban: added \(excludedFoodsAugmented.count - excludedFoods.count) keyword(s) to forbidden foods.")
        }
        try Task.checkCancellation()
        // --- START OF CHANGE ---
        func buildUserPrompt(excludedLimit: Int) -> String {
            let qualitativeGoalsSection = interpretedPrompts.qualitativeGoals.isEmpty ? "None." : "- " + interpretedPrompts.qualitativeGoals.joined(separator: "\n- ")
            let excludedFoodsSection = excludedFoodsAugmented.prefix(excludedLimit).isEmpty ? "None." : "- " + excludedFoodsAugmented.prefix(excludedLimit).joined(separator: "\n- ")
            
            // 1. Определяме демографската група на потребителя
            let demographic = determineDemographic(for: profile)
            var nutritionalTargetPrompts: [String] = []
            
            // 2. Итерираме през приоритетните витамини и намираме техните изисквания
            for vitamin in profile.priorityVitamins {
                if let req = vitamin.requirements.first(where: { $0.demographic == demographic }) {
                    var promptLine = "- \(vitamin.name): Aim for at least \(req.dailyNeed) \(vitamin.unit)."
                    if let upperLimit = req.upperLimit {
                        promptLine += " The upper limit is \(upperLimit) \(vitamin.unit)."
                    }
                    nutritionalTargetPrompts.append(promptLine)
                }
            }
            
            // 3. Итерираме през приоритетните минерали и намираме техните изисквания
            for mineral in profile.priorityMinerals {
                if let req = mineral.requirements.first(where: { $0.demographic == demographic }) {
                    var promptLine = "- \(mineral.name): Aim for at least \(req.dailyNeed) \(mineral.unit)."
                    if let upperLimit = req.upperLimit {
                        promptLine += " The upper limit is \(upperLimit) \(mineral.unit)."
                    }
                    nutritionalTargetPrompts.append(promptLine)
                }
            }
            
            // 4. Създаваме новата секция за промпта
            let nutritionalTargetsSection = nutritionalTargetPrompts.isEmpty
            ? ""
            : """
                --- NUTRITIONAL TARGETS (daily) ---
                Strive to meet these daily goals by including foods rich in these nutrients:
                \(nutritionalTargetPrompts.joined(separator: "\n"))
                """
            
            // 5. Включваме новата секция в основния промпт
            return """
            --- USER PROFILE & GOALS ---
            - Goal: \(profile.goal?.title ?? "General Wellness")
            - Diets: \(profile.diets.isEmpty ? "None" : profile.diets.map { $0.name }.joined(separator: ", "))
            - Allergies (CRITICAL): \(profile.allergens.isEmpty ? "None" : profile.allergens.map { $0.rawValue }.joined(separator: ", "))
            - Forbidden Foods (CRITICAL):\n\(excludedFoodsSection)
            \(nutritionalTargetsSection)
            --- GENERAL PREFERENCES & REQUESTS ---
            \(qualitativeGoalsSection)
            --- OTHER INCLUDED FOODS (use these flexibly if they fit) ---
            \(includedFoods.isEmpty ? "None." : "- " + includedFoods.joined(separator: "\n- "))
            """
        }
        // --- END OF CHANGE ---
        
        // ... (останалата част от функцията 'generateFullPlanWithAI' остава непроменена) ...
        func buildRules(palettes: [(kind: String, tag: String, foods: [String], associatedCuisine: String?)], daysAndMeals: [Int: [String]]) -> String {
            let planStructureBlock = daysAndMeals.keys.sorted().map { "Day \($0): [\((daysAndMeals[$0] ?? []).joined(separator: ", "))]" }.joined(separator: "\n")
            
            var palettePromptSection = ""
            var headwordAssociationRules = ""
            
            for p in palettes {
                if p.kind == "cuisine" {
                    palettePromptSection += "\n--- FOOD PALETTE for Cuisine '\(p.tag.capitalized)' ---\n- \(p.foods.joined(separator: ", "))\n"
                } else if p.kind == "headword", let assocCuisine = p.associatedCuisine, !assocCuisine.isEmpty {
                    palettePromptSection += "\n--- FOOD PALETTE for Headword '\(p.tag.capitalized)' ---\n- \(p.foods.joined(separator: ", "))\n"
                    headwordAssociationRules += "- Any meal containing a food from the '\(p.tag.capitalized)' palette (like '\(p.tag)') MUST have its other components chosen from the '\(assocCuisine.capitalized)' cuisine palette.\n"
                }
            }
            
            let mandatoryPlacements = specificVariantPlacements + interpretedPrompts.structuralRequests
            let mandatoryPlacementsSection = mandatoryPlacements.isEmpty
            ? ""
            : """
            --- MANDATORY PLACEMENT RULES (HIGHEST PRIORITY) ---
            You MUST follow these rules exactly. They are not suggestions and override all other contextual hints.
            - \(mandatoryPlacements.joined(separator: "\n- "))
            """
            
            // **NEW**: Always forbid alcohol; also add negative constraints for breakfast-only foods
            let breakfastOnly = findBreakfastOnlyTopics(from: mandatoryPlacements)
            let alcoholBanLine = "- Alcohol is strictly forbidden in all meals. Do NOT include alcoholic beverages or dishes containing alcohol (e.g., \(alcoholKeywords.joined(separator: ", ")))."
            let negativeConstraintSection: String
            if !breakfastOnly.isEmpty {
                negativeConstraintSection = """
                --- CRITICAL NEGATIVE CONSTRAINTS (HIGHEST PRIORITY) ---
                \(alcoholBanLine)
                - The following topics and any variants containing these words MUST ONLY appear in Breakfast meals. Do NOT use them in Lunch or Dinner: \(breakfastOnly.joined(separator: ", ")).
                """
            } else {
                negativeConstraintSection = """
                --- CRITICAL NEGATIVE CONSTRAINTS (HIGHEST PRIORITY) ---
                \(alcoholBanLine)
                """
            }
            
            return """
            \(mandatoryPlacementsSection)
            \(negativeConstraintSection)
            
            --- CORE DIRECTIVES (NON-NEGOTIABLE) ---
            1.  **Plan Structure**: Generate a plan for the EXACT days and meals specified:
                \(planStructureBlock)
            2.  **Meal Naming**: The `name` field MUST EXACTLY match a name from the structure (e.g., "Breakfast"). Use `descriptiveTitle` for creative names.
            3.  **Mandatory Composition**: Each meal MUST contain between 3 and 5 components. This is a strict requirement.
            
            --- CRITICAL CONTEXTUAL COMPOSITION RULE ---
            - **NO FUSION**: Each component `name` MUST be a SINGLE item chosen from the food palettes. Do not invent dishes by combining names.
            - **CONTEXTUAL INTEGRITY**: You MUST follow these rules for combining palettes:
            \(headwordAssociationRules.isEmpty ? "  - General meals should draw from any relevant cuisine palette." : headwordAssociationRules)
            - For meals with a specific theme mentioned in the placement rules, you MUST prioritize foods from that specific cuisine's palette.
            
            --- FOOD PALETTES ---
            \(palettePromptSection)
            
            --- STRICT VARIETY RULES ---
            - **CRITICAL: NO MEAL REPETITION**: For any given meal name across days, the set of component names MUST differ by at least two components.
            - **MAIN MAY REPEAT ONLY IF REQUESTED**: If the same main is explicitly requested in the MANDATORY PLACEMENT RULES, you MUST fulfill that request but vary at least two other components each day.
            - **NO COPY/PASTE LISTS**: Re-using the same component list (even in a different order) is not allowed.
            
            --- IMPORTANT NOTE ABOUT EXAMPLES ---
            - Do not copy any example tokens from these instructions. Treat any examples as placeholders only; never include them verbatim in outputs.
            """
        }
        
        do {
            try Task.checkCancellation()
            let rules1 = buildRules(palettes: foodPalettesByContext, daysAndMeals: daysAndMeals)
            try Task.checkCancellation()
            let session1 = LanguageModelSession(instructions: Instructions { rules1 })
            try Task.checkCancellation()
            let prompt1 = buildUserPrompt(excludedLimit: 24)
            try Task.checkCancellation()
            onLog?("  -> Sending contextual prompt to AI for full plan generation...")
            let rawPlan = try await generatePlanViaInterface(session: session1, prompt: prompt1, daysAndMeals: daysAndMeals)
            try Task.checkCancellation()
            return rawPlan // Purging is now part of the consolidated polish function
        } catch {
            onLog?("  -> ⚠️ Main generation attempt failed: \(error.localizedDescription). Retrying with minimal prompt.")
            let rules2 = buildRules(palettes: [], daysAndMeals: daysAndMeals)
            let session2 = LanguageModelSession(instructions: Instructions { rules2 })
            let prompt2 = buildUserPrompt(excludedLimit: 12)
            let rawPlan = try await generatePlanViaInterface(session: session2, prompt: prompt2, daysAndMeals: daysAndMeals)
            return rawPlan // Purging is now part of the consolidated polish function
        }
    }
    
    private func buildMustContainRules(
        structuralRequests: [String],
        daysAndMeals: [Int: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) -> [MustContainRule] {
        guard !structuralRequests.isEmpty else { return [] }
        let validDays = Set(daysAndMeals.keys)
        var out: [MustContainRule] = []
        
        var mealMaps: [Int: [String: String]] = [:]
        for (day, meals) in daysAndMeals {
            var m: [String: String] = [:]
            for name in meals { m[name.lowercased()] = name }
            mealMaps[day] = m
        }
        
        let p1 = #"on\s+day\s+([1-7])\s*,?\s*include\s+([a-zA-Z][a-zA-Z\s]+?)\s+at\s+([a-zA-Z][a-zA-Z\s]+)"#
        let p2 = #"on\s+day\s+([1-7])\s*,?\s*the\s+([a-zA-Z][a-zA-Z\s]+)\s+meal\s+must\s+contain\s+([a-zA-Z][a-zA-Z\s]+)"#
        let p3 = #"on\s+day\s+([1-7])\s*,?\s*one\s+meal\s+must\s+contain\s+([a-zA-Z][a-zA-Z\s]+)"#
        
        for raw in structuralRequests {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            func addRule(dayStr: String, mealStr: String?, topicStr: String) {
                guard let day = Int(dayStr), validDays.contains(day) else { return }
                let topic = topicStr.trimmingCharacters(in: .whitespaces).capitalized
                let meal: String? = {
                    guard let ms = mealStr?.trimmingCharacters(in: .whitespacesAndNewlines), !ms.isEmpty else { return nil }
                    let ci = ms.lowercased()
                    if let mapped = mealMaps[day]?[ci] { return mapped }
                    if ci.contains("breakfast") { return mealMaps[day]?["breakfast"] }
                    if ci.contains("lunch") { return mealMaps[day]?["lunch"] }
                    if ci.contains("dinner") { return mealMaps[day]?["dinner"] }
                    return nil
                }()
                out.append(MustContainRule(day: day, meal: meal, topic: topic))
            }
            
            if let r = try? NSRegularExpression(pattern: p1, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                if let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 4,
                   let g1 = Range(m.range(at: 1), in: s),
                   let g2 = Range(m.range(at: 2), in: s),
                   let g3 = Range(m.range(at: 3), in: s) {
                    addRule(dayStr: String(s[g1]), mealStr: String(s[g3]), topicStr: String(s[g2]))
                    continue
                }
            }
            if let r = try? NSRegularExpression(pattern: p2, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                if let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 4,
                   let g1 = Range(m.range(at: 1), in: s),
                   let g2 = Range(m.range(at: 2), in: s),
                   let g3 = Range(m.range(at: 3), in: s) {
                    addRule(dayStr: String(s[g1]), mealStr: String(s[g2]), topicStr: String(s[g3]))
                    continue
                }
            }
            if let r = try? NSRegularExpression(pattern: p3, options: .caseInsensitive) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                if let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 3,
                   let g1 = Range(m.range(at: 1), in: s),
                   let g2 = Range(m.range(at: 2), in: s) {
                    addRule(dayStr: String(s[g1]), mealStr: nil, topicStr: String(s[g2]))
                    continue
                }
            }
        }
        
        if !out.isEmpty {
            onLog?("  -> Built \(out.count) must-contain rule(s): \(out)")
        }
        return out
    }
    
    @MainActor
    private func aiFetchNutritionData(for foodNames: [String], onLog: (@Sendable (String) -> Void)?) async -> [AINutritionInfo] {
        guard !foodNames.isEmpty else { return [] }
        onLog?("    - Fetching nutrition data from AI for \(foodNames.count) items...")
        let prompt = """
        For the following food items, provide typical nutritional values (protein, fat, carbohydrates) in grams per 100g. The names in your response must exactly match the names in this list.
        FOODS:
        \(foodNames.map { "- \($0)" }.joined(separator: "\n"))
        """
        let session = LanguageModelSession(instructions: Instructions {
        """
        TASK:
            - Return nutrition for the given food names **exactly as listed** (names must match 1:1).
            - For each item, provide protein, fat, and carbohydrates per 100 g.
            - Do not add extra items, do not rename items, and do not include units in the numeric fields.
        """
        })
        
        do {
            try Task.checkCancellation()
            let response = try await session.respond(to: prompt, generating: AINutritionResponse.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy))
            try Task.checkCancellation()
            return response.content.nutritionData
        } catch {
            onLog?("    - ⚠️ AI nutrition data fetch failed: \(error.localizedDescription). Adjustment may be skipped.")
            return []
        }
    }
    
    @MainActor
    private func removeBannedCuisineKeywords(
        plan: AIConceptualPlanResponse,
        bannedKeywords: [String],
        onLog: (@Sendable (String) -> Void)?
    ) -> AIConceptualPlanResponse {
        guard !bannedKeywords.isEmpty else { return plan }
        var out = plan
        let bans = bannedKeywords.map { $0.lowercased() }
        for d in 0..<out.days.count {
            for m in 0..<out.days[d].meals.count {
                var comps = out.days[d].meals[m].components
                let before = comps.count
                comps.removeAll { c in
                    let l = c.name.lowercased()
                    return bans.contains { l.contains($0) }
                }
                if comps.count != before {
                    let removed = before - comps.count
                    onLog?("🧹 Removed \(removed) off-cuisine component(s) from Day \(out.days[d].day) • \(out.days[d].meals[m].name).")
                    if comps.isEmpty { comps = [ConceptualComponent(name: "Greek Yogurt", grams: 180)] }
                }
                out.days[d].meals[m].components = comps
            }
        }
        return out
    }
    
    @MainActor
    private func validateAndAdjustDayForGoals(
        day: ConceptualDay,
        goals: [NumericalGoal],
        onLog: (@Sendable (String) -> Void)?
    ) async -> ConceptualDay {
        guard !goals.isEmpty else { return day }
        
        let names = Array(Set(day.meals.flatMap { $0.components.map { $0.name } }))
        let nutritionData = await aiFetchNutritionData(for: names, onLog: onLog)
        
        guard !nutritionData.isEmpty else {
            onLog?("    - Could not fetch nutrition data for Day \(day.day). Skipping day-level adjustments.")
            return day
        }
        
        let nutritionMap = Dictionary(uniqueKeysWithValues: nutritionData.map { ($0.name.lowercased(), $0) })
        
        let pre = computeDayMacroTotals(day: day, nutritionMap: nutritionMap)
        onLog?("    - Day \(day.day) PRE totals: Protein \(Int(pre.protein))g • Fat \(Int(pre.fat))g • Carbs \(Int(pre.carbs))g")
        
        var adjusted = day
        for goal in goals {
            adjusted = adjustDayForGoal(day: adjusted, goal: goal, nutritionMap: nutritionMap, onLog: onLog)
        }
        
        let post = computeDayMacroTotals(day: adjusted, nutritionMap: nutritionMap)
        onLog?("    - Day \(day.day) POST totals: Protein \(Int(post.protein))g • Fat \(Int(post.fat))g • Carbs \(Int(post.carbs))g")
        
        return adjusted
    }
    
    @MainActor
    private func ensureIncludedFoodsPlaced(
        plan: AIConceptualPlanResponse,
        includedFoods: [String],
        targetMealName: String?,
        wantVariants: Bool,
        excludedFoods: [String],
        daysAndMeals: [Int: [String]],
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async -> AIConceptualPlanResponse {
        guard !includedFoods.isEmpty else { return plan }
        var out = plan
        
        let banned = Set(excludedFoods.map { $0.lowercased() })
        func violatesExcluded(_ n: String) -> Bool { banned.contains { n.lowercased().contains($0) } }
        
        func targetMealIndex(forDay dIdx: Int) -> Int? {
            let names = out.days[dIdx].meals.map { $0.name }
            if let t = targetMealName,
               let ix = names.firstIndex(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                return ix
            }
            return names.indices.first
        }
        
        let dayCount = out.days.count
        var variantsPerFood: [String: [String]] = [:]
        for base in includedFoods {
            let clean = base.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !violatesExcluded(clean) else { continue }
            if wantVariants && dayCount > 1 {
                let v = await aiGenerateVariants(for: clean, count: dayCount, mealName: targetMealName, excludedFoods: excludedFoods, onLog: onLog)
                variantsPerFood[clean.lowercased()] = v
            } else {
                variantsPerFood[clean.lowercased()] = Array(repeating: clean.capitalized, count: dayCount)
            }
        }
        
        func indexOfMainComponent(in meal: ConceptualMeal) -> Int? {
            let candidates = meal.components.enumerated().filter { $0.element.grams >= 90 }
            return candidates.max(by: { $0.element.grams < $1.element.grams })?.offset
        }
        
        for dIdx in 0..<out.days.count {
            guard let mIdx = targetMealIndex(forDay: dIdx) else { continue }
            let dayNum = out.days[dIdx].day
            
            if targetMealName != nil {
                for ix in 0..<out.days[dIdx].meals.count where ix != mIdx {
                    let before = out.days[dIdx].meals[ix].components.count
                    out.days[dIdx].meals[ix].components.removeAll { c in
                        includedFoods.contains { inc in c.name.range(of: inc, options: .caseInsensitive) != nil }
                    }
                    let after = out.days[dIdx].meals[ix].components.count
                    if after < before { onLog?("🧹 Removed included-food duplicates from Day \(dayNum) • \(out.days[dIdx].meals[ix].name).") }
                }
            }
            
            for (key, labels) in variantsPerFood {
                let label = labels.indices.contains(dIdx) ? labels[dIdx] : (labels.first ?? key.capitalized)
                var meal = out.days[dIdx].meals[mIdx]
                
                let alreadyThere = meal.components.contains { $0.name.range(of: key, options: .caseInsensitive) != nil }
                if !alreadyThere {
                    if await !isConcreteFoodName(label, smartSearch: smartSearch) {
                        onLog?("⏭️ Skipped non-concrete included-food label ‘\(label)’ for Day \(dayNum) • \(meal.name).")
                    } else if let mainIdx = indexOfMainComponent(in: meal) {
                        meal.components[mainIdx] = ConceptualComponent(name: label, grams: max(120, meal.components[mainIdx].grams))
                        onLog?("✅ Day \(dayNum) • \(meal.name): replaced main with ‘\(label)’.")
                    } else {
                        meal.components.append(ConceptualComponent(name: label, grams: 150))
                        onLog?("✅ Day \(dayNum) • \(meal.name): appended ‘\(label)’.")
                    }
                }
                
                var seen: Set<String> = []
                meal.components = meal.components.filter { c in
                    let k = c.name.lowercased()
                    if includedFoods.contains(where: { k.contains($0.lowercased()) }) {
                        return seen.insert(k).inserted
                    }
                    return true
                }
                
                out.days[dIdx].meals[mIdx] = meal
            }
        }
        
        return out
    }
    
    private func validateAndAdjustPlan(plan: AIConceptualPlanResponse, goals: [NumericalGoal], onLog: (@Sendable (String) -> Void)?) async -> AIConceptualPlanResponse {
        var adjustedPlan = plan
        onLog?("    - AIConceptualPlanResponse plan: \(adjustedPlan)")
        let allFoodNames = Array(Set(adjustedPlan.days.flatMap { $0.meals }.flatMap { $0.components }.map { $0.name }))
        let nutritionData = await aiFetchNutritionData(for: allFoodNames, onLog: onLog)
        
        guard !nutritionData.isEmpty else {
            onLog?("    - Could not fetch nutrition data. Skipping programmatic adjustments.")
            return plan
        }
        
        let nutritionMap = Dictionary(uniqueKeysWithValues: nutritionData.map { ($0.name.lowercased(), $0) })
        for dayIndex in 0..<adjustedPlan.days.count {
            for goal in goals {
                adjustedPlan.days[dayIndex] = adjustDayForGoal(
                    day: adjustedPlan.days[dayIndex], goal: goal, nutritionMap: nutritionMap, onLog: onLog
                )
            }
        }
        return adjustedPlan
    }
    
    private func adjustDayForGoal(day: ConceptualDay, goal: NumericalGoal, nutritionMap: [String: AINutritionInfo], onLog: (@Sendable (String) -> Void)?) -> ConceptualDay {
        var adjustedDay = day
        func getNutrientValue(from info: AINutritionInfo, for nutrient: MacronutrientType) -> Double {
            switch nutrient {
            case .protein: return info.protein_g
            case .fat: return info.fat_g
            case .carbohydrates: return info.carbohydrates_g
            }
        }
        var currentTotal: Double = 0
        for meal in adjustedDay.meals {
            for component in meal.components {
                if let nutritionInfo = nutritionMap[component.name.lowercased()] {
                    currentTotal += (getNutrientValue(from: nutritionInfo, for: goal.nutrient) / 100.0) * component.grams
                }
            }
        }
        
        let error = currentTotal - goal.value
        onLog?("    - Day \(day.day), Goal (\(goal.nutrient.rawValue) \(goal.constraint) \(Int(goal.value))g): Current value is \(Int(currentTotal))g. Error: \(Int(error))g.")
        
        var needsAdjustment = false
        switch goal.constraint {
        case .exactly: needsAdjustment = abs(error) > (goal.value * 0.1)
        case .lessThan: needsAdjustment = currentTotal > goal.value
        case .moreThan: needsAdjustment = currentTotal < goal.value
        }
        
        guard needsAdjustment else {
            onLog?("    - Value is within acceptable limits. No adjustment needed.")
            return adjustedDay
        }
        
        var adjustableComponents: [(mealIdx: Int, compIdx: Int, nutrientDensity: Double)] = []
        for (mIdx, meal) in adjustedDay.meals.enumerated() {
            for (cIdx, component) in meal.components.enumerated() {
                if let nutritionInfo = nutritionMap[component.name.lowercased()], getNutrientValue(from: nutritionInfo, for: goal.nutrient) > 5 {
                    adjustableComponents.append((mIdx, cIdx, getNutrientValue(from: nutritionInfo, for: goal.nutrient) / 100.0))
                }
            }
        }
        
        guard !adjustableComponents.isEmpty else {
            onLog?("    - No adjustable components found for this nutrient. Cannot adjust.")
            return adjustedDay
        }
        
        let adjustmentPerSource = -error / Double(adjustableComponents.count)
        
        for item in adjustableComponents {
            let component = adjustedDay.meals[item.mealIdx].components[item.compIdx]
            let currentNutrientAmount = component.grams * item.nutrientDensity
            if item.nutrientDensity > 0 {
                let newGrams = max(20.0, (currentNutrientAmount + adjustmentPerSource) / item.nutrientDensity)
                adjustedDay.meals[item.mealIdx].components[item.compIdx].grams = newGrams
            }
        }
        
        let finalTotal = adjustedDay.meals.flatMap { $0.components }.reduce(0.0) { total, component in
            if let info = nutritionMap[component.name.lowercased()] { return total + (getNutrientValue(from: info, for: goal.nutrient) / 100.0) * component.grams }
            return total
        }
        onLog?("    - Day \(day.day) adjusted for \(goal.nutrient.rawValue). New value: \(Int(finalTotal))g.")
        return adjustedDay
    }
    
    @MainActor
    private func resolveFoodConcept(
        smartSearch: SmartFoodSearch,
        conceptName: String,
        mealContext: ConceptualMeal,
        relevantPrompts: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> ResolvedFoodInfo? {
        onLog?("    - Resolving '\(conceptName)' in context of '\(mealContext.descriptiveTitle)'...")
        
        let searchLimit = 50
        
        let otherComponentsText = mealContext.components
            .filter { $0.name.caseInsensitiveCompare(conceptName) != .orderedSame }
            .map(\.name)
            .joined(separator: ", ")
        
        let relevantPromptsText = relevantPrompts.isEmpty ? "none" : relevantPrompts.joined(separator: "\n- ")
        
        let contextString = """
        Meal Title: \(mealContext.descriptiveTitle)
        Meal Slot: \(mealContext.name)
        Relevant User Prompts for this Meal:
        - \(relevantPromptsText)
        Other Components in Meal: \(otherComponentsText.isEmpty ? "none" : otherComponentsText)
        """
        
        let (smartQueries, banned) = await aiBuildSmartQueries(
            for: conceptName,
            mealContext: mealContext,
            relevantPrompts: relevantPrompts,
            onLog: onLog
        )
        
        let combinedQueries = ([conceptName] + smartQueries).filter { !$0.isEmpty }
        
        var candidateIDs: [PersistentIdentifier] = []
        let tokenizedWords = FoodItem.makeTokens(from: conceptName)
        
        var seen = Set<PersistentIdentifier>()
        onLog?("combinedQueries: \(combinedQueries)\ncontextString: \(contextString) \ntokenizedWords: \(tokenizedWords)")
        
        for q in combinedQueries {
            let ids = await smartSearch.searchFoodsAI(
                query: q,
                limit: searchLimit,
                context: contextString,
                requiredHeadwords: tokenizedWords
            )
            for id in ids where !seen.contains(id) {
                seen.insert(id)
                candidateIDs.append(id)
            }
        }
        onLog?("candidate ids \(candidateIDs.count)")
        
        guard !candidateIDs.isEmpty else {
            onLog?("    - ⚠️ No candidates found for '\(conceptName)'.")
            return nil
        }
        
        let ctx = ModelContext(self.container)
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { candidateIDs.contains($0.persistentModelID) })
        guard var candidates = try? ctx.fetch(descriptor), !candidates.isEmpty else {
            onLog?("    - ⚠️ Could not fetch FoodItem models for candidates.")
            return nil
        }
        
        let beforeFilterCount = candidates.count
        let filtered = filterCandidates(candidates, banned: banned)
        if filtered.count != beforeFilterCount {
            onLog?("    - Banned filter removed \(beforeFilterCount - filtered.count) candidates. Banned: \(banned)")
        }
        candidates = filtered.isEmpty ? candidates : filtered
        
        let smartNames = candidates.map { $0.name }
        onLog?("    - SMART candidates (after bans) → \(smartNames.count). Top: \(Array(smartNames.prefix(8)))")
        
        if candidates.count == 1 {
            onLog?("    - Found single direct match: '\(candidates[0].name)'")
            return ResolvedFoodInfo(persistentID: candidates[0].persistentModelID, resolvedName: candidates[0].name)
        }
        
        do {
            try Task.checkCancellation()
            let choice = try await aiChooseBestFoodCandidate(
                conceptName: conceptName,
                candidates: candidates.map { $0.name },
                mealContext: mealContext,
                onLog: onLog
            )
            try Task.checkCancellation()
            if candidates.indices.contains(choice.bestCandidateIndex) {
                let chosen = candidates[choice.bestCandidateIndex]
                onLog?("    - AI refined choice to '\(chosen.name)'. Reason: \(choice.reason)\n Candidates: \(candidates.map(\.name))")
                return ResolvedFoodInfo(persistentID: chosen.persistentModelID, resolvedName: chosen.name)
            }
        } catch {
            onLog?("    - ⚠️ AI refinement failed: \(error.localizedDescription). Falling back to similarity search.")
        }
        
        onLog?("    - Using fallback similarity search...")
        let (bestMatch, bestMatchName) = findBestCandidateBySimilarity(conceptName: conceptName, candidates: candidates)
        if let match = bestMatch {
            return ResolvedFoodInfo(persistentID: match.persistentModelID, resolvedName: bestMatchName ?? match.name)
        }
        return nil
    }
    
    @MainActor
    private func aiBuildSmartQueries(
        for conceptName: String,
        mealContext: ConceptualMeal?,
        relevantPrompts: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> (queries: [String], banned: [String]) {
        let micro = conceptName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let microSet: Set<String> = [
            "salt","pepper","black pepper","cilantro","coriander","parsley","basil","oregano",
            "garlic","ginger","cumin","paprika","chili powder","cayenne","lemon","lime"
        ]
        if microSet.contains(micro) || (micro.hasSuffix("s") && microSet.contains(String(micro.dropLast()))) {
            let proteinBan = [
                "chicken","turkey","salmon","tuna","fish","shrimp","pork","beef","lamb","ham",
                "egg","eggs","tofu","tempeh","lentil","lentils","bean","beans"
            ]
            var finalQueries: [String] = []
            let conceptTrimmed = conceptName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !conceptTrimmed.isEmpty {
                finalQueries.append(conceptTrimmed)
            }
            if !finalQueries.contains(where: { $0.caseInsensitiveCompare(micro) == .orderedSame }) {
                finalQueries.append(micro)
            }
            onLog?("    - AI smart queries (concept first, micro): \(finalQueries) | banned: \(proteinBan)")
            return (finalQueries, proteinBan)
        }
        
        let baseBan = [
            "powder","dressing","sauce","oil","butter","flour","shake","mix","tots","paste",
            "topping","toppings","candy","candies","bar","cookie","cookies","cake","pie","dessert",
            "belly","steelhead","baby food","infant","toddler","gerber","stage 1","stage 2","stage 3",
            "plavnik"
        ]
        
        let instructions = Instructions {
           """
              RULES:
              - priorityKeywords: 2–4 lowercase tokens, ordered by importance.
                * token[0] MUST be the headword (core ingredient).
                * Prefer cuts/methods/dish-type terms (preparation or form), not marketing adjectives.
                * No quantities, no stopwords, no cuisine adjectives.
              - bannedKeywords: tokens to exclude that indicate powders, sauces, dressings, shakes, or other non-solid/prepared forms.
              - headwordSynonyms: up to 3 lowercase synonyms for the headword that commonly appear in USDA-like names.
           """
        }
        let session = LanguageModelSession(instructions: instructions)
        
        let other = mealContext.map { mc in
            mc.components
                .filter { $0.name.caseInsensitiveCompare(conceptName) != .orderedSame }
                .map(\.name)
                .joined(separator: ", ")
        } ?? ""
        
        let relevantPromptsText = relevantPrompts.isEmpty ? "n/a" : relevantPrompts.joined(separator: " | ")
        
        let prompt = """
       Extract prioritized search tokens for a food concept so they match USDA-like food names.
       
       CONCEPT: "\(conceptName)"
       MEAL CONTEXT: \(mealContext?.name ?? "n/a") — \(mealContext?.descriptiveTitle ?? "n/a")
       USER REQUIREMENTS FOR THIS MEAL: \(relevantPromptsText)
       OTHER COMPONENTS IN THIS MEAL: \(other.isEmpty ? "n/a" : other)
       """
        
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(
                to: prompt,
                generating: AISearchKeywordResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content
            try Task.checkCancellation()
            var queries: [String] = []
            let kw = resp.priorityKeywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            try Task.checkCancellation()
            if !kw.isEmpty {
                let top3 = Array(kw.prefix(3))
                if top3.count >= 3 { queries.append(top3.joined(separator: " ")) }
                if top3.count >= 2 { queries.append(top3.prefix(2).joined(separator: " ")) }
                queries.append(String(top3[0]))
            }
            try Task.checkCancellation()
            if let head = kw.first, !resp.headwordSynonyms.isEmpty, kw.count >= 2 {
                let tail1 = kw[1]
                for syn in resp.headwordSynonyms.prefix(3) {
                    queries.append("\(syn) \(tail1)")
                    queries.append(syn)
                }
            }
            try Task.checkCancellation()
            var seen = Set<String>()
            queries = queries.filter { seen.insert($0).inserted }
            try Task.checkCancellation()
            var bannedSet = Set((resp.bannedKeywords + baseBan).map { $0.lowercased() })
            let cn = conceptName.lowercased()
            
            if cn.contains("mixed green") || (cn.contains("salad") && !cn.contains("chicken") && !cn.contains("tuna") && !cn.contains("salmon") && !cn.contains("egg")) {
                ["chicken","turkey","salmon","tuna","fish","shrimp","pork","beef","lamb","ham"].forEach { bannedSet.insert($0) }
            }
            if cn.contains("lemon wedge") || (cn.contains("lemon") && (cn.contains("wedge") || cn.contains("slice"))) {
                ["fish","salmon","cod","tuna"].forEach { bannedSet.insert($0) }
            }
            if cn.contains("berries") || cn.contains("berry") {
                ["topping","toppings","pie","syrup","jam","jelly","preserves","dessert"].forEach { bannedSet.insert($0) }
            }
            if cn.contains("bell pepper") {
                bannedSet.insert("belly")
                bannedSet.insert("pork belly")
            }
            if cn.contains("steel cut oat") || cn.contains("steel-cut oat") || cn.contains("steelcut oat") {
                ["steelhead","trout","fish"].forEach { bannedSet.insert($0) }
            }
            if !cn.contains("baby ") {
                ["baby","infant","toddler","formula"].forEach { bannedSet.insert($0) }
            }
            
            let banned = Array(bannedSet)
            try Task.checkCancellation()
            var finalQueries = queries
            let conceptTrimmed = conceptName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !conceptTrimmed.isEmpty {
                if let i = finalQueries.firstIndex(where: { $0.caseInsensitiveCompare(conceptTrimmed) == .orderedSame }) {
                    if i != 0 {
                        finalQueries.remove(at: i)
                        finalQueries.insert(conceptTrimmed, at: 0)
                    }
                } else {
                    finalQueries.insert(conceptTrimmed, at: 0)
                }
            }
            onLog?("    - AI smart queries (concept first): \(finalQueries) | banned: \(banned)")
            return (finalQueries, banned)
            
        } catch {
            onLog?("    - ⚠️ Keyword AI failed: \(error.localizedDescription). Using heuristic tokens.")
            
            let stop: Set<String> = ["of","with","and","or","in","on","for","a","an","the","style","fresh","raw","cooked","very","tasty"]
            let tokens = conceptName
                .lowercased()
                .replacingOccurrences(of: "[()\\[\\]{},:;./\\\\\\d]", with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty && !stop.contains($0) }
            
            var queries: [String] = []
            if !tokens.isEmpty {
                let head = tokens[0]
                let rest = Array(tokens.dropFirst())
                if rest.count >= 2 { queries.append([head, rest[0], rest[1]].joined(separator: " ")) }
                if rest.count >= 1 { queries.append([head, rest[0]].joined(separator: " ")) }
                queries.append(head)
            }
            
            var seen = Set<String>()
            queries = queries.filter { seen.insert($0).inserted }
            
            var finalQueries = queries
            let conceptTrimmed = conceptName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !conceptTrimmed.isEmpty {
                if let i = finalQueries.firstIndex(where: { $0.caseInsensitiveCompare(conceptTrimmed) == .orderedSame }) {
                    if i != 0 {
                        finalQueries.remove(at: i)
                        finalQueries.insert(conceptTrimmed, at: 0)
                    }
                } else {
                    finalQueries.insert(conceptTrimmed, at: 0)
                }
            }
            onLog?("    - AI smart queries (concept first, fallback): \(finalQueries) | banned: \(baseBan)")
            return (finalQueries, baseBan)
        }
    }
    
    @MainActor
    private func aiChooseBestFoodCandidate(conceptName: String, candidates: [String], mealContext: ConceptualMeal, onLog: (@Sendable (String) -> Void)?) async throws -> AIBestCandidateChoice {
        let otherComponents = mealContext.components.filter { $0.name != conceptName }.map { $0.name }.joined(separator: ", ")
        let prompt = """
        You are a culinary assistant. Your job is to select the most appropriate preparation for an ingredient to fit a specific meal.
        **Meal Context:** A '\(mealContext.name)' titled '\(mealContext.descriptiveTitle)' which also contains: \(otherComponents).
        **Task:**
        The user wants to add "\(conceptName)". From the following list of specific food preparations, choose the one that makes the most sense in this meal. For example, 'steamed' or 'cooked' is better for a hot dinner than 'raw'.
        **Candidates (choose one):**
        \(candidates.enumerated().map { "\($0). \($1)" }.joined(separator: "\n"))
        including the index and a brief reason in response.
        """
        try Task.checkCancellation()
        let session = LanguageModelSession()
        try Task.checkCancellation()
        let response = try await session.respond(to: prompt, generating: AIBestCandidateChoice.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy))
        try Task.checkCancellation()
        return response.content
    }
    
    private func findBestCandidateBySimilarity(conceptName: String, candidates: [FoodItem]) -> (FoodItem?, String?) {
        var bestMatch: FoodItem? = nil
        var lowestDistance = Int.max
        let penaltyWords = ["milk", "oil", "butter", "flour", "powder", "dressing", "sauce", "paste", "tots", "salad"]
        let queryContainsPenaltyWord = penaltyWords.contains { conceptName.lowercased().contains($0) }
        for candidate in candidates {
            var distance = conceptName.levenshteinDistance(to: candidate.name)
            if !queryContainsPenaltyWord {
                for word in penaltyWords {
                    if candidate.name.lowercased().contains(" \(word)") {
                        distance += 20; break
                    }
                }
            }
            if distance < lowestDistance {
                lowestDistance = distance
                bestMatch = candidate
            }
        }
        return (bestMatch, bestMatch?.name)
    }
    
    private func trimToRequestedDaysAndMeals(
        plan: AIConceptualPlanResponse,
        daysAndMeals: [Int: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) -> AIConceptualPlanResponse {
        var out = plan
        let wantedDays = Set(daysAndMeals.keys)
        out.days.removeAll { !wantedDays.contains($0.day) }
        for i in 0..<out.days.count {
            let day = out.days[i].day
            let wantedMeals = daysAndMeals[day] ?? []
            out.days[i].meals = out.days[i].meals
                .filter { m in wantedMeals.contains { $0.caseInsensitiveCompare(m.name) == .orderedSame } }
                .sorted { a, b in
                    let ia = wantedMeals.firstIndex { $0.caseInsensitiveCompare(a.name) == .orderedSame } ?? .max
                    let ib = wantedMeals.firstIndex { $0.caseInsensitiveCompare(b.name) == .orderedSame } ?? .max
                    return ia < ib
                }
        }
        onLog?("✅ Normalized to requested days/meals: kept days \(out.days.map{ $0.day }).")
        return out
    }
    
    // **MODIFIED**: This is the new, consolidated polishing function with context-aware trimming.
    @MainActor
    private func polishConceptualPlan(
        plan: AIConceptualPlanResponse,
        profile: Profile,
        daysAndMeals: [Int: [String]],
        rules: [MustContainRule],
        excludedFoods: [String],
        foodPalette: [String],
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async -> AIConceptualPlanResponse {
        var polishedPlan = plan
        onLog?(" polishing conceptual plan...")
        
        // --- Start Helper Functions (scoped to polishing) ---
        let excludedSet = Set(excludedFoods.map { $0.lowercased() })
        func isExcluded(_ name: String) -> Bool {
            let lower = name.lowercased()
            return excludedSet.contains { lower.contains($0) }
        }
        
        func isProtein(_ n: String) -> Bool {
            let keys = ["chicken", "pork", "beef", "turkey", "salmon", "tuna", "fish", "lamb", "loin", "breast", "steak", "ham", "shrimp", "egg", "tofu", "tempeh", "lentil", "bean"]
            return keys.contains { n.lowercased().contains($0) }
        }
        
        func coreProteinKey(_ name: String) -> String {
            let keys = ["chicken", "turkey", "salmon", "tuna", "fish", "shrimp", "pork", "beef", "lamb", "egg", "tofu", "tempeh", "lentil", "bean"]
            for k in keys { if name.lowercased().contains(k) { return k } }
            return name.lowercased()
        }
        
        func isSalad(_ n: String) -> Bool { let l = n.lowercased(); return l.contains("salad") || l.contains("greens") }
        func isFruit(_ n: String) -> Bool { n.lowercased().contains("fruit") }
        
        var sideCandidates: [String] = {
            var candidates: [String] = []
            let paletteSides = foodPalette.filter { isSalad($0) || isFruit($0) }
            var seen = Set<String>()
            for side in paletteSides {
                if seen.insert(side.lowercased()).inserted && !isExcluded(side) {
                    candidates.append(side)
                }
            }
            return candidates
        }()
        
        if sideCandidates.isEmpty {
            let ctx = ModelContext(self.container)
            let descriptor = FetchDescriptor<FoodItem>()
            if let all = try? ctx.fetch(descriptor) {
                for f in all {
                    if (isSalad(f.name) || isFruit(f.name)) && !isExcluded(f.name) {
                        sideCandidates.append(f.name)
                    }
                }
            }
        }
        
        // --- End Helper Functions ---
        
        var seenSignatures: [String: Set<String>] = [:]
        var usedDinnerProteins = Set<String>()
        
        var protectedByDayMeal: [Int: [String: Set<String>]] = [:]
        for r in rules {
            let keyMeal = (r.meal?.lowercased()) ?? "*"
            var meals = protectedByDayMeal[r.day] ?? [:]
            var set = meals[keyMeal] ?? Set()
            set.insert(r.topic.lowercased())
            meals[keyMeal] = set
            protectedByDayMeal[r.day] = meals
        }
        
        let orderedDayIndices = polishedPlan.days.indices.sorted(by: { polishedPlan.days[$0].day < polishedPlan.days[$1].day })
        
        for dayIndex in orderedDayIndices {
            let dayNumber = polishedPlan.days[dayIndex].day
            var dayHasSaladOrFruit = false
            
            for mealIndex in 0..<polishedPlan.days[dayIndex].meals.count {
                var meal = polishedPlan.days[dayIndex].meals[mealIndex]
                
                // --- Rule 1: Purge Excluded Foods ---
                let beforeCount = meal.components.count
                meal.components.removeAll { isExcluded($0.name) }
                if meal.components.count < beforeCount {
                    onLog?("🧹 Day \(dayNumber) • \(meal.name): Removed \(beforeCount - meal.components.count) excluded component(s).")
                }
                if meal.components.isEmpty {
                    meal.components.append(ConceptualComponent(name: "Mixed Greens", grams: 80))
                }
                
                // --- Rule 2: Enforce Must-Contain ---
                let relevantRules = rules.filter { $0.day == dayNumber }
                for rule in relevantRules {
                    let mealMatches = (rule.meal == nil) || (rule.meal?.caseInsensitiveCompare(meal.name) == .orderedSame)
                    if mealMatches && !meal.components.contains(where: { $0.name.range(of: rule.topic, options: .caseInsensitive) != nil }) {
                        if let proteinIdx = meal.components.firstIndex(where: { isProtein($0.name) }) {
                            let old = meal.components[proteinIdx].name
                            meal.components[proteinIdx] = ConceptualComponent(name: rule.topic, grams: 120)
                            onLog?("✅ Enforced: Day \(dayNumber) • \(meal.name) now has '\(rule.topic)' (replaced '\(old)').")
                        } else {
                            meal.components.append(ConceptualComponent(name: rule.topic, grams: 120))
                            onLog?("✅ Enforced: Day \(dayNumber) • \(meal.name) now has '\(rule.topic)' (added).")
                        }
                    }
                }
                
                // --- Rule 3: Diversify Dinner & Enforce Single Main Course ---
                var proteinIndices = meal.components.indices.filter { isProtein(meal.components[$0].name) }
                
                if meal.name.caseInsensitiveCompare("Dinner") == .orderedSame {
                    if let mainProteinIdx = proteinIndices.first {
                        let currentKey = coreProteinKey(meal.components[mainProteinIdx].name)
                        if usedDinnerProteins.contains(currentKey) {
                            let isProtectedByRule = protectedByDayMeal[dayNumber]?[meal.name.lowercased()]?.contains(where: { currentKey.contains($0) }) ?? false
                            if !isProtectedByRule {
                                let replacementOptions = foodPalette.filter { isProtein($0) && !isExcluded($0) }
                                if let replacement = replacementOptions.first(where: { !usedDinnerProteins.contains(coreProteinKey($0)) }) {
                                    let oldName = meal.components[mainProteinIdx].name
                                    meal.components[mainProteinIdx].name = replacement
                                    onLog?("🔁 Diversified Dinner on Day \(dayNumber): replaced '\(oldName)' with '\(replacement)'.")
                                    usedDinnerProteins.insert(coreProteinKey(replacement))
                                }
                            }
                        } else {
                            usedDinnerProteins.insert(currentKey)
                        }
                    }
                }
                
                proteinIndices = meal.components.indices.filter { isProtein(meal.components[$0].name) }
                if proteinIndices.count > 1 {
                    for extraIdx in proteinIndices.dropFirst().reversed() {
                        let old = meal.components[extraIdx].name
                        if let replacement = sideCandidates.randomElement() {
                            meal.components[extraIdx] = ConceptualComponent(name: replacement, grams: 100)
                            onLog?("✅ Single Main: Day \(dayNumber) • \(meal.name) replaced extra protein '\(old)' with '\(replacement)'.")
                        } else {
                            meal.components.remove(at: extraIdx)
                        }
                    }
                }
                
                // --- Rule 4: Inter-day Variety Check ---
                let signature = mealSignature(meal)
                if seenSignatures[meal.name, default: []].contains(signature) {
                    onLog?("‼️ Duplicate meal signature detected for \(meal.name) on Day \(dayNumber). Attempting to vary.")
                    var varied = false
                    // Try to vary a side component first
                    if let sideIdx = meal.components.firstIndex(where: { !isProtein($0.name) }) {
                        if let newSide = sideCandidates.first(where: { !meal.components.map({$0.name}).contains($0) }) {
                            let oldSide = meal.components[sideIdx].name
                            meal.components[sideIdx].name = newSide
                            onLog?("🔀 Varied side in Day \(dayNumber) • \(meal.name): '\(oldSide)' → '\(newSide)'.")
                            varied = true
                        }
                    }
                    // If no side could be varied, try the main
                    if !varied, let mainIdx = meal.components.firstIndex(where: { isProtein($0.name) }) {
                        let currentMain = meal.components[mainIdx].name
                        let variants = await aiGenerateVariants(for: currentMain, count: 2, mealName: meal.name, excludedFoods: excludedFoods, onLog: onLog)
                        if let replacement = variants.first(where: { $0.lowercased() != currentMain.lowercased() }) {
                            meal.components[mainIdx].name = replacement
                            onLog?("🔀 Varied main in Day \(dayNumber) • \(meal.name): '\(currentMain)' → '\(replacement)'.")
                        }
                    }
                }
                seenSignatures[meal.name, default: []].insert(mealSignature(meal))
                
                // **MODIFIED**: This rule is now context-aware.
                // --- Rule 5: Component Limits (Context-Aware) ---
                let cuisine = inferCuisineFromMeal(meal: meal)
                let maxCount = maxComponents(for: cuisine)
                if meal.components.count > maxCount {
                    let originalCount = meal.components.count
                    meal.components = trimComponents(
                        components: meal.components,
                        maxCount: maxCount,
                        cuisine: cuisine,
                        onLog: onLog
                    )
                    onLog?("✂️ Trimmed components for Day \(dayNumber) • \(meal.name) from \(originalCount) to \(meal.components.count) (Cuisine: \(cuisine)).")
                }
                
                
                // --- Rule 6: Portion Clamping ---
                meal = clampPortionsHeuristically(for: meal, profile: profile, onLog: onLog)
                
                // --- Update State & Final Meal ---
                polishedPlan.days[dayIndex].meals[mealIndex] = meal
                if meal.components.contains(where: { isSalad($0.name) || isFruit($0.name) }) {
                    dayHasSaladOrFruit = true
                }
            }
            
            // --- Rule 7: Sprinkle Salads/Fruits (Day-level check) ---
            if !dayHasSaladOrFruit {
                if let lunchIndex = polishedPlan.days[dayIndex].meals.firstIndex(where: { $0.name.caseInsensitiveCompare("Lunch") == .orderedSame }),
                   let pick = sideCandidates.randomElement() {
                    polishedPlan.days[dayIndex].meals[lunchIndex].components.append(ConceptualComponent(name: pick, grams: isFruit(pick) ? 150 : 120))
                    onLog?("🥗 Sprinkled '\(pick)' into Day \(dayNumber) Lunch.")
                }
            }
        }
        
        let finalPolishedPlan = await diversifyDescriptiveTitlesIfNeeded(plan: polishedPlan, onLog: onLog)
        
        return finalPolishedPlan
    }
    
    // **NEW**: Helper for `polishConceptualPlan` to infer cuisine
    private func inferCuisineFromMeal(meal: ConceptualMeal) -> String {
        let title = meal.descriptiveTitle.lowercased()
        let componentNames = meal.components.map { $0.name.lowercased() }.joined(separator: " ")
        let combinedText = title + " " + componentNames
        
        if combinedText.contains("ayurvedic") || combinedText.contains("indian") || combinedText.contains("thali") || combinedText.contains("curry") {
            return "Indian/Ayurvedic"
        }
        if combinedText.contains("slovak") || combinedText.contains("banica") {
            return "Slovak"
        }
        if combinedText.contains("italian") || combinedText.contains("pasta") || combinedText.contains("risotto") {
            return "Italian"
        }
        if combinedText.contains("mexican") || combinedText.contains("taco") || combinedText.contains("burrito") {
            return "Mexican"
        }
        if combinedText.contains("chinese") || combinedText.contains("wok") || combinedText.contains("dim sum") {
            return "Chinese"
        }
        if combinedText.contains("japanese") || combinedText.contains("sushi") || combinedText.contains("ramen") {
            return "Japanese"
        }
        return "Generic"
    }
    
    // **NEW**: Helper for `polishConceptualPlan` to get max components
    private func maxComponents(for cuisine: String) -> Int {
        switch cuisine {
        case "Indian/Ayurvedic", "Slovak":
            return 8 // Allow more components for these cuisines
        case "Mexican", "Chinese", "Japanese":
            return 6
        default:
            return 5 // Default for "Generic", "Italian", etc.
        }
    }
    
    // **NEW**: Helper for `polishConceptualPlan` to identify essential ingredients like spices
    private func isEssentialIngredient(name: String, cuisine: String) -> Bool {
        guard cuisine == "Indian/Ayurvedic" else {
            return false // This logic currently only applies to Indian/Ayurvedic food
        }
        let lowercasedName = name.lowercased()
        let spicesAndHerbs: Set<String> = [
            "turmeric", "cumin", "coriander", "cardamom", "clove", "cinnamon", "fenugreek",
            "mustard seed", "fennel seed", "asafoetida", "hing", "ginger", "garlic", "chili",
            "curry leaves", "tamarind", "ashwagandha", "amla", "sesame", "black pepper"
        ]
        
        return spicesAndHerbs.contains { lowercasedName.contains($0) }
    }
    
    // **NEW**: Helper for `polishConceptualPlan` for intelligent trimming
    private func trimComponents(
        components: [ConceptualComponent],
        maxCount: Int,
        cuisine: String,
        onLog: (@Sendable (String) -> Void)?
    ) -> [ConceptualComponent] {
        guard components.count > maxCount else { return components }
        
        var essential: [ConceptualComponent] = []
        var nonEssential: [ConceptualComponent] = []
        
        for component in components {
            if isEssentialIngredient(name: component.name, cuisine: cuisine) {
                essential.append(component)
            } else {
                nonEssential.append(component)
            }
        }
        
        var finalComponents = essential
        let remainingSlots = maxCount - finalComponents.count
        
        if remainingSlots > 0 {
            // Sort non-essential by grams descending to keep the "main" parts
            nonEssential.sort { $0.grams > $1.grams }
            finalComponents.append(contentsOf: nonEssential.prefix(remainingSlots))
        } else {
            // This case happens if there are more essential ingredients than allowed slots
            onLog?("  - NOTE: More essential ingredients than available slots. Trimming essentials.")
            finalComponents = Array(finalComponents.prefix(maxCount))
        }
        
        return finalComponents
    }
    
    // Helper function for polishConceptualPlan to handle portion clamping for a single meal
    private func clampPortionsHeuristically(
        for meal: ConceptualMeal,
        profile: Profile,
        onLog: (@Sendable (String) -> Void)?
    ) -> ConceptualMeal {
        var newMeal = meal
        // This logic is identical to the original, just scoped to a single meal
        func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, x)) }
        func round5(_ x: Double) -> Double { (x / 5.0).rounded() * 5.0 }
        
        let goal = profile.goal
        let (preferLower, preferHighProtein, preferHigherCarb) = (
            goal == .weightLoss,
            [.muscleGain, .strength, .injuryRecovery].contains(goal),
            [.endurance, .sportPerformance].contains(goal)
        )
        
        func has(_ n: String, _ keys: [String]) -> Bool { let l = n.lowercased(); return keys.contains { l.contains($0) } }
        func isProtein(_ n: String) -> Bool { has(n, ["chicken","turkey","salmon","tuna","fish","shrimp","pork","beef","lamb","loin","breast","steak","ham","egg","eggs","tofu","tempeh","lentil","lentils","bean","beans"]) }
        func isStarchy(_ n: String) -> Bool { has(n, ["potato","sweet potato","yuca","cassava","corn","peas","rice","quinoa","pasta","noodle","oat","oatmeal","bread","toast","couscous","bulgur","barley","tortilla","pita","wrap"]) }
        func isDairyDrink(_ n: String) -> Bool { let l = n.lowercased(); return (l.contains("milk") || l.contains("kefir") || l.contains("yogurt drink") || l.contains("smoothie")) && !l.contains("powder") }
        func isCheeseOrYogurt(_ n: String) -> Bool { has(n, ["cheese","mozzarella","cheddar","feta","ricotta","cottage","yogurt","yoghurt","skyr","quark"]) }
        func isNutOrSeed(_ n: String) -> Bool { has(n, ["almond","walnut","hazelnut","peanut","pistachio","cashew","pecan","chia","flax","linseed","sunflower seed","pumpkin seed","sesame"]) }
        func isFruit(_ n: String) -> Bool { has(n, ["apple","banana","orange","grape","grapes","kiwi","pear","berries","berry","blueberry","strawberry","raspberry","mango","pineapple","peach","plum","apricot","watermelon","melon","cherry"]) }
        func isSalad(_ n: String) -> Bool { let l = n.lowercased(); return l.contains("salad") || l.contains("greens") }
        func isVeg(_ n: String) -> Bool { has(n, ["broccoli","spinach","tomato","cucumber","carrot","pepper","bell pepper","capsicum","zucchini","courgette","eggplant","aubergine","lettuce","arugula","rocket","cabbage","cauliflower","asparagus","mushroom","onion","leek"]) }
        func isSoup(_ n: String) -> Bool { let l = n.lowercased(); return l.contains("soup") || l.contains("broth") }
        func isSweetenerOrCondiment(_ n: String) -> Bool { has(n, ["honey","sugar","maple","syrup","jam","jelly","ketchup","mustard","mayo","dressing","sauce","pesto","butter","ghee","cream"]) }
        
        let proteinMax = preferHighProtein ? 220.0 : (preferLower ? 150.0 : 180.0)
        let starchHi = preferHigherCarb ? 240.0 : (preferLower ? 150.0 : 180.0)
        
        for c in 0..<newMeal.components.count {
            let name = newMeal.components[c].name
            var g = newMeal.components[c].grams
            let lower = name.lowercased()
            
            if isSweetenerOrCondiment(lower) { g = clamp(g, 5.0, preferLower ? 15.0 : 20.0) }
            else if isProtein(lower) { g = clamp(g, 90.0, proteinMax) }
            else if isStarchy(lower) { g = clamp(g, preferLower ? 80.0 : 90.0, starchHi) }
            else if isDairyDrink(lower) { g = clamp(g, 200.0, 300.0) }
            else if isCheeseOrYogurt(lower) { g = clamp(g, preferLower ? 20.0 : 25.0, preferLower ? 50.0 : 60.0) }
            else if isNutOrSeed(lower) { g = clamp(g, preferLower ? 15.0 : 20.0, preferLower ? 30.0 : 40.0) }
            else if isSoup(lower) { g = clamp(g, 250.0, 400.0) }
            else if isSalad(lower) { g = clamp(g, 90.0, 180.0) }
            else if isFruit(lower) { g = clamp(g, preferLower ? 100.0 : 120.0, preferLower ? 160.0 : 180.0) }
            else if isVeg(lower) { g = clamp(g, preferLower ? 60.0 : 70.0, preferLower ? 160.0 : 200.0) }
            else { g = clamp(g, preferLower ? 50.0 : 60.0, preferLower ? 180.0 : 200.0) }
            
            newMeal.components[c].grams = round5(g)
        }
        return newMeal
    }
    
    private func clampPortionsHeuristically(
        plan: AIConceptualPlanResponse,
        profile: Profile,
        onLog: (@Sendable (String) -> Void)?
    ) -> AIConceptualPlanResponse {
        var newPlan = plan
        for d in 0..<newPlan.days.count {
            for m in 0..<newPlan.days[d].meals.count {
                newPlan.days[d].meals[m] = clampPortionsHeuristically(for: newPlan.days[d].meals[m], profile: profile, onLog: onLog)
            }
        }
        onLog?("✅ Applied heuristic portion clamping across the plan.")
        return newPlan
    }
    
    @MainActor
    private func isGenericTitle(_ s: String) -> Bool {
        let l = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if l.isEmpty { return true }
        let genericTokens = ["morning", "evening", "balanced", "wellness", "start", "meal", "hearty", "comforting", "light", "nutritious"]
        return genericTokens.contains { l.contains($0) }
    }
    
    @MainActor
    private func aiPolishTitle(for meal: ConceptualMeal, day: Int, onLog: (@Sendable (String) -> Void)?) async -> String? {
        let items = meal.components.map { "\($0.name) (\(Int($0.grams))g)" }.joined(separator: ", ")
        let prompt = """
        You are assisting in a meal plan UI. Rewrite the descriptive title for a \(meal.name) so it is concise (max ~6 words), specific, and cuisine-aware, based on its components.
        Avoid generic words like “morning”, “evening”, “balanced”, “start”, “meal”, “wellness”.
        Keep it natural and non-marketing. Do not include quantities.
        
        MEAL: \(meal.name)
        COMPONENTS: \(items)
        CURRENT TITLE: \(meal.descriptiveTitle.ifEmpty("n/a"))
        
        Respond with a single improved title string.
        """
        do {
            try Task.checkCancellation()
            let session = LanguageModelSession()
            try Task.checkCancellation()
            let resp = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy))
            try Task.checkCancellation()
            let out = resp.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !out.isEmpty, out.count <= 60 else { return nil }
            onLog?("🖋️ Polished title for Day \(day) • \(meal.name): '\(meal.descriptiveTitle)' → '\(out)'")
            return out
        } catch {
            onLog?("   - Title polish skipped (\(error.localizedDescription)).")
            return nil
        }
    }
    
    @MainActor
    private func diversifyDescriptiveTitlesIfNeeded(plan: AIConceptualPlanResponse, onLog: (@Sendable (String) -> Void)?) async -> AIConceptualPlanResponse {
        var out = plan
        for d in 0..<out.days.count {
            for m in 0..<out.days[d].meals.count {
                let t = out.days[d].meals[m].descriptiveTitle
                if isGenericTitle(t) {
                    if let newT = await aiPolishTitle(for: out.days[d].meals[m], day: out.days[d].day, onLog: onLog) {
                        let old = out.days[d].meals[m]
                        out.days[d].meals[m] = ConceptualMeal(name: old.name, descriptiveTitle: newT, components: old.components)
                    }
                }
            }
        }
        return out
    }
    
    private func filterCandidates(_ candidates: [FoodItem], banned: [String]) -> [FoodItem] {
        guard !candidates.isEmpty else { return [] }
        let dynamicBans = banned.map { $0.lowercased() }
        let hardBans = [
            "baby food","infant","toddler","gerber",
            "stage 1","stage 2","stage 3",
            "steelhead",
            "dog food","cat food","pet food"
        ]
        let allBans = Set(dynamicBans + hardBans)
        return candidates.filter { f in
            let name = f.name.lowercased()
            return !allBans.contains { name.contains($0) }
        }
    }
    
    private func debugDumpConceptualPlan(
        _ plan: AIConceptualPlanResponse,
        title: String,
        onLog: (@Sendable (String) -> Void)?
    ) {
        onLog?("──────── \(title) ────────")
        onLog?("Plan: \(plan.planName) • minAge=\(plan.minAgeMonths)mo • days=\(plan.days.count)")
        for d in plan.days.sorted(by: { $0.day < $1.day }) {
            onLog?("  Day \(d.day):")
            for m in d.meals {
                onLog?("    • \(m.name) — '\(m.descriptiveTitle)' (\(m.components.count) items)")
                for c in m.components {
                    onLog?("        - \(c.name) : \(Int(c.grams)) g")
                }
                onLog?("      • signature: \(mealSignature(m))")
            }
        }
        onLog?("────────────────────────────")
    }
    
    private func computeDayMacroTotals(
        day: ConceptualDay,
        nutritionMap: [String: AINutritionInfo]
    ) -> (protein: Double, fat: Double, carbs: Double) {
        var p = 0.0, f = 0.0, c = 0.0
        for meal in day.meals {
            for comp in meal.components {
                guard let info = nutritionMap[comp.name.lowercased()] else { continue }
                p += (info.protein_g / 100.0) * comp.grams
                f += (info.fat_g / 100.0) * comp.grams
                c += (info.carbohydrates_g / 100.0) * comp.grams
            }
        }
        return (p, f, c)
    }
    
    @MainActor
    private func fetchFoodNames(for ids: [PersistentIdentifier]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let ctx = ModelContext(self.container)
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.persistentModelID) })
        let items = (try? ctx.fetch(descriptor)) ?? []
        return items.map { $0.name }
    }
    
    @MainActor private func fetchFoodItem(by id: PersistentIdentifier) -> FoodItem? { let ctx = ModelContext(self.container); return ctx.model(for: id) as? FoodItem }
    private func logInterpretedGoals(_ interpreted: InterpretedPrompts, onLog: (@Sendable (String) -> Void)?) { for goal in interpreted.numericalGoals { onLog?("  -> Interpreted numerical goal: \(goal.nutrient.rawValue) \(goal.constraint) \(goal.value)g") }; for goal in interpreted.qualitativeGoals { onLog?("  -> Interpreted qualitative goal: \(goal)") }; for request in interpreted.structuralRequests { onLog?("  -> Interpreted structural request: \(request)") } }
    private func estimatedDailyCalories(for p: Profile) -> Double { let ageY = Calendar.current.dateComponents([.year], from: p.birthday, to: .now).year ?? 30; let w = max(20, p.weight); let h = max(120, p.height); let base = (p.gender.lowercased() == "female") ? (10*w + 6.25*h - 5*Double(ageY) - 161) : (10*w + 6.25*h - 5*Double(ageY) + 5); let mult = p.activityLevel.rawValue; var tdee = base * mult; if p.isPregnant { tdee += 300 }; if p.isLactating { tdee += 500 }; return max(1400, tdee.rounded()) }
    private func logPreview(_ days: [MealPlanPreviewDay]) { for day in days { print("  -> Day \(day.dayIndex):"); for meal in day.meals { let title = meal.descriptiveTitle ?? meal.name; print("    - Meal: \(meal.name) ('\(title)') (\(meal.items.count) items, \(Int(meal.kcalTotal)) kcal)"); for item in meal.items { print("      - \(item.name), \(Int(item.grams))g, \(Int(item.kcal)) kcal") } } } }
    
    private func mealSignature(_ meal: ConceptualMeal) -> String {
        let names = meal.components.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return names.sorted().joined(separator: "|")
    }
    
    @MainActor
    private func aiGenerateVariantIdeas(
        for baseFood: String,
        count: Int,
        context: String,
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        let session = LanguageModelSession(instructions: Instructions {
            """
            You are a creative culinary assistant. Your task is to generate distinct, realistic variations of a given base food.
            RULES:
            - Generate exactly the requested number of variations.
            - Each variation must be a full, plausible dish name.
            - The variations should be diverse (change fillings, preparation style, or key ingredients).
            - Do not include explanations or bullets; return only the list of names.
            - Ensure the variants are appropriate for the provided meal context (e.g., breakfast, lunch, dinner).
            - **CRITICAL**: Do NOT invent hybrid names by combining the headword with generic dish types unless they are real, well-known dishes. Focus on authentic variations.
            """
        })
        let prompt = """
        Generate \(count) distinct variations of the dish "\(baseFood)" suitable for a \(context) meal.
        """
        do {
            try Task.checkCancellation()
            let response = try await session.respond(
                to: prompt,
                generating: AIVariantListResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            try Task.checkCancellation()
            var seen = Set<String>()
            let variants = response.content.variants.compactMap { variant -> String? in
                let cleaned = variant.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return nil }
                return seen.insert(cleaned.lowercased()).inserted ? cleaned : nil
            }
            try Task.checkCancellation()
            onLog?("  -> Generated \(variants.count) variant ideas for '\(baseFood)': \(variants)")
            return variants
        } catch {
            onLog?("  -> ⚠️ AI variant idea generation failed for '\(baseFood)': \(error.localizedDescription)")
            return []
        }
    }
    
    @MainActor
    private func validateAndSelectBestVariants(
        variantIdeas: [String],
        baseFood: String,
        count: Int,
        smartSearch: SmartFoodSearch,
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        guard !variantIdeas.isEmpty else { return [] }
        var validatedVariants: [String] = []
        
        for idea in variantIdeas {
            if let existing = try? ModelContext(self.container).fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name == idea })).first {
                validatedVariants.append(existing.name)
                onLog?("    - ✅ Validated variant by exact match: '\(existing.name)'")
                continue
            }
            
            let tokenizedWords = FoodItem.makeTokens(from: baseFood)
            let ids = await smartSearch.searchFoodsAI(
                query: idea,
                limit: 5,
                context: "Validating variants for \(baseFood)",
                requiredHeadwords: tokenizedWords
            )
            
            if let bestCandidateID = ids.first, let foodItem = fetchFoodItem(by: bestCandidateID) {
                validatedVariants.append(foodItem.name)
                onLog?("    - ✅ Validated variant by smart search: '\(idea)' -> '\(foodItem.name)'")
            } else {
                onLog?("    - ⚠️ Could not validate variant idea '\(idea)' against the database. It will be created if needed.")
                validatedVariants.append(idea)
            }
        }
        
        var finalSelection: [String] = []
        var seen = Set<String>()
        for variant in validatedVariants {
            if seen.insert(variant.lowercased()).inserted {
                finalSelection.append(variant)
            }
        }
        
        return Array(finalSelection.prefix(count))
    }
    
    @MainActor
    private func aiGenerateVariants(
        for baseDish: String,
        count: Int,
        mealName: String?,
        excludedFoods: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        let cleanCount = max(1, min(count, 7))
        let exclusions = excludedFoods.isEmpty ? "none" : excludedFoods.joined(separator: ", ")
        let meal = mealName ?? "Meal"
        
        let instructions = Instructions {
            """
            You are a culinary planner. Generate realistic, distinct variants of a base dish for a specific meal across different days.
            Rules:
            - Output exactly N full dish names (no bullets, no numbering, no extra prose).
            - Variants must be plausible and diverse (change method, cut, garnish OR style), not just repeat the same words.
            - **CRITICAL**: Do NOT invent hybrid names by combining the headword with generic dish types (e.g., do not create 'Pizza' or 'Risotto' variants unless they are real, well-known dishes). Focus on authentic variations.
            - Respect exclusions/banned ingredients.
            - Avoid returning the base dish name unchanged.
            - Keep names concise; avoid listing long topping lists.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        BASE DISH: \(baseDish)
        MEAL: \(meal)
        EXCLUDED INGREDIENTS: \(exclusions)
        N: \(cleanCount)
        
        Respond with exactly N variant names as an array according to the provided schema.
        """
        
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(
                to: prompt,
                generating: AIVariantListResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content
            try Task.checkCancellation()
            func normalize(_ s: String) -> String {
                return s
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "[\n\t]+", with: " ", options: .regularExpression)
            }
            let baseNorm = baseDish.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var uniq: [String] = []
            var seen = Set<String>()
            for v in resp.variants {
                try Task.checkCancellation()
                let k = normalize(v)
                guard !k.isEmpty else { continue }
                let lc = k.lowercased()
                if lc == baseNorm { continue }
                if seen.insert(lc).inserted { uniq.append(k) }
            }
            try Task.checkCancellation()
            if uniq.count < cleanCount {
                let methods = ["grilled","baked","roasted","steamed","pan-seared","air-fried","poached"]
                let cutsOrForms = ["slices","cubes","fillet","strips","whole","chips","roast"]
                let lightAdds = ["with herbs","with vegetables","with yogurt","with cheese","with tomato","with greens","with spices"]
                
                var i = 0
                while uniq.count < cleanCount && i < 40 {
                    try Task.checkCancellation()
                    let method = methods[i % methods.count]
                    let form = cutsOrForms[(i / methods.count) % cutsOrForms.count]
                    let add = lightAdds[(i / (methods.count * cutsOrForms.count)) % lightAdds.count]
                    let candidate = "\(baseDish) (\(method) \(form)) \(add)"
                    let lc = candidate.lowercased()
                    if lc != baseNorm && !seen.contains(lc) {
                        uniq.append(candidate)
                        seen.insert(lc)
                    }
                    i += 1
                }
            }
            
            if uniq.count < cleanCount {
                var padded = uniq
                while padded.count < cleanCount {
                    try Task.checkCancellation()
                    let candidate = "\(baseDish) (variant \(padded.count + 1))"
                    if !seen.contains(candidate.lowercased()) {
                        padded.append(candidate)
                        seen.insert(candidate.lowercased())
                    }
                }
                onLog?("    - Not enough distinct AI variants for '\(baseDish)'. Added generic placeholders.")
                return padded
            }
            try Task.checkCancellation()
            return Array(uniq.prefix(cleanCount))
        } catch {
            onLog?("    - ⚠️ Variant generation failed for \(baseDish): \(error.localizedDescription). Using generic labels.")
            return (0..<cleanCount).map { "\(baseDish) (variant \($0+1))" }
        }
    }
    
    private func normalizeMealsToRequestedOrder(
        plan: AIConceptualPlanResponse,
        daysAndMeals: [Int: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) -> AIConceptualPlanResponse {
        var newPlan = plan
        for dIdx in 0..<newPlan.days.count {
            let dayNumber = newPlan.days[dIdx].day
            guard let requested = daysAndMeals[dayNumber], !requested.isEmpty else { continue }
            let currentMeals = newPlan.days[dIdx].meals
            var normalized: [ConceptualMeal] = []
            for (i, reqName) in requested.enumerated() {
                if i < currentMeals.count {
                    var m = currentMeals[i]
                    if m.name.caseInsensitiveCompare(reqName) != .orderedSame {
                        let newTitle = m.descriptiveTitle.isEmpty ? m.name : m.descriptiveTitle
                        m = ConceptualMeal(name: reqName, descriptiveTitle: newTitle, components: m.components)
                    }
                    normalized.append(m)
                } else {
                    normalized.append(ConceptualMeal(name: reqName, descriptiveTitle: reqName, components: []))
                }
            }
            newPlan.days[dIdx].meals = normalized
        }
        onLog?("✅ Normalized meal names to requested structure (Breakfast/Lunch/Dinner).")
        return newPlan
    }
    
    private struct MustContainRule: Equatable, Hashable {
        let day: Int
        let meal: String?
        let topic: String
    }
    
    private func parseMustContainRules(_ requests: [String]) -> [MustContainRule] {
        var rules: [MustContainRule] = []
        let rx1 = try! NSRegularExpression(pattern: #"On Day (\d+), the ([A-Za-z]+) meal must contain ([^\.]+)\."#)
        let rx2 = try! NSRegularExpression(pattern: #"On Day (\d+), one meal must contain ([^\.]+)\."#)
        for s in requests {
            if let m = rx1.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let day = Int((s as NSString).substring(with: m.range(at: 1))) ?? 0
                let meal = (s as NSString).substring(with: m.range(at: 2))
                let topic = (s as NSString).substring(with: m.range(at: 3))
                rules.append(.init(day: day, meal: meal, topic: topic))
            } else if let m = rx2.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let day = Int((s as NSString).substring(with: m.range(at: 1))) ?? 0
                let topic = (s as NSString).substring(with: m.range(at: 2))
                rules.append(.init(day: day, meal: nil, topic: topic))
            }
        }
        return rules
    }
    
    private func determineDemographic(for profile: Profile) -> String {
        let age = profile.age
        let ageInMonths = profile.ageInMonths
        let gender = profile.gender.lowercased()
        
        if profile.isPregnant { return Demographic.pregnantWomen }
        if profile.isLactating { return Demographic.lactatingWomen }
        
        if ageInMonths <= 6 { return Demographic.babies0_6m }
        if ageInMonths <= 12 { return Demographic.babies7_12m }
        
        switch age {
        case 1...3:
            return Demographic.children1_3y
        case 4...8:
            return Demographic.children4_8y
        case 9...13:
            return Demographic.children9_13y
        case 14...18:
            return gender == "female" ? Demographic.adolescentFemales14_18y : Demographic.adolescentMales14_18y
        case 19...50:
            return gender == "female" ? Demographic.adultWomen19_50y : Demographic.adultMen19_50y
        case 51...:
            return gender == "female" ? Demographic.adultWomen51plusY : Demographic.adultMen51plusY
        default:
            // Fallback за възраст над 18, ако друга логика не успее
            return gender == "female" ? Demographic.adultWomen19_50y : Demographic.adultMen19_50y
        }
    }
}



fileprivate func isMetaDirective(_ text: String) -> Bool {
    let t = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    if t.isEmpty { return false }
    let patterns: [String] = [
        #"^no other (menu|menus|options|cuisines?)$"#,
        #"^no other menu options$"#,
        #"^no other (menu\s+options|cuisine\s+options)$"#,
        #"^do not include other (menu|menus|cuisines?)$"#,
        #"^avoid other (menu|menus|cuisines?)$"#,
        #"^(keep|stick)\s+to\s+(this|the)\s+(menu|cuisine)$"#,
        #"^exclusively\s+(this|the)\s+(menu|cuisine)$"#,
        #"^(only|just)\s+(italian|this|the)\s+(menu|cuisine)$"#,
        #"^only\s+italian(\s+menu)?$"#,
        #".*\bno other (menu|menus|menu\s+options|cuisine|cuisines|options)\b.*"#,

    ]
    for p in patterns {
        if t.range(of: p, options: .regularExpression) != nil { return true }
    }
    return false
}

fileprivate func filterMetaDirectives(_ items: [String]) -> [String] {
    items.filter { !isMetaDirective($0) }
}

