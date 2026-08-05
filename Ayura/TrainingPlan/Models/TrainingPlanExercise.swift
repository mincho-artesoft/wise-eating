import Foundation
import SwiftData

@Model
public final class TrainingPlanExercise: Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(originalName: "durationMinutes")
    public var durationSeconds: Double

    @Relationship(deleteRule: .nullify)
    public var exercise: ExerciseItem?

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanSet.exercise)
    public var sets: [TrainingPlanSet] = []

    // ✅ to-one без @Relationship
    public var workout: TrainingPlanWorkout?

    public init(exercise: ExerciseItem, durationSeconds: Double, workout: TrainingPlanWorkout? = nil) {
        self.id = UUID()
        self.exercise = exercise
        self.durationSeconds = durationSeconds
        self.workout = workout
    }
}
