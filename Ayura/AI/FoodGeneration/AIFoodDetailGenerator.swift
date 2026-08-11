import Foundation
import SwiftData
import FoundationModels

// MARK: - Main Generator Class

@MainActor
class AIFoodDetailGenerator {
    private let globalTaskManager = GlobalTaskManager.shared
    private let foodSearcher: SmartFoodSearch3
    
    // Инициализаторът вече приема ModelContainer, за да създаде SmartFoodSearch
    init(container: ModelContainer) {
        self.foodSearcher = SmartFoodSearch3(container: container)
    }
    
    private func loadUserSettings(from ctx: ModelContext) -> UserSettings? {
        do {
            let descriptor = FetchDescriptor<UserSettings>()
            return try ctx.fetch(descriptor).first
        } catch {
            print("⚠️ Failed to fetch UserSettings: \(error)")
            return nil
        }
    }

    
    @available(iOS 26.0, *)
    func generateDetails(
        for foodName: String,
        ctx: ModelContext,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> FoodItemDTO {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let diff = CFAbsoluteTimeGetCurrent() - start
            print("⏱️ Завърши за \(diff) секунди")
        }

        guard !AyurvedaRecommendationGate.nameIsExcluded(foodName, context: ctx) else {
            onLog?("🚫 AyurvedaGate: dropped excluded generated food '\(foodName)'")
            throw NSError(domain: "AyurvedaRecommendationGate", code: 1, userInfo: [NSLocalizedDescriptionKey: "This food is not available for recommendations."])
        }
        
        onLog?("🚀 Starting AI data generation for '\(foodName)' (PARALLEL, FRESH session per step, with retries)…")
        
        
        let baseInstructions = """
        You are a structured nutrition assistant. For EACH prompt:
        - Reply ONLY with JSON matching the provided schema (no extra keys, no prose).
        - Obey units and constraints stated in the prompt or in the schema guides.
        - All numeric values MUST be for the RAW, EDIBLE PORTION **per 100 g exactly** (weightG = { "value": 100, "unit": "g" }).
        - NEVER use per-serving, per-cup, per-piece, or cooked values unless explicitly requested; if you recall such values, convert them to per 100 g before answering.
        - If a well-known nutrient is characteristically high for the food (e.g., vitamin C in bell peppers), do not return implausibly low numbers.
        - Treat every prompt as independent from chat history; do not reuse prior outputs.
        - FOOD IDENTITY IS STRICT:
          - The provided food name is the exact item. DO NOT substitute synonyms, varieties, colors, species, cultivars, or cooking/processing forms.
          - If a term could refer to related items (e.g., \(foodName)), assume it refers to **exactly** the literal name provided and nothing else.
        - CRITICAL OUTPUT RULES:
          - Never output strings like "N/A", "NA", "nan", "null", or objects missing required fields.
          - Empty strings are allowed only when a schema field explicitly asks for one; nutrient units must never be empty.
          - If the nutrient is absent/unknown/not detected, return EXACTLY zero in the correct unit (e.g., { "value": 0, "unit": "g" }).
          - Values must be finite numbers (no Infinity/NaN), non-negative, and plausible for **per 100 g**.
        """
        
        @Sendable func makeSession() -> LanguageModelSession {
            LanguageModelSession(instructions: baseInstructions)
        }
        
        // --- START: Търсене на подобна храна ---
        onLog?("  🔎 Fetching up to 20 potential reference foods…")
        
        // 2. Търсим кандидати
        let fetchedCandidates = await foodSearcher.searchResults(
            query: foodName,
            limit: 20
        )
        let excludedFoodIds = AyurvedaRecommendationGate.excludedFoodIds(context: ctx)
        let candidates = fetchedCandidates.filter { !excludedFoodIds.contains($0.id) }
        onLog?("🚫 AyurvedaGate: AyurvedaGate active, \(fetchedCandidates.count - candidates.count) candidates filtered")
        
        var similarFood: FoodItem?
        
        if !candidates.isEmpty {
            let candidateNames = candidates.map { $0.name }
            
            // ПРИНТ ЗА ДЕБЪГ: Виж кои са кандидатите
            print("📋 [DEBUG] Намерени кандидати: \(candidateNames)")
            
            onLog?("  🧠 Asking AI to select the best match from \(candidateNames.count) candidates…")
            
            // 3. Създаваме промпт за избор
            let selectionSession = makeSession()
            
            let selectionPrompt = """
                    From the list below, which is the SINGLE most semantically similar and appropriate food item to be used as a nutritional reference for "\(foodName)"?
                    
                    CRITICAL:
                    - The match must be extremely close. For example, "apple" and "apple juice" are NOT good matches. "Raw chicken breast" and "cooked chicken breast" are NOT good matches.
                    - If no item in the list is a very close match, return null for the 'bestMatch' field.
                    - Respond ONLY with the exact name from the list. Do not invent new names.
                    
                    Candidate Names:
                    \(candidateNames.map { "- \($0)" }.joined(separator: "\n"))
                    """
            
            // 4. Изпращаме запитването към езиковия модел
            do {
                let selectionResult = try await selectionSession.respond(
                    to: selectionPrompt,
                    generating: AIBestMatchResponse.self,
                    includeSchemaInPrompt: true
                ).content
                
                if let bestMatchName = selectionResult.bestMatch, !bestMatchName.isEmpty {
                    // 5. Намираме избрания FoodItem в нашия списък
                    if let foundFood = candidates.first(where: { $0.name == bestMatchName }) {
                        similarFood = foundFood
                        
                        // ✅ ТУК Е ИЗРИЧНИЯТ ПРИНТ
                        print("\n🎯 [AI MATCH] ИЗБРАН КАНДИДАТ: \(foundFood.name)\n")
                        
                        onLog?("  ✅ AI selected reference food: '\(foundFood.name)'")
                    } else {
                        print("⚠️ AI върна име '\(bestMatchName)', което не е в списъка с кандидати.")
                        onLog?("  ⚠️ AI returned a name ('\(bestMatchName)') not found in the candidate list. Proceeding without reference.")
                    }
                } else {
                    print("ℹ️ AI реши, че няма подходящ кандидат.")
                    onLog?("  ℹ️ AI concluded no candidate is a good match. Proceeding without reference food.")
                }
            } catch {
                onLog?("  ⚠️ AI selection step failed: \(error.localizedDescription)")
            }
        } else {
            print("ℹ️ Търсачката не върна никакви резултати за '\(foodName)'.")
            onLog?("  ℹ️ No similar foods found in the initial search.")
        }
        // Базови инструкции – държим ги в променлива, за да можем да създаваме fresh session-и при ретраели.
        
        
        // Will be filled after we generate the first-step description.
        var sharedPromptPrefix = ""
        
        let greedyOptions = GenerationOptions(sampling: .greedy, maximumResponseTokens: 64)
        // 🔧 UserSettings → кои „тежки“ детайли да се генерират
        let settings = loadUserSettings(from: ctx)

        // Ако няма UserSettings, можеш да решиш какъв да е default.
        // Аз слагам `true`, за да не счупим текущото поведение.
        // Ако искаш по default да НЯМА детайлни полета – смени на `false`.
        let shouldGenerateLipids       = settings?.generateLipids       ?? true
        let shouldGenerateAminoAcids   = settings?.generateAminoAcids   ?? true
        let shouldGenerateCarbDetails  = settings?.generateCarbDetails  ?? true
        let shouldGenerateSterols      = settings?.generateSterols      ?? true

        @Sendable func shortPause() async { try? await Task.sleep(nanoseconds: 300_000_000) }
        
        /// Универсален helper с retry, експоненциален бекоф и **fresh session при всеки опит**.
        func askWithRetry<T: Decodable & Generable>(
            _ step: String,
            _ prompt: String,
            generating: T.Type,
            retries: Int = 5,
            backoffMs: Int = 400,
            salvageAfter: Int = 3,
            maxTokens: Int? = nil,
            salvage: (() async throws -> T)? = nil
        ) async throws -> T {
            var attempt = 0
            var lastError: Error?
            
            while attempt <= retries {
                try Task.checkCancellation() // <-- ДОБАВЕТЕ ТОВА
                
                attempt += 1
                // ... останалата част от функцията остава същата ...
                if attempt == 1 {
                    onLog?("  -> \(step) …")
                } else {
                    onLog?("  ↻ \(step) retry \(attempt)/\(retries + 1)…")
                }
                
                let localSession: LanguageModelSession = makeSession()
                
                do {
                    let fullPrompt = sharedPromptPrefix.isEmpty ? prompt : "\(sharedPromptPrefix)\n\n\(prompt)"
                    let opts = GenerationOptions(
                        sampling: .greedy,
                        maximumResponseTokens: maxTokens ?? greedyOptions.maximumResponseTokens! * attempt
                    )
                    let result = try await localSession.respond(
                        to: fullPrompt,
                        generating: T.self,
                        includeSchemaInPrompt: true,
                        options: opts
                    ).content
                    onLog?("  ✅ \(step) ✓ (attempt \(attempt))")
                    await shortPause()
                    return result
                } catch {
                    lastError = error
                    onLog?("  ⚠️ \(step) failed on attempt \(attempt): \(error.localizedDescription)")
                    
                    if attempt >= salvageAfter, let salvage = salvage {
                        onLog?("  🛟 \(step): switching to salvage mode (narrow schema)…")
                        return try await salvage()
                    }
                    
                    if attempt <= retries {
                        let rawDelay = Int(Double(backoffMs) * pow(1.8, Double(attempt - 1)))
                        let delayMs = min(rawDelay, 60_000)
                        onLog?("     …retrying after ~\(delayMs) ms with a fresh session")
                        try? await Task.sleep(for: .milliseconds(delayMs)) // По-модерен синтаксис
                        continue
                    }
                }
            }
            
            throw lastError ?? NSError(domain: "AIGenerationError", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Unknown error in \(step)"])
        }
        
        func askWithRetryOrNil<T: Decodable & Generable>(
            _ step: String,
            _ prompt: String,
            generating: T.Type,
            retries: Int = 5,
            backoffMs: Int = 400,
            salvageAfter: Int = 3,
            maxTokens: Int? = nil,
            salvage: (() async throws -> T)? = nil
        ) async -> T? {
            do {
                return try await askWithRetry(
                    step,
                    prompt,
                    generating: generating,
                    retries: retries,
                    backoffMs: backoffMs,
                    salvageAfter: salvageAfter,
                    maxTokens: maxTokens,
                    salvage: salvage
                )
            } catch {
                onLog?("  ⛔️ \(step) exhausted \(retries + 1) attempts → returning nil")
                return nil
            }
        }
        
        // --- (nameSimilarity и magnitudeBucket са извън refactoring-а, пропускам ги за краткост) ---
        
        func createPromptWithReference(basePrompt: String, referenceValue: Nutrient?) -> String {
            guard
                let ref = referenceValue,
                let unit = ref.unit?.trimmingCharacters(in: .whitespacesAndNewlines),
                let simName = similarFood?.name
            else {
                return basePrompt
            }
            
            // изискваме прилична близост между имената, иначе не подаваме контекст
            let simScore = nameSimilarity(simName, foodName)
            let similarEnough = simScore >= 0.6   // емпирично добър праг
            
            guard similarEnough else { return basePrompt }
            
            let v = ref.value ?? 0
            let bucket = magnitudeBucket(value: v, unit: unit)
            
            // НЕ подаваме число, само „величина“ и изрично казваме да се игнорира при противоречие
            return """
            \(basePrompt)
            
            CONTEXT (rough magnitude only — do NOT copy numbers or units):
            - A nearby DB item "\(simName)" suggests this nutrient is \(bucket) for similar foods.
            - This is a plausibility hint. If this contradicts the strict identity of "\(foodName)", IGNORE it.
            """
        }
        
        // MARK: 1) Description (Последователно – задава се global context)
        var descBase = """
        Write a concise, friendly description for the EXACT food name '\(foodName)'. Do not reinterpret or substitute with related varieties (colors/species) or processed forms.
        Return ONLY the 'description' field as per the schema.
        """
        if let sim = similarFood?.name {
            descBase += "\n\nNOTE: A nearby reference item in the DB is '\(sim)'. Do NOT copy its description; keep identity strict."
        }
        let descResp: AIDescriptionResponse = try await askWithRetry(
            "Description",
            descBase,
            generating: AIDescriptionResponse.self,
            maxTokens: 512
        )
        try Task.checkCancellation()
        // Make the first-step description available to all subsequent prompts.
        sharedPromptPrefix = """
        Food identity (STRICT — no substitution):
        - EXACT name (do not reinterpret or generalize): \(foodName)
        - Use RAW, edible portion **per 100 g exactly**.
        - Do NOT switch to another color/variety/species or to cooked/processed forms.
        
        Output must follow the JSON schema and units precisely. No prose. No extra keys.
        """
        
        let refName: String? = similarFood?.name
        let refMinAge: Int?  = similarFood?.minAgeMonths
        // 2) Построяваме промптовете предварително, като вмъкваме контекста само ако е наличен
        let minAgePrompt = """
        You are a pediatric nutrition specialist.
        Provide 'minAgeMonths' for '\(foodName)' as an integer.
        If the food is suitable for all ages, return 0.
        Return ONLY the 'minAgeMonths' field.\( (refName != nil && refMinAge != nil) ? "\n\nCONTEXT: For reference, similar food '\(refName!)' has minAgeMonths = \(refMinAge!). Use for plausibility only." : "" )
        """
        
        let allergensPrompt = """
        List the common allergens present in the food '\(foodName)'.
        Return ONLY the 'allergens' array using the provided enum values.\( (refName != nil) ? "\n\nNOTE: Similar reference '\(refName!)'. Use only as plausibility; do not fabricate allergens." : "" )
        """

        let safetyAyurvedaPrompt = """
        Classify the EXACT item '\(foodName)' for food safety and Ayurvedic metadata.

        Rules:
        - Do not substitute a related species, color, preparation, extract, or supplement.
        - Ayurveda values are review-required estimates. Prefer conservative/neutral values when evidence is weak.
        - Dosha, agniEffect, and digestibility values MUST be integers in -2...2.
        - Use only the vocabularies stated in the schema guides for rasa, virya, vipaka, and gunas.
        - Do not make medical-treatment claims.
        - Return every schema field. Use empty strings/arrays only where the guide explicitly permits them.
        """
        
        // 3) Паралелни задачи без директен capture на similarFood
        // вместо async let ... = askWithRetry(...)
        
        let minAgeTask = Task<AIMinAgeResponse, Error> {
            try await askWithRetry(
                "Min Age (months)",
                minAgePrompt,
                generating: AIMinAgeResponse.self
            )
        }
        await globalTaskManager.addTask(minAgeTask)
        try Task.checkCancellation()
        let allergensTask = Task<AIAllergensResponse, Error> {
            try await askWithRetry(
                "Allergens",
                allergensPrompt,
                generating: AIAllergensResponse.self,
                maxTokens: 512
            )
        }
        try Task.checkCancellation()
        await globalTaskManager.addTask(allergensTask)
        let safetyAyurvedaTask = Task<AIFoodSafetyAyurvedaResponse, Error> {
            try await askWithRetry(
                "Safety & Ayurveda",
                safetyAyurvedaPrompt,
                generating: AIFoodSafetyAyurvedaResponse.self,
                maxTokens: 1600
            )
        }
        await globalTaskManager.addTask(safetyAyurvedaTask)
        try Task.checkCancellation()
        // и тук вместо tuple-await на async let:
        let minAgeResp = try await minAgeTask.value
        let allergensResp = try await allergensTask.value
        let safetyAyurvedaResp = try await safetyAyurvedaTask.value
        
        // MARK: 6) Macronutrients - PARALLEL BATCH 2
        let carbohydratesPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName) (RAW, edible portion). Return ONLY the field 'carbohydrates' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.totalCarbohydrates
        )
        let proteinPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName) (RAW, edible portion). Return ONLY the field 'protein' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.totalProtein
        )
        let fatPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName) (RAW, edible portion). Return ONLY the field 'fat' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.totalFat
        )
        let fiberPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName) (RAW, edible portion). Return ONLY the field 'fiber' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.macronutrients?.fiber
        )
        let totalSugarsPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName) (RAW, edible portion). Return ONLY the field 'totalSugars' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.macronutrients?.totalSugars
        )
        
        // 2) Пускаме паралелните задачи без директен capture на similarFood
        let carbohydratesTask = Task<AICarbohydratesResponse, Error> {
            try await askWithRetry(
                "Macros → Carbohydrates (g/100g)",
                carbohydratesPrompt,
                generating: AICarbohydratesResponse.self
            )
        }
        await globalTaskManager.addTask(carbohydratesTask)
        try Task.checkCancellation()
        let proteinTask = Task<AIProteinResponse, Error> {
            try await askWithRetry(
                "Macros → Protein (g/100g)",
                proteinPrompt,
                generating: AIProteinResponse.self
            )
        }
        await globalTaskManager.addTask(proteinTask)
        try Task.checkCancellation()
        let fatTask = Task<AIFatResponse, Error> {
            try await askWithRetry(
                "Macros → Fat (g/100g)",
                fatPrompt,
                generating: AIFatResponse.self
            )
        }
        await globalTaskManager.addTask(fatTask)
        try Task.checkCancellation()
        let fiberTask = Task<AIFiberResponse, Error> {
            try await askWithRetry(
                "Macros → Fiber (g/100g)",
                fiberPrompt,
                generating: AIFiberResponse.self
            )
        }
        await globalTaskManager.addTask(fiberTask)
        try Task.checkCancellation()
        let totalSugarsTask = Task<AITotalSugarsResponse, Error> {
            try await askWithRetry(
                "Macros → Total Sugars (g/100g)",
                totalSugarsPrompt,
                generating: AITotalSugarsResponse.self
            )
        }
        await globalTaskManager.addTask(totalSugarsTask)
        try Task.checkCancellation()
        // 3) Await на резултатите (без tuple-await на async let)
        let carbohydrates = try await carbohydratesTask.value
        let protein       = try await proteinTask.value
        let fat           = try await fatTask.value
        let fiber         = try await fiberTask.value
        let totalSugars   = try await totalSugarsTask.value
        try Task.checkCancellation()
        
        let macrosMerged = AIMacronutrients(
            carbohydrates: carbohydrates.carbohydrates,
            protein:       protein.protein,
            fat:           fat.fat,
            fiber:         fiber.fiber,
            totalSugars:   totalSugars.totalSugars
        )
        let macros = AIMacrosResponse(macronutrients: macrosMerged)
        
        // MARK: 7) Other (alcohol, caffeine, energy, water, etc.) - PARALLEL BATCH 3
        let alcoholPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'alcoholEthyl' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.alcoholEthyl
        )
        let caffeinePrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'caffeine' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.caffeine
        )
        let theobrominePrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'theobromine' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.theobromine
        )
        let cholesterolPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'cholesterol' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.cholesterol
        )
        let energyPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'energyKcal' as JSON with { value: <number>, unit: 'kcal' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.energyKcal
        )
        let waterPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'water' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.water
        )
        let weightPrompt = """
        Food: \(foodName). Return ONLY the field 'weightG' as JSON with { value: 100, unit: 'g' }.
        CRITICAL: It MUST be exactly 100 (value: 100, unit: 'g'). No prose. No other keys.
        """
        let ashPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'ash' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.ash
        )
        let betainePrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'betaine' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.other?.betaine
        )
        
        let alkalinityPHPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'alkalinityPH' as JSON with { value: <number>, unit: 'pH' }. If the food is neutral, use 7.0. No prose. No other keys.",
            referenceValue: similarFood?.other?.alkalinityPH // Предполагаме, че моделът FoodItem ще има това поле
        )
        
        // 2) Паралелни задачи с Task{ }
        let alcoholTask = Task<AIAlcoholEthylResponse, Error> {
            try await askWithRetry("Other → Alcohol (g/100g)", alcoholPrompt, generating: AIAlcoholEthylResponse.self)
        }
        await globalTaskManager.addTask(alcoholTask)
        try Task.checkCancellation()
        let caffeineTask = Task<AICaffeineResponse, Error> {
            try await askWithRetry("Other → Caffeine (mg/100g)", caffeinePrompt, generating: AICaffeineResponse.self)
        }
        await globalTaskManager.addTask(caffeineTask)
        try Task.checkCancellation()
        let theobromineTask = Task<AITheobromineResponse, Error> {
            try await askWithRetry("Other → Theobromine (mg/100g)", theobrominePrompt, generating: AITheobromineResponse.self)
        }
        await globalTaskManager.addTask(theobromineTask)
        try Task.checkCancellation()
        let cholesterolTask = Task<AICholesterolResponse, Error> {
            try await askWithRetry("Other → Cholesterol (mg/100g)", cholesterolPrompt, generating: AICholesterolResponse.self)
        }
        await globalTaskManager.addTask(cholesterolTask)
        try Task.checkCancellation()
        let energyTask = Task<AIEnergyKcalResponse, Error> {
            try await askWithRetry("Other → Energy (kcal/100g)", energyPrompt, generating: AIEnergyKcalResponse.self)
        }
        await globalTaskManager.addTask(energyTask)
        try Task.checkCancellation()
        let waterTask = Task<AIWaterResponse, Error> {
            try await askWithRetry("Other → Water (g/100g)", waterPrompt, generating: AIWaterResponse.self)
        }
        await globalTaskManager.addTask(waterTask)
        try Task.checkCancellation()
        let weightTask = Task<AIWeightGResponse, Error> {
            try await askWithRetry("Other → WeightG (MUST be exactly 100 g)", weightPrompt, generating: AIWeightGResponse.self)
        }
        await globalTaskManager.addTask(weightTask)
        try Task.checkCancellation()
        let ashTask = Task<AIAshResponse, Error> {
            try await askWithRetry("Other → Ash (g/100g)", ashPrompt, generating: AIAshResponse.self)
        }
        await globalTaskManager.addTask(ashTask)
        try Task.checkCancellation()
        let betaineTask = Task<AIBetaineResponse, Error> {
            try await askWithRetry("Other → Betaine (mg/100g)", betainePrompt, generating: AIBetaineResponse.self)
        }
        await globalTaskManager.addTask(betaineTask)
        try Task.checkCancellation()
        
        let alkalinityPHTask = Task<AIAlkalinityPHResponse, Error> {
            try await askWithRetry("Other → Alkalinity (pH)", alkalinityPHPrompt, generating: AIAlkalinityPHResponse.self)
        }
        await globalTaskManager.addTask(alkalinityPHTask)
        try Task.checkCancellation()
        
        
        let alkalinityPHResponse = try await alkalinityPHTask.value
        
        var alkalinityP = alkalinityPHResponse
        let rawPH = alkalinityP.alkalinityPH.value
        
        let clampedPH = min(14.0, max(0.0, rawPH))
        alkalinityP.alkalinityPH.value = clampedPH
        // 3) Await на резултатите (избягваме tuple-await)
        let alcohol     = try await alcoholTask.value
        let caffeine    = try await caffeineTask.value
        let theobromine = try await theobromineTask.value
        let cholesterol = try await cholesterolTask.value
        let energy      = try await energyTask.value
        let water       = try await waterTask.value
        let varWeight   = try await weightTask.value
        let ash         = try await ashTask.value
        let betaine     = try await betaineTask.value
        let alkalinityPH = alkalinityP
        try Task.checkCancellation()
        
        // Валидация на weightG
        var weight = varWeight
        func isWeightExactly100(_ w: AIWeightGResponse) -> Bool {
            (abs(w.weightG.value - 100.0) < 0.0001) && (w.weightG.unit.lowercased() == "g")
        }
        if !isWeightExactly100(weight) {
            onLog?("  ⚠️ weightG validation failed: got \(weight.weightG.value) \(weight.weightG.unit), expected 100 g. Retrying STRICT with fresh session…")
            weight = try await askWithRetry(
                "Other → WeightG STRICT (exactly 100 g)",
                """
                Food: \(foodName).
                Return ONLY 'weightG' as JSON with { value: 100, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.
                """,
                generating: AIWeightGResponse.self,
                retries: 1,
                backoffMs: 500
            )
        }
        if !isWeightExactly100(weight) {
            onLog?("❌ weightG validation failed (strict): got \(weight.weightG.value) \(weight.weightG.unit), expected 100 g")
            throw NSError(domain: "AIGenerationError", code: 1012, userInfo: [NSLocalizedDescriptionKey: "Invalid weightG — must be exactly 100 g."])
        }
        
        let othersMerged = AIOtherCompounds(
            alcoholEthyl: alcohol.alcoholEthyl,
            caffeine:     caffeine.caffeine,
            theobromine:  theobromine.theobromine,
            cholesterol:  cholesterol.cholesterol,
            energyKcal:   energy.energyKcal,
            water:        water.water,
            weightG:      weight.weightG,
            ash:          ash.ash,
            betaine:      betaine.betaine,
            alkalinityPH: alkalinityPH.alkalinityPH
        )
        let others = AIOtherResponse(other: othersMerged)
        
        // MARK: 8) Vitamins - PARALLEL BATCH 4
        let vitA_RAEPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminA_RAE' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminA_RAE
        )
        let retinolPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'retinol' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.retinol
        )
        let carAPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'caroteneAlpha' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.caroteneAlpha
        )
        let carBPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'caroteneBeta' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.caroteneBeta
        )
        let crypBPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'cryptoxanthinBeta' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.cryptoxanthinBeta
        )
        let lutZeaPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'luteinZeaxanthin' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.luteinZeaxanthin
        )
        let lycoPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'lycopene' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.lycopene
        )
        let b1Prompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminB1_Thiamin' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminB1_Thiamin
        )
        let b2Prompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminB2_Riboflavin' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminB2_Riboflavin
        )
        let b3Prompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminB3_Niacin' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminB3_Niacin
        )
        let b5Prompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminB5_PantothenicAcid' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminB5_PantothenicAcid
        )
        let b6Prompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminB6' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminB6
        )
        let folDFEPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'folateDFE' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.folateDFE
        )
        let folFoodPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'folateFood' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.folateFood
        )
        let folTotalPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'folateTotal' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.folateTotal
        )
        let folicAcidPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'folicAcid' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.folicAcid
        )
        let b12Prompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminB12' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminB12
        )
        let vitCPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName) (RAW, edible portion). Return ONLY the field 'vitaminC' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. Double-check you are using per 100 g numbers. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminC
        )
        let vitDPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminD' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminD
        )
        let vitEPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminE' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminE
        )
        let vitKPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'vitaminK' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.vitaminK
        )
        let cholinePrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'choline' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.vitamins?.choline
        )
        
        let vitA_RAETask = Task<AIVitA_RAE_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminA_RAE (µg/100g)", vitA_RAEPrompt, generating: AIVitA_RAE_Resp.self)
        }
        await globalTaskManager.addTask(vitA_RAETask)
        try Task.checkCancellation()
        
        let retinolTask = Task<AIRetinol_Resp, Error> {
            try await askWithRetry("Vitamins → retinol (µg/100g)", retinolPrompt, generating: AIRetinol_Resp.self)
        }
        await globalTaskManager.addTask(retinolTask)
        try Task.checkCancellation()
        
        let carATask = Task<AICaroteneAlpha_Resp, Error> {
            try await askWithRetry("Vitamins → caroteneAlpha (µg/100g)", carAPrompt, generating: AICaroteneAlpha_Resp.self)
        }
        await globalTaskManager.addTask(carATask)
        try Task.checkCancellation()
        
        let carBTask = Task<AICaroteneBeta_Resp, Error> {
            try await askWithRetry("Vitamins → caroteneBeta (µg/100g)", carBPrompt, generating: AICaroteneBeta_Resp.self)
        }
        await globalTaskManager.addTask(carBTask)
        try Task.checkCancellation()
        
        let crypBTask = Task<AICryptoxanthinBeta_Resp, Error> {
            try await askWithRetry("Vitamins → cryptoxanthinBeta (µg/100g)", crypBPrompt, generating: AICryptoxanthinBeta_Resp.self)
        }
        await globalTaskManager.addTask(crypBTask)
        try Task.checkCancellation()
        
        let lutZeaTask = Task<AILuteinZeaxanthin_Resp, Error> {
            try await askWithRetry("Vitamins → luteinZeaxanthin (µg/100g)", lutZeaPrompt, generating: AILuteinZeaxanthin_Resp.self)
        }
        await globalTaskManager.addTask(lutZeaTask)
        try Task.checkCancellation()
        
        let lycoTask = Task<AILycopene_Resp, Error> {
            try await askWithRetry("Vitamins → lycopene (µg/100g)", lycoPrompt, generating: AILycopene_Resp.self)
        }
        await globalTaskManager.addTask(lycoTask)
        try Task.checkCancellation()
        
        let b1Task = Task<AIVitB1_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminB1_Thiamin (mg/100g)", b1Prompt, generating: AIVitB1_Resp.self)
        }
        await globalTaskManager.addTask(b1Task)
        try Task.checkCancellation()
        
        let b2Task = Task<AIVitB2_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminB2_Riboflavin (mg/100g)", b2Prompt, generating: AIVitB2_Resp.self)
        }
        await globalTaskManager.addTask(b2Task)
        try Task.checkCancellation()
        
        let b3Task = Task<AIVitB3_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminB3_Niacin (mg/100g)", b3Prompt, generating: AIVitB3_Resp.self)
        }
        await globalTaskManager.addTask(b3Task)
        try Task.checkCancellation()
        
        let b5Task = Task<AIVitB5_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminB5_PantothenicAcid (mg/100g)", b5Prompt, generating: AIVitB5_Resp.self)
        }
        await globalTaskManager.addTask(b5Task)
        try Task.checkCancellation()
        
        let b6Task = Task<AIVitB6_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminB6 (mg/100g)", b6Prompt, generating: AIVitB6_Resp.self)
        }
        await globalTaskManager.addTask(b6Task)
        try Task.checkCancellation()
        
        let folDFETask = Task<AIFolateDFE_Resp, Error> {
            try await askWithRetry("Vitamins → folateDFE (µg/100g)", folDFEPrompt, generating: AIFolateDFE_Resp.self)
        }
        await globalTaskManager.addTask(folDFETask)
        try Task.checkCancellation()
        
        let folFoodTask = Task<AIFolateFood_Resp, Error> {
            try await askWithRetry("Vitamins → folateFood (µg/100g)", folFoodPrompt, generating: AIFolateFood_Resp.self)
        }
        await globalTaskManager.addTask(folFoodTask)
        try Task.checkCancellation()
        
        let folTotalTask = Task<AIFolateTotal_Resp, Error> {
            try await askWithRetry("Vitamins → folateTotal (µg/100g)", folTotalPrompt, generating: AIFolateTotal_Resp.self)
        }
        await globalTaskManager.addTask(folTotalTask)
        try Task.checkCancellation()
        
        let folicAcidTask = Task<AIFolicAcid_Resp, Error> {
            try await askWithRetry("Vitamins → folicAcid (µg/100g)", folicAcidPrompt, generating: AIFolicAcid_Resp.self)
        }
        await globalTaskManager.addTask(folicAcidTask)
        try Task.checkCancellation()
        
        let b12Task = Task<AIVitB12_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminB12 (µg/100g)", b12Prompt, generating: AIVitB12_Resp.self)
        }
        await globalTaskManager.addTask(b12Task)
        try Task.checkCancellation()
        
        let vitCTask = Task<AIVitC_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminC (mg/100g)", vitCPrompt, generating: AIVitC_Resp.self)
        }
        await globalTaskManager.addTask(vitCTask)
        try Task.checkCancellation()
        
        let vitDTask = Task<AIVitD_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminD (µg/100g)", vitDPrompt, generating: AIVitD_Resp.self)
        }
        await globalTaskManager.addTask(vitDTask)
        try Task.checkCancellation()
        
        let vitETask = Task<AIVitE_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminE (mg/100g)", vitEPrompt, generating: AIVitE_Resp.self)
        }
        await globalTaskManager.addTask(vitETask)
        try Task.checkCancellation()
        
        let vitKTask = Task<AIVitK_Resp, Error> {
            try await askWithRetry("Vitamins → vitaminK (µg/100g)", vitKPrompt, generating: AIVitK_Resp.self)
        }
        await globalTaskManager.addTask(vitKTask)
        try Task.checkCancellation()
        
        let cholineTask = Task<AICholine_Resp, Error> {
            try await askWithRetry("Vitamins → choline (mg/100g)", cholinePrompt, generating: AICholine_Resp.self)
        }
        await globalTaskManager.addTask(cholineTask)
        try Task.checkCancellation()
        
        // 3) Await на резултатите (без tuple-await)
        let vitA_RAE   = try await vitA_RAETask.value
        let retinol    = try await retinolTask.value
        let carA       = try await carATask.value
        let carB       = try await carBTask.value
        let crypB      = try await crypBTask.value
        let lutZea     = try await lutZeaTask.value
        let lyco       = try await lycoTask.value
        let b1         = try await b1Task.value
        let b2         = try await b2Task.value
        let b3         = try await b3Task.value
        let b5         = try await b5Task.value
        let b6         = try await b6Task.value
        let folDFE     = try await folDFETask.value
        let folFood    = try await folFoodTask.value
        let folTotal   = try await folTotalTask.value
        let folicAcid  = try await folicAcidTask.value
        let b12        = try await b12Task.value
        let vitC       = try await vitCTask.value
        let vitD       = try await vitDTask.value
        let vitE       = try await vitETask.value
        let vitK       = try await vitKTask.value
        let choline    = try await cholineTask.value
        try Task.checkCancellation()
        
        let vitaminsMerged = AIVitamins(
            vitaminA_RAE: vitA_RAE.vitaminA_RAE,
            retinol: retinol.retinol,
            caroteneAlpha: carA.caroteneAlpha,
            caroteneBeta: carB.caroteneBeta,
            cryptoxanthinBeta: crypB.cryptoxanthinBeta,
            luteinZeaxanthin: lutZea.luteinZeaxanthin,
            lycopene: lyco.lycopene,
            vitaminB1_Thiamin: b1.vitaminB1_Thiamin,
            vitaminB2_Riboflavin: b2.vitaminB2_Riboflavin,
            vitaminB3_Niacin: b3.vitaminB3_Niacin,
            vitaminB5_PantothenicAcid: b5.vitaminB5_PantothenicAcid,
            vitaminB6: b6.vitaminB6,
            folateDFE: folDFE.folateDFE,
            folateFood: folFood.folateFood,
            folateTotal: folTotal.folateTotal,
            folicAcid: folicAcid.folicAcid,
            vitaminB12: b12.vitaminB12,
            vitaminC: vitC.vitaminC,
            vitaminD: vitD.vitaminD,
            vitaminE: vitE.vitaminE,
            vitaminK: vitK.vitaminK,
            choline:  choline.choline
        )
        let vitamins = AIVitaminsResponse(vitamins: vitaminsMerged)
        
        
        // MARK: 9) Minerals - PARALLEL BATCH 5
        let calciumPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'calcium' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.calcium
        )
        let ironPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'iron' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.iron
        )
        let magnesiumPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'magnesium' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.magnesium
        )
        let phosphorusPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'phosphorus' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.phosphorus
        )
        let potassiumPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'potassium' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.potassium
        )
        let sodiumPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'sodium' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.sodium
        )
        let seleniumPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'selenium' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.selenium
        )
        let zincPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'zinc' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.zinc
        )
        let copperPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'copper' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.copper
        )
        let manganesePrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'manganese' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.manganese
        )
        let fluoridePrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'fluoride' as JSON with { value: <number>, unit: 'µg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.minerals?.fluoride
        )
        
        // 2) Launch parallel tasks
        
        let calciumTask = Task<AICalcium_Resp, Error> {
            try await askWithRetry("Minerals → calcium (mg/100g)", calciumPrompt, generating: AICalcium_Resp.self)
        }
        await globalTaskManager.addTask(calciumTask)
        try Task.checkCancellation()
        
        let ironTask = Task<AIIron_Resp, Error> {
            try await askWithRetry("Minerals → iron (mg/100g)", ironPrompt, generating: AIIron_Resp.self)
        }
        await globalTaskManager.addTask(ironTask)
        try Task.checkCancellation()
        
        let magnesiumTask = Task<AIMagnesium_Resp, Error> {
            try await askWithRetry("Minerals → magnesium (mg/100g)", magnesiumPrompt, generating: AIMagnesium_Resp.self)
        }
        await globalTaskManager.addTask(magnesiumTask)
        try Task.checkCancellation()
        
        let phosphorusTask = Task<AIPhosphorus_Resp, Error> {
            try await askWithRetry("Minerals → phosphorus (mg/100g)", phosphorusPrompt, generating: AIPhosphorus_Resp.self)
        }
        await globalTaskManager.addTask(phosphorusTask)
        try Task.checkCancellation()
        
        let potassiumTask = Task<AIPotassium_Resp, Error> {
            try await askWithRetry("Minerals → potassium (mg/100g)", potassiumPrompt, generating: AIPotassium_Resp.self)
        }
        await globalTaskManager.addTask(potassiumTask)
        try Task.checkCancellation()
        
        let sodiumTask = Task<AISodium_Resp, Error> {
            try await askWithRetry("Minerals → sodium (mg/100g)", sodiumPrompt, generating: AISodium_Resp.self)
        }
        await globalTaskManager.addTask(sodiumTask)
        try Task.checkCancellation()
        
        let seleniumTask = Task<AISelenium_Resp, Error> {
            try await askWithRetry("Minerals → selenium (µg/100g)", seleniumPrompt, generating: AISelenium_Resp.self)
        }
        await globalTaskManager.addTask(seleniumTask)
        try Task.checkCancellation()
        
        let zincTask = Task<AIZinc_Resp, Error> {
            try await askWithRetry("Minerals → zinc (mg/100g)", zincPrompt, generating: AIZinc_Resp.self)
        }
        await globalTaskManager.addTask(zincTask)
        try Task.checkCancellation()
        
        let copperTask = Task<AICopper_Resp, Error> {
            try await askWithRetry("Minerals → copper (mg/100g)", copperPrompt, generating: AICopper_Resp.self)
        }
        await globalTaskManager.addTask(copperTask)
        try Task.checkCancellation()
        
        let manganeseTask = Task<AIManganese_Resp, Error> {
            try await askWithRetry("Minerals → manganese (mg/100g)", manganesePrompt, generating: AIManganese_Resp.self)
        }
        await globalTaskManager.addTask(manganeseTask)
        try Task.checkCancellation()
        
        let fluorideTask = Task<AIFluoride_Resp, Error> {
            try await askWithRetry("Minerals → fluoride (µg/100g)", fluoridePrompt, generating: AIFluoride_Resp.self)
        }
        await globalTaskManager.addTask(fluorideTask)
        try Task.checkCancellation()
        
        
        // 3) Await results
        let calcium    = try await calciumTask.value
        let iron       = try await ironTask.value
        let magnesium  = try await magnesiumTask.value
        let phosphorus = try await phosphorusTask.value
        let potassium  = try await potassiumTask.value
        let sodium     = try await sodiumTask.value
        let selenium   = try await seleniumTask.value
        let zinc       = try await zincTask.value
        let copper     = try await copperTask.value
        let manganese  = try await manganeseTask.value
        let fluoride   = try await fluorideTask.value
        try Task.checkCancellation()
        
        let mineralsMerged = AIMinerals(
            calcium: calcium.calcium,
            iron: iron.iron,
            magnesium: magnesium.magnesium,
            phosphorus: phosphorus.phosphorus,
            potassium: potassium.potassium,
            sodium: sodium.sodium,
            selenium: selenium.selenium,
            zinc: zinc.zinc,
            copper: copper.copper,
            manganese: manganese.manganese,
            fluoride: fluoride.fluoride
        )
        let minerals = AIMineralsResponse(minerals: mineralsMerged)
        
        var lipids: AILipidsResponse

        if shouldGenerateLipids {
            
        let totalSaturatedPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'totalSaturated' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.lipids?.totalSaturated
        )
        let totalMonounsaturatedPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'totalMonounsaturated' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.lipids?.totalMonounsaturated
        )
        let totalPolyunsaturatedPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'totalPolyunsaturated' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.lipids?.totalPolyunsaturated
        )
        let totalTransPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'totalTrans' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.lipids?.totalTrans
        )
        let totalTransMonoenoicPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'totalTransMonoenoic' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.lipids?.totalTransMonoenoic
        )
        let totalTransPolyenoicPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'totalTransPolyenoic' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.lipids?.totalTransPolyenoic
        )
        
        let totalSaturatedTask = Task<AITotalSaturated_Resp?, Never> {
            await askWithRetryOrNil(
                "Lipids → totalSaturated (g/100g)",
                totalSaturatedPrompt,
                generating: AITotalSaturated_Resp.self
            )
        }
        await globalTaskManager.addTask(totalSaturatedTask)
        try Task.checkCancellation()
        
        let totalMonounsaturatedTask = Task<AITotalMonounsaturated_Resp?, Never> {
            await askWithRetryOrNil(
                "Lipids → totalMonounsaturated (g/100g)",
                totalMonounsaturatedPrompt,
                generating: AITotalMonounsaturated_Resp.self
            )
        }
        await globalTaskManager.addTask(totalMonounsaturatedTask)
        try Task.checkCancellation()
        
        let totalPolyunsaturatedTask = Task<AITotalPolyunsaturated_Resp?, Never> {
            await askWithRetryOrNil(
                "Lipids → totalPolyunsaturated (g/100g)",
                totalPolyunsaturatedPrompt,
                generating: AITotalPolyunsaturated_Resp.self
            )
        }
        await globalTaskManager.addTask(totalPolyunsaturatedTask)
        try Task.checkCancellation()
        
        let totalTransTask = Task<AITotalTrans_Resp?, Never> {
            await askWithRetryOrNil(
                "Lipids → totalTrans (g/100g)",
                totalTransPrompt,
                generating: AITotalTrans_Resp.self
            )
        }
        await globalTaskManager.addTask(totalTransTask)
        try Task.checkCancellation()
        
        let totalTransMonoenoicTask = Task<AITotalTransMonoenoic_Resp?, Never> {
            await askWithRetryOrNil(
                "Lipids → totalTransMonoenoic (g/100g)",
                totalTransMonoenoicPrompt,
                generating: AITotalTransMonoenoic_Resp.self
            )
        }
        await globalTaskManager.addTask(totalTransMonoenoicTask)
        try Task.checkCancellation()
        
        let totalTransPolyenoicTask = Task<AITotalTransPolyenoic_Resp?, Never> {
            await askWithRetryOrNil(
                "Lipids → totalTransPolyenoic (g/100g)",
                totalTransPolyenoicPrompt,
                generating: AITotalTransPolyenoic_Resp.self
            )
        }
        await globalTaskManager.addTask(totalTransPolyenoicTask)
        try Task.checkCancellation()
        
        
        let totalSaturated: AITotalSaturated_Resp =
        await totalSaturatedTask.value
        ?? AITotalSaturated_Resp(totalSaturated: AINutrient(value: 0, unit: "g"))
        
        let totalMonounsaturated: AITotalMonounsaturated_Resp =
        await totalMonounsaturatedTask.value
        ?? AITotalMonounsaturated_Resp(totalMonounsaturated: AINutrient(value: 0, unit: "g"))
        
        let totalPolyunsaturated: AITotalPolyunsaturated_Resp =
        await totalPolyunsaturatedTask.value
        ?? AITotalPolyunsaturated_Resp(totalPolyunsaturated: AINutrient(value: 0, unit: "g"))
        
        let totalTrans: AITotalTrans_Resp =
        await totalTransTask.value
        ?? AITotalTrans_Resp(totalTrans: AINutrient(value: 0, unit: "g"))
        
        let totalTransMonoenoic: AITotalTransMonoenoic_Resp =
        await totalTransMonoenoicTask.value
        ?? AITotalTransMonoenoic_Resp(totalTransMonoenoic: AINutrient(value: 0, unit: "g"))
        
        let totalTransPolyenoic: AITotalTransPolyenoic_Resp =
        await totalTransPolyenoicTask.value
        ?? AITotalTransPolyenoic_Resp(totalTransPolyenoic: AINutrient(value: 0, unit: "g"))
        try Task.checkCancellation()
        
        // --- BATCH 7 (SFA) — FIXED SNAPSHOTS & TASKS ---
        
        // 1) Prompts up front
        let sfa4_0Prompt  = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa4_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",  referenceValue: similarFood?.lipids?.sfa4_0)
        let sfa6_0Prompt  = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa6_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",  referenceValue: similarFood?.lipids?.sfa6_0)
        let sfa8_0Prompt  = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa8_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",  referenceValue: similarFood?.lipids?.sfa8_0)
        let sfa10_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa10_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa10_0)
        let sfa12_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa12_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa12_0)
        let sfa13_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa13_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa13_0)
        let sfa14_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa14_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa14_0)
        let sfa15_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa15_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa15_0)
        let sfa16_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa16_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa16_0)
        let sfa17_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa17_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa17_0)
        let sfa18_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa18_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa18_0)
        let sfa20_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa20_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa20_0)
        let sfa22_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa22_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa22_0)
        let sfa24_0Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'sfa24_0' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.sfa24_0)
        
        // 2) Parallel tasks
        // ——— tolerant SFA tasks (uses askWithRetryOrNil) ———
        // --- START OF CHANGE (Lipids → SFA tasks registered in GlobalTaskManager) ---
        
        let sfa4_0Task  = Task<AISFA4_0_Resp?, Never>  { await askWithRetryOrNil("Lipids → sfa4_0",  sfa4_0Prompt,  generating: AISFA4_0_Resp.self) }
        await globalTaskManager.addTask(sfa4_0Task)
        try Task.checkCancellation()
        
        let sfa6_0Task  = Task<AISFA6_0_Resp?, Never>  { await askWithRetryOrNil("Lipids → sfa6_0",  sfa6_0Prompt,  generating: AISFA6_0_Resp.self) }
        await globalTaskManager.addTask(sfa6_0Task)
        try Task.checkCancellation()
        
        let sfa8_0Task  = Task<AISFA8_0_Resp?, Never>  { await askWithRetryOrNil("Lipids → sfa8_0",  sfa8_0Prompt,  generating: AISFA8_0_Resp.self) }
        await globalTaskManager.addTask(sfa8_0Task)
        try Task.checkCancellation()
        
        let sfa10_0Task = Task<AISFA10_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa10_0", sfa10_0Prompt, generating: AISFA10_0_Resp.self) }
        await globalTaskManager.addTask(sfa10_0Task)
        try Task.checkCancellation()
        
        let sfa12_0Task = Task<AISFA12_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa12_0", sfa12_0Prompt, generating: AISFA12_0_Resp.self) }
        await globalTaskManager.addTask(sfa12_0Task)
        try Task.checkCancellation()
        
        let sfa13_0Task = Task<AISFA13_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa13_0", sfa13_0Prompt, generating: AISFA13_0_Resp.self) }
        await globalTaskManager.addTask(sfa13_0Task)
        try Task.checkCancellation()
        
        let sfa14_0Task = Task<AISFA14_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa14_0", sfa14_0Prompt, generating: AISFA14_0_Resp.self) }
        await globalTaskManager.addTask(sfa14_0Task)
        try Task.checkCancellation()
        
        let sfa15_0Task = Task<AISFA15_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa15_0", sfa15_0Prompt, generating: AISFA15_0_Resp.self) }
        await globalTaskManager.addTask(sfa15_0Task)
        try Task.checkCancellation()
        
        let sfa16_0Task = Task<AISFA16_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa16_0", sfa16_0Prompt, generating: AISFA16_0_Resp.self) }
        await globalTaskManager.addTask(sfa16_0Task)
        try Task.checkCancellation()
        
        let sfa17_0Task = Task<AISFA17_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa17_0", sfa17_0Prompt, generating: AISFA17_0_Resp.self) }
        await globalTaskManager.addTask(sfa17_0Task)
        try Task.checkCancellation()
        
        let sfa18_0Task = Task<AISFA18_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa18_0", sfa18_0Prompt, generating: AISFA18_0_Resp.self) }
        await globalTaskManager.addTask(sfa18_0Task)
        try Task.checkCancellation()
        
        let sfa20_0Task = Task<AISFA20_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa20_0", sfa20_0Prompt, generating: AISFA20_0_Resp.self) }
        await globalTaskManager.addTask(sfa20_0Task)
        try Task.checkCancellation()
        
        let sfa22_0Task = Task<AISFA22_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa22_0", sfa22_0Prompt, generating: AISFA22_0_Resp.self) }
        await globalTaskManager.addTask(sfa22_0Task)
        try Task.checkCancellation()
        
        let sfa24_0Task = Task<AISFA24_0_Resp?, Never> { await askWithRetryOrNil("Lipids → sfa24_0", sfa24_0Prompt, generating: AISFA24_0_Resp.self) }
        await globalTaskManager.addTask(sfa24_0Task)
        try Task.checkCancellation()
        
        // --- END OF CHANGE ---
        
        
        // ——— await with zero fallbacks ———
        let sfa4_0:  AISFA4_0_Resp  = await sfa4_0Task.value  ?? AISFA4_0_Resp (sfa4_0:  AINutrient(value: 0, unit: "g"))
        let sfa6_0:  AISFA6_0_Resp  = await sfa6_0Task.value  ?? AISFA6_0_Resp (sfa6_0:  AINutrient(value: 0, unit: "g"))
        let sfa8_0:  AISFA8_0_Resp  = await sfa8_0Task.value  ?? AISFA8_0_Resp (sfa8_0:  AINutrient(value: 0, unit: "g"))
        let sfa10_0: AISFA10_0_Resp = await sfa10_0Task.value ?? AISFA10_0_Resp(sfa10_0: AINutrient(value: 0, unit: "g"))
        let sfa12_0: AISFA12_0_Resp = await sfa12_0Task.value ?? AISFA12_0_Resp(sfa12_0: AINutrient(value: 0, unit: "g"))
        let sfa13_0: AISFA13_0_Resp = await sfa13_0Task.value ?? AISFA13_0_Resp(sfa13_0: AINutrient(value: 0, unit: "g"))
        let sfa14_0: AISFA14_0_Resp = await sfa14_0Task.value ?? AISFA14_0_Resp(sfa14_0: AINutrient(value: 0, unit: "g"))
        let sfa15_0: AISFA15_0_Resp = await sfa15_0Task.value ?? AISFA15_0_Resp(sfa15_0: AINutrient(value: 0, unit: "g"))
        let sfa16_0: AISFA16_0_Resp = await sfa16_0Task.value ?? AISFA16_0_Resp(sfa16_0: AINutrient(value: 0, unit: "g"))
        let sfa17_0: AISFA17_0_Resp = await sfa17_0Task.value ?? AISFA17_0_Resp(sfa17_0: AINutrient(value: 0, unit: "g"))
        let sfa18_0: AISFA18_0_Resp = await sfa18_0Task.value ?? AISFA18_0_Resp(sfa18_0: AINutrient(value: 0, unit: "g"))
        let sfa20_0: AISFA20_0_Resp = await sfa20_0Task.value ?? AISFA20_0_Resp(sfa20_0: AINutrient(value: 0, unit: "g"))
        let sfa22_0: AISFA22_0_Resp = await sfa22_0Task.value ?? AISFA22_0_Resp(sfa22_0: AINutrient(value: 0, unit: "g"))
        let sfa24_0: AISFA24_0_Resp = await sfa24_0Task.value ?? AISFA24_0_Resp(sfa24_0: AINutrient(value: 0, unit: "g"))
        try Task.checkCancellation()
        
        
        // --- BATCH 8 (MUFA + TFA) — FIXED SNAPSHOTS & TASKS ---
        
        // 1) Промптове предварително
        let mufa14_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa14_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa14_1)
        let mufa15_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa15_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa15_1)
        let mufa16_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa16_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa16_1)
        let mufa17_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa17_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa17_1)
        let mufa18_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa18_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa18_1)
        let mufa20_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa20_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa20_1)
        let mufa22_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa22_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa22_1)
        let mufa24_1Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'mufa24_1' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.mufa24_1)
        let tfa16_1_tPrompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'tfa16_1_t' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.tfa16_1_t)
        let tfa18_1_tPrompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'tfa18_1_t' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.tfa18_1_t)
        let tfa22_1_tPrompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'tfa22_1_t' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.tfa22_1_t)
        let tfa18_2_tPrompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'tfa18_2_t' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.tfa18_2_t)
        
        // 2) Паралелни задачи
        // ——— tolerant MUFA + TFA tasks (uses askWithRetryOrNil) ———
        // --- START OF CHANGE (Lipids → MUFA & TFA tasks registered in GlobalTaskManager) ---
        
        let mufa14_1Task = Task<AIMUFA14_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa14_1", mufa14_1Prompt, generating: AIMUFA14_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa14_1Task)
        try Task.checkCancellation()
        
        let mufa15_1Task = Task<AIMUFA15_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa15_1", mufa15_1Prompt, generating: AIMUFA15_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa15_1Task)
        try Task.checkCancellation()
        
        let mufa16_1Task = Task<AIMUFA16_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa16_1", mufa16_1Prompt, generating: AIMUFA16_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa16_1Task)
        try Task.checkCancellation()
        
        let mufa17_1Task = Task<AIMUFA17_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa17_1", mufa17_1Prompt, generating: AIMUFA17_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa17_1Task)
        try Task.checkCancellation()
        
        let mufa18_1Task = Task<AIMUFA18_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa18_1", mufa18_1Prompt, generating: AIMUFA18_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa18_1Task)
        try Task.checkCancellation()
        
        let mufa20_1Task = Task<AIMUFA20_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa20_1", mufa20_1Prompt, generating: AIMUFA20_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa20_1Task)
        try Task.checkCancellation()
        
        let mufa22_1Task = Task<AIMUFA22_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa22_1", mufa22_1Prompt, generating: AIMUFA22_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa22_1Task)
        try Task.checkCancellation()
        
        let mufa24_1Task = Task<AIMUFA24_1_Resp?, Never> {
            await askWithRetryOrNil("Lipids → mufa24_1", mufa24_1Prompt, generating: AIMUFA24_1_Resp.self)
        }
        await globalTaskManager.addTask(mufa24_1Task)
        try Task.checkCancellation()
        
        let tfa16_1_tTask = Task<AITFA16_1_t_Resp?, Never> {
            await askWithRetryOrNil("Lipids → tfa16_1_t", tfa16_1_tPrompt, generating: AITFA16_1_t_Resp.self)
        }
        await globalTaskManager.addTask(tfa16_1_tTask)
        try Task.checkCancellation()
        
        let tfa18_1_tTask = Task<AITFA18_1_t_Resp?, Never> {
            await askWithRetryOrNil("Lipids → tfa18_1_t", tfa18_1_tPrompt, generating: AITFA18_1_t_Resp.self)
        }
        await globalTaskManager.addTask(tfa18_1_tTask)
        try Task.checkCancellation()
        
        let tfa22_1_tTask = Task<AITFA22_1_t_Resp?, Never> {
            await askWithRetryOrNil("Lipids → tfa22_1_t", tfa22_1_tPrompt, generating: AITFA22_1_t_Resp.self)
        }
        await globalTaskManager.addTask(tfa22_1_tTask)
        try Task.checkCancellation()
        
        let tfa18_2_tTask = Task<AITFA18_2_t_Resp?, Never> {
            await askWithRetryOrNil("Lipids → tfa18_2_t", tfa18_2_tPrompt, generating: AITFA18_2_t_Resp.self)
        }
        await globalTaskManager.addTask(tfa18_2_tTask)
        try Task.checkCancellation()
        
        // --- END OF CHANGE ---
        
        
        // ——— await with zero fallbacks ———
        let mufa14_1: AIMUFA14_1_Resp = await mufa14_1Task.value ?? AIMUFA14_1_Resp(mufa14_1: AINutrient(value: 0, unit: "g"))
        let mufa15_1: AIMUFA15_1_Resp = await mufa15_1Task.value ?? AIMUFA15_1_Resp(mufa15_1: AINutrient(value: 0, unit: "g"))
        let mufa16_1: AIMUFA16_1_Resp = await mufa16_1Task.value ?? AIMUFA16_1_Resp(mufa16_1: AINutrient(value: 0, unit: "g"))
        let mufa17_1: AIMUFA17_1_Resp = await mufa17_1Task.value ?? AIMUFA17_1_Resp(mufa17_1: AINutrient(value: 0, unit: "g"))
        let mufa18_1: AIMUFA18_1_Resp = await mufa18_1Task.value ?? AIMUFA18_1_Resp(mufa18_1: AINutrient(value: 0, unit: "g"))
        let mufa20_1: AIMUFA20_1_Resp = await mufa20_1Task.value ?? AIMUFA20_1_Resp(mufa20_1: AINutrient(value: 0, unit: "g"))
        let mufa22_1: AIMUFA22_1_Resp = await mufa22_1Task.value ?? AIMUFA22_1_Resp(mufa22_1: AINutrient(value: 0, unit: "g"))
        let mufa24_1: AIMUFA24_1_Resp = await mufa24_1Task.value ?? AIMUFA24_1_Resp(mufa24_1: AINutrient(value: 0, unit: "g"))
        
        let tfa16_1_t: AITFA16_1_t_Resp = await tfa16_1_tTask.value ?? AITFA16_1_t_Resp(tfa16_1_t: AINutrient(value: 0, unit: "g"))
        let tfa18_1_t: AITFA18_1_t_Resp = await tfa18_1_tTask.value ?? AITFA18_1_t_Resp(tfa18_1_t: AINutrient(value: 0, unit: "g"))
        let tfa22_1_t: AITFA22_1_t_Resp = await tfa22_1_tTask.value ?? AITFA22_1_t_Resp(tfa22_1_t: AINutrient(value: 0, unit: "g"))
        let tfa18_2_t: AITFA18_2_t_Resp = await tfa18_2_tTask.value ?? AITFA18_2_t_Resp(tfa18_2_t: AINutrient(value: 0, unit: "g"))
        try Task.checkCancellation()
        
        
        
        // --- BATCH 9 (PUFA) — FIXED SNAPSHOTS & TASKS ---
        
        // 1) Prompts up front
        let pufa18_2Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa18_2' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa18_2)
        let pufa18_3Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa18_3' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa18_3)
        let pufa18_4Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa18_4' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa18_4)
        let pufa20_2Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa20_2' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa20_2)
        let pufa20_3Prompt = createPromptWithReference(basePrompt: "Food: \(foodName) (RAW, edible portion). Return ONLY the field 'pufa20_3' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa20_3)
        let pufa20_4Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa20_4' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa20_4)
        let pufa20_5Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa20_5' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa20_5)
        let pufa21_5Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa21_5' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa21_5)
        let pufa22_4Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa22_4' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa22_4)
        let pufa22_5Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa22_5' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa22_5)
        let pufa22_6Prompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa22_6' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa22_6)
        let pufa2_4Prompt  = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'pufa2_4'  as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.lipids?.pufa2_4)
        
        // 2) Parallel tasks
        // ——— tolerant PUFA tasks (uses askWithRetryOrNil) ———
        // --- START OF CHANGE (Lipids → PUFA tasks registered in GlobalTaskManager) ---
        
        let pufa18_2Task = Task<AIPUFA18_2_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa18_2", pufa18_2Prompt, generating: AIPUFA18_2_Resp.self)
        }
        await globalTaskManager.addTask(pufa18_2Task)
        try Task.checkCancellation()
        
        let pufa18_3Task = Task<AIPUFA18_3_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa18_3", pufa18_3Prompt, generating: AIPUFA18_3_Resp.self)
        }
        await globalTaskManager.addTask(pufa18_3Task)
        try Task.checkCancellation()
        
        let pufa18_4Task = Task<AIPUFA18_4_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa18_4", pufa18_4Prompt, generating: AIPUFA18_4_Resp.self)
        }
        await globalTaskManager.addTask(pufa18_4Task)
        try Task.checkCancellation()
        
        let pufa20_2Task = Task<AIPUFA20_2_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa20_2", pufa20_2Prompt, generating: AIPUFA20_2_Resp.self)
        }
        await globalTaskManager.addTask(pufa20_2Task)
        try Task.checkCancellation()
        
        let pufa20_3Task = Task<AIPUFA20_3_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa20_3", pufa20_3Prompt, generating: AIPUFA20_3_Resp.self)
        }
        await globalTaskManager.addTask(pufa20_3Task)
        try Task.checkCancellation()
        
        let pufa20_4Task = Task<AIPUFA20_4_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa20_4", pufa20_4Prompt, generating: AIPUFA20_4_Resp.self)
        }
        await globalTaskManager.addTask(pufa20_4Task)
        try Task.checkCancellation()
        
        let pufa20_5Task = Task<AIPUFA20_5_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa20_5", pufa20_5Prompt, generating: AIPUFA20_5_Resp.self)
        }
        await globalTaskManager.addTask(pufa20_5Task)
        try Task.checkCancellation()
        
        let pufa21_5Task = Task<AIPUFA21_5_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa21_5", pufa21_5Prompt, generating: AIPUFA21_5_Resp.self)
        }
        await globalTaskManager.addTask(pufa21_5Task)
        try Task.checkCancellation()
        
        let pufa22_4Task = Task<AIPUFA22_4_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa22_4", pufa22_4Prompt, generating: AIPUFA22_4_Resp.self)
        }
        await globalTaskManager.addTask(pufa22_4Task)
        try Task.checkCancellation()
        
        let pufa22_5Task = Task<AIPUFA22_5_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa22_5", pufa22_5Prompt, generating: AIPUFA22_5_Resp.self)
        }
        await globalTaskManager.addTask(pufa22_5Task)
        try Task.checkCancellation()
        
        let pufa22_6Task = Task<AIPUFA22_6_Resp?, Never> {
            await askWithRetryOrNil("Lipids → pufa22_6", pufa22_6Prompt, generating: AIPUFA22_6_Resp.self)
        }
        await globalTaskManager.addTask(pufa22_6Task)
        try Task.checkCancellation()
        
        let pufa2_4Task  = Task<AIPUFA2_4_Resp?,  Never> {
            await askWithRetryOrNil("Lipids → pufa2_4",  pufa2_4Prompt,  generating: AIPUFA2_4_Resp.self)
        }
        await globalTaskManager.addTask(pufa2_4Task)
        try Task.checkCancellation()
        
        // --- END OF CHANGE ---
        
        // ——— await with zero fallbacks ———
        let pufa18_2: AIPUFA18_2_Resp = await pufa18_2Task.value ?? AIPUFA18_2_Resp(pufa18_2: AINutrient(value: 0, unit: "g"))
        let pufa18_3: AIPUFA18_3_Resp = await pufa18_3Task.value ?? AIPUFA18_3_Resp(pufa18_3: AINutrient(value: 0, unit: "g"))
        let pufa18_4: AIPUFA18_4_Resp = await pufa18_4Task.value ?? AIPUFA18_4_Resp(pufa18_4: AINutrient(value: 0, unit: "g"))
        let pufa20_2: AIPUFA20_2_Resp = await pufa20_2Task.value ?? AIPUFA20_2_Resp(pufa20_2: AINutrient(value: 0, unit: "g"))
        let pufa20_3: AIPUFA20_3_Resp = await pufa20_3Task.value ?? AIPUFA20_3_Resp(pufa20_3: AINutrient(value: 0, unit: "g"))
        let pufa20_4: AIPUFA20_4_Resp = await pufa20_4Task.value ?? AIPUFA20_4_Resp(pufa20_4: AINutrient(value: 0, unit: "g"))
        let pufa20_5: AIPUFA20_5_Resp = await pufa20_5Task.value ?? AIPUFA20_5_Resp(pufa20_5: AINutrient(value: 0, unit: "g"))
        let pufa21_5: AIPUFA21_5_Resp = await pufa21_5Task.value ?? AIPUFA21_5_Resp(pufa21_5: AINutrient(value: 0, unit: "g"))
        let pufa22_4: AIPUFA22_4_Resp = await pufa22_4Task.value ?? AIPUFA22_4_Resp(pufa22_4: AINutrient(value: 0, unit: "g"))
        let pufa22_5: AIPUFA22_5_Resp = await pufa22_5Task.value ?? AIPUFA22_5_Resp(pufa22_5: AINutrient(value: 0, unit: "g"))
        let pufa22_6: AIPUFA22_6_Resp = await pufa22_6Task.value ?? AIPUFA22_6_Resp(pufa22_6: AINutrient(value: 0, unit: "g"))
        let pufa2_4:  AIPUFA2_4_Resp  = await pufa2_4Task.value  ?? AIPUFA2_4_Resp (pufa2_4:  AINutrient(value: 0, unit: "g"))
        try Task.checkCancellation()
        
        
        
        let lipidsMerged = AILipids(
            totalSaturated: totalSaturated.totalSaturated,
            totalMonounsaturated: totalMonounsaturated.totalMonounsaturated,
            totalPolyunsaturated: totalPolyunsaturated.totalPolyunsaturated,
            totalTrans: totalTrans.totalTrans,
            totalTransMonoenoic: totalTransMonoenoic.totalTransMonoenoic,
            totalTransPolyenoic: totalTransPolyenoic.totalTransPolyenoic,
            sfa4_0:  sfa4_0.sfa4_0, sfa6_0:  sfa6_0.sfa6_0, sfa8_0:  sfa8_0.sfa8_0,
            sfa10_0: sfa10_0.sfa10_0, sfa12_0: sfa12_0.sfa12_0, sfa13_0: sfa13_0.sfa13_0,
            sfa14_0: sfa14_0.sfa14_0, sfa15_0: sfa15_0.sfa15_0, sfa16_0: sfa16_0.sfa16_0,
            sfa17_0: sfa17_0.sfa17_0, sfa18_0: sfa18_0.sfa18_0, sfa20_0: sfa20_0.sfa20_0,
            sfa22_0: sfa22_0.sfa22_0, sfa24_0: sfa24_0.sfa24_0,
            mufa14_1: mufa14_1.mufa14_1, mufa15_1: mufa15_1.mufa15_1, mufa16_1: mufa16_1.mufa16_1,
            mufa17_1: mufa17_1.mufa17_1, mufa18_1: mufa18_1.mufa18_1, mufa20_1: mufa20_1.mufa20_1,
            mufa22_1: mufa22_1.mufa22_1, mufa24_1: mufa24_1.mufa24_1,
            tfa16_1_t: tfa16_1_t.tfa16_1_t, tfa18_1_t: tfa18_1_t.tfa18_1_t,
            tfa22_1_t: tfa22_1_t.tfa22_1_t, tfa18_2_t: tfa18_2_t.tfa18_2_t,
            pufa18_2: pufa18_2.pufa18_2, pufa18_3: pufa18_3.pufa18_3, pufa18_4: pufa18_4.pufa18_4,
            pufa20_2: pufa20_2.pufa20_2, pufa20_3: pufa20_3.pufa20_3, pufa20_4: pufa20_4.pufa20_4,
            pufa20_5: pufa20_5.pufa20_5, pufa21_5: pufa21_5.pufa21_5, pufa22_4: pufa22_4.pufa22_4,
            pufa22_5: pufa22_5.pufa22_5, pufa22_6: pufa22_6.pufa22_6, pufa2_4:  pufa2_4.pufa2_4
        )
            lipids = AILipidsResponse(lipids: lipidsMerged)
        } else {
            // ❌ Не генерираме – връщаме всичко 0 g, за да не чупим DTO-то.
            let zeroG = AINutrient(value: 0, unit: "g")
            let lipidsMerged = AILipids(
                totalSaturated: zeroG,
                totalMonounsaturated: zeroG,
                totalPolyunsaturated: zeroG,
                totalTrans: zeroG,
                totalTransMonoenoic: zeroG,
                totalTransPolyenoic: zeroG,
                sfa4_0: zeroG,  sfa6_0: zeroG,  sfa8_0: zeroG,
                sfa10_0: zeroG, sfa12_0: zeroG, sfa13_0: zeroG,
                sfa14_0: zeroG, sfa15_0: zeroG, sfa16_0: zeroG,
                sfa17_0: zeroG, sfa18_0: zeroG, sfa20_0: zeroG,
                sfa22_0: zeroG, sfa24_0: zeroG,
                mufa14_1: zeroG, mufa15_1: zeroG, mufa16_1: zeroG,
                mufa17_1: zeroG, mufa18_1: zeroG, mufa20_1: zeroG,
                mufa22_1: zeroG, mufa24_1: zeroG,
                tfa16_1_t: zeroG, tfa18_1_t: zeroG,
                tfa22_1_t: zeroG, tfa18_2_t: zeroG,
                pufa18_2: zeroG, pufa18_3: zeroG, pufa18_4: zeroG,
                pufa20_2: zeroG, pufa20_3: zeroG, pufa20_4: zeroG,
                pufa20_5: zeroG, pufa21_5: zeroG, pufa22_4: zeroG,
                pufa22_5: zeroG, pufa22_6: zeroG, pufa2_4: zeroG
            )
            lipids = AILipidsResponse(lipids: lipidsMerged)
        }
        // MARK: 11) Amino Acids - PARALLEL BATCH 10, 11
        
        var aminoAcids: AIAminoAcidsResponse

        if shouldGenerateAminoAcids {
        // 1) Prompts up front
        let alaninePrompt      = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'alanine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",      referenceValue: similarFood?.aminoAcids?.alanine)
        let argininePrompt     = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'arginine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",     referenceValue: similarFood?.aminoAcids?.arginine)
        let asparticAcidPrompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'asparticAcid' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.aminoAcids?.asparticAcid)
        let cystinePrompt      = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'cystine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",      referenceValue: similarFood?.aminoAcids?.cystine)
        let glutamicAcidPrompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'glutamicAcid' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.aminoAcids?.glutamicAcid)
        let glycinePrompt      = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'glycine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",      referenceValue: similarFood?.aminoAcids?.glycine)
        let histidinePrompt    = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'histidine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",    referenceValue: similarFood?.aminoAcids?.histidine)
        let isoleucinePrompt   = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'isoleucine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",   referenceValue: similarFood?.aminoAcids?.isoleucine)
        let leucinePrompt      = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'leucine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",      referenceValue: similarFood?.aminoAcids?.leucine)
        let lysinePrompt       = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'lysine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",       referenceValue: similarFood?.aminoAcids?.lysine)
        
        // 2) Parallel tasks
        // ——— tolerant Amino Acids A–L (uses askWithRetryOrNil) ———
        // --- START OF CHANGE (Amino Acids A–L tasks registered in GlobalTaskManager) ---
        
        let alanineTask = Task<AIAlanine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → alanine (g/100g)", alaninePrompt, generating: AIAlanine_Resp.self)
        }
        await globalTaskManager.addTask(alanineTask)
        try Task.checkCancellation()
        
        let arginineTask = Task<AIArginine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → arginine (g/100g)", argininePrompt, generating: AIArginine_Resp.self)
        }
        await globalTaskManager.addTask(arginineTask)
        try Task.checkCancellation()
        
        let asparticAcidTask = Task<AIAsparticAcid_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → asparticAcid (g/100g)", asparticAcidPrompt, generating: AIAsparticAcid_Resp.self)
        }
        await globalTaskManager.addTask(asparticAcidTask)
        try Task.checkCancellation()
        
        let cystineTask = Task<AICystine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → cystine (g/100g)", cystinePrompt, generating: AICystine_Resp.self)
        }
        await globalTaskManager.addTask(cystineTask)
        try Task.checkCancellation()
        
        let glutamicAcidTask = Task<AIGlutamicAcid_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → glutamicAcid (g/100g)", glutamicAcidPrompt, generating: AIGlutamicAcid_Resp.self)
        }
        await globalTaskManager.addTask(glutamicAcidTask)
        try Task.checkCancellation()
        
        let glycineTask = Task<AIGlycine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → glycine (g/100g)", glycinePrompt, generating: AIGlycine_Resp.self)
        }
        await globalTaskManager.addTask(glycineTask)
        try Task.checkCancellation()
        
        let histidineTask = Task<AIHistidine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → histidine (g/100g)", histidinePrompt, generating: AIHistidine_Resp.self)
        }
        await globalTaskManager.addTask(histidineTask)
        try Task.checkCancellation()
        
        let isoleucineTask = Task<AIIsoleucine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → isoleucine (g/100g)", isoleucinePrompt, generating: AIIsoleucine_Resp.self)
        }
        await globalTaskManager.addTask(isoleucineTask)
        try Task.checkCancellation()
        
        let leucineTask = Task<AILeucine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → leucine (g/100g)", leucinePrompt, generating: AILeucine_Resp.self)
        }
        await globalTaskManager.addTask(leucineTask)
        try Task.checkCancellation()
        
        let lysineTask = Task<AILysine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → lysine (g/100g)", lysinePrompt, generating: AILysine_Resp.self)
        }
        await globalTaskManager.addTask(lysineTask)
        try Task.checkCancellation()
        
        // --- END OF CHANGE ---
        
        
        // ——— await with zero fallbacks ———
        let alanine:      AIAlanine_Resp      = await alanineTask.value      ?? AIAlanine_Resp(alanine: AINutrient(value: 0, unit: "g"))
        let arginine:     AIArginine_Resp     = await arginineTask.value     ?? AIArginine_Resp(arginine: AINutrient(value: 0, unit: "g"))
        let asparticAcid: AIAsparticAcid_Resp = await asparticAcidTask.value ?? AIAsparticAcid_Resp(asparticAcid: AINutrient(value: 0, unit: "g"))
        let cystine:      AICystine_Resp      = await cystineTask.value      ?? AICystine_Resp(cystine: AINutrient(value: 0, unit: "g"))
        let glutamicAcid: AIGlutamicAcid_Resp = await glutamicAcidTask.value ?? AIGlutamicAcid_Resp(glutamicAcid: AINutrient(value: 0, unit: "g"))
        let glycine:      AIGlycine_Resp      = await glycineTask.value      ?? AIGlycine_Resp(glycine: AINutrient(value: 0, unit: "g"))
        let histidine:    AIHistidine_Resp    = await histidineTask.value    ?? AIHistidine_Resp(histidine: AINutrient(value: 0, unit: "g"))
        let isoleucine:   AIIsoleucine_Resp   = await isoleucineTask.value   ?? AIIsoleucine_Resp(isoleucine: AINutrient(value: 0, unit: "g"))
        let leucine:      AILeucine_Resp      = await leucineTask.value      ?? AILeucine_Resp(leucine: AINutrient(value: 0, unit: "g"))
        let lysine:       AILysine_Resp       = await lysineTask.value       ?? AILysine_Resp(lysine: AINutrient(value: 0, unit: "g"))
        try Task.checkCancellation()
        
        
        
        // BATCH 11 (Amino Acids M-H)
        // --- BATCH 11 (Amino Acids M–H) — FIXED SNAPSHOTS & TASKS ---
        
        // 1) Prompts up front
        let methioninePrompt     = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'methionine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",     referenceValue: similarFood?.aminoAcids?.methionine)
        let phenylalaninePrompt  = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'phenylalanine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",  referenceValue: similarFood?.aminoAcids?.phenylalanine)
        let prolinePrompt        = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'proline' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",        referenceValue: similarFood?.aminoAcids?.proline)
        let threoninePrompt      = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'threonine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",      referenceValue: similarFood?.aminoAcids?.threonine)
        let tryptophanPrompt     = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'tryptophan' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",     referenceValue: similarFood?.aminoAcids?.tryptophan)
        let tyrosinePrompt       = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'tyrosine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",       referenceValue: similarFood?.aminoAcids?.tyrosine)
        let valinePrompt         = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'valine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",         referenceValue: similarFood?.aminoAcids?.valine)
        let serinePrompt         = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'serine' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",         referenceValue: similarFood?.aminoAcids?.serine)
        let hydroxyprolinePrompt = createPromptWithReference(basePrompt: "Food: \(foodName). Return ONLY the field 'hydroxyproline' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.", referenceValue: similarFood?.aminoAcids?.hydroxyproline)
        
        // ——— tolerant Amino Acids M–H (uses askWithRetryOrNil) ———
        // --- START OF CHANGE (Amino Acids M–H tasks registered in GlobalTaskManager) ---
        
        let methionineTask = Task<AIMethionine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → methionine (g/100g)", methioninePrompt, generating: AIMethionine_Resp.self)
        }
        await globalTaskManager.addTask(methionineTask)
        try Task.checkCancellation()
        
        let phenylalanineTask = Task<AIPhenylalanine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → phenylalanine (g/100g)", phenylalaninePrompt, generating: AIPhenylalanine_Resp.self)
        }
        await globalTaskManager.addTask(phenylalanineTask)
        try Task.checkCancellation()
        
        let prolineTask = Task<AIProline_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → proline (g/100g)", prolinePrompt, generating: AIProline_Resp.self)
        }
        await globalTaskManager.addTask(prolineTask)
        try Task.checkCancellation()
        
        let threonineTask = Task<AIThreonine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → threonine (g/100g)", threoninePrompt, generating: AIThreonine_Resp.self)
        }
        await globalTaskManager.addTask(threonineTask)
        try Task.checkCancellation()
        
        let tryptophanTask = Task<AITryptophan_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → tryptophan (g/100g)", tryptophanPrompt, generating: AITryptophan_Resp.self)
        }
        await globalTaskManager.addTask(tryptophanTask)
        try Task.checkCancellation()
        
        let tyrosineTask = Task<AITyrosine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → tyrosine (g/100g)", tyrosinePrompt, generating: AITyrosine_Resp.self)
        }
        await globalTaskManager.addTask(tyrosineTask)
        try Task.checkCancellation()
        
        let valineTask = Task<AIValine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → valine (g/100g)", valinePrompt, generating: AIValine_Resp.self)
        }
        await globalTaskManager.addTask(valineTask)
        try Task.checkCancellation()
        
        let serineTask = Task<AISerine_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → serine (g/100g)", serinePrompt, generating: AISerine_Resp.self)
        }
        await globalTaskManager.addTask(serineTask)
        try Task.checkCancellation()
        
        let hydroxyprolineTask = Task<AIHydroxyproline_Resp?, Never> {
            await askWithRetryOrNil("Amino Acids → hydroxyproline (g/100g)", hydroxyprolinePrompt, generating: AIHydroxyproline_Resp.self)
        }
        await globalTaskManager.addTask(hydroxyprolineTask)
        try Task.checkCancellation()
        
        // --- END OF CHANGE ---
        
        
        // ——— await with zero fallbacks ———
        let methionine:     AIMethionine_Resp     = await methionineTask.value     ?? AIMethionine_Resp(methionine: AINutrient(value: 0, unit: "g"))
        let phenylalanine:  AIPhenylalanine_Resp  = await phenylalanineTask.value  ?? AIPhenylalanine_Resp(phenylalanine: AINutrient(value: 0, unit: "g"))
        let proline:        AIProline_Resp        = await prolineTask.value        ?? AIProline_Resp(proline: AINutrient(value: 0, unit: "g"))
        let threonine:      AIThreonine_Resp      = await threonineTask.value      ?? AIThreonine_Resp(threonine: AINutrient(value: 0, unit: "g"))
        let tryptophan:     AITryptophan_Resp     = await tryptophanTask.value     ?? AITryptophan_Resp(tryptophan: AINutrient(value: 0, unit: "g"))
        let tyrosine:       AITyrosine_Resp       = await tyrosineTask.value       ?? AITyrosine_Resp(tyrosine: AINutrient(value: 0, unit: "g"))
        let valine:         AIValine_Resp         = await valineTask.value         ?? AIValine_Resp(valine: AINutrient(value: 0, unit: "g"))
        let serine:         AISerine_Resp         = await serineTask.value         ?? AISerine_Resp(serine: AINutrient(value: 0, unit: "g"))
        let hydroxyproline: AIHydroxyproline_Resp = await hydroxyprolineTask.value ?? AIHydroxyproline_Resp(hydroxyproline: AINutrient(value: 0, unit: "g"))
        try Task.checkCancellation()
        
            
        let aminoMerged = AIAminoAcids(
            alanine: alanine.alanine, arginine: arginine.arginine, asparticAcid: asparticAcid.asparticAcid,
            cystine: cystine.cystine, glutamicAcid: glutamicAcid.glutamicAcid, glycine: glycine.glycine,
            histidine: histidine.histidine, isoleucine: isoleucine.isoleucine, leucine: leucine.leucine,
            lysine: lysine.lysine, methionine: methionine.methionine, phenylalanine: phenylalanine.phenylalanine,
            proline: proline.proline, threonine: threonine.threonine, tryptophan: tryptophan.tryptophan,
            tyrosine: tyrosine.tyrosine, valine: valine.valine, serine: serine.serine,
            hydroxyproline: hydroxyproline.hydroxyproline
        )
            aminoAcids = AIAminoAcidsResponse(aminoAcids: aminoMerged)
        } else {
            let zeroG = AINutrient(value: 0, unit: "g")
            let aminoMerged = AIAminoAcids(
                alanine: zeroG, arginine: zeroG, asparticAcid: zeroG,
                cystine: zeroG, glutamicAcid: zeroG, glycine: zeroG,
                histidine: zeroG, isoleucine: zeroG, leucine: zeroG,
                lysine: zeroG, methionine: zeroG, phenylalanine: zeroG,
                proline: zeroG, threonine: zeroG, tryptophan: zeroG,
                tyrosine: zeroG, valine: zeroG, serine: zeroG,
                hydroxyproline: zeroG
            )
            aminoAcids = AIAminoAcidsResponse(aminoAcids: aminoMerged)
        }
        
        var carbDetails: AICarbDetailsResponse

        if shouldGenerateCarbDetails {
        // MARK: 12) Carb Details - PARALLEL BATCH 12
        // --- BATCH 12 (Carb Details) — FIXED SNAPSHOTS & TASKS ---
        
        // 1) Prompts up front
        let starchPrompt    = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'starch' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.carbDetails?.starch
        )
        let sucrosePrompt   = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'sucrose' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.carbDetails?.sucrose
        )
        let glucosePrompt   = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'glucose' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.carbDetails?.glucose
        )
        let fructosePrompt  = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'fructose' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.carbDetails?.fructose
        )
        let lactosePrompt   = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'lactose' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.carbDetails?.lactose
        )
        let maltosePrompt   = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'maltose' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.carbDetails?.maltose
        )
        let galactosePrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'galactose' as JSON with { value: <number>, unit: 'g' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.carbDetails?.galactose
        )
        
        // 2) Parallel tasks
        // --- START OF CHANGE (CarbDetails tasks registered in GlobalTaskManager) ---
        
        let starchTask = Task<AIStarch_Resp, Error> {
            try await askWithRetry("CarbDetails → starch (g/100g)", starchPrompt, generating: AIStarch_Resp.self)
        }
        await globalTaskManager.addTask(starchTask)
        try Task.checkCancellation()
        
        let sucroseTask = Task<AISucrose_Resp, Error> {
            try await askWithRetry("CarbDetails → sucrose (g/100g)", sucrosePrompt, generating: AISucrose_Resp.self)
        }
        await globalTaskManager.addTask(sucroseTask)
        try Task.checkCancellation()
        
        let glucoseTask = Task<AIGlucose_Resp, Error> {
            try await askWithRetry("CarbDetails → glucose (g/100g)", glucosePrompt, generating: AIGlucose_Resp.self)
        }
        await globalTaskManager.addTask(glucoseTask)
        try Task.checkCancellation()
        
        let fructoseTask = Task<AIFructose_Resp, Error> {
            try await askWithRetry("CarbDetails → fructose (g/100g)", fructosePrompt, generating: AIFructose_Resp.self)
        }
        await globalTaskManager.addTask(fructoseTask)
        try Task.checkCancellation()
        
        let lactoseTask = Task<AILactose_Resp, Error> {
            try await askWithRetry("CarbDetails → lactose (g/100g)", lactosePrompt, generating: AILactose_Resp.self)
        }
        await globalTaskManager.addTask(lactoseTask)
        try Task.checkCancellation()
        
        let maltoseTask = Task<AIMaltose_Resp, Error> {
            try await askWithRetry("CarbDetails → maltose (g/100g)", maltosePrompt, generating: AIMaltose_Resp.self)
        }
        await globalTaskManager.addTask(maltoseTask)
        try Task.checkCancellation()
        
        let galactoseTask = Task<AIGalactose_Resp, Error> {
            try await askWithRetry("CarbDetails → galactose (g/100g)", galactosePrompt, generating: AIGalactose_Resp.self)
        }
        await globalTaskManager.addTask(galactoseTask)
        try Task.checkCancellation()
        
        // --- END OF CHANGE ---
        
        
        // 3) Await results
        let starch    = try await starchTask.value
        let sucrose   = try await sucroseTask.value
        let glucose   = try await glucoseTask.value
        let fructose  = try await fructoseTask.value
        let lactose   = try await lactoseTask.value
        let maltose   = try await maltoseTask.value
        let galactose = try await galactoseTask.value
        try Task.checkCancellation()
        
        
        let carbMerged = AICarbDetails(
            starch: starch.starch, sucrose: sucrose.sucrose, glucose: glucose.glucose,
            fructose: fructose.fructose, lactose: lactose.lactose, maltose: maltose.maltose,
            galactose: galactose.galactose
        )
            
        carbDetails = AICarbDetailsResponse(carbDetails: carbMerged)
            
        } else {
            let zeroG = AINutrient(value: 0, unit: "g")
            let carbMerged = AICarbDetails(
                starch: zeroG, sucrose: zeroG, glucose: zeroG,
                fructose: zeroG, lactose: zeroG, maltose: zeroG,
                galactose: zeroG
            )
            carbDetails = AICarbDetailsResponse(carbDetails: carbMerged)
        }
        
        var sterols: AISterolsResponse

        if shouldGenerateSterols {
        // --- BATCH 13 (Sterols) — FIXED SNAPSHOTS & TASKS ---
        
        // 1) Prompts up front
        let phytosterolsPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'phytosterols' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.sterols?.phytosterols
        )
        let betaSitosterolPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'betaSitosterol' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.sterols?.betaSitosterol
        )
        let campesterolPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'campesterol' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.sterols?.campesterol
        )
        let stigmasterolPrompt = createPromptWithReference(
            basePrompt: "Food: \(foodName). Return ONLY the field 'stigmasterol' as JSON with { value: <number>, unit: 'mg' } for **per 100 g exactly**. No prose. No other keys.",
            referenceValue: similarFood?.sterols?.stigmasterol
        )
        
        // 2) Parallel tasks
        // --- START OF CHANGE (Sterols tasks registered in GlobalTaskManager) ---
        
        let phytosterolsTask = Task<AIPhytosterols_Resp, Error> {
            try await askWithRetry("Sterols → phytosterols (mg/100g)", phytosterolsPrompt, generating: AIPhytosterols_Resp.self)
        }
        await globalTaskManager.addTask(phytosterolsTask)
        try Task.checkCancellation()
        
        let betaSitosterolTask = Task<AIBetaSitosterol_Resp, Error> {
            try await askWithRetry("Sterols → betaSitosterol (mg/100g)", betaSitosterolPrompt, generating: AIBetaSitosterol_Resp.self)
        }
        await globalTaskManager.addTask(betaSitosterolTask)
        try Task.checkCancellation()
        
        let campesterolTask = Task<AICampesterol_Resp, Error> {
            try await askWithRetry("Sterols → campesterol (mg/100g)", campesterolPrompt, generating: AICampesterol_Resp.self)
        }
        await globalTaskManager.addTask(campesterolTask)
        try Task.checkCancellation()
        
        let stigmasterolTask = Task<AIStigmasterol_Resp, Error> {
            try await askWithRetry("Sterols → stigmasterol (mg/100g)", stigmasterolPrompt, generating: AIStigmasterol_Resp.self)
        }
        await globalTaskManager.addTask(stigmasterolTask)
        try Task.checkCancellation()
        
        // --- END OF CHANGE ---
        
        
        // 3) Await results
        let phytosterols   = try await phytosterolsTask.value
        let betaSitosterol = try await betaSitosterolTask.value
        let campesterol    = try await campesterolTask.value
        let stigmasterol   = try await stigmasterolTask.value
        try Task.checkCancellation()
        
        
        let sterolsMerged = AISterols(
            phytosterols:   phytosterols.phytosterols,
            betaSitosterol: betaSitosterol.betaSitosterol,
            campesterol:    campesterol.campesterol,
            stigmasterol:   stigmasterol.stigmasterol
        )
            
            sterols = AISterolsResponse(sterols: sterolsMerged)
            
        } else {
            let zeroMg = AINutrient(value: 0, unit: "mg")
            let sterolsMerged = AISterols(
                phytosterols:   zeroMg,
                betaSitosterol: zeroMg,
                campesterol:    zeroMg,
                stigmasterol:   zeroMg
            )
            sterols = AISterolsResponse(sterols: sterolsMerged)
        }
        
        
        // --- Final assembly -> FoodItemDTO (остава непроменено) ---
        let dto = FoodItemDTO(
            id: UUID(),
            name: foodName,
            minAgeMonths: minAgeResp.minAgeMonths,
            ageProvenance: "ai-estimate",
            ageSource: "Apple Foundation Models; review required",
            desctiption: descResp.description,
            isEdible: safetyAyurvedaResp.isEdible,
            inedibleReason: safetyAyurvedaResp.inedibleReason
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty(),
            inedibleContraindications: safetyAyurvedaResp.inedibleContraindications,
            allergens: allergensResp.allergens.compactMap { Allergen(rawValue: $0.rawValue) },
            ayurveda: AyurvedaGeneratedFoodDTO(
                sanskrit: safetyAyurvedaResp.sanskrit
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty(),
                aliases: Array(safetyAyurvedaResp.aliases.prefix(5)),
                doshaVata: min(2, max(-2, safetyAyurvedaResp.doshaVata)),
                doshaPitta: min(2, max(-2, safetyAyurvedaResp.doshaPitta)),
                doshaKapha: min(2, max(-2, safetyAyurvedaResp.doshaKapha)),
                rasa: safetyAyurvedaResp.rasa,
                virya: safetyAyurvedaResp.virya
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .nilIfEmpty(),
                vipaka: safetyAyurvedaResp.vipaka
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .nilIfEmpty(),
                gunas: safetyAyurvedaResp.gunas,
                seasons: safetyAyurvedaResp.seasons,
                timeOfDay: safetyAyurvedaResp.timeOfDay,
                viruddha: safetyAyurvedaResp.viruddha,
                prabhava: safetyAyurvedaResp.prabhava
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty(),
                agniEffect: min(2, max(-2, safetyAyurvedaResp.agniEffect)),
                digestibility: min(2, max(-2, safetyAyurvedaResp.digestibility)),
                combinations: Array(safetyAyurvedaResp.combinations.prefix(5)),
                contraindications: safetyAyurvedaResp.contraindications,
                preparation: safetyAyurvedaResp.preparation
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty(),
                guidance: safetyAyurvedaResp.guidance
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty(),
                confidenceAyur: min(1, max(0, safetyAyurvedaResp.confidenceAyur))
            ),
            // ... останалата част от DTO асемблирането ...
            
            // ... (Вмъквам само част, за да покажа, че съвпадат)
            macronutrients: MacronutrientsDTO(
                carbohydrates: Nutrient(from: macros.macronutrients.carbohydrates),
                protein:       Nutrient(from: macros.macronutrients.protein),
                fat:           Nutrient(from: macros.macronutrients.fat),
                fiber:         Nutrient(from: macros.macronutrients.fiber),
                totalSugars:   Nutrient(from: macros.macronutrients.totalSugars)
            ),
            lipids: LipidsDTO(
                totalSaturated:         Nutrient(from: lipids.lipids.totalSaturated),
                totalMonounsaturated:   Nutrient(from: lipids.lipids.totalMonounsaturated),
                totalPolyunsaturated:   Nutrient(from: lipids.lipids.totalPolyunsaturated),
                totalTrans:             Nutrient(from: lipids.lipids.totalTrans),
                totalTransMonoenoic:    Nutrient(from: lipids.lipids.totalTransMonoenoic),
                totalTransPolyenoic:    Nutrient(from: lipids.lipids.totalTransPolyenoic),
                sfa4_0:  Nutrient(from: lipids.lipids.sfa4_0), sfa6_0:  Nutrient(from: lipids.lipids.sfa6_0),
                sfa8_0:  Nutrient(from: lipids.lipids.sfa8_0), sfa10_0: Nutrient(from: lipids.lipids.sfa10_0),
                sfa12_0: Nutrient(from: lipids.lipids.sfa12_0), sfa13_0: Nutrient(from: lipids.lipids.sfa13_0),
                sfa14_0: Nutrient(from: lipids.lipids.sfa14_0), sfa15_0: Nutrient(from: lipids.lipids.sfa15_0),
                sfa16_0: Nutrient(from: lipids.lipids.sfa16_0), sfa17_0: Nutrient(from: lipids.lipids.sfa17_0),
                sfa18_0: Nutrient(from: lipids.lipids.sfa18_0), sfa20_0: Nutrient(from: lipids.lipids.sfa20_0),
                sfa22_0: Nutrient(from: lipids.lipids.sfa22_0), sfa24_0: Nutrient(from: lipids.lipids.sfa24_0),
                mufa14_1: Nutrient(from: lipids.lipids.mufa14_1), mufa15_1: Nutrient(from: lipids.lipids.mufa15_1),
                mufa16_1: Nutrient(from: lipids.lipids.mufa16_1), mufa17_1: Nutrient(from: lipids.lipids.mufa17_1),
                mufa18_1: Nutrient(from: lipids.lipids.mufa18_1), mufa20_1: Nutrient(from: lipids.lipids.mufa20_1),
                mufa22_1: Nutrient(from: lipids.lipids.mufa22_1), mufa24_1: Nutrient(from: lipids.lipids.mufa24_1),
                tfa16_1_t: Nutrient(from: lipids.lipids.tfa16_1_t), tfa18_1_t: Nutrient(from: lipids.lipids.tfa18_1_t),
                tfa22_1_t: Nutrient(from: lipids.lipids.tfa22_1_t), tfa18_2_t: Nutrient(from: lipids.lipids.tfa18_2_t),
                pufa18_2: Nutrient(from: lipids.lipids.pufa18_2), pufa18_3: Nutrient(from: lipids.lipids.pufa18_3),
                pufa18_4: Nutrient(from: lipids.lipids.pufa18_4), pufa20_2: Nutrient(from: lipids.lipids.pufa20_2),
                pufa20_3: Nutrient(from: lipids.lipids.pufa20_3), pufa20_4: Nutrient(from: lipids.lipids.pufa20_4),
                pufa20_5: Nutrient(from: lipids.lipids.pufa20_5), pufa21_5: Nutrient(from: lipids.lipids.pufa21_5),
                pufa22_4: Nutrient(from: lipids.lipids.pufa22_4), pufa22_5: Nutrient(from: lipids.lipids.pufa22_5),
                pufa22_6: Nutrient(from: lipids.lipids.pufa22_6), pufa2_4:  Nutrient(from: lipids.lipids.pufa2_4)
            ),
            // ... (останалите полета)
            vitamins: VitaminsDTO(
                vitaminA_RAE: Nutrient(from: vitamins.vitamins.vitaminA_RAE),
                retinol:      Nutrient(from: vitamins.vitamins.retinol),
                caroteneAlpha:     Nutrient(from: vitamins.vitamins.caroteneAlpha),
                caroteneBeta:      Nutrient(from: vitamins.vitamins.caroteneBeta),
                cryptoxanthinBeta: Nutrient(from: vitamins.vitamins.cryptoxanthinBeta),
                luteinZeaxanthin:  Nutrient(from: vitamins.vitamins.luteinZeaxanthin),
                lycopene:          Nutrient(from: vitamins.vitamins.lycopene),
                vitaminB1_Thiamin:         Nutrient(from: vitamins.vitamins.vitaminB1_Thiamin),
                vitaminB2_Riboflavin:      Nutrient(from: vitamins.vitamins.vitaminB2_Riboflavin),
                vitaminB3_Niacin:          Nutrient(from: vitamins.vitamins.vitaminB3_Niacin),
                vitaminB5_PantothenicAcid: Nutrient(from: vitamins.vitamins.vitaminB5_PantothenicAcid),
                vitaminB6:                 Nutrient(from: vitamins.vitamins.vitaminB6),
                folateDFE:   Nutrient(from: vitamins.vitamins.folateDFE),
                folateFood:  Nutrient(from: vitamins.vitamins.folateFood),
                folateTotal: Nutrient(from: vitamins.vitamins.folateTotal),
                folicAcid:   Nutrient(from: vitamins.vitamins.folicAcid),
                vitaminB12:  Nutrient(from: vitamins.vitamins.vitaminB12),
                vitaminC:    Nutrient(from: vitamins.vitamins.vitaminC),
                vitaminD:    Nutrient(from: vitamins.vitamins.vitaminD),
                vitaminE:    Nutrient(from: vitamins.vitamins.vitaminE),
                vitaminK:    Nutrient(from: vitamins.vitamins.vitaminK),
                choline:     Nutrient(from: vitamins.vitamins.choline)
            ),
            minerals: MineralsDTO(
                calcium:    Nutrient(from: minerals.minerals.calcium),
                iron:       Nutrient(from: minerals.minerals.iron),
                magnesium:  Nutrient(from: minerals.minerals.magnesium),
                phosphorus: Nutrient(from: minerals.minerals.phosphorus),
                potassium:  Nutrient(from: minerals.minerals.potassium),
                sodium:     Nutrient(from: minerals.minerals.sodium),
                selenium:   Nutrient(from: minerals.minerals.selenium),
                zinc:       Nutrient(from: minerals.minerals.zinc),
                copper:     Nutrient(from: minerals.minerals.copper),
                manganese:  Nutrient(from: minerals.minerals.manganese),
                fluoride:   Nutrient(from: minerals.minerals.fluoride)
            ),
            other: OtherDTO(
                alcoholEthyl: Nutrient(from: others.other.alcoholEthyl),
                caffeine:     Nutrient(from: others.other.caffeine),
                theobromine:  Nutrient(from: others.other.theobromine),
                cholesterol:  Nutrient(from: others.other.cholesterol),
                energyKcal:   Nutrient(from: others.other.energyKcal),
                water:        Nutrient(from: others.other.water),
                weightG:      Nutrient(from: others.other.weightG),
                ash:          Nutrient(from: others.other.ash),
                betaine:      Nutrient(from: others.other.betaine),
                alkalinityPH: Nutrient(from: others.other.alkalinityPH)
            ),
            aminoAcids: AminoAcidsDTO(
                alanine:        Nutrient(from: aminoAcids.aminoAcids.alanine),
                arginine:       Nutrient(from: aminoAcids.aminoAcids.arginine),
                asparticAcid:   Nutrient(from: aminoAcids.aminoAcids.asparticAcid),
                cystine:        Nutrient(from: aminoAcids.aminoAcids.cystine),
                glutamicAcid:   Nutrient(from: aminoAcids.aminoAcids.glutamicAcid),
                glycine:        Nutrient(from: aminoAcids.aminoAcids.glycine),
                histidine:      Nutrient(from: aminoAcids.aminoAcids.histidine),
                isoleucine:     Nutrient(from: aminoAcids.aminoAcids.isoleucine),
                leucine:        Nutrient(from: aminoAcids.aminoAcids.leucine),
                lysine:         Nutrient(from: aminoAcids.aminoAcids.lysine),
                methionine:     Nutrient(from: aminoAcids.aminoAcids.methionine),
                phenylalanine:  Nutrient(from: aminoAcids.aminoAcids.phenylalanine),
                proline:        Nutrient(from: aminoAcids.aminoAcids.proline),
                threonine:      Nutrient(from: aminoAcids.aminoAcids.threonine),
                tryptophan:     Nutrient(from: aminoAcids.aminoAcids.tryptophan),
                tyrosine:       Nutrient(from: aminoAcids.aminoAcids.tyrosine),
                valine:         Nutrient(from: aminoAcids.aminoAcids.valine),
                serine:         Nutrient(from: aminoAcids.aminoAcids.serine),
                hydroxyproline: Nutrient(from: aminoAcids.aminoAcids.hydroxyproline)
            ),
            carbDetails: CarbDetailsDTO(
                starch:    Nutrient(from: carbDetails.carbDetails.starch),
                sucrose:   Nutrient(from: carbDetails.carbDetails.sucrose),
                glucose:   Nutrient(from: carbDetails.carbDetails.glucose),
                fructose:  Nutrient(from: carbDetails.carbDetails.fructose),
                lactose:   Nutrient(from: carbDetails.carbDetails.lactose),
                maltose:   Nutrient(from: carbDetails.carbDetails.maltose),
                galactose: Nutrient(from: carbDetails.carbDetails.galactose)
            ),
            sterols: SterolsDTO(
                phytosterols:   Nutrient(from: sterols.sterols.phytosterols),
                betaSitosterol: Nutrient(from: sterols.sterols.betaSitosterol),
                campesterol:    Nutrient(from: sterols.sterols.campesterol),
                stigmasterol:   Nutrient(from: sterols.sterols.stigmasterol)
            )
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(dto)
            if let json = String(data: data, encoding: .utf8) {
                onLog?("📦 Final FoodItemDTO:\n\(json)")
            }
        } catch {
            onLog?("⚠️ Could not encode final DTO to JSON: \(error.localizedDescription)")
        }
        
        onLog?("✅ Successfully generated (PARALLEL, with retries + session reinit).")
        return dto
        
    }
    
    @available(iOS 26.0, *)
    func mapResponseToState(
        dto: FoodItemDTO,
        ctx: ModelContext
    ) throws -> (
        description: String,
        minAgeMonthsTxt: String,
        allergens: Set<Allergen.ID>,
        macros: MacroForm,
        others: OtherForm,
        vitamins: VitaminForm,
        minerals: MineralForm,
        lipids: LipidForm,
        aminoAcids: AminoAcidsForm,
        carbDetails: CarbDetailsForm,
        sterols: SterolsForm,
        ayurveda: AyurvedaGeneratedFoodDTO?,
        isEdible: Bool,
        inedibleReason: String?,
        inedibleContraindications: [String],
        ageProvenance: String?,
        ageSource: String?
    ) {
        let description = dto.desctiption ?? ""   // <— от DTO-то
        let minAge = dto.minAgeMonths ?? 0
        let minAgeMonthsTxt = minAge > 0 ? String(minAge) : ""
        
        let allergens  = Set((dto.allergens ?? []).map { $0.id })
        let macros      = MacroForm(from: dto.macronutrients)
        let others      = OtherForm(from: dto.other)
        let vitamins    = VitaminForm(from: dto.vitamins)
        let minerals    = MineralForm(from: dto.minerals)
        let lipids      = LipidForm(from: dto.lipids)
        let aminoAcids  = AminoAcidsForm(from: dto.aminoAcids)
        let carbDetails = CarbDetailsForm(from: dto.carbDetails)
        let sterols     = SterolsForm(from: dto.sterols)
        
        return (
            description,
            minAgeMonthsTxt,
            allergens,
            macros,
            others,
            vitamins,
            minerals,
            lipids,
            aminoAcids,
            carbDetails,
            sterols,
            dto.ayurveda,
            dto.isEdible ?? true,
            dto.inedibleReason,
            dto.inedibleContraindications ?? [],
            dto.ageProvenance,
            dto.ageSource
        )
    }
    
    // Груба, но ефективна Jaccard-подобна близост между две имена (по токени)
    private func nameSimilarity(_ a: String, _ b: String) -> Double {
        func tokens(_ s: String) -> Set<String> {
            let lowered = s.lowercased()
                .replacingOccurrences(of: #"[^a-zа-я0-9\s\-_/]"#, with: " ", options: .regularExpression)
            let raw = lowered.split{ $0.isWhitespace || $0 == "/" || $0 == "-" || $0 == "_" }.map(String.init)
            // махаме очевидни шумове
            let stop: Set<String> = ["raw","fresh","food","product","and","or","of","the","a",
                                     "суров","пресен","и","или"]
            return Set(raw.filter{ !stop.contains($0) })
        }
        let A = tokens(a), B = tokens(b)
        if A.isEmpty || B.isEmpty { return 0 }
        let inter = Double(A.intersection(B).count)
        let uni   = Double(A.union(B).count)
        return inter / uni
    }
    
    // Квантуване на "величина" по единица, за да не подаваш числа в prompt-а
    private func magnitudeBucket(value: Double, unit: String) -> String {
        let v = max(0, value)
        switch unit.lowercased() {
        case "g":
            if v == 0 { return "zero" }
            if v <= 0.05 { return "trace" }
            if v <= 0.5  { return "very-low" }
            if v <= 3    { return "low" }
            if v <= 10   { return "moderate" }
            if v <= 30   { return "high" }
            return "very-high"
        case "mg":
            if v == 0 { return "zero" }
            if v <= 1   { return "trace" }
            if v <= 10  { return "very-low" }
            if v <= 50  { return "low" }
            if v <= 200 { return "moderate" }
            if v <= 1000{ return "high" }
            return "very-high"
        case "µg", "mcg":
            if v == 0 { return "zero" }
            if v <= 5    { return "trace" }
            if v <= 50   { return "very-low" }
            if v <= 200  { return "low" }
            if v <= 1000 { return "moderate" }
            if v <= 5000 { return "high" }
            return "very-high"
        case "kcal":
            if v == 0 { return "zero" }
            if v <= 20   { return "very-low" }
            if v <= 80   { return "low" }
            if v <= 200  { return "moderate" }
            if v <= 400  { return "high" }
            return "very-high"
        default:
            // дефолт за непозната единица – само presence/absence
            return v == 0 ? "zero" : "non-zero"
        }
    }
    
}

@available(iOS 26.0, *)
extension AIFoodDetailGenerator {
    
    /// Кои грешки да ретраим (можеш да си добавиш по-фина логика по кодове/домейни)
    nonisolated private func shouldRetry(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        // пример: не ретраим при weightG валидация (user input issue), всичко друго — да
        let ns = error as NSError
        if ns.domain == "AIGenerationError", ns.code == 1012 { return false }
        return true
    }
    
    /// Експоненциален бекоф с лек джитър (не блокира нишка; `Task.sleep` просто суспендва).
    nonisolated private func backoffSleep(attempt: Int,
                                          baseMs: Int,
                                          maxMs: Int = 30_000) async {
        let powFactor = pow(1.8, Double(max(0, attempt - 1)))
        let raw = min(Int(Double(baseMs) * powFactor), maxMs)
        let jitter = Int.random(in: 0...250)
        let delayMs = max(0, raw + jitter)
        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
    }
    
    /// Хвърляща версия: прави N опита; хвърля последната грешка.
    @MainActor
    func generateDetailsRetrying(
        for foodName: String,
        ctx: ModelContext,
        onLog: (@Sendable (String) -> Void)?,
        attempts: Int = 3,
        baseBackoffMs: Int = 600
    ) async throws -> FoodItemDTO {
        precondition(attempts >= 1, "attempts must be >= 1")
        
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                // ПРОМЯНА: Проверяваме преди да започнем нов пълен опит.
                try Task.checkCancellation()
                
                if attempt > 1 { onLog?("🔁 generateDetails attempt \(attempt)/\(attempts)…") }
                return try await generateDetails(for: foodName, ctx: ctx, onLog: onLog)
            } catch {
                lastError = error
                if !shouldRetry(error) || attempt == attempts {
                    onLog?("❌ generateDetails failed on attempt \(attempt): \(error.localizedDescription)")
                    throw error
                }
                onLog?("⚠️ generateDetails failed (attempt \(attempt)): \(error.localizedDescription). Retrying with backoff…")
                await backoffSleep(attempt: attempt, baseMs: baseBackoffMs)
            }
        }
        
        throw lastError ?? NSError(domain: "AIGenerationError",
                                   code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Unknown failure in generateDetailsRetrying"])
    }
    /// Не-хвърляща версия: връща `nil`, ако всички опити се провалят.
    @MainActor
    func generateDetailsOrNil(
        for foodName: String,
        ctx: ModelContext,
        onLog: (@Sendable (String) -> Void)?,
        attempts: Int = 3,
        baseBackoffMs: Int = 600
    ) async -> FoodItemDTO? {
        do {
            return try await generateDetailsRetrying(for: foodName, ctx: ctx, onLog: onLog, attempts: attempts, baseBackoffMs: baseBackoffMs)
        } catch {
            return nil
        }
    }
}
