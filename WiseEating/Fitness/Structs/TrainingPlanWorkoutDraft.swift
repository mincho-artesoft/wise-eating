import Foundation

public struct TrainingPlanWorkoutDraft: Codable, Sendable {
    public let workoutName: String
    public var exercises: [TrainingPlanExerciseDraft]
}
