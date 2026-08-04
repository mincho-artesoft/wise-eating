import Foundation

// ✅ НОВО: Енумерация за мерната единица
public enum TimeUnit: String, Codable, CaseIterable, Identifiable {
    case seconds = "Seconds"
    case minutes = "Minutes"
    public var id: String { rawValue }
}

/// Represents a single set of an exercise (e.g., 10 reps with 50 kg).
public struct WorkoutSet: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var reps: Int?
    public var weight: Double?
    
    // Флаг за отказ
    public var isToFailure: Bool = false
    
    // Флаг за време
    public var isTimeBased: Bool = false
    
    // ✅ НОВО: Мерна единица (по подразбиране секунди)
    public var timeUnit: TimeUnit = .seconds
    
    public init(id: UUID = UUID(), reps: Int? = nil, weight: Double? = nil, isToFailure: Bool = false, isTimeBased: Bool = false, timeUnit: TimeUnit = .seconds) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.isToFailure = isToFailure
        self.isTimeBased = isTimeBased
        self.timeUnit = timeUnit
    }
    
    enum CodingKeys: String, CodingKey {
        case id, reps, weight, isToFailure, isTimeBased, timeUnit
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        isToFailure = try container.decodeIfPresent(Bool.self, forKey: .isToFailure) ?? false
        isTimeBased = try container.decodeIfPresent(Bool.self, forKey: .isTimeBased) ?? false
        // ✅ НОВО: Decode с fallback към .seconds
        timeUnit = try container.decodeIfPresent(TimeUnit.self, forKey: .timeUnit) ?? .seconds
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reps, forKey: .reps)
        try container.encode(weight, forKey: .weight)
        try container.encode(isToFailure, forKey: .isToFailure)
        try container.encode(isTimeBased, forKey: .isTimeBased)
        try container.encode(timeUnit, forKey: .timeUnit)
    }
}

// ... (ExerciseLog, DetailedTrainingLog и TrainingPayload остават без промяна)
/// Represents the detailed log for a single exercise within a workout.
public struct ExerciseLog: Codable, Hashable, Identifiable {
    public var id: UUID { exerciseID }
    public let exerciseID: UUID
    public var sets: [WorkoutSet]
    
    public init(exerciseID: UUID, sets: [WorkoutSet]) {
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
