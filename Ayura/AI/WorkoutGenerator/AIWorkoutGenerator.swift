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

        let resolvedExercises = generatedTraining.exercises(using: ModelContext(container))
        if resolvedExercises.isEmpty {
            let error = NSError(domain: "AIWorkoutGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Generated training contains no resolved exercises."])
            emitLog("❌ Generated training has no exercises.", onLog: onLog)
            throw error
        }
        try Task.checkCancellation()

        let totalDuration = Int(resolvedExercises.values.reduce(0, +))
        emitLog("✅ Exercises resolved. Total duration: \(totalDuration) min.", onLog: onLog)

        // 2. Генерираме описание (summary + steps) на база получените упражнения
        let description = try await regenerateDescriptionForWorkout(
            workoutName: generatedTraining.name, // Подаваме временното име за контекст
            exercises: resolvedExercises,
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
            totalDurationMinutes: totalDuration,
            exercises: resolvedExercises.map { (item, duration) in
                ResolvedExercise(exerciseID: item.id, durationMinutes: duration)
            }
        )

        emitLog("🏁 Successfully created ResolvedWorkoutResponseDTO for '\(dto.name)'.", onLog: onLog)
        return dto
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
        WORKOUT DURATION: \(totalDuration) minutes
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
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let exerciseList = exercises
            .map { "\($0.key.name) (\(Int($0.value)) min)" }
            .joined(separator: ", ")

        let instructions = Instructions {
            """
            You are a fitness coach. Write a description for a workout.
            - The description MUST be a single string with a "Summary: ..." line, a blank line, and 3-8 numbered steps.
            - Steps should be short, imperative sentences.
            - Do not list ingredients in the steps; just ensure the steps naturally use them.
            - Return ONLY valid JSON for AIWorkoutDetailsOnly.
            """
        }
        
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        WORKOUT NAME: "\(workoutName)"
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

            return resp.description
        } catch {
            emitLog("⚠️ Workout description generation failed: \(error.localizedDescription). Falling back to simple list.", onLog: onLog)
            return "Summary: A workout focusing on \(workoutName).\n\n1) Warm up for 5-10 minutes.\n2) Perform the following exercises: \(exerciseList).\n3) Cool down with light stretching."
        }
    }
}
