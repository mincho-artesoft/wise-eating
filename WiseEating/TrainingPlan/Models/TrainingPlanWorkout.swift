import Foundation
import SwiftData

@Model
public final class TrainingPlanWorkout: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var workoutName: String

    /// ID на ExerciseItem (isWorkout = true), който е автоматично генериран от този запис.
    public var linkedWorkoutID: Int? = nil

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanExercise.workout)
    public var exercises: [TrainingPlanExercise] = []

    // ✅ to-one без @Relationship
    public var day: TrainingPlanDay?

    public init(workoutName: String, day: TrainingPlanDay? = nil) {
        self.id = UUID()
        self.workoutName = workoutName
        self.day = day
    }
}
