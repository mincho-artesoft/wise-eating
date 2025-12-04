import Foundation
import SwiftData
import FoundationModels


// MARK: - Progress (actor)
@available(iOS 26.0, *)
private actor ProgressTracker {
    private var processed = 0
    private var succeeded = 0
    private var failedBatches = 0
    private let total: Int
    private let t0 = Date()

    init(total: Int) { self.total = total }

    func mark(batchItems: Int, successes: Int, failedBatch: Bool) {
        processed += batchItems
        succeeded += successes
        if failedBatch { failedBatches += 1 }
    }

    func snapshot() -> (processed: Int, succeeded: Int, failedBatches: Int, total: Int, elapsed: TimeInterval) {
        (processed, succeeded, failedBatches, total, Date().timeIntervalSince(t0))
    }
}

// MARK: - Worker (actor) – now generates String JSON + robust decoding
@available(iOS 26.0, *)
actor BatchLLMWorker {
    enum BatchErrorKind: Sendable { case none, contextOverflow, decoding }

    struct BatchEvalResult: Sendable {
        let successful: [(sid: String, score: Double, reason: String)]
        let failedCount: Int
        let errorReason: String?
        let errorKind: BatchErrorKind
        let submitted: [FoodForBatchEvaluation]
    }

    private let options: GenerationOptions
    private let systemPrompt: String
    private let model: SystemLanguageModel

    init(options: GenerationOptions, systemPrompt: String) {
        self.options = options
        self.systemPrompt = systemPrompt
        // Permissive for String outputs
        self.model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    // Exponential backoff with jitter
    private func backoff(attempt: Int, baseMs: UInt64 = 400) async {
        let factor = UInt64(1 << max(0, attempt - 1))
        let jitter = UInt64(Int.random(in: 0...250))
        try? await Task.sleep(nanoseconds: (baseMs * factor + jitter) * 1_000_000)
    }

    private func decodeBatch(from raw: String) -> AIBatchEvaluationResponse? {
        let decoder = JSONDecoder()
        // Try as-is
        if let d = raw.data(using: .utf8), let r = try? decoder.decode(AIBatchEvaluationResponse.self, from: d) {
            return r
        }
        // Try substring { ... }
        if let l = raw.firstIndex(of: "{"), let r = raw.lastIndex(of: "}") {
            let sub = String(raw[l...r])
            if let d2 = sub.data(using: .utf8), let r2 = try? decoder.decode(AIBatchEvaluationResponse.self, from: d2) {
                return r2
            }
        }
        return nil
    }

    func evaluateBatch(
        foods: [FoodForBatchEvaluation],
        rulesText: String,
        scoreCutoff: Double
    ) async -> BatchEvalResult {
        let encoder = JSONEncoder()
        if #available(iOS 17.0, *) { encoder.outputFormatting = [] } // compact JSON
        guard let encoded = try? encoder.encode(foods),
              let foodsJSON = String(data: encoded, encoding: .utf8) else {
            return .init(successful: [], failedCount: foods.count, errorReason: "Encoding error", errorKind: .none, submitted: foods)
        }

        let evaluationPrompt = """
        You are a strict JSON generator. Using the rules and the foods array below,
        return ONLY valid JSON with this exact shape (no prose, no markdown):

        {"evaluations":[{"sid":"<echo sid>","suitabilityScore":<0.0..1.0>,"reason":"<<=6 words>"} ...]}

        • Include exactly one object per input item, IN THE SAME ORDER AND COUNT.
        • If facts are missing, estimate conservatively.
        • Reasons must be neutral, non-medical, ≤ 6 words.
        • Respond in English, ASCII only.

        Rules: \(rulesText)
        Foods(JSON): \(foodsJSON)
        """

        let instructions = Instructions {
            @Sendable in systemPrompt + " Output JSON only."
        }
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            do {
                let session = LanguageModelSession(model: model, instructions: instructions)
                // Generate STRING (permissive guardrails), then decode JSON
                let raw = try await session.respond(to: evaluationPrompt, options: options).content
                guard let response = decodeBatch(from: raw) else {
                    throw LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "Could not decode JSON from model output"))
                }

                var ok: [(sid: String, score: Double, reason: String)] = []
                for eval in response.evaluations {
                    if let sid = eval.sid, eval.suitabilityScore >= scoreCutoff {
                        ok.append((sid, eval.suitabilityScore, eval.reason))
                    }
                }
                let failed = foods.count - ok.count
                return .init(successful: ok, failedCount: failed, errorReason: nil, errorKind: .none, submitted: foods)

            } catch {
                let msg = String(describing: error)
                let overflow = msg.localizedCaseInsensitiveContains("exceed") || msg.localizedCaseInsensitiveContains("context")
                let decoding = msg.localizedCaseInsensitiveContains("decoding")
                if attempt < maxAttempts {
                    await backoff(attempt: attempt)
                } else {
                    return .init(successful: [], failedCount: foods.count, errorReason: msg, errorKind: overflow ? .contextOverflow : (decoding ? .decoding : .none), submitted: foods)
                }
            }
        }
        return .init(successful: [], failedCount: foods.count, errorReason: "Unknown", errorKind: .none, submitted: foods)
    }
}

// MARK: - Main generator
@available(iOS 26.0, *)
@MainActor
final class AIDietGenerator {
    private let globalTaskManager = GlobalTaskManager.shared

    private let container: ModelContainer
    
    init(container: ModelContainer) { self.container = container }
    
    private func emitLog(_ message: String, onLog: (@Sendable (String) -> Void)?) {
        onLog?(message)
    }
    
    @MainActor
    private func saveProgress(
        jobID: PersistentIdentifier,
        progress: DietGenerationProgress,
        onLog: (@Sendable (String) -> Void)?
    ) async {
        // Ако задачата е отменена – не пишем нищо (избягва race при изтриване)
        if Task.isCancelled {
            emitLog("⏹️ [Progress] Task cancelled; skipping progress save.", onLog: onLog)
            return
        }

        do {
            // Винаги fresh контекст за да няма преплитане с UI/main
            let context = ModelContext(self.container)

            // ВАЖНО: рефетч по persistentModelID вместо context.model(for:)
            let fd = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.persistentModelID == jobID })
            guard let job = try context.fetch(fd).first else {
                emitLog("⚠️ [Progress] Job \(jobID) not found (deleted?) – skip save.", onLog: onLog)
                return
            }

            // Още една проверка точно преди писането за да пресечем race с delete
            try Task.checkCancellation()

            let data = try JSONEncoder().encode(progress)
            job.intermediateResultData = data
            try context.save()

            emitLog(
                "💾 [Progress] Saved (\(progress.processedFoodItemIDs.count) processed, \(progress.scoredResults.count) high-scored).",
                onLog: onLog
            )
        } catch is CancellationError {
            emitLog("⏹️ [Progress] Cancelled mid-save; skipping.", onLog: onLog)
        } catch {
            emitLog("❌ [Progress] Save failed: \(error.localizedDescription)", onLog: onLog)
        }
    }
    // --- END OF CHANGE ---


    private func generateDietName(prompts: [String], onLog: (@Sendable (String) -> Void)?) async -> String {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let options = GenerationOptions(sampling: .greedy, temperature: 0.0, maximumResponseTokens: 24)
        
        let collapsed = prompts.joined(separator: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let safeRules = String(collapsed.prefix(400))
        
        let nameInstructions = Instructions {
            """
            You are a neutral formatter. From given dietary rules, output a harmless, short diet name (2–4 words), ASCII only.
            Avoid sexual, violent, hateful, medical or unsafe content. If unsure, output 'Balanced Diet'.
            Output ONLY the name text (no quotes/markdown/punctuation beyond spaces or hyphens).
            Respond in English.
            """
        }
        let namePrompt = "Rules: \(safeRules)\nName:"
        
        do {
            let s = LanguageModelSession(model: model, instructions: nameInstructions)
            let raw = try await s.respond(to: namePrompt, options: options).content
            let cleaned = asciiClean(raw)
            return cleaned.isEmpty ? heuristicDietName(from: prompts) : cleaned
        } catch {
            emitLog("❌ Name gen failed (permissive String): \(error)", onLog: onLog)
            return heuristicDietName(from: prompts)
        }
    }
    
        @available(iOS 26.0, *)
        @MainActor
    func generateDiet(jobID: PersistentIdentifier, prompts: [String], onLog: (@Sendable (String) -> Void)?) async throws -> AIDietResponseDTO {
        emitLog("🚀 Starting BATCHED LLM-based diet generation with prompts: \(prompts)", onLog: onLog)
        let t0 = Date()
        
        let ctx = ModelContext(self.container)
        
        // --- START OF CORRECTION ---
        // 1. Проверяваме дали задачата все още съществува, преди да започнем.
        guard (ctx.model(for: jobID) as? AIGenerationJob) != nil else {
            emitLog("⚠️ Задачата с ID \(jobID) е била изтрита преди началото на генерирането. Прекратяване.", onLog: onLog)
            throw CancellationError()
        }
        
        // 2. Зареждаме прогреса, като извличаме обекта "job" само за тази операция.
        var progress: DietGenerationProgress
        if let job = ctx.model(for: jobID) as? AIGenerationJob,
           let data = job.intermediateResultData,
           let loadedProgress = try? JSONDecoder().decode(DietGenerationProgress.self, from: data) {
            progress = loadedProgress
            emitLog("🔄 Продължаване на генерирането на диета.", onLog: onLog)
        } else {
            progress = DietGenerationProgress(suggestedName: nil, exclusionKeywords: nil, processedFoodItemIDs: [], scoredResults: [:])
            emitLog("  -> Не е намерен съществуващ прогрес. Започва се отначало.", onLog: onLog)
        }
        // --- END OF CORRECTION ---
        
        // --- Checkpoint 1: Генериране на име ---
        let suggestedName: String
        if let cachedName = progress.suggestedName {
            suggestedName = cachedName
            emitLog("  -> ✅ Използване на кеширано име на диета: '\(suggestedName)'", onLog: onLog)
        } else {
            suggestedName = await generateDietName(prompts: prompts, onLog: onLog)
            progress.suggestedName = suggestedName
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog) // Запазваме след стъпката
            emitLog("✅ Генерирано и запазено име на диета: '\(suggestedName)'", onLog: onLog)
        }
        
        // Зареждаме всички храни от базата данни.
        var fd = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\FoodItem.name, order: .forward)])
        let allFoodsRaw = try ctx.fetch(fd)
        emitLog("📚 Заредени са \(allFoodsRaw.count) храни", onLog: onLog)
        guard !allFoodsRaw.isEmpty else { return .init(suggestedName: suggestedName, foodItemIDs: []) }
        
        // --- Checkpoint 2: Извличане на ключови думи за изключване ---
        let exclusion: [String]
        if let cachedKeywords = progress.exclusionKeywords {
            exclusion = cachedKeywords
            emitLog("  -> ✅ Използване на кеширани ключови думи за изключване: \(exclusion)", onLog: onLog)
        } else {
            exclusion = await aiDeriveExclusionKeywords(from: prompts, maxKeywords: 24, onLog: onLog)
            progress.exclusionKeywords = exclusion
            await saveProgress(jobID: jobID, progress: progress, onLog: onLog) // Запазваме след стъпката
            if !exclusion.isEmpty { emitLog("🧹 Генерирани и запазени ключови думи за изключване: \(exclusion)", onLog: onLog) }
        }
        
        // Прилагаме филтъра за ключови думи.
        let prefilteredFoods = allFoodsRaw.filter { !nameContainsAnyKeyword(name: $0.name, keywords: exclusion) }
        let removedCount = allFoodsRaw.count - prefilteredFoods.count
        emitLog("🧹 Филтрирани са \(removedCount) храни по ключови думи; остават \(prefilteredFoods.count).", onLog: onLog)
        
        var scored: [(id: PersistentIdentifier, score: Double)] = []
        var foodsToProcess: [FoodItem]
        
        let baseFoodList = prefilteredFoods.isEmpty ? allFoodsRaw : prefilteredFoods
        
        // --- Логика за възстановяване на прогреса при оценяване ---
        if !progress.processedFoodItemIDs.isEmpty {
            emitLog("  -> 🔄 Възстановяване на прогрес: \(progress.scoredResults.count) с висок резултат от \(progress.processedFoodItemIDs.count) общо обработени.", onLog: onLog)
            
            // Възстановяваме `scored` масива от запазените резултати
            let scoredFoodItemIDs = Set(progress.scoredResults.keys)
            if !scoredFoodItemIDs.isEmpty {
                let scoredItems = try ctx.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { scoredFoodItemIDs.contains($0.id) }))
                scored = scoredItems.compactMap { item in
                    guard let score = progress.scoredResults[item.id] else { return nil }
                    return (id: item.persistentModelID, score: score)
                }
            }
            
            // Филтрираме базовия списък, за да останат само тези храни, които НЕ са обработени
            foodsToProcess = baseFoodList.filter { food in
                !progress.processedFoodItemIDs.contains(food.id)
            }
            emitLog("  -> От \(baseFoodList.count) филтрирани храни, премахнати са \(baseFoodList.count - foodsToProcess.count) вече обработени.", onLog: onLog)
            emitLog("  -> Остават \(foodsToProcess.count) храни за обработка.", onLog: onLog)
        } else {
            // Ако няма прогрес, започваме с целия филтриран списък
            foodsToProcess = baseFoodList
        }
        
        // Ако няма повече храни за обработка, финализираме и излизаме.
        guard !foodsToProcess.isEmpty else {
            emitLog("✅ Няма повече храни за обработка. Финализиране на резултата.", onLog: onLog)
            // --- START OF CORRECTION ---
            // Извличаме обекта отново, преди да го модифицираме
            if let finalJob = ctx.model(for: jobID) as? AIGenerationJob {
                finalJob.intermediateResultData = nil
                try ctx.save()
            }
            // --- END OF CORRECTION ---
            
            if !scored.isEmpty {
                let sortedScores = scored.map { $0.score }.sorted()
                let p80 = sortedScores[Int(Double(sortedScores.count - 1) * 0.80)]
                let refined = max(0.55, min(0.8, p80))
                scored = scored.filter { $0.score >= refined }
            }
            
            let ids = scored.map { $0.id }
            let scoreMap = Dictionary(uniqueKeysWithValues: scored.map { ($0.id, $0.score) })
            let finalFD = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.persistentModelID) })
            let finalItems = try ctx.fetch(finalFD)
            let top = finalItems.sorted { a, b in
                let sa = scoreMap[a.persistentModelID] ?? 0
                let sb = scoreMap[b.persistentModelID] ?? 0
                return sa == sb ? (a.name < b.name) : (sa > sb)
            }
            
            emitLog("✅ Избрани са топ \(top.count) храни от предишния прогрес.", onLog: onLog)
            emitLog("✅ Общо време за изпълнение: \(String(format: "%.2f", Date().timeIntervalSince(t0))) секунди", onLog: onLog)
            
            return .init(suggestedName: suggestedName, foodItemIDs: top)
        }
        
        let allFoods = foodsToProcess
        
        // Подготвяме данните за LLM
        let evalData: [FoodForBatchEvaluation] = allFoods.map { f in
            let facts: FoodFacts? = {
                if let m = f.macronutrients {
                    return FoodFacts(p: m.protein?.value, c: m.carbohydrates?.value, f: m.fat?.value, r: (f.isRecipe || f.isMenu) ? 1 : 0)
                } else {
                    return (f.isRecipe || f.isMenu) ? FoodFacts(p: nil, c: nil, f: nil, r: 1) : nil
                }
            }()
            return FoodForBatchEvaluation(sid: String(f.id), name: f.name, facts: facts)
        }
        
        // Настройки за паралелна обработка
        let cpu = ProcessInfo.processInfo.processorCount
        let concurrencyLimit = min(16, max(6, cpu + 4))
        
        let rulesRaw = prompts.joined(separator: " ")
        let rulesText: String = {
            let collapsed = rulesRaw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let maxLen = 900
            return String(collapsed.prefix(maxLen))
        }()
        
        let batchSize = 8
        let approxTokensPerEval = 42
        let overheadTokens = 120
        let responseTokenBudget = min(1800, max(256, batchSize * approxTokensPerEval + overheadTokens))
        
        let responseOptions = GenerationOptions(
            sampling: .greedy,
            temperature: nil,
            maximumResponseTokens: responseTokenBudget
        )
        
        let scoreCutoff = 0.6
        
        let chunks = evalData.chunks(ofCount: batchSize)
        var workQueue: [ArraySlice<FoodForBatchEvaluation>] = chunks
        let totalItems = evalData.count
        let totalBatchesInitial = workQueue.count
        emitLog("⏳ Parallel evaluation of \(totalItems) foods in \(totalBatchesInitial) batches (size: \(batchSize), concurrency: \(concurrencyLimit))", onLog: onLog)
        
        let tracker = ProgressTracker(total: totalItems)
        let heartbeat = Task<Void, Never> { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
                guard !Task.isCancelled else { break }
                
                let s = await tracker.snapshot()
                if s.processed > 0 && s.processed < s.total {
                    let ips = Double(s.processed) / s.elapsed
                    let remaining = s.total - s.processed
                    let eta = ips > 0 ? Double(remaining) / ips : .infinity
                    
                    await MainActor.run {
                        self?.emitLog("📈 Progress: \(s.processed)/\(s.total) (✓\(s.succeeded), failed batches: \(s.failedBatches)). ETA: \(formatTimeInterval(eta))", onLog: onLog)
                    }
                }
            }
        }
        await globalTaskManager.addTask(heartbeat)
        try Task.checkCancellation()
        defer { heartbeat.cancel() }
        
        let systemPrompt = "Score foods using only provided numeric facts. Return JSON (AIBatchEvaluationResponse). Echo 'sid'. Reasons ≤6 words. No prose."
        let worker = BatchLLMWorker(options: responseOptions, systemPrompt: systemPrompt)
        
        var requeueCountByKey: [String: Int] = [:]
        
        let groupTask = Task<Void, Error> {
            try await withThrowingTaskGroup(of: BatchLLMWorker.BatchEvalResult.self) { group in
                func enqueue(_ foods: ArraySlice<FoodForBatchEvaluation>) {
                    let submitted = Array(foods)
                    group.addTask { @Sendable in
                        await worker.evaluateBatch(foods: submitted, rulesText: rulesText, scoreCutoff: scoreCutoff)
                    }
                }
                
                for _ in 0..<min(concurrencyLimit, workQueue.count) {
                    if workQueue.isEmpty { break }
                    enqueue(workQueue.removeFirst())
                }
                
                var processedBatches = 0
                while let result = try await group.next() {
                    processedBatches += 1
                    let itemsInBatch = result.successful.count + result.failedCount
                    await tracker.mark(batchItems: itemsInBatch, successes: result.successful.count, failedBatch: result.errorKind != .none)
                    
                    if result.errorKind == .none {
                        for food in result.submitted {
                            if let foodID = Int(food.sid) {
                                progress.processedFoodItemIDs.insert(foodID)
                            }
                        }
                        
                        for e in result.successful {
                            if let foodID = Int(e.sid) {
                                let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == foodID })
                                if let item = (try? ctx.fetch(descriptor))?.first {
                                    scored.append((id: item.persistentModelID, score: e.score))
                                    progress.scoredResults[foodID] = e.score
                                    let s = String(format: "%.2f", e.score)
                                    emitLog("✅ [Batch \(processedBatches)/\(totalBatchesInitial)] id:\(foodID) = \(s) – \(e.reason)", onLog: onLog)
                                }
                            } else {
                                emitLog("⚠️ Грешен sid (не е Int) \(e.sid).", onLog: onLog)
                            }
                        }
                        
                        await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
                    }
                    
                    try Task.checkCancellation()
                    switch result.errorKind {
                    case .contextOverflow:
                        let failedFoods = ArraySlice(result.submitted)
                        let mid = max(1, failedFoods.count / 2)
                        let left = failedFoods.prefix(mid)
                        let right = failedFoods.suffix(from: failedFoods.index(failedFoods.startIndex, offsetBy: mid))
                        if !left.isEmpty { workQueue.append(left) }
                        if !right.isEmpty { workQueue.append(right) }
                        emitLog("↘️ Auto-downshift: split overflowing batch into \(left.count) + \(right.count).", onLog: onLog)
                    case .decoding:
                        let key = result.submitted.map { $0.sid }.joined(separator: ",")
                        let count = requeueCountByKey[key, default: 0]
                        if count < 1 {
                            requeueCountByKey[key] = count + 1
                            workQueue.append(ArraySlice(result.submitted))
                            emitLog("🔁 Decoding error: re-enqueued batch once.", onLog: onLog)
                        } else {
                            emitLog("🧯 Decoding still failing: dropping batch after 1 retry.", onLog: onLog)
                        }
                    case .none:
                        break
                    }
                    try Task.checkCancellation()
                    if let err = result.errorReason { emitLog("❌ Batch error: \(err)", onLog: onLog) }
                    try Task.checkCancellation()
                    if !workQueue.isEmpty {
                        enqueue(workQueue.removeFirst())
                    }
                    try Task.checkCancellation()
                }
            }
        }
        
        await globalTaskManager.addTask(groupTask)
        try await groupTask.value
        try Task.checkCancellation()
        
        // --- START OF CORRECTION ---
        // Извличаме обекта отново, преди да го модифицираме
        if let finalJob = ctx.model(for: jobID) as? AIGenerationJob {
            finalJob.intermediateResultData = nil
            try ctx.save()
            emitLog("✅ Генерирането на диета завърши успешно. Междинният прогрес е изчистен.", onLog: onLog)
        }
        // --- END OF CORRECTION ---
        
        if !scored.isEmpty {
            let sortedScores = scored.map { $0.score }.sorted()
            let p80 = sortedScores[Int(Double(sortedScores.count - 1) * 0.80)]
            let refined = max(0.55, min(0.8, p80))
            scored = scored.filter { $0.score >= refined }
        }
        
        let ids = scored.map { $0.id }
        let scoreMap = Dictionary(uniqueKeysWithValues: scored.map { ($0.id, $0.score) })
        let finalFD = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.persistentModelID) })
        let finalItems = try ctx.fetch(finalFD)
        let top = finalItems.sorted { a, b in
            let sa = scoreMap[a.persistentModelID] ?? 0
            let sb = scoreMap[b.persistentModelID] ?? 0
            return sa == sb ? (a.name < b.name) : (sa > sb)
        }
        
        emitLog("✅ Selected top \(top.count) foods.", onLog: onLog)
        emitLog("✅ Total execution time: \(String(format: "%.2f", Date().timeIntervalSince(t0))) seconds", onLog: onLog)
        return .init(suggestedName: suggestedName, foodItemIDs: top)
    }

    
    @available(iOS 26.0, *)
    @MainActor
    private func aiDeriveExclusionKeywords(
        from prompts: [String],
        maxKeywords: Int = 24,
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        
        // 1) Сгъстяване на входа
        let collapsed = prompts
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let safeRules = String(collapsed.prefix(600))
        
        // 2) Общи помощни
        func dedupAndCap(_ arr: [String]) -> [String] {
            var cleaned = arr
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            cleaned = Array(NSOrderedSet(array: cleaned)) as? [String] ?? cleaned
            if cleaned.count > maxKeywords { cleaned = Array(cleaned.prefix(maxKeywords)) }
            return cleaned
        }
        
        // 3) Първи път: типизирано извикване към схемата
        let typedOpts = GenerationOptions(
            sampling: .greedy,
            temperature: 0.0,
            maximumResponseTokens: 256 // по-щедро, за да не реже
        )
        
        let typedInstructions = Instructions {
            """
            Generate exclusion KEYWORDS for FOOD NAMES based on the provided diet rules.
            Return ONLY JSON that matches the provided schema EXACTLY.
            If unsure, return {"keywords": []}.
            Constraints:
            • ASCII only; neutral.
            • 1–3 words per keyword.
            • Avoid generic words.
            • Include only terms that CONTRADICT the rules.
            • Limit to the requested maximum count.
            """
        }
        
        let typedPrompt = """
        Diet rules / user prompts:
        \(safeRules)
        
        Max count: \(maxKeywords)
        """
        
        let typedAttempts = 2
        for attempt in 1...typedAttempts {
            do {
                let session = LanguageModelSession(model: model, instructions: typedInstructions)
                let resp = try await session.respond(
                    to: typedPrompt,
                    generating: ExclusionKeywordsResponse.self,
                    includeSchemaInPrompt: true,
                    options: typedOpts
                )
                let out = dedupAndCap(resp.content.keywords)
                if !out.isEmpty {
                    onLog?("🧹 Typed keywords OK on attempt \(attempt): \(out.count) items.")
                    return out
                } else {
                    onLog?("🧹 Typed empty on attempt \(attempt).")
                }
            } catch {
                onLog?("🧹 Typed attempt \(attempt) failed: \(error)")
            }
        }
        
        // 4) Fallback: String-only + JSON repair
        onLog?("🧹 Falling back to String generation for keywords...")
        let stringOpts = GenerationOptions(sampling: .greedy, temperature: 0.0, maximumResponseTokens: 192)
        
        let stringInstructions = Instructions {
            """
            You are a strict JSON emitter.
            Output ONLY JSON, no prose, no markdown.
            Prefer the exact shape: {"keywords": ["...", "..."]}.
            If you cannot comply, output just ["...", "..."].
            Never include comments or trailing commas. ASCII only.
            """
        }
        
        let stringPrompt = """
        Diet rules / user prompts:
        \(safeRules)
        
        Task: produce exclusion keywords for FOOD NAMES that contradict these rules.
        Limit to \(maxKeywords) items. Each 1–3 words, concise, ASCII.
        
        Output ONLY JSON as described.
        """
        
        do {
            let s = LanguageModelSession(model: model, instructions: stringInstructions)
            let raw = try await s.respond(to: stringPrompt, options: stringOpts).content
            if let arr = parseKeywordsFromStringJSON(raw, maxKeywords: maxKeywords) {
                let final = dedupAndCap(arr)
                onLog?("🧹 String fallback extracted \(final.count) keywords.")
                return final
            } else {
                onLog?("🧹 String fallback could not parse JSON.")
            }
        } catch {
            onLog?("🧹 String fallback failed: \(error)")
        }
        
        // 5) Последна линия – празен списък
        onLog?("🧹 Returning [] after all attempts.")
        return []
    }
    
    // MARK: - Helpers for fallback JSON extraction
    
    /// Accepts either:
    /// 1) {"keywords":[...]}  or
    /// 2) ["...", "..."]  (bare array)
    /// Tries to repair minor issues (quotes, stray prose) by slicing first JSON array/object found.
    private func parseKeywordsFromStringJSON(_ raw: String, maxKeywords: Int) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try object {"keywords":[...]}
        if let objRange = trimmed.range(of: #"(?s)\{\s*"?keywords"?\s*:\s*\[[^\]]*\]\s*\}"#, options: .regularExpression) {
            let obj = String(trimmed[objRange])
            if let data = obj.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = dict["keywords"] as? [Any] {
                return arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        
        // Try bare array [...]
        if let arrRange = trimmed.range(of: #"(?s)\[[^\]]*\]"#, options: .regularExpression) {
            let arrStr = String(trimmed[arrRange])
            if let data = arrStr.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        
        // Light repair: replace single quotes with double and retry array parse
        let repaired = trimmed.replacingOccurrences(of: #"(?<!\\)\'"#, with: "\"", options: .regularExpression)
        if let arrRange = repaired.range(of: #"(?s)\[[^\]]*\]"#, options: .regularExpression) {
            let arrStr = String(repaired[arrRange])
            if let data = arrStr.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        
        return nil
    }
    
}
