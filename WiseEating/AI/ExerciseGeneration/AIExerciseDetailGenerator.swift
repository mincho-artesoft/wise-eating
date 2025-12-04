import Foundation
import SwiftData
import FoundationModels

@available(iOS 26.0, *)
@MainActor
final class AIExerciseDetailGenerator {
    private let globalTaskManager = GlobalTaskManager.shared

    // Запазваме същата сигнатура (контейнерът не се държи като поле)
    init(container _: ModelContainer) {}

    // MARK: - Logging
    private func emitLog(_ message: String, onLog: (@Sendable (String) -> Void)?) {
        onLog?(message)
    }

    // Нормализиране и токенизация
    private func normalizeExerciseName(_ s: String) -> String {
        s.lowercased()
         .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
         .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(_ s: String) -> Set<String> {
        let stop: Set<String> = ["and","or","of","the","a","for","to","with","by",
                                 "за","и","или","от","по","с","в","на"]
        let toks = normalizeExerciseName(s).split(separator: " ").map { String($0) }
        return Set(toks.filter { !stop.contains($0) })
    }

    private func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        let inter = Double(a.intersection(b).count)
        let uni   = Double(a.union(b).count)
        return inter / uni
    }

    // Хевристичен избор — предпочитаме „най-генеричния“ вариант при generic заявка
    private func heuristicBestMatch(query: String, in candidates: [ExerciseItem]) -> ExerciseItem? {
        let qNorm  = normalizeExerciseName(query)
        let qToks  = tokenSet(query)

        // 1) exact/starts-with по нормализирано име (силен сигнал)
        if let exact = candidates.first(where: { normalizeExerciseName($0.name) == qNorm }) {
            return exact
        }
        if let starts = candidates.first(where: { normalizeExerciseName($0.name).hasPrefix(qNorm) }) {
            return starts
        }

        // 2) скoring с Jaccard + наказания за специфични модификатори
        let negativeHints: Set<String> = [
            "single","one","oneleg","one-leg","singleleg","single-leg",
            "suspended","tabletop","ball","exercise","fyr2","kv","metaburn"
        ]
        var best: (idx: Int, score: Double)? = nil

        for (i, c) in candidates.enumerated() {
            let cNorm = normalizeExerciseName(c.name)
            let cToks = tokenSet(c.name)

            var score = jaccard(qToks, cToks) * 2.0 // базова прилика, по-силно тегло

            // фраза „hip thrust“ като цял substring носи бонус
            if cNorm.contains(qNorm) { score += 0.7 }

            // наказание за излишни токени извън заявката (търсим „по-генеричен“ вариант)
            let extras = cToks.subtracting(qToks).count
            score -= Double(extras) * 0.12

            // наказание за негативни модификатори (single-leg, suspended, …)
            let negHits = cToks.filter { negativeHints.contains($0) }.count
            score -= Double(negHits) * 0.6

            if best == nil || score > best!.score {
                best = (i, score)
            }
        }

        // праг за смисленост; ако е твърде ниско — няма да връщаме хевристика
        if let b = best, b.score >= 0.45 {
            return candidates[b.idx]
        }
        return nil
    }

    // MARK: - Identity helpers
    func magnitudeBucketMET(_ v: Double) -> String {
        let x = max(0, v)
        if x == 0 { return "zero" }
        if x <= 2   { return "very-low" }
        if x <= 4   { return "low" }
        if x <= 8   { return "moderate" }
        if x <= 12  { return "high" }
        return "very-high"
    }

    func magnitudeBucketMonths(_ m: Int) -> String {
        let x = max(0, m)
        switch x {
        case 0: return "zero"
        case 1...36: return "toddler"
        case 37...144: return "child"
        case 145...180: return "teen"
        default: return "adult"
        }
    }

    func nameSimilarity(_ a: String, _ b: String) -> Double {
        func tokens(_ s: String) -> Set<String> {
            let lowered = s.lowercased()
                .replacingOccurrences(of: #"[^a-zа-я0-9\s\-_/]"#, with: " ", options: .regularExpression)
            let raw = lowered.split{ $0.isWhitespace || $0 == "/" || $0 == "-" || $0 == "_" }.map(String.init)
            let stop: Set<String> = ["and","or","of","the","a","за","и","или"]
            return Set(raw.filter{ !stop.contains($0) })
        }
        let A = tokens(a), B = tokens(b)
        if A.isEmpty || B.isEmpty { return 0 }
        let inter = Double(A.intersection(B).count)
        let uni   = Double(A.union(B).count)
        return inter / uni
    }

    private func names(_ muscles: [MuscleGroup]) -> String {
        muscles.map { String(describing: $0) }.joined(separator: ", ")
    }

    private func names(_ sports: [Sport]) -> String {
        sports.map { String(describing: $0) }.joined(separator: ", ")
    }

    // ── Контекстни промптове на база similarExercise (меки подсказки, без копиране) ──
    private func createPromptWithReference_Description(
        basePrompt: String,
        exerciseName: String,
        similar: ExerciseItem?
    ) -> String {
        guard let sim = similar else { return basePrompt }
        let simScore = nameSimilarity(sim.name, exerciseName)
        guard simScore >= 0.6 else { return basePrompt }

        var extra: [String] = [
            "A nearby DB item is \"\(sim.name)\". DO NOT copy any text; identity stays strictly \"\(exerciseName)\"."
        ]
        if !sim.muscleGroups.isEmpty {
            extra.append("Typical muscles there: \(names(sim.muscleGroups)). Treat as plausibility only.")
        }
        if let ss = sim.sports, !ss.isEmpty {
            extra.append("Related sports there: \(names(ss)). Plausibility only.")
        }
        return basePrompt + "\n\nCONTEXT:\n- " + extra.joined(separator: "\n- ")
    }

    private func createPromptWithReference_MET(
        basePrompt: String,
        exerciseName: String,
        similar: ExerciseItem?
    ) -> String {
        guard let sim = similar else { return basePrompt }
        let simScore = nameSimilarity(sim.name, exerciseName)
        guard simScore >= 0.6 else { return basePrompt }

        let bucket = magnitudeBucketMET(sim.metValue ?? 0)
        return """
        \(basePrompt)

        CONTEXT (rough magnitude only — do NOT copy numbers):
        - A nearby DB item "\(sim.name)" suggests MET is \(bucket) for similar exercises.
        - If this contradicts the strict identity of "\(exerciseName)", IGNORE it.
        """
    }

    private func createPromptWithReference_Muscles(
        basePrompt: String,
        exerciseName: String,
        similar: ExerciseItem?
    ) -> String {
        guard let sim = similar, !sim.muscleGroups.isEmpty else { return basePrompt }
        let simScore = nameSimilarity(sim.name, exerciseName)
        guard simScore >= 0.6 else { return basePrompt }

        return """
        \(basePrompt)

        CONTEXT (plausibility hints only):
        - Nearby DB item "\(sim.name)" targets: \(names(sim.muscleGroups)).
        - Prefer canonical choices for "\(exerciseName)". Do not force identical muscles.
        """
    }

    private func createPromptWithReference_Sports(
        basePrompt: String,
        exerciseName: String,
        similar: ExerciseItem?
    ) -> String {
        guard let sim = similar, let ss = sim.sports, !ss.isEmpty else { return basePrompt }
        let simScore = nameSimilarity(sim.name, exerciseName)
        guard simScore >= 0.6 else { return basePrompt }

        return """
        \(basePrompt)

        CONTEXT (plausibility hints only):
        - Nearby DB item "\(sim.name)" relates to: \(names(ss)).
        - Prefer canonical sports for "\(exerciseName)". Do not force identical sports.
        """
    }

    private func createPromptWithReference_MinAge(
        basePrompt: String,
        exerciseName: String,
        similar: ExerciseItem?
    ) -> String {
        let (floorMin, reason) = inferredMinAgeFloor(for: exerciseName)

        var rules = """
        HARD RULES:
        - The output MUST be a single non-negative integer months value (no strings, no ranges).
        - Never output 0, and never output 12 unless the exercise is explicitly infant-safe (e.g., crawling/tummy time).
        - For '\(exerciseName)', the minimum age MUST be AT LEAST \(floorMin) months (reason: \(reason)).
        - If this exercise is a heavy barbell or Olympic lift, prefer ≥168 months even if context suggests lower.
        - If unsure, choose the SAFER (older) age.
        """

        if let sim = similar {
            let simScore = nameSimilarity(sim.name, exerciseName)
            if simScore >= 0.6 {
                let bucket = magnitudeBucketMonths(sim.minimalAgeMonths)
                rules += """

                CONTEXT (bucketed hint, do NOT copy numbers):
                - A nearby DB item "\(sim.name)" suggests age bucket: \(bucket).
                - If this contradicts strict identity of "\(exerciseName)", IGNORE it.
                """
            }
        }

        return """
        \(basePrompt)

        \(rules)
        """
    }


    // MARK: - Public API
    func generateDetails(
        for exerciseName: String,
        ctx: ModelContext,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> ExerciseItemDTO {
        emitLog("🚀 Starting AI data generation for exercise '\(exerciseName)'…", onLog: onLog)

        // Базови инструкции – огледални спрямо Foods версията (STRICT ID + JSON only)
        let baseInstructions = """
        You are a structured fitness and exercise assistant. For EACH prompt:
        - Reply ONLY with JSON matching the provided schema (no extra keys, no prose, no code fences).
        - Treat every prompt as independent from chat history; do not reuse prior outputs.
        - EXERCISE IDENTITY IS STRICT:
          - The provided exercise name is the exact item. DO NOT substitute synonyms, variations, or different implements.
          - If the term could refer to related items, assume it refers to **exactly** the literal name provided and nothing else.
        - CRITICAL OUTPUT RULES:
          - Never output strings like "N/A", "NA", "nan", "null", empty strings, or objects missing required fields.
          - Numeric values must be finite, non-negative, and realistic.
        """

        @Sendable func makeSession() -> LanguageModelSession {
            LanguageModelSession(instructions: baseInstructions)
        }

        @Sendable func shortPause() async { try? await Task.sleep(nanoseconds: 300_000_000) }

        // Универсален helper (fresh session при всеки опит, експоненциален backoff)
        func askWithRetry<T: Decodable & Generable>(
            _ step: String,
            _ prompt: String,
            generating: T.Type,
            retries: Int = 5,
            backoffMs: Int = 400,
            maxTokens: Int? = nil
        ) async throws -> T {
            var attempt = 0
            var lastError: Error?

            while attempt <= retries {
                attempt += 1
                emitLog((attempt == 1 ? "  -> " : "  ↻ ") + "\(step) (attempt \(attempt))…", onLog: onLog)

                let localSession = makeSession()
                do {
                    let result = try await localSession.respond(
                        to: prompt,
                        generating: T.self,
                        includeSchemaInPrompt: true,
                        options: GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens)
                    ).content
                    emitLog("  ✅ \(step) ✓ (attempt \(attempt))", onLog: onLog)
                    await shortPause()
                    return result
                } catch {
                    lastError = error
                    emitLog("  ⚠️ \(step) failed on attempt \(attempt): \(error.localizedDescription)", onLog: onLog)
                    if attempt <= retries {
                        let rawDelay = Int(Double(backoffMs) * pow(1.8, Double(attempt - 1)))
                        let delayMs = min(rawDelay, 60_000)
                        emitLog("     …retrying after ~\(delayMs) ms with a fresh session", onLog: onLog)
                        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                    }
                }
            }
            throw lastError ?? NSError(domain: "AIGenerationError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error in \(step)"])
        }

        // shared identity prefix (като при Foods)
        var sharedPromptPrefix = """
        Exercise identity (STRICT — no substitution):
        - EXACT name (do not reinterpret or generalize): \(exerciseName)
        - Output must follow the JSON schema precisely. No prose. No extra keys.
        """

        // MARK: 0) Similar exercise search (SmartExerciseSearch → AI best-match)
        emitLog("  🔎 Fetching up to 20 potential reference exercises…", onLog: onLog)
        let exerciseSearcher = SmartExerciseSearch(container: ctx.container)
        let candidateIDs = await exerciseSearcher.searchExercisesAI(
            query: exerciseName,
            limit: 20,
            context: nil,
            requiredHeadwords: nil
        )

        var similarExercise: ExerciseItem? = nil

        if !candidateIDs.isEmpty {
            do {
                let descriptor = FetchDescriptor<ExerciseItem>(
                    predicate: #Predicate { candidateIDs.contains($0.persistentModelID) }
                )
                let candidates = try ctx.fetch(descriptor)
                if !candidates.isEmpty {
                    // 1) Първо опитваме детерминистично
                    if let picked = heuristicBestMatch(query: exerciseName, in: candidates) {
                        similarExercise = picked
                        emitLog("  ✅ Heuristic picked reference: '\(picked.name)'", onLog: onLog)
                    } else {
                        // 2) Ако няма хевристика – питаме AI по ИНДЕКС
                        let enumeratedList = candidates.enumerated().map { "\($0): \($1.name)" }.joined(separator: "\n")
                        let selectionSession = makeSession()
                        let selectionPrompt = """
                        You must pick the SINGLE best reference exercise for "\(exerciseName)".

                        Rules:
                        - Prefer candidates that match the head phrase exactly (e.g., 'hip thrust').
                        - Prefer general/canonical variants over brand/program-specific or overly modified versions.
                        - Penalize modifiers like 'single-leg', 'one-leg', 'suspended', 'tabletop', 'exercise ball'.
                        - If the query is generic, choose the most generic matching variant (fewest extra modifiers).
                        - Return the index from the enumerated list below. Return -1 ONLY if none is reasonably close.

                        Candidates (index: name):
                        \(enumeratedList)
                        """

                        let choice = try await selectionSession.respond(
                            to: selectionPrompt,
                            generating: AIBestExerciseChoice.self,
                            includeSchemaInPrompt: true
                        ).content

                        if choice.choiceIndex >= 0, choice.choiceIndex < candidates.count {
                            similarExercise = candidates[choice.choiceIndex]
                            emitLog("  ✅ AI selected reference exercise [\(choice.choiceIndex)]: '\(similarExercise!.name)' – \(choice.reason)", onLog: onLog)
                        } else {
                            // 3) Последен fallback – хевристика с по-нисък праг или топ резултат от търсачката
                            if let picked = heuristicBestMatch(query: exerciseName, in: candidates) {
                                similarExercise = picked
                                emitLog("  ✅ Heuristic fallback picked: '\(picked.name)'", onLog: onLog)
                            } else {
                                similarExercise = candidates.first
                                emitLog("  ⚠️ Falling back to top search result: '\(similarExercise!.name)'", onLog: onLog)
                            }
                        }
                    }
                }

            } catch {
                emitLog("  ⚠️ Could not fetch or process candidate exercises: \(error.localizedDescription)", onLog: onLog)
            }
        } else {
            emitLog("  ℹ️ No similar exercises found in the initial search.", onLog: onLog)
        }
        try Task.checkCancellation()
        // MARK: 1) Description (с референтен контекст, ако е приложим)
        let descPrompt = createPromptWithReference_Description(
            basePrompt: """
            Write a concise, helpful description for the EXACT exercise name '\(exerciseName)'.
            Focus on proper form cues and main benefits. Return ONLY the 'description' field.
            """,
            exerciseName: exerciseName,
            similar: similarExercise
        )
        let descResp = try await askWithRetry(
            "Description",
            sharedPromptPrefix + "\n\n" + descPrompt,
            generating: AIExerciseDescriptionResponse.self,
            maxTokens: 400
        )
        try Task.checkCancellation()
        // MARK: 2) Другите полета — всички с референтни „hints“
        let metPrompt = createPromptWithReference_MET(
            basePrompt: """
            Provide a typical Metabolic Equivalent (MET) value for the exercise '\(exerciseName)'.
            Return ONLY the 'metValue' field as a number.
            """,
            exerciseName: exerciseName,
            similar: similarExercise
        )

        let musclesPrompt = createPromptWithReference_Muscles(
            basePrompt: """
            List the primary muscle groups targeted by '\(exerciseName)'.
            Choose ONLY from the provided enum values. Return ONLY the 'muscleGroups' array.
            """,
            exerciseName: exerciseName,
            similar: similarExercise
        )

        let sportsPrompt = createPromptWithReference_Sports(
            basePrompt: """
            List sports that benefit from or include '\(exerciseName)'.
            Choose ONLY from the provided enum values. Return ONLY the 'sports' array.
            """,
            exerciseName: exerciseName,
            similar: similarExercise
        )

        let minAgePrompt = createPromptWithReference_MinAge(
            basePrompt: """
            Estimate the minimum suitable age in months for a child to safely perform a variation of '\(exerciseName)'.
            If it's primarily for adults, use a higher number like 192 (16 years).
            Return ONLY the 'minAgeMonths' field.
            """,
            exerciseName: exerciseName,
            similar: similarExercise
        )

        // MARK: 3) Паралелни задачи
        let metTask = Task<AIExerciseMETValueResponse, Error> {
            try await askWithRetry(
                "MET Value",
                sharedPromptPrefix + "\n\n" + metPrompt,
                generating: AIExerciseMETValueResponse.self
            )
        }
        await globalTaskManager.addTask(metTask)
        try Task.checkCancellation()

        let musclesTask = Task<AIExerciseMuscleGroupsResponse, Error> {
            try await askWithRetry(
                "Muscle Groups",
                sharedPromptPrefix + "\n\n" + musclesPrompt,
                generating: AIExerciseMuscleGroupsResponse.self,
                maxTokens: 600
            )
        }
        await globalTaskManager.addTask(musclesTask)
        try Task.checkCancellation()

        let sportsTask = Task<AIExerciseSportsResponse, Error> {
            try await askWithRetry(
                "Related Sports",
                sharedPromptPrefix + "\n\n" + sportsPrompt,
                generating: AIExerciseSportsResponse.self,
                maxTokens: 600
            )
        }
        await globalTaskManager.addTask(sportsTask)
        try Task.checkCancellation()

        let minAgeTask = Task<AIExerciseMinAgeResponse, Error> {
            try await askWithRetry(
                "Min Age (months)",
                sharedPromptPrefix + "\n\n" + minAgePrompt,
                generating: AIExerciseMinAgeResponse.self
            )
        }
        await globalTaskManager.addTask(minAgeTask)
        try Task.checkCancellation()

        // --- END OF CHANGE ---

        // MARK: 4) Await & map към домейн
        let metResp       = try await metTask.value
        let musclesResp   = try await musclesTask.value
        let sportsResp    = try await sportsTask.value
        let minAgeResp    = try await minAgeTask.value
        try Task.checkCancellation()
        let correctedMinAge = validateAndCorrectMinAge(minAgeResp.minAgeMonths, for: exerciseName, onLog: onLog)
        let domainMuscles: [MuscleGroup] = musclesResp.muscleGroups.compactMap { $0.toDomain() }
        let domainSports:  [Sport]       = sportsResp.sports.compactMap { $0.toDomain() }
        try Task.checkCancellation()
        let dto = ExerciseItemDTO(
            id: 0,
            title: exerciseName,
            desc: descResp.description,
            muscleGroups: domainMuscles,
            metValue: metResp.metValue,
            sports: domainSports,
            minimalAgeMonths: correctedMinAge
        )
        
        emitLog("✅ Successfully generated all details for '\(exerciseName)'.", onLog: onLog)
        return dto
    }

    // MARK: - UI Mapping (оставен без промяна)
    @MainActor
    func mapResponseToState(
        dto: ExerciseItemDTO
    ) -> (
        description: String,
        metValueString: String,
        selectedMuscleGroups: Set<MuscleGroup.ID>,
        selectedSports: Set<Sport.ID>,
        minAgeMonthsTxt: String
    ) {
        let description = dto.desc ?? ""
        let metValueString = dto.metValue.map { String(format: "%.1f", $0) } ?? ""
        let selectedMuscleGroups = Set(dto.muscleGroups.map(\.id))
        let selectedSports = Set(dto.sports.map(\.id))
        let minAgeMonthsTxt: String = (dto.minimalAgeMonths ?? 0) > 0 ? String(dto.minimalAgeMonths!) : ""
        return (description, metValueString, selectedMuscleGroups, selectedSports, minAgeMonthsTxt)
    }
    
    // Хевристика: минимален възрастов ПРАГ (в месеци) според името
    private func inferredMinAgeFloor(for exerciseName: String) -> (floor: Int, reason: String) {
        let s = normalizeExerciseName(exerciseName)
        let toks = tokenSet(s)

        // Ключови групи (можеш да разширяваш списъците спокойно)
        let olympicLifts: Set<String> = ["snatch","clean","jerk","cleanandjerk","clean-and-jerk"]
        let heavyBarbell: Set<String> = ["barbell","deadlift","squat","bench","hip","thrust","row","overhead","press"]
        let freeWeights: Set<String>  = ["kettlebell","dumbbell","kb","db"]
        let machines: Set<String>     = ["machine","smith","cable","leg","press","lat","pulldown"]
        let plyoSpeed: Set<String>    = ["plyo","jump","box","sprint","hiit","burpee"]
        let calisthenics: Set<String> = ["pull","pullup","pull-up","dip","pushup","push-up","plank","bodyweight","chinup","chin-up"]
        let mobility: Set<String>     = ["mobility","stretch","stretching","yoga","pilates","balance","rehab","rehabilitation"]
        let infantSafe: Set<String>   = ["tummy","crawl","crawling"]

        func hasAny(_ set: Set<String>) -> Bool { !toks.intersection(set).isEmpty || set.contains(where: { s.contains($0) }) }

        // 1) Явно бебешко/инфант упражнение
        if hasAny(infantSafe) {
            return (12, "explicit infant-safe keywords")
        }

        // 2) Олимпийски щанги – изискват техника, координация, тренер
        if hasAny(olympicLifts) {
            return (168, "olympic lift heuristics (≥14y)")
        }

        // 3) Тежки щанги/силови базови
        if hasAny(heavyBarbell) {
            return (156, "heavy barbell heuristics (≥13y)")
        }

        // 4) Свободни тежести (гири/кети)
        if hasAny(freeWeights) {
            return (120, "free weights heuristics (≥10y)")
        }

        // 5) Машини/кабели – контролируеми, но все пак натоварване/размер
        if hasAny(machines) {
            return (132, "machines heuristics (≥11y)")
        }

        // 6) Плио/скорост – нужни зрялост/координация
        if hasAny(plyoSpeed) {
            return (96, "plyometrics/speed heuristics (≥8y)")
        }

        // 7) Калистеника – често става по-рано, но за универсална безопасност
        if hasAny(calisthenics) {
            return (84, "calisthenics heuristics (≥7y)")
        }

        // 8) Мобилност, стречинг, йога/пилатес, баланс
        if hasAny(mobility) {
            return (72, "mobility/yoga/pilates heuristics (≥6y)")
        }

        // 9) По подразбиране за неразпознато/възрастово рисково
        return (156, "default conservative floor (≥13y)")
    }

    // Пост-валидатор: коригира твърде ниски/нереалистични стойности според прага
    private func validateAndCorrectMinAge(_ raw: Int, for exerciseName: String, onLog: (@Sendable (String) -> Void)?) -> Int {
        let (floorMin, reason) = inferredMinAgeFloor(for: exerciseName)
        var v = max(0, raw)

        // Горен кап – 20 години (240 месеца), за да не се "изстреля" абсурдно
        if v > 240 { v = 240 }

        if v < floorMin {
            emitLog("  🔧 MinAge corrected from \(raw) → \(floorMin) (floor due to \(reason))", onLog: onLog)
            v = floorMin
        }

        // Специална защита: ако моделът “инатливо” даде 12 без infant-safe ключове → повдигаме
        if v == 12 {
            let toks = tokenSet(exerciseName)
            let infantSafe: Set<String> = ["tummy","crawl","crawling"]
            if toks.intersection(infantSafe).isEmpty {
                emitLog("  🔧 MinAge 12 raised to \(floorMin) (not infant-safe exercise)", onLog: onLog)
                v = max(v, floorMin)
            }
        }

        return v
    }

}

