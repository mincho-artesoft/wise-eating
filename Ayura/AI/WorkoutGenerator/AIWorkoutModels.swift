import Foundation
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
    let exerciseID: UUID
    let durationSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case exerciseID
        case durationSeconds
        case durationMinutes
    }

    init(exerciseID: UUID, durationSeconds: Double) {
        self.exerciseID = exerciseID
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decode(UUID.self, forKey: .exerciseID)
        if let seconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) {
            durationSeconds = seconds
        } else {
            durationSeconds = try container.decode(Double.self, forKey: .durationMinutes) * 60
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(durationSeconds, forKey: .durationSeconds)
    }
}

struct ResolvedWorkoutResponseDTO: Codable, Sendable {
    let name: String
    let description: String
    let totalDurationSeconds: Int
    let exercises: [ResolvedExercise]

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case totalDurationSeconds
        case totalDurationMinutes
        case exercises
    }

    init(
        name: String,
        description: String,
        totalDurationSeconds: Int,
        exercises: [ResolvedExercise]
    ) {
        self.name = name
        self.description = description
        self.totalDurationSeconds = totalDurationSeconds
        self.exercises = exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        exercises = try container.decode([ResolvedExercise].self, forKey: .exercises)
        if let seconds = try container.decodeIfPresent(Int.self, forKey: .totalDurationSeconds) {
            totalDurationSeconds = seconds
        } else {
            totalDurationSeconds = try container.decode(Int.self, forKey: .totalDurationMinutes) * 60
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(totalDurationSeconds, forKey: .totalDurationSeconds)
        try container.encode(exercises, forKey: .exercises)
    }
}
