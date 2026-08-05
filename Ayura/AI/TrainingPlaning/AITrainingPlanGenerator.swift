import SwiftData
import Foundation
import FoundationModels

// MARK: - Helper Struct (File Level Scope)
private struct MustDoRule: Equatable, Hashable {
    let day: Int
    let workout: String? // e.g., "Morning Workout"
    let exercise: String // e.g., a muscle group or a specific exercise
}


@available(iOS 26.0, *)
@MainActor
final class AITrainingPlanGenerator {
    
    private let container: ModelContainer
    
    init(container: ModelContainer) {
        self.container = container
    }
    
    // MARK: - Public API (Orchestrator)
    
    @MainActor
    func fillPlanDetails(
        jobID: PersistentIdentifier, // Добавяме jobID
        profileID: PersistentIdentifier,
        prompts: [String],
        workoutsToFill: [Int: [String]],
        existingWorkouts: [Int: [TrainingPlanWorkoutDraft]]?,
        plannedTimes: [Int: Date] = [:],
        plannedWorkoutTimes: [String: Date] = [:],
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> TrainingPlanDraft {
        
        func tag(_ s: String) -> String { "[AI BG TrainingPlan]   \(s)" }
        
        emit(tag("📥 BEGIN fillPlanDetails"), onLog)
        try Task.checkCancellation()
        
        let ctx = ModelContext(self.container)
        guard let job = ctx.model(for: jobID) as? AIGenerationJob else {
            throw NSError(domain: "AITrainingPlanGenerator", code: 404, userInfo: [NSLocalizedDescriptionKey: "AIGenerationJob not found."])
        }
        
        var progress: TrainingPlanGenerationProgress
        if let data = job.intermediateResultData, let loaded = try? JSONDecoder().decode(TrainingPlanGenerationProgress.self, from: data) {
            progress = loaded
            emit(tag("🔄 Възобновяване на генерирането на тренировъчен план."), onLog)
        } else {
            progress = TrainingPlanGenerationProgress()
            emit(tag("  -> Не е намерен съществуващ прогрес. Започва се отначало."), onLog)
        }
        
        guard let profile = ctx.model(for: profileID) as? Profile else {
            let err = NSError(domain: "AITrainingPlanGenerator", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found."])
            emit(tag("❌ Aborting (no profile)."), onLog)
            throw err
        }
        try Task.checkCancellation()
        
        emit(tag("👤 Profile: \(profile.name) | age=\(profile.age) | gender=\(profile.gender)"), onLog)
        
        do {
            emit(tag("🚀 Starting Training Plan Generation for '\(profile.name)'..."), onLog)
            
            // ================
            // STAGE 1: Interpretation & Specialization
            // ================
            if progress.interpretedPrompts == nil {
                let atomicPromptsRaw = await aiSplitIntoAtomicPrompts(prompts, onLog: onLog)
                let (included0, excluded0) = await aiExtractRequestedExercises(from: atomicPromptsRaw, onLog: onLog)
                let fix = await aiFixAtomsAndExercises(originalPrompts: prompts, atoms: atomicPromptsRaw, included: included0, excluded: excluded0, onLog: onLog)
                
                progress.atomicPrompts = fix.directives
                progress.includedExercises = fix.included
                progress.excludedExercises = fix.excluded
                progress.interpretedPrompts = await aiInterpretUserPrompts(prompts: fix.directives, workoutsToFill: workoutsToFill, onLog: onLog)
                
                await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
                emit(tag("✅ Checkpoint 1: Интерпретацията е завършена и запазена."), onLog)
            } else {
                emit(tag("  -> ✅ Checkpoint 1: Използване на кеширани резултати от интерпретация."), onLog)
            }
            guard var interpreted = progress.interpretedPrompts else { throw NSError(domain: "AITrainingPlanGenerator", code: 501, userInfo: [NSLocalizedDescriptionKey: "Interpretation failed."]) }
            
            // ===============================
            // STAGE 2: Context & Palettes
            // ===============================
            if progress.palettes == nil || progress.specializedStructuralRequests == nil {
                let (contextTags, _) = await aiInferContextTags(structural: interpreted.structuralRequests, qualitative: interpreted.qualitativeGoals, included: progress.includedExercises ?? [], onLog: onLog)
                progress.contextTags = contextTags
                
                var palettes: [String: [String]] = [:]
                for tagObj in contextTags {
                    let key = "\(tagObj.kind):\(tagObj.tag)"
                    palettes[key] = await aiGenerateExercisePaletteForContext(profile: profile, context: tagObj, onLog: onLog)
                }
                progress.palettes = palettes
                
                let specializedRequests = await specializeStructuralRequestsWithVariants(requests: interpreted.structuralRequests, workoutsToFill: workoutsToFill, palettes: palettes, profile: profile, onLog: onLog)
                interpreted.structuralRequests = specializedRequests
                progress.specializedStructuralRequests = specializedRequests
                progress.interpretedPrompts = interpreted // Запазваме и обновените промпти
                
                await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
                emit(tag("✅ Checkpoint 2: Контекстът и палитрите са генерирани и запазени."), onLog)
            } else {
                emit(tag("  -> ✅ Checkpoint 2: Използване на кеширани палитри и специализирани промпти."), onLog)
                interpreted.structuralRequests = progress.specializedStructuralRequests!
            }
            guard let palettes = progress.palettes else { throw NSError(domain: "AITrainingPlanGenerator", code: 502, userInfo: [NSLocalizedDescriptionKey: "Palette generation failed."]) }
            
            // ===============================
            // STAGE 3: Main AI Generation
            // ===============================
            if progress.conceptualPlan == nil {
                progress.conceptualPlan = try await generateFullPlanWithAI(
                    profile: profile, workoutsToFill: workoutsToFill, interpretedPrompts: interpreted,
                    palettes: palettes, includedExercises: progress.includedExercises ?? [],
                    excludedExercises: progress.excludedExercises ?? [], existingWorkouts: existingWorkouts, onLog: onLog
                )
                await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
                emit(tag("✅ Checkpoint 3: Концептуалният план е генериран и запазен."), onLog)
            } else {
                emit(tag("  -> ✅ Checkpoint 3: Използване на кеширан концептуален план."), onLog)
            }
            guard var conceptualPlan = progress.conceptualPlan else { throw NSError(domain: "AITrainingPlanGenerator", code: 503, userInfo: [NSLocalizedDescriptionKey: "Conceptual plan generation failed."]) }
            
            debugDumpConceptualPlan(conceptualPlan, title: "RAW CONCEPTUAL PLAN", onLog: onLog)
            
            // ==========================================
            // STAGE 4: Post-Processing & Refinement (бърз етап, изпълнява се винаги)
            // ==========================================
            let mustDoRules = parseMustDoRules(from: interpreted.structuralRequests, onLog: onLog)
            conceptualPlan = await polishConceptualPlan(
                plan: conceptualPlan, profile: profile, workoutsToFill: workoutsToFill,
                rules: mustDoRules, excludedExercises: progress.excludedExercises ?? [],
                palettes: palettes, onLog: onLog
            )
            debugDumpConceptualPlan(conceptualPlan, title: "FINAL CONCEPTUAL PLAN", onLog: onLog)
            
            // ===========================
            // STAGE 5: Resolution (с частично запазване)
            // ===========================
            let resolvedPlanDraft = await resolveConceptualPlan(
                conceptualPlan,
                progress: &progress, // Подаваме за модификация
                jobID: jobID,
                plannedTimes: plannedTimes,
                plannedWorkoutTimes: plannedWorkoutTimes,
                onLog: onLog
            )
            
            emit(tag("✅ Генерирането на план завърши. Изчистване на междинния прогрес."), onLog)
            job.intermediateResultData = nil
            try ctx.save()
            
            emit(tag("📤 END fillPlanDetails → TrainingPlanDraft '\(resolvedPlanDraft.name)' with \(resolvedPlanDraft.days.flatMap { $0.trainings }.count) training(s)."), onLog)
            return resolvedPlanDraft
            
        } catch {
            emit(tag("❌ END fillPlanDetails with error: \(error.localizedDescription)"), onLog)
            throw error
        }
    }
    
    // MARK: - STAGE 1: Interpretation
    
    private func aiSplitIntoAtomicPrompts(_ prompts: [String], onLog: (@Sendable (String) -> Void)?) async -> [String] {
        guard !prompts.isEmpty else { return [] }
        
        let instructions = Instructions {
            """
            You split messy, compound training requests into atomic, standalone directives.
            RULES:
            - Each unit MUST express exactly one requirement (day/workout placement, inclusion/exclusion, frequency).
            - Preserve negations ("no", "avoid", "without").
            - If a line has multiple 'and/;/-/•' parts, split it.
            - Keep wording concise and preserve the user's intent.
            - Return at most 16 units.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        
        var allAtoms: [String] = []
        for single in prompts {
            do {
                try Task.checkCancellation()
                
                let resp = try await session.respond(
                    to: "Split into atomic directives:\n\n\(single)",
                    generating: AIAtomicTrainingPromptsResponse.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(sampling: .greedy)
                )
                try Task.checkCancellation()
                
                let atoms = resp.content.directives
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters) }
                    .filter { !$0.isEmpty }
                    .map { s in
                        var x = s; if let first = x.first { x.replaceSubrange(x.startIndex...x.startIndex, with: String(first).uppercased()) }; return x
                    }
                try Task.checkCancellation()
                
                allAtoms.append(contentsOf: atoms)
                try Task.checkCancellation()
                
            } catch {
                onLog?("    - ⚠️ Atomic split via AI failed for prompt: '\(single)'.")
            }
        }
        
        var seen = Set<String>()
        let uniqueAtoms = allAtoms.filter { seen.insert($0.lowercased()).inserted }
        
        if !uniqueAtoms.isEmpty { emit("  -> Atomic prompts (AI): \(uniqueAtoms)", onLog) }
        return uniqueAtoms
    }
    
    private func specializeStructuralRequestsWithVariants(
        requests: [String],
        workoutsToFill: [Int: [String]],
        palettes: [String: [String]],
        profile: Profile,
        onLog: (@Sendable (String) -> Void)?
    ) async -> [String] {
        emit("  -> Specializing structural requests for variety...", onLog)
        
        let genericMuscleGroups: Set<String> = [
            "arm", "arms", "arm workout", "legs", "leg", "chest", "back",
            "shoulders", "shoulder", "core", "upper body", "full body"
        ]
        
        var finalRequests: [String] = []
        var requestsToRewrite: Set<String> = []
        
        var topicsToSpecialize: [String: [MustDoRule]] = [:]
        for req in requests {
            for rule in parseMustDoRules(from: [req], onLog: onLog) {
                let topic = rule.exercise.lowercased()
                if genericMuscleGroups.contains(topic) {
                    requestsToRewrite.insert(req)
                    topicsToSpecialize[topic, default: []].append(rule)
                }
            }
        }
        
        if topicsToSpecialize.isEmpty {
            return requests
        }
        
        var assetsByTopic: [String: [String]] = palettes
        for topic in topicsToSpecialize.keys {
            
            let potentialKeys = ["musclegroup:\(topic)", "headword:\(topic)"]
            let existingKey = potentialKeys.first { assetsByTopic[$0]?.isEmpty == false }
            
            if existingKey == nil {
                let context = AITrainingContextTag(kind: "muscleGroup", tag: topic)
                let palette = await aiGenerateExercisePaletteForContext(profile: profile, context: context, onLog: onLog)
                if !palette.isEmpty {
                    assetsByTopic["musclegroup:\(topic)"] = palette
                    emit("    - [Specialize] Fetched new palette for topic='\(topic)' -> \(palette.count) exercises", onLog)
                }
            }
        }
        
        for (topic, rules) in topicsToSpecialize {
            
            for rule in rules {
                guard let workoutNames = workoutsToFill[rule.day], !workoutNames.isEmpty else { continue }
                
                let relevantPalette = assetsByTopic["musclegroup:\(topic)"]
                ?? assetsByTopic["headword:\(topic)"]
                ?? assetsByTopic["trainingtype:\(topic)"]
                
                guard let palette = relevantPalette, !palette.isEmpty else {
                    emit("    - ⚠️ [Specialize] Could not find any palette for topic '\(topic)'. Skipping rewrite.", onLog)
                    continue
                }
                
                var availableExercises = palette.shuffled()
                
                for workoutName in workoutNames {
                    let injectionCount = Int.random(in: 4...5)
                    let exercisesToInject = (0..<injectionCount).compactMap { _ -> String? in
                        guard !availableExercises.isEmpty else { return nil }
                        return availableExercises.removeFirst()
                    }
                    
                    if !exercisesToInject.isEmpty {
                        let exerciseList = exercisesToInject.map { "'\($0)'" }.joined(separator: ", ")
                        let rewritten = "On Day \(rule.day), the \(workoutName) must contain \(exerciseList)."
                        finalRequests.append(rewritten)
                        emit("    - REWRITTEN rule: \"\(rewritten)\"", onLog)
                    }
                }
                
                let otherDays = workoutsToFill.keys.filter { $0 != rule.day }
                if !otherDays.isEmpty {
                    let negative = "On Days \(otherDays.map(String.init).joined(separator: ", ")), workouts MUST NOT focus on \(topic) and should be for general fitness or other goals."
                    finalRequests.append(negative)
                    emit("    - ADDED negative constraint: \"\(negative)\"", onLog)
                }
            }
        }
        
        finalRequests.append(contentsOf: requests.filter { !requestsToRewrite.contains($0) })
        
        var seen = Set<String>()
        return finalRequests.filter { seen.insert($0.lowercased()).inserted }
    }
    
    // MARK: - STAGE 2: Context & Palette Generation
    
    private func aiInferContextTags(
        structural: [String], qualitative: [String], included: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async -> (tags: [AITrainingContextTag], headwords: [String]) {
        let session = LanguageModelSession(instructions: Instructions {
            """
            Identify primary training themes. Classify each into a `kind`:
            - `trainingType`: style (strength, cardio, HIIT, flexibility).
            - `muscleGroup`: major group (legs, chest, back, shoulders, arms, core, full body).
            - `headword`: a specific, named exercise as a central focus.
            Return the 1-3 most dominant themes. Keep tags lowercase.
            """
        })
        let prompt = "STRUCTURAL: \(structural.joined(separator: " | "))\nQUALITATIVE: \(qualitative.joined(separator: " | "))\nINCLUDED: \(included.joined(separator: " | "))"
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(to: prompt, generating: AITrainingContextTagsResponse.self, includeSchemaInPrompt: true).content
            try Task.checkCancellation()
            
            let tags = resp.tags.map { AITrainingContextTag(kind: $0.kind.lowercased(), tag: $0.tag.lowercased().replacingOccurrences(of: "_", with: " ")) }
            let headwords = tags.filter { $0.kind == "headword" }.map { $0.tag }
            try Task.checkCancellation()
            
            if !tags.isEmpty { emit("  -> Context tags inferred: \(tags.map { "\($0.kind):\($0.tag)" }.joined(separator: ", "))", onLog) }
            return (tags, headwords)
        } catch {
            emit("  -> ⚠️ Context inference failed: \(error.localizedDescription)", onLog)
            return ([], [])
        }
    }
    
    private func aiGenerateExercisePaletteForContext(profile: Profile, context: AITrainingContextTag, onLog: (@Sendable (String) -> Void)?) async -> [String] {
        let session = LanguageModelSession(instructions: Instructions {
           """
           Generate 15–25 common, specific exercises for a training context.
           - Names must be specific (use clear, standard exercise names; avoid vague categories).
           - Ensure variety (compound, isolation, bodyweight).
           - Strictly respect the user's profile and goals.
           """
        })
        let prompt = "PROFILE: Age \(profile.age), Gender \(profile.gender)\nCONTEXT: \(context.kind): \(context.tag)"
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(to: prompt, generating: AIExercisePaletteResponse.self, includeSchemaInPrompt: true).content
            try Task.checkCancellation()
            emit("  -> Palette for [\(context.kind):\(context.tag)] created with \(resp.exercises.count) items.", onLog)
            return resp.exercises
        } catch {
            emit("  -> ⚠️ Palette gen failed for [\(context.kind):\(context.tag)]: \(error.localizedDescription)", onLog)
            return []
        }
    }
    
    // MARK: - STAGE 3: Main AI Generation
    
    private func generateFullPlanWithAI(
        profile: Profile,
        workoutsToFill: [Int: [String]],
        interpretedPrompts: InterpretedTrainingPrompts,
        palettes: [String: [String]],
        includedExercises: [String],
        excludedExercises: [String],
        existingWorkouts: [Int: [TrainingPlanWorkoutDraft]]?,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> AIConceptualTrainingPlanResponse {
        let planStructure = workoutsToFill.keys.sorted().map { "Day \($0): [\(workoutsToFill[$0]!.joined(separator: ", "))]" }.joined(separator: "\n")
        let existingWorkoutsText = buildExistingWorkoutsText(existingWorkouts)
        
        let palettesText = palettes.sorted(by: { $0.key < $1.key }).map { (key, exercises) in "--- EXERCISE PALETTE for [\(key)] ---\n- \(exercises.joined(separator: ", "))" }.joined(separator: "\n\n")
        
        let mandatoryPlacements = interpretedPrompts.structuralRequests
        let mandatoryPlacementsSection = mandatoryPlacements.isEmpty ? "" : "--- MANDATORY PLACEMENT RULES (HIGHEST PRIORITY) ---\nYou MUST follow these rules exactly. They override all other hints.\n- \(mandatoryPlacements.joined(separator: "\n- "))"
        
        let rules = """
        --- CORE DIRECTIVES (STRUCTURE IS CRITICAL) ---
        1.  **Plan Structure**: Your output MUST contain ONLY the days and workout names specified below.
            \(planStructure)
        2.  **Workout Names**: Each workout `name` MUST EXACTLY match one from the structure.
        3.  **Composition**: Each workout MUST contain **5–7 distinct** exercises.
        4.  **Durations**: Use a **varied mix** of durations (360–1200 seconds).
        5.  **Inter-Day Variety**: Do not repeat the exact same set of exercises across different days.
        6.  **Safety (age \(profile.age))**: Avoid unsafe lifts; prefer age-appropriate selections.
        
        \(mandatoryPlacementsSection)
        """
        
        let prompt = """
        \(palettesText)
        
        --- USER PROFILE & GOALS ---
        - Profile: Age \(profile.age), Gender \(profile.gender)
        - Qualitative Goals: \(interpretedPrompts.qualitativeGoals.isEmpty ? "None" : interpretedPrompts.qualitativeGoals.joined(separator: ", "))
        - Must Include (use on matching focus days): \(includedExercises.isEmpty ? "None" : includedExercises.joined(separator: ", "))
        - Must Exclude (CRITICAL): \(excludedExercises.isEmpty ? "None" : excludedExercises.joined(separator: ", "))
        \(existingWorkoutsText)
        
        TASK: Generate the plan now according to ALL rules.
        """
        
        let session = LanguageModelSession(instructions: Instructions { rules })
        emit("  -> Sending contextual prompt to AI for full plan generation...", onLog)
        
        do {
            try Task.checkCancellation()
            let response = try await session.respond(to: prompt, generating: AIConceptualTrainingPlanResponse.self, includeSchemaInPrompt: true, options: GenerationOptions(temperature: 0.6)).content
            try Task.checkCancellation()
            emit("  -> Conceptual plan received: '\(response.planName)' with \(response.days.count) day(s).", onLog)
            return response
        } catch {
            emit("  -> ⚠️ Main generation failed: \(error.localizedDescription). Retrying with simple prompt.", onLog)
            return try await generateConceptualPlanSimple(profile: profile, prompts: interpretedPrompts.structuralRequests, workoutsToFill: workoutsToFill, existingWorkouts: existingWorkouts, onLog: onLog)
        }
    }
    
    // MARK: - STAGE 4: Post-Processing & Refinement
    
    private func polishConceptualPlan(
        plan: AIConceptualTrainingPlanResponse,
        profile: Profile,
        workoutsToFill: [Int: [String]],
        rules: [MustDoRule],
        excludedExercises: [String],
        palettes: [String: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) async -> AIConceptualTrainingPlanResponse {
        emit("  -> Polishing conceptual plan...", onLog)
        var polished = plan
        
        polished = normalizeWorkoutNamesToRequestedStructure(plan: polished, workoutsToFill: workoutsToFill, onLog: onLog)
        polished = purgeExcludedExercises(plan: polished, excluded: excludedExercises, onLog: onLog)
        polished = await enforceMustDoExercises(plan: polished, rules: rules, onLog: onLog)
        
        let palettesNorm = await ensureGeneralPalettes(palettes: palettes, profile: profile, onLog: onLog)

        polished = await enrichAndVaryWorkouts(plan: polished, palettes: palettesNorm, excluded: excludedExercises, onLog: onLog)
        polished = await enforceInterDayVariety(plan: polished, protectedRules: rules, palettes: palettesNorm, onLog: onLog)
        polished = clampDurationsHeuristically(plan: polished, onLog: onLog)
        
        return polished
    }
    
    private func normalizeWorkoutNamesToRequestedStructure(
        plan: AIConceptualTrainingPlanResponse,
        workoutsToFill: [Int: [String]],
        onLog: (@Sendable (String) -> Void)?
    ) -> AIConceptualTrainingPlanResponse {
        var out = plan
        
        let wantedDays = Set(workoutsToFill.keys)
        out.days.removeAll { !wantedDays.contains($0.dayIndex) }
        for day in wantedDays where !out.days.contains(where: { $0.dayIndex == day }) {
            let emptyWorkouts = (workoutsToFill[day] ?? []).map { ConceptualWorkout(name: $0, exercises: []) }
            out.days.append(ConceptualTrainingDay(dayIndex: day, workouts: emptyWorkouts))
        }
        out.days.sort { $0.dayIndex < $1.dayIndex }
        
        for i in 0..<out.days.count {
            
            let dayIndex = out.days[i].dayIndex
            guard let requestedNames = workoutsToFill[dayIndex] else { continue }
            
            let generatedWorkouts = out.days[i].workouts
            var newWorkouts: [ConceptualWorkout] = []
            
            for (j, requestedName) in requestedNames.enumerated() {
                if j < generatedWorkouts.count {
                    var workout = generatedWorkouts[j]
                    if workout.name != requestedName {
                        emit("    - Aligning workout name: '\(workout.name)' -> '\(requestedName)' on Day \(dayIndex)", onLog)
                        workout.name = requestedName
                    }
                    newWorkouts.append(workout)
                } else {
                    newWorkouts.append(ConceptualWorkout(name: requestedName, exercises: []))
                }
            }
            out.days[i].workouts = newWorkouts
        }
        
        emit("  -> Aligned and normalized plan to requested structure.", onLog)
        return out
    }
    
    private func purgeExcludedExercises(plan: AIConceptualTrainingPlanResponse, excluded: [String], onLog: (@Sendable (String) -> Void)?) -> AIConceptualTrainingPlanResponse {
        guard !excluded.isEmpty else { return plan }
        var out = plan
        let banned = excluded.map { $0.lowercased() }
        var removedCount = 0
        for d in 0..<out.days.count {
            for w in 0..<out.days[d].workouts.count {
                let before = out.days[d].workouts[w].exercises.count
                out.days[d].workouts[w].exercises.removeAll { ex in let nameLower = ex.name.lowercased(); return banned.contains { nameLower.contains($0) } }
                removedCount += before - out.days[d].workouts[w].exercises.count
            }
        }
        if removedCount > 0 { emit("  -> Purged \(removedCount) excluded exercise(s).", onLog) }
        return out
    }
    
    private func enforceMustDoExercises(plan: AIConceptualTrainingPlanResponse, rules: [MustDoRule], onLog: (@Sendable (String) -> Void)?) async -> AIConceptualTrainingPlanResponse {
        guard !rules.isEmpty else { return plan }
        var out = plan
        for rule in rules {
            guard let dIdx = out.days.firstIndex(where: { $0.dayIndex == rule.day }) else { continue }
            
            let targetIndices: [Int] = {
                if let workoutName = rule.workout { return out.days[dIdx].workouts.indices.filter { out.days[dIdx].workouts[$0].name.caseInsensitiveCompare(workoutName) == .orderedSame } }
                return Array(out.days[dIdx].workouts.indices)
            }()
            
            for wIdx in targetIndices {
                let alreadyHas = out.days[dIdx].workouts[wIdx].exercises.contains { $0.name.range(of: rule.exercise, options: .caseInsensitive) != nil }
                if !alreadyHas {
                    out.days[dIdx].workouts[wIdx].exercises.insert(.init(name: rule.exercise, durationSeconds: 600), at: 0)
                    emit("  -> Enforced rule: Added '\(rule.exercise)' to Day \(rule.day) - \(out.days[dIdx].workouts[wIdx].name).", onLog)
                }
            }
        }
        return out
    }
    
    // MARK: - STAGE 5: Resolution
    @MainActor
    private func resolveConceptualPlan(
        _ conceptualPlan: AIConceptualTrainingPlanResponse,
        progress: inout TrainingPlanGenerationProgress,
        jobID: PersistentIdentifier,
        plannedTimes: [Int: Date],
        plannedWorkoutTimes: [String: Date],
        onLog: (@Sendable (String) -> Void)?
    ) async -> TrainingPlanDraft {
        let searcher = SmartExerciseSearch(container: self.container)
        let modelContext = ModelContext(self.container)
        
        if progress.resolvedDayDrafts == nil {
            progress.resolvedDayDrafts = []
        }
        
        let resolvedDayIndices = Set(progress.resolvedDayDrafts?.map { $0.dayIndex } ?? [])
        let daysToProcess = conceptualPlan.days
            .filter { !resolvedDayIndices.contains($0.dayIndex) }
            .sorted(by: { $0.dayIndex < $1.dayIndex })
        
        if !daysToProcess.isEmpty {
            emit("  • Resolving workouts for \(daysToProcess.count) remaining day(s)...", onLog)
        }
        
        for day in daysToProcess {
            var resolvedTrainingsForDay: [Training] = []
            for workout in day.workouts {
                var resolvedExercises: [ExerciseItem: Double] = [:]
                emit("  • Resolving workout: '\(workout.name)' (Day \(day.dayIndex))", onLog)
                
                for conceptualExercise in workout.exercises {
                    if let exerciseItem = await resolveOrCreateExercise(named: conceptualExercise.name, searcher: searcher, ctx: modelContext, onLog: onLog) {
                        resolvedExercises[exerciseItem] = Double(conceptualExercise.durationSeconds)
                    } else {
                        emit("    - ⚠️ Could not resolve '\(conceptualExercise.name)' → skipped", onLog)
                    }
                }
                
                guard !resolvedExercises.isEmpty else { continue }
                
                let chosenStart = plannedWorkoutTimes[workout.name] ?? plannedTimes[day.dayIndex] ?? Date()
                let totalMinutes = resolvedExercises.values.reduce(0, +)
                let endTime = chosenStart.addingTimeInterval(totalMinutes * 60.0)
                
                let training = Training(name: workout.name, startTime: chosenStart, endTime: endTime)
                training.updateNotes(exercises: resolvedExercises, detailedLog: nil)
                resolvedTrainingsForDay.append(training)
            }
            
            if !resolvedTrainingsForDay.isEmpty {
                // Създаваме DTO версията за запазване в progress
                let codableDayDraft = CodableTrainingPlanDayDraft(
                    dayIndex: day.dayIndex,
                    trainings: resolvedTrainingsForDay.map { TrainingDTO(from: $0) }
                )
                progress.resolvedDayDrafts?.append(codableDayDraft)
                
                // Запазваме прогреса след всеки обработен ден
                await saveProgress(jobID: jobID, progress: progress, onLog: onLog)
                emit("  -> ✅ Checkpoint 5: Резолвирането за Ден \(day.dayIndex) е завършено и запазено.", onLog)
            }
        }
        
        // Реконструираме финалния резултат от DTO-тата в прогреса
        let finalResolvedDays: [TrainingPlanDayDraft] = (progress.resolvedDayDrafts ?? []).map { dtoDay in
            let trainings = dtoDay.trainings.map { dtoTraining -> Training in
                let training = Training(name: dtoTraining.name, startTime: dtoTraining.startTime, endTime: dtoTraining.endTime)
                training.notes = dtoTraining.notes // Възстановяваме енкодираните упражнения
                return training
            }
            return TrainingPlanDayDraft(dayIndex: dtoDay.dayIndex, trainings: trainings)
        }
        
        emit("  -> Resolved \(finalResolvedDays.flatMap { $0.trainings }.count) training item(s) across \(finalResolvedDays.count) days.", onLog)
        return TrainingPlanDraft(name: conceptualPlan.planName, days: finalResolvedDays)
    }
    
    // MARK: - Helpers & Fallbacks
    
    private func emit(_ message: String, _ onLog: (@Sendable (String) -> Void)?) { onLog?(message) }
    
    private func parseMustDoRules(from requests: [String], onLog: (@Sendable (String) -> Void)?) -> [MustDoRule] {
        var rules: [MustDoRule] = []
        let p1 = #"(?:on|for)\s+day\s+([1-7])\s*,?\s*the\s+([A-Za-z\s]+?)\s+(?:workout|workouts?)\s+(?:must\s+contain|include|are\s+for)\s+(.*)"#
        let p2 = #"(?:on|for)\s+day\s+([1-7])\s*,?\s*(?:workouts?|exercises?)\s+(?:must\s+be|are)\s+for\s+([A-Za-z\s\-']+)"#
        let p3 = #"(?:on|for)\s+day\s+([1-7])\s*,?\s*include\s+(.*)"#
        
        func cleanExerciseList(_ list: String) -> [String] {
            return list.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }.filter { !$0.isEmpty }
        }
        
        for req in requests {
            do {
                try Task.checkCancellation()
                
                let regex1 = try NSRegularExpression(pattern: p1, options: .caseInsensitive)
                if let match = regex1.firstMatch(in: req, range: NSRange(req.startIndex..., in: req)) {
                    let dayStr = (req as NSString).substring(with: match.range(at: 1))
                    let workoutName = (req as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    let exercisesStr = (req as NSString).substring(with: match.range(at: 3))
                    if let day = Int(dayStr) {
                        for exercise in cleanExerciseList(exercisesStr) { rules.append(MustDoRule(day: day, workout: workoutName, exercise: exercise)) }
                    }
                    continue
                }
                try Task.checkCancellation()
                
                let regex2 = try NSRegularExpression(pattern: p2, options: .caseInsensitive)
                if let match = regex2.firstMatch(in: req, range: NSRange(req.startIndex..., in: req)) {
                    let dayStr = (req as NSString).substring(with: match.range(at: 1))
                    let exercise = (req as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    if let day = Int(dayStr) { rules.append(MustDoRule(day: day, workout: nil, exercise: exercise)) }
                    continue
                }
                try Task.checkCancellation()
                
                let regex3 = try NSRegularExpression(pattern: p3, options: .caseInsensitive)
                if let match = regex3.firstMatch(in: req, range: NSRange(req.startIndex..., in: req)) {
                    let dayStr = (req as NSString).substring(with: match.range(at: 1))
                    let exercisesStr = (req as NSString).substring(with: match.range(at: 2))
                    if let day = Int(dayStr) {
                        for exercise in cleanExerciseList(exercisesStr) { rules.append(MustDoRule(day: day, workout: nil, exercise: exercise)) }
                    }
                }
                try Task.checkCancellation()
                
            } catch { emit("Regex parsing failed for request: \(req)", onLog) }
        }
        
        return rules
    }
    
    private func debugDumpConceptualPlan(_ plan: AIConceptualTrainingPlanResponse, title: String, onLog: (@Sendable (String) -> Void)?) {
        emit("──────── \(title) ────────", onLog)
        emit("Plan Name: \(plan.planName)", onLog)
        for day in plan.days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
            emit("  Day \(day.dayIndex):", onLog)
            for workout in day.workouts {
                emit("    • \(workout.name) (\(workout.exercises.count) exercises)", onLog)
                for ex in workout.exercises { emit("        - \(ex.name) (\(ex.durationSeconds) sec)", onLog) }
            }
        }
        emit("────────────────────────────", onLog)
    }
    
    private func buildProfileInfo(_ profile: Profile) -> String {
        return """
        - Age: \(profile.age)
        - Gender: \(profile.gender)
        """
    }
    
    private func buildExistingWorkoutsText(_ existing: [Int: [TrainingPlanWorkoutDraft]]?) -> String {
        guard let existing = existing, !existing.isEmpty else { return "EXISTING WORKOUTS: None." }
        let lines = existing.keys.sorted().map { dayIndex -> String in
            let workoutsStr = existing[dayIndex]!.map { workout -> String in
                let exercisesStr = workout.exercises.map { "\($0.exerciseName) (\(Int($0.durationSeconds)) sec)" }.joined(separator: ", ")
                return "  - \(workout.workoutName): [\(exercisesStr)]"
            }.joined(separator: "\n")
            return "Day \(dayIndex):\n\(workoutsStr)"
        }.joined(separator: "\n")
        return "EXISTING WORKOUTS (for context and variety):\n\(lines)"
    }
    
    private func generateConceptualPlanSimple(
        profile: Profile,
        prompts: [String],
        workoutsToFill: [Int: [String]],
        existingWorkouts: [Int: [TrainingPlanWorkoutDraft]]?,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> AIConceptualTrainingPlanResponse {
        let planStructure = workoutsToFill.keys.sorted().map { "Day \($0): [\(workoutsToFill[$0]!.joined(separator: ", "))]" }.joined(separator: "\n")
        let existingWorkoutsText = buildExistingWorkoutsText(existingWorkouts)
        let profileInfo = buildProfileInfo(profile)
        let requests = prompts.isEmpty ? "(no extra requests)" : prompts.map { "- \($0)" }.joined(separator: "\n")
        try Task.checkCancellation()
        
        let session = LanguageModelSession(instructions: Instructions {
            """
            You are a certified personal trainer creating a multi-day workout plan.
            - Generate ONLY the missing workouts specified in the PLAN STRUCTURE.
            - Each workout must contain 3-8 distinct exercises.
            - Ensure exercise names are common and specific (use clear, standard exercise names rather than vague categories).
            - Durations should be realistic for each exercise within a workout.
            - Adhere strictly to the requested JSON output format.
            - Use the EXISTING WORKOUTS as context to ensure variety and avoid repetition.
            """
        })
        let prompt = """
        USER PROFILE:
        \(profileInfo)
        USER REQUESTS:
        \(requests)
        \(existingWorkoutsText)
        TASK:
        Generate ONLY the missing workouts specified in the PLAN STRUCTURE below.
        PLAN STRUCTURE (fill these blanks):
        \(planStructure)
        """
        emit("  -> Fallback prompt prepared.", onLog)
        try Task.checkCancellation()
        
        return try await session.respond(to: prompt, generating: AIConceptualTrainingPlanResponse.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy)).content
    }
    
    private func resolveOrCreateExercise(
        named rawName: String,
        searcher: SmartExerciseSearch,
        ctx: ModelContext,
        onLog: (@Sendable (String) -> Void)?
    ) async -> ExerciseItem? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return nil }
        
        do {
            try Task.checkCancellation()
            let desc = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.name == name })
            try Task.checkCancellation()
            if let exactMatch = try ctx.fetch(desc).first { return exactMatch }
            try Task.checkCancellation()
        } catch { emit("    - ⚠️ Could not perform exact match lookup: \(error.localizedDescription)", onLog) }
        
        let head = canonicalHeadword(from: name)
        let reqHeads = [head]
        
        let ids = await searcher.searchExercisesAI(query: name, limit: 1, context: "Resolving '\(name)' for a training plan.", requiredHeadwords: reqHeads)
        
        if !ids.isEmpty, let firstID = ids.first {
            do {
                try Task.checkCancellation()
                let desc = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.persistentModelID == firstID })
                try Task.checkCancellation()
                if let bestMatch = try ctx.fetch(desc).first { return bestMatch }
                try Task.checkCancellation()
            } catch { emit("    - ⚠️ Fetching best candidate failed: \(error.localizedDescription)", onLog) }
        }
        
        emit("    - 🛠️ No suitable candidate found for '\(name)'. Creating new via AIExerciseDetailGenerator…", onLog)
        do {
            try Task.checkCancellation()
            let gen = AIExerciseDetailGenerator(container: ctx.container)
            try Task.checkCancellation()
            let dto = try await gen.generateDetails(for: name, ctx: ctx, onLog: onLog)
            try Task.checkCancellation()
            let finalName = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? dto.title! : name
            try Task.checkCancellation()
            if let existing = try? ctx.fetch(FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.name == finalName })).first {
                emit("    - ⚠️ Aborted creation. An item with name '\(finalName)' was found just before saving.", onLog)
                return existing
            }
            try Task.checkCancellation()
            let newID = UUID()
            try Task.checkCancellation()
            let model = ExerciseItem(id: newID, name: finalName, description: dto.desc, metValue: dto.metValue, isUserAdded: false, muscleGroups: dto.muscleGroups, minimalAgeMonths: dto.minimalAgeMonths)
            try Task.checkCancellation()
            ctx.insert(model)
            try Task.checkCancellation()
            try ctx.save()
            emit("    - ✅ Created and saved new ExerciseItem '\(model.name)'", onLog)
            return model
        } catch {
            emit("    - ❌ Failed to create ExerciseItem for '\(name)': \(error.localizedDescription)", onLog)
            return nil
        }
    }
    
    private func canonicalHeadword(from s: String) -> String {
        let toks = SmartExerciseSearch.tokenize(s)
        if toks.contains("pushup") || toks.contains("push-up") { return "pushup" }
        if toks.contains("squat") { return "squat" }
        if toks.contains("deadlift") { return "deadlift" }
        if toks.contains("press") { return "press" }
        if toks.contains("row") { return "row" }
        if toks.contains("pullup") || toks.contains("pull-up") { return "pullup" }
        if toks.contains("lunge") { return "lunge" }
        if toks.contains("curl") { return "curl" }
        if toks.contains("plank") { return "plank" }
        return toks.last ?? s.lowercased()
    }
    
    private func workoutSignature(_ workout: ConceptualWorkout, replacing: ConceptualExercise? = nil, with newName: String? = nil) -> String {
        var names = workout.exercises.map { $0.name.lowercased() }
        if let toReplace = replacing, let replacement = newName {
            if let index = names.firstIndex(of: toReplace.name.lowercased()) {
                names[index] = replacement.lowercased()
            }
        }
        return names.sorted().joined(separator: "|")
    }
    
    private func aiGenerateExerciseVariants(for exerciseName: String, count: Int, onLog: (@Sendable (String) -> Void)?) async -> [String] {
        let session = LanguageModelSession(instructions: Instructions {
               """
               You generate distinct, realistic variations of a given exercise or muscle group.
               - Return exactly the requested number of variations.
               - Variations can involve different equipment (barbell, dumbbell, kettlebell), stance, or style.
               - Do not include the original exercise name itself.
               - Return ONLY a valid JSON array of strings.
               """
        })
        let prompt = "Generate \(count) variations for the exercise or muscle group '\(exerciseName)'."
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(to: prompt, generating: AIVariantExerciseResponse.self, includeSchemaInPrompt: true, options: GenerationOptions(sampling: .greedy)).content
            try Task.checkCancellation()
            onLog?("  -> Generated \(resp.variants.count) variants for '\(exerciseName)': \(resp.variants)")
            return resp.variants
        } catch {
            onLog?("  -> ⚠️ AI variant generation failed for '\(exerciseName)': \(error.localizedDescription)")
            return []
        }
    }
    
    private func aiExtractRequestedExercises(from prompts: [String], onLog: (@Sendable (String) -> Void)?) async -> (included: [String], excluded: [String]) {
        guard !prompts.isEmpty else { return ([], []) }
        let session = LanguageModelSession(instructions: Instructions {
               """
               You extract specific exercise names from user prompts into two lists: `includedExercises` and `excludedExercises`.
               - Normalize names (singular/plural and casing).
               - Ignore goals, frequencies, and workout types for this task.
               """
        })
        let prompt = "PROMPTS:\n\(prompts.map { "- \($0)" }.joined(separator: "\n"))"
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(to: prompt, generating: AIExerciseExtractionResponse.self, includeSchemaInPrompt: true).content
            try Task.checkCancellation()
            if !resp.includedExercises.isEmpty { emit("  -> Requested to include: \(resp.includedExercises)", onLog) }
            if !resp.excludedExercises.isEmpty { emit("  -> Requested to exclude: \(resp.excludedExercises)", onLog) }
            return (resp.includedExercises, resp.excludedExercises)
        } catch {
            emit("  -> ⚠️ Exercise extraction failed: \(error.localizedDescription)", onLog)
            return ([], [])
        }
    }
    
    private func aiInterpretUserPrompts(prompts: [String], workoutsToFill: [Int: [String]], onLog: (@Sendable (String) -> Void)?) async -> InterpretedTrainingPrompts {
        guard !prompts.isEmpty else { return InterpretedTrainingPrompts() }
        emit("  -> Interpreting user prompts with AI classifier...", onLog)
        var interpreted = InterpretedTrainingPrompts()
        let availableDays = workoutsToFill.keys.sorted()
        for prompt in prompts {
            let session = LanguageModelSession(instructions: Instructions {
                """
                You are an expert prompt analyzer for workout plans. Classify the user's prompt into ONE of two categories:
                - `structuralRequest`: If the prompt specifies WHAT to do, WHEN, or WHERE.
                - `qualitativeGoal`: If the prompt is a general preference or broad goal without a specific, structural command.
                **CRITICAL RULE**: If a prompt mentions a duration like "one day for arms", convert it to a rule for a specific day from `AVAILABLE_DAYS`, like "On Day 1, workouts are for arms.".
                """
            })
            let promptForAI = "AVAILABLE_DAYS: \(availableDays)\nAnalyze and classify the following single user prompt:\nUSER PROMPT: \"\(prompt)\""
            do {
                try Task.checkCancellation()
                let response = try await session.respond(to: promptForAI, generating: AIInterpretedPromptResponse.self, includeSchemaInPrompt: true).content
                try Task.checkCancellation()
                if let structural = response.structuralRequest, !structural.isEmpty {
                    try Task.checkCancellation()
                    interpreted.structuralRequests.append(structural)
                    try Task.checkCancellation()
                }
                else if let qualitative = response.qualitativeGoal, !qualitative.isEmpty {
                    try Task.checkCancellation()
                    interpreted.qualitativeGoals.append(qualitative)
                    try Task.checkCancellation()
                }
                else {
                    try Task.checkCancellation()
                    interpreted.qualitativeGoals.append(prompt)
                    try Task.checkCancellation()
                }
            } catch {
                onLog?("    - ⚠️ AI interpretation for prompt '\(prompt)' failed. Treating as qualitative goal.")
                interpreted.qualitativeGoals.append(prompt)
            }
        }
        if !interpreted.structuralRequests.isEmpty { emit("  -> Structural Requests: \(interpreted.structuralRequests)", onLog) }
        if !interpreted.qualitativeGoals.isEmpty { emit("  -> Qualitative Goals: \(interpreted.qualitativeGoals)", onLog) }
        return interpreted
    }
    
    @MainActor
    private func aiFixAtomsAndExercises(originalPrompts: [String], atoms: [String], included: [String], excluded: [String], onLog: (@Sendable (String) -> Void)?) async -> (directives: [String], included: [String], excluded: [String]) {
        guard !originalPrompts.isEmpty else { return (atoms, included, excluded) }
        let instructions = Instructions { "You reconcile atomic training directives with raw prompts and exercise lists." }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "RAW_PROMPTS:\n\(originalPrompts.joined(separator: "\n"))\n\nCURRENT_ATOMIC_DIRECTIVES:\n\(atoms.joined(separator: "\n"))\n\nCURRENT_INCLUDED_EXERCISES:\n\(included)\nCURRENT_EXCLUDED_EXERCISES:\n\(excluded)"
        do {
            try Task.checkCancellation()
            let resp = try await session.respond(to: prompt, generating: AIAtomsAndExercisesFixResponse.self, includeSchemaInPrompt: true).content
            try Task.checkCancellation()
            func clean(_ arr: [String]) -> [String] {
                var out: [String] = [], s = Set<String>()
                for r in arr { let n = r.trimmingCharacters(in: .whitespacesAndNewlines); if !n.isEmpty, s.insert(n.lowercased()).inserted { out.append(n) } }
                return out
            }
            try Task.checkCancellation()
            let inc = clean(resp.includedExercises)
            let exc0 = clean(resp.excludedExercises)
            let incSet = Set(inc.map { $0.lowercased() })
            let exc = exc0.filter { !incSet.contains($0.lowercased()) }
            return (resp.fixedDirectives, inc, exc)
        } catch {
            onLog?("    - ⚠️ Post-fix AI pass failed: \(error.localizedDescription).")
            return (atoms, included, excluded)
        }
    }
    
    @MainActor
    private func ensureGeneralPalettes(palettes: [String: [String]], profile: Profile, onLog: (@Sendable (String) -> Void)?) async -> [String: [String]] {
        var out = palettes
        let fullBodyKey = "musclegroup:full body"
        if out[fullBodyKey]?.isEmpty ?? true {
            let fb = await aiGenerateExercisePaletteForContext(profile: profile, context: AITrainingContextTag(kind: "muscleGroup", tag: "full body"), onLog: onLog)
            if !fb.isEmpty { out[fullBodyKey] = fb; emit("  -> Added fallback full body palette (\(fb.count)).", onLog) }
        }
        return out
    }
    
    @MainActor
    private func enrichAndVaryWorkouts(plan: AIConceptualTrainingPlanResponse, palettes: [String: [String]], excluded: [String], onLog: (@Sendable (String) -> Void)?) async -> AIConceptualTrainingPlanResponse {
        var out = plan
        let banned = Set(excluded.map { $0.lowercased() })
        let flatPalette = palettes.values.flatMap { $0 }.shuffled()
        for d in 0..<out.days.count {
            for w in 0..<out.days[d].workouts.count {
                var exs = out.days[d].workouts[w].exercises
                var seen = Set(exs.map { $0.name.lowercased() })
                while exs.count < 5 {
                    if let pick = flatPalette.first(where: { !seen.contains($0.lowercased()) && !banned.contains($0.lowercased()) }) {
                        exs.append(.init(name: pick, durationSeconds: Int.random(in: 360...1200)))
                        seen.insert(pick.lowercased())
                    } else { break }
                }
                if Set(exs.map { $0.durationSeconds }).count <= 1 { exs.indices.forEach { exs[$0].durationSeconds = Int.random(in: 360...1200) } }
                out.days[d].workouts[w].exercises = exs
            }
        }
        return out
    }
    
    private func enforceInterDayVariety(plan: AIConceptualTrainingPlanResponse, protectedRules: [MustDoRule], palettes: [String: [String]], onLog: (@Sendable (String) -> Void)?) async -> AIConceptualTrainingPlanResponse {
        var out = plan
        var seenSignatures: [String: Set<String>] = [:]
        for dIdx in 0..<out.days.count {
            for wIdx in 0..<out.days[dIdx].workouts.count {
                var workout = out.days[dIdx].workouts[wIdx]
                if seenSignatures[workout.name, default: []].contains(workoutSignature(workout)) {
                    emit("  -> DUPLICATE found for '\(workout.name)' on Day \(out.days[dIdx].dayIndex). Varying.", onLog)
                    if let idx = workout.exercises.firstIndex(where: { ex in !protectedRules.contains(where: { $0.exercise.caseInsensitiveCompare(ex.name) == .orderedSame }) }) {
                        let existing = Set(workout.exercises.map { $0.name.lowercased() })
                        if let replacement = palettes.values.flatMap({$0}).first(where: {!existing.contains($0.lowercased())}) {
                            let oldName = workout.exercises[idx].name
                            workout.exercises[idx].name = replacement
                            emit("    - Varied: '\(oldName)' -> '\(replacement)'", onLog)
                        }
                    }
                }
                seenSignatures[workout.name, default: []].insert(workoutSignature(workout))
                out.days[dIdx].workouts[wIdx] = workout
            }
        }
        return out
    }
    
    private func clampDurationsHeuristically(plan: AIConceptualTrainingPlanResponse, onLog: (@Sendable (String) -> Void)?) -> AIConceptualTrainingPlanResponse {
        var out = plan
        var adjustedCount = 0
        for d in 0..<out.days.count {
            for w in 0..<out.days[d].workouts.count {
                for e in 0..<out.days[d].workouts[w].exercises.count {
                    let original = out.days[d].workouts[w].exercises[e].durationSeconds
                    let clamped = max(300, min(1800, original))
                    if original != clamped {
                        out.days[d].workouts[w].exercises[e].durationSeconds = clamped
                        adjustedCount += 1
                    }
                }
            }
        }
        if adjustedCount > 0 { emit("  -> Clamped \(adjustedCount) exercise duration(s) to be within 300-1800 sec.", onLog) }
        return out
    }
    
    // --- START OF CHANGE: crash-safe saveProgress (TrainingPlanGenerationProgress) ---
    @MainActor
    private func saveProgress(
        jobID: PersistentIdentifier,
        progress: TrainingPlanGenerationProgress,
        onLog: (@Sendable (String) -> Void)?
    ) async {
        // Ако задачата е отменена – не записваме
        if Task.isCancelled {
            emit("⏹️ [Progress] Task cancelled; skip training plan progress save.", onLog)
            return
        }
        
        do {
            // Винаги fresh контекст за писане
            let writeCtx = ModelContext(self.container)
            
            // Рефетч по persistentModelID (НЕ context.model(for:))
            let fd = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.persistentModelID == jobID })
            guard let job = try writeCtx.fetch(fd).first else {
                emit("⚠️ [Progress] Не може да се намери задача с ID \(jobID) (изтрита?) – пропуск.", onLog)
                return
            }
            
            // Последна проверка точно преди сетъра – пресича race с delete
            try Task.checkCancellation()
            
            job.intermediateResultData = try JSONEncoder().encode(progress)
            try writeCtx.save()
            
            emit("💾 [Progress] Прогресът за тренировъчен план е запазен.", onLog)
        } catch is CancellationError {
            emit("⏹️ [Progress] Cancelled mid-save; skipping training plan progress.", onLog)
        } catch {
            emit("❌ [Progress] Неуспешен запис на прогреса: \(error.localizedDescription)", onLog)
        }
    }
    // --- END OF CHANGE ---
    
}
