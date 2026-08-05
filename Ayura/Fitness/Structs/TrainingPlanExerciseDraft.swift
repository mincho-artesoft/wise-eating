import Foundation

public struct TrainingPlanExerciseDraft: Codable, Sendable {
    public let exerciseName: String
    public let durationSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case exerciseName
        case durationSeconds
        case durationMinutes
    }

    public init(exerciseName: String, durationSeconds: Double) {
        self.exerciseName = exerciseName
        self.durationSeconds = durationSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseName = try container.decode(String.self, forKey: .exerciseName)
        if let seconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) {
            durationSeconds = seconds
        } else {
            durationSeconds = try container.decode(Double.self, forKey: .durationMinutes) * 60
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encode(durationSeconds, forKey: .durationSeconds)
    }
}
