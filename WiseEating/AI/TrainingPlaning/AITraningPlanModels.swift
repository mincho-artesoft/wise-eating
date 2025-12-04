import FoundationModels
import Foundation

// MARK: - AI Schemas & Local Structs
// Note: This would typically be in a separate file, but is included here
// to make the provided code block self-contained and complete.

@available(iOS 26.0, *)
@Generable
struct ConceptualExercise: Codable, Sendable {
    @Guide(description: "A specific, common exercise name (e.g., 'Barbell Squat', 'Push-up', 'Plank'). Names within a single workout MUST be all distinct.")
    var name: String

    @Guide(description: "Duration in minutes for this exercise. Use a varied mix per workout; avoid identical durations across all exercises in the same workout. Typical range: 6–20.")
    var durationMinutes: Int
}

@available(iOS 26.0, *)
@Generable
struct ConceptualWorkout: Codable, Sendable {
    @Guide(description: "The workout name; MUST exactly match one from the requested structure.")
    var name: String

    @Guide(description: "A list of 5–7 distinct exercises for this workout. Avoid overlap of the same exercise name.", .count(5...7))
    var exercises: [ConceptualExercise]
}


@available(iOS 26.0, *)
@Generable
struct ConceptualTrainingDay: Codable, Sendable {
    @Guide(description: "The day index (1-based), must match one of the requested days.")
    let dayIndex: Int
    var workouts: [ConceptualWorkout]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualTrainingPlanResponse: Codable, Sendable {
    @Guide(description: "A creative and descriptive name for the entire training plan.")
    let planName: String
    @Guide(description: "The days of the training plan, matching the requested structure.")
    var days: [ConceptualTrainingDay]
}

@available(iOS 26.0, *)
@Generable
struct AIExerciseExtractionResponse: Codable {
    @Guide(description: "List ONLY the concrete exercise names the user explicitly asked to INCLUDE.")
    let includedExercises: [String]
    @Guide(description: "List ONLY the concrete exercise names the user explicitly asked to EXCLUDE or AVOID.")
    let excludedExercises: [String]
}

@available(iOS 26.0, *)
@Generable
struct AITrainingContextTag: Codable, Sendable { // Уверяваме се, че е Codable и Sendable
    @Guide(description: "The kind of tag: 'trainingType' (e.g., strength, cardio, hypertrophy), 'muscleGroup' (e.g., legs, chest), or 'headword' (a specific focus exercise like 'Squat').")
    let kind: String
    @Guide(description: "A concise, lowercase tag for the identified concept.")
    let tag: String
}

@available(iOS 26.0, *)
@Generable
struct AITrainingContextTagsResponse: Codable, Sendable {
    @Guide(description: "1–3 context tags ordered by relevance.")
    let tags: [AITrainingContextTag]
}

@available(iOS 26.0, *)
@Generable
struct AIExercisePaletteResponse: Codable {
    @Guide(description: "A list of 15-25 specific, common exercise names suitable for the given context (training type and/or muscle group).", .count(15...25))
    let exercises: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIVariantExerciseResponse: Codable {
    @Guide(description: "A list of distinct, realistic variations for the given base exercise.")
    let variants: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIAtomicTrainingPromptsResponse: Codable {
    @Guide(description: "Atomic, standalone directives split from the user's raw prompts.")
    let directives: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIInterpretedPromptResponse: Codable {
    @Guide(description: "A short, imperative sentence describing a concrete constraint (e.g., what to do on a specific day, an exercise to include/exclude). This field is for specific, actionable commands.")
    let structuralRequest: String?

    @Guide(description: "A concise preference or general goal if the prompt is not a concrete structural command. This is for broader, non-actionable preferences.")
    let qualitativeGoal: String?
}

struct InterpretedTrainingPrompts: Codable, Sendable, CustomStringConvertible {
    var qualitativeGoals: [String] = []
    var structuralRequests: [String] = []

    var description: String {
        return "InterpretedPrompts(qualitativeGoals: \(qualitativeGoals), structuralRequests: \(structuralRequests))"
    }
}

@available(iOS 26.0, *)
@Generable
struct AIAtomsAndExercisesFixResponse: Codable, Sendable {
    @Guide(description: "The corrected, concise, and standalone directives, reconciled with the user's raw prompts.")
    let fixedDirectives: [String]
    @Guide(description: "The final list of included exercises, ensuring it aligns with what the user explicitly requested.")
    let includedExercises: [String]
    @Guide(description: "The final list of excluded exercises, ensuring it aligns with what the user explicitly requested to avoid.")
    let excludedExercises: [String]
}

struct TrainingDTO: Codable, Sendable {
    let name: String
    let startTime: Date
    let endTime: Date
    let notes: String? // Запазваме енкодираните упражнения

    init(from training: Training) {
        self.name = training.name
        self.startTime = training.startTime
        self.endTime = training.endTime
        self.notes = training.notes
    }
}

/// Codable DTO за 'TrainingPlanDayDraft'.
struct CodableTrainingPlanDayDraft: Codable, Sendable {
    let dayIndex: Int
    let trainings: [TrainingDTO]
}

/// Съхранява междинния прогрес на задача за генериране на тренировъчен план.
@available(iOS 26.0, *)
struct TrainingPlanGenerationProgress: Codable, Sendable {
    // Етап 1: Интерпретация
    var atomicPrompts: [String]?
    var includedExercises: [String]?
    var excludedExercises: [String]?
    var interpretedPrompts: InterpretedTrainingPrompts?

    // Етап 2: Контекст и Палитри
    var contextTags: [AITrainingContextTag]?
    var palettes: [String: [String]]?
    var specializedStructuralRequests: [String]?

    // Етап 3: Основна AI Генерация
    var conceptualPlan: AIConceptualTrainingPlanResponse?
    
    // Етап 5: Резолвиране (запазва се частично)
    var resolvedDayDrafts: [CodableTrainingPlanDayDraft]? // Използваме Codable DTO

    init() {}
}
