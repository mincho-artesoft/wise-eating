import Foundation
import SwiftData
import FoundationModels

@available(iOS 26.0, *)
@MainActor
final class AIWorkoutGenerator {

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }
    
    private func emitLog(_ message: String, onLog: (@Sendable (String) -> Void)?) {
        onLog?(message)
    }

    /// Основна публична функция, която оркестрира генерирането на една тренировка.
    func generateWorkout(
        jobID: PersistentIdentifier,
        profile: Profile,
        prompts: [String],
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> ResolvedWorkoutResponseDTO {
        emitLog("🚀 Starting single workout generation for '\(prompts)'...", onLog: onLog)

        // 1. Използваме AITrainingPlanGenerator за генериране на упражненията
        let planGenerator = AITrainingPlanGenerator(container: container)
        let planDraft: TrainingPlanDraft
        do {
            try Task.checkCancellation()
            // Искаме план за 1 ден с 1 тренировка, носеща името, което потребителят е въвел.
            planDraft = try await planGenerator.fillPlanDetails(
                jobID: jobID,
                profileID: profile.persistentModelID,
                prompts: prompts,
                workoutsToFill: [1: ["Workout"]], // Името тук вече е без значение
                existingWorkouts: nil,
                onLog: onLog
            )
            try Task.checkCancellation()

        } catch {
            emitLog("❌ Failed during exercise resolution via AITrainingPlanGenerator: \(error.localizedDescription)", onLog: onLog)
            throw error
        }
        
        guard let generatedTraining = planDraft.days.first?.trainings.first else {
            let error = NSError(domain: "AIWorkoutGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "AITrainingPlanGenerator returned no trainings."])
            emitLog("❌ No training was generated in the draft plan.", onLog: onLog)
            throw error
        }
        try Task.checkCancellation()

        let initiallyResolvedExercises = generatedTraining.exercises(using: ModelContext(container))
        let equipmentConstrainedExercises = applyingEquipmentConstraints(
            to: initiallyResolvedExercises,
            prompts: prompts
        )
        let resolvedExercises = normalizeDurationIfRequested(
            equipmentConstrainedExercises,
            prompts: prompts
        )
        if resolvedExercises.isEmpty {
            let error = NSError(domain: "AIWorkoutGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Generated training contains no resolved exercises."])
            emitLog("❌ Generated training has no exercises.", onLog: onLog)
            throw error
        }
        try Task.checkCancellation()

        let totalDuration = Int(resolvedExercises.values.reduce(0, +))
        emitLog("✅ Exercises resolved. Total duration: \(totalDuration) sec.", onLog: onLog)

        // 2. Генерираме описание (summary + steps) на база получените упражнения
        let description = try await regenerateDescriptionForWorkout(
            workoutName: generatedTraining.name, // Подаваме временното име за контекст
            exercises: resolvedExercises,
            totalDuration: totalDuration,
            isYoga: prompts.joined(separator: " ").lowercased().contains("yoga"),
            onLog: onLog
        )
        try Task.checkCancellation()

        emitLog("✅ Description generated.", onLog: onLog)
        
        // +++ НАЧАЛО НА ПРОМЯНАТА (1/2): Генерираме ново, по-добро име +++
        // 3. Генерираме креативно име на база съдържанието
        let finalWorkoutName = try await regenerateWorkoutName(
            prompts: prompts,
            exercises: resolvedExercises,
            totalDuration: totalDuration,
            originalName: generatedTraining.name, // Подаваме старото име за fallback
            onLog: onLog
        )
        try Task.checkCancellation()

        emitLog("✅ Creative name generated: '\(finalWorkoutName)'.", onLog: onLog)
        // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++

        // 4. Сглобяваме финалния DTO с новото име
        let dto = ResolvedWorkoutResponseDTO(
            name: finalWorkoutName, // Използваме новото име
            description: description,
            totalDurationSeconds: totalDuration,
            exercises: orderedWorkoutEntries(resolvedExercises).map { (item, duration) in
                ResolvedExercise(exerciseID: item.id, durationSeconds: duration)
            }
        )

        emitLog("🏁 Successfully created ResolvedWorkoutResponseDTO for '\(dto.name)'.", onLog: onLog)
        return dto
    }

    private func applyingEquipmentConstraints(
        to exercises: [ExerciseItem: Double],
        prompts: [String]
    ) -> [ExerciseItem: Double] {
        let raw = prompts.joined(separator: " ").lowercased()
        let noEquipment = ["no equipment", "without equipment", "bodyweight only", "body-weight only"]
            .contains(where: { raw.contains($0) })
        guard noEquipment else { return exercises }

        let banned = [
            "barbell", "dumbbell", "kettlebell", "machine", "cable",
            "bench press", "overhead press", "shoulder press", "bent-over row",
            "bent over row", "lat pulldown", "pull-up", "pull up", "chin-up",
            "chin up", "deadlift", "bicep curl", "tricep extension"
        ]
        let filtered = exercises.filter { item, _ in
            let name = item.name.lowercased()
            return !banned.contains(where: { name.contains($0) })
        }
        return filtered.count >= 3 ? filtered : exercises
    }

    private func normalizeDurationIfRequested(
        _ exercises: [ExerciseItem: Double],
        prompts: [String]
    ) -> [ExerciseItem: Double] {
        guard !exercises.isEmpty,
              let targetSeconds = requestedDurationSeconds(in: prompts),
              targetSeconds >= exercises.count * 15 else { return exercises }

        // The user's requested workout type is authoritative. A strength
        // exercise may resolve near a yoga catalogue entry, but that must not
        // turn the whole workout into a yoga flow.
        let yogaSession = prompts.joined(separator: " ").lowercased().contains("yoga")
        let ordered = orderedWorkoutEntries(exercises).map(\.0)
        let currentTotal = exercises.values.reduce(0, +)
        guard currentTotal > 0 else { return exercises }

        let finalRelaxation = yogaSession
            ? ordered.last(where: {
                $0.name.lowercased().contains("savasana")
                    || $0.name.lowercased().contains("corpse pose")
            })
            : nil
        let relaxationSeconds = finalRelaxation == nil
            ? 0
            : min(600, max(180, Int((Double(targetSeconds) * 0.18).rounded())))
        let activeItems = ordered.filter { $0 != finalRelaxation }
        let activeCurrentTotal = activeItems.reduce(0.0) { $0 + (exercises[$1] ?? 0) }

        var normalized: [ExerciseItem: Double] = [:]
        var remaining = targetSeconds - relaxationSeconds
        for (index, item) in activeItems.enumerated() {
            let itemsAfterThis = activeItems.count - index - 1
            if itemsAfterThis == 0 {
                normalized[item] = Double(remaining)
                break
            }
            let proportional = Double(targetSeconds - relaxationSeconds)
                * ((exercises[item] ?? 0) / max(activeCurrentTotal, 1))
            let rounded = Int((proportional / 5).rounded()) * 5
            let maximum = remaining - itemsAfterThis * 15
            let duration = max(15, min(maximum, rounded))
            normalized[item] = Double(duration)
            remaining -= duration
        }
        if let finalRelaxation {
            normalized[finalRelaxation] = Double(relaxationSeconds)
        }
        return normalized
    }

    private func requestedDurationSeconds(in prompts: [String]) -> Int? {
        let raw = prompts.joined(separator: " ").lowercased()
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(\d{1,3})\s*(?:-|–)?\s*(?:minute|minutes|min)\b"#
        ) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              let numberRange = Range(match.range(at: 1), in: raw),
              let minutes = Int(raw[numberRange]) else { return nil }
        return minutes * 60
    }
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (2/2): Добавяме нова функция за генериране на име +++
    /// Генерира креативно име за тренировка на база съдържанието й.
    private func regenerateWorkoutName(
        prompts: [String],
        exercises: [ExerciseItem: Double],
        totalDuration: Int,
        originalName: String,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let exerciseList = exercises.keys.map { $0.name }.joined(separator: ", ")

        let instructions = Instructions {
            """
            You are a creative fitness coach who names workouts.
            - The name should be catchy, descriptive, and between 2-4 words.
            - It must NOT contain emojis or brand names.
            - It should reflect the main exercises and the user's goal.
            - Return ONLY valid JSON for AIWorkoutNameResponse.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        USER'S GOAL/PROMPTS: "\(prompts.joined(separator: ", "))"
        WORKOUT DURATION: \(totalDuration) seconds
        MAIN EXERCISES: \(exerciseList)
        TASK: Generate a creative and fitting name for this workout.
        """
        emitLog("LLM workout-name prompt → \(prompt)", onLog: onLog)

        do {
            try Task.checkCancellation()

            let resp = try await session.respond(
                to: prompt,
                generating: AIWorkoutNameResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .random(top: 50), temperature: 0.7)
            ).content
            try Task.checkCancellation()

            let cleanedName = resp.name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
            return cleanedName.isEmpty ? originalName : cleanedName
            
        } catch {
            emitLog("⚠️ Workout name generation failed: \(error.localizedDescription). Falling back to original name '\(originalName)'.", onLog: onLog)
            // При грешка, просто връщаме името, което AITrainingPlanGenerator е дал
            return originalName
        }
    }
    // +++ КРАЙ НА ПРОМЯНАТА (2/2) +++

    /// Генерира описание (summary + steps) за дадена тренировка.
    private func regenerateDescriptionForWorkout(
        workoutName: String,
        exercises: [ExerciseItem: Double],
        totalDuration: Int,
        isYoga: Bool,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let exerciseList = exercises
            .map { "\($0.key.name) (\(Int($0.value)) sec)" }
            .joined(separator: ", ")

        let instructions = Instructions {
            """
            You are a fitness coach. Write a description for a workout.
            - The description MUST be a single string with a "Summary: ..." line, a blank line, and 3-8 numbered steps.
            - Steps should be short, imperative sentences.
            - Do not list ingredients in the steps; just ensure the steps naturally use them.
            - The stated duration must exactly match the supplied total. Never call it a one-hour workout unless the supplied total is 3600 seconds.
            - Describe one pass through the supplied exercises. Do not tell the user to repeat the whole workout.
            - Return ONLY valid JSON for AIWorkoutDetailsOnly.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        WORKOUT NAME: "\(workoutName)"
        EXACT TOTAL DURATION: \(totalDuration) seconds (\(totalDuration / 60) minutes)
        EXERCISES: \(exerciseList)
        TASK: Generate a description for this workout.
        """
        emitLog("LLM workout-description prompt → \(prompt)", onLog: onLog)

        do {
            try Task.checkCancellation()

            let resp = try await session.respond(
                to: prompt,
                generating: AIWorkoutDetailsOnly.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            ).content
            try Task.checkCancellation()

            let generated = resp.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isConsistentWorkoutDescription(generated, totalDuration: totalDuration) else {
                emitLog("⚠️ Generated description added time or repetition outside the resolved workout. Using exact-duration description.", onLog: onLog)
                return exactWorkoutDescription(
                    workoutName: workoutName,
                    exercises: exercises,
                    totalDuration: totalDuration,
                    isYoga: isYoga
                )
            }
            emitLog("✅ AI description validated; applying the exact interval/sequence formatter.", onLog: onLog)
            return exactWorkoutDescription(
                workoutName: workoutName,
                exercises: exercises,
                totalDuration: totalDuration,
                isYoga: isYoga
            )
        } catch {
            emitLog("⚠️ Workout description generation failed: \(error.localizedDescription). Falling back to simple list.", onLog: onLog)
            return exactWorkoutDescription(
                workoutName: workoutName,
                exercises: exercises,
                totalDuration: totalDuration,
                isYoga: isYoga
            )
        }
    }

    private func isConsistentWorkoutDescription(_ description: String, totalDuration: Int) -> Bool {
        let lower = description.lowercased()
        let repeatsWholeWorkout = [
            "repeat the circuit", "repeat this circuit", "repeat the workout",
            "repeat the whole", "another round"
        ].contains(where: { lower.contains($0) })
        if repeatsWholeWorkout { return false }

        if totalDuration != 3600,
           ["one-hour", "one hour", "60-minute", "60 minute"]
            .contains(where: { lower.contains($0) }) {
            return false
        }

        guard description.hasPrefix("Summary:"), description.contains("\n\n") else {
            return false
        }
        let minutes = totalDuration / 60
        return lower.contains("\(totalDuration) seconds")
            || lower.contains("\(minutes)-minute")
            || lower.contains("\(minutes) minute")
    }

    private func exactWorkoutDescription(
        workoutName: String,
        exercises: [ExerciseItem: Double],
        totalDuration: Int,
        isYoga: Bool
    ) -> String {
        let minutes = totalDuration / 60
        let ordered = orderedWorkoutEntries(exercises)
        if isYoga {
            let steps = ordered.enumerated().map { index, entry in
                let breath = entry.0.breath?.rawValue ?? "slow, comfortable breathing"
                return "\(index + 1)) Practice \(entry.0.name) for \(Int(entry.1)) seconds with \(breath.lowercased())."
            }
            return "Summary: A \(minutes)-minute \(workoutName) sequenced from active poses toward final rest; the allocations total exactly \(totalDuration) seconds.\n\n"
                + steps.joined(separator: "\n")
        }

        let rounds = totalDuration >= 1_200 ? 5 : 3
        let steps = ordered.enumerated().map { index, entry in
            let perRound = max(20, Int(entry.1) / rounds)
            let transition = min(20, max(10, perRound / 4))
            let work = max(15, perRound - transition)
            return "\(index + 1)) Across \(rounds) rounds, do \(entry.0.name) for about \(work) seconds, then use about \(transition) seconds to recover or change position (\(Int(entry.1)) seconds allocated total)."
        }
        return "Summary: A \(minutes)-minute \(workoutName) organized as \(rounds) controlled rounds; exercise allocations include work and short recovery and total exactly \(totalDuration) seconds.\n\n"
            + steps.joined(separator: "\n")
    }

    private func orderedWorkoutEntries(
        _ exercises: [ExerciseItem: Double]
    ) -> [(ExerciseItem, Double)] {
        exercises.map { ($0.key, $0.value) }.sorted { left, right in
            let leftRest = left.0.name.lowercased().contains("savasana")
                || left.0.name.lowercased().contains("corpse pose")
            let rightRest = right.0.name.lowercased().contains("savasana")
                || right.0.name.lowercased().contains("corpse pose")
            if leftRest != rightRest { return !leftRest }
            return left.0.name.localizedCaseInsensitiveCompare(right.0.name) == .orderedAscending
        }
    }
}
