import Foundation

/// Represents a single set of an exercise (e.g., 10 reps with 50 kg).
public struct WorkoutSet: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var reps: Int?
    public var weight: Double?
    
    // Флаг за отказ
    public var isToFailure: Bool = false
    
    // ✅ НОВО: Флаг за време
    public var isTimeBased: Bool = false
    
    public init(id: UUID = UUID(), reps: Int? = nil, weight: Double? = nil, isToFailure: Bool = false, isTimeBased: Bool = false) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.isToFailure = isToFailure
        self.isTimeBased = isTimeBased
    }
    
    // Трябва да обновим и CodingKeys, ако искаме да се запазва правилно в JSON (в Training.notes)
    enum CodingKeys: String, CodingKey {
        case id, reps, weight, isToFailure, isTimeBased
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        isToFailure = try container.decodeIfPresent(Bool.self, forKey: .isToFailure) ?? false
        isTimeBased = try container.decodeIfPresent(Bool.self, forKey: .isTimeBased) ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reps, forKey: .reps)
        try container.encode(weight, forKey: .weight)
        try container.encode(isToFailure, forKey: .isToFailure)
        try container.encode(isTimeBased, forKey: .isTimeBased)
    }
}

/// Represents the detailed log for a single exercise within a workout.
public struct ExerciseLog: Codable, Hashable, Identifiable {
    public var id: Int { exerciseID }
    public let exerciseID: Int
    public var sets: [WorkoutSet]
    
    public init(exerciseID: Int, sets: [WorkoutSet]) {
        self.exerciseID = exerciseID
        self.sets = sets
    }
}

/// Represents the complete detailed log for an entire training session.
public struct DetailedTrainingLog: Codable, Hashable {
    public var logs: [ExerciseLog]
    
    public init(logs: [ExerciseLog]) {
        self.logs = logs
    }
}

/// A container payload that holds both the simple exercise list (for backward compatibility and quick display)
/// and the new detailed log. This entire object will be JSON-encoded and stored in the event's notes.
public struct TrainingPayload: Codable {
    /// The original format: "exerciseID1=duration1|exerciseID2=duration2"
    public var exercises: String
    
    /// The new, detailed log containing sets, reps, and weight.
    public var detailedLog: DetailedTrainingLog?
    
    public init(exercises: String, detailedLog: DetailedTrainingLog? = nil) {
        self.exercises = exercises
        self.detailedLog = detailedLog
    }
}
