import Foundation
import SwiftData

@Model
public final class TrainingPlanExercise: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var durationMinutes: Double

    @Relationship(deleteRule: .nullify)
    public var exercise: ExerciseItem?

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanSet.exercise)
    public var sets: [TrainingPlanSet] = []

    // ✅ to-one без @Relationship
    public var workout: TrainingPlanWorkout?

    public init(exercise: ExerciseItem, durationMinutes: Double, workout: TrainingPlanWorkout? = nil) {
        self.id = UUID()
        self.exercise = exercise
        self.durationMinutes = durationMinutes
        self.workout = workout
    }
}
