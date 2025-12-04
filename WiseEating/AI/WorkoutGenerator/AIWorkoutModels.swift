import FoundationModels

@available(iOS 26.0, *)
@Generable
struct AIWorkoutDetailsOnly: Codable, Sendable {
    /// Описание във формат: Summary ред + празен ред + номерирани стъпки.
    @Guide(description: "A single plain-text string that starts with 'Summary: <1–2 sentences>', followed by a blank line, and then numbered steps '1) ...\\n2) ...'. 3-8 steps total. No Markdown.")
    var description: String
}

@available(iOS 26.0, *)
@Generable
struct AIWorkoutNameResponse: Codable, Sendable {
    @Guide(description: "A creative, descriptive name for the workout (2-4 words). No emojis or brand names.")
    var name: String
}

// DTO-та за комуникация на резултата
struct ResolvedExercise: Codable, Sendable {
    let exerciseID: Int
    let durationMinutes: Double
}

struct ResolvedWorkoutResponseDTO: Codable, Sendable {
    let name: String
    let description: String
    let totalDurationMinutes: Int
    let exercises: [ResolvedExercise]
}
