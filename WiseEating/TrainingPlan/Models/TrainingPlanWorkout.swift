import Foundation
import SwiftData

@Model
public final class TrainingPlanWorkout: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var workoutName: String // e.g., "Morning Workout"

    // --- НАЧАЛО НА ПРОМЯНАТА ---
    /// ID на ExerciseItem (isWorkout = true), който е автоматично генериран от този запис.
    public var linkedWorkoutID: Int? = nil
    // --- КРАЙ НА ПРОМЯНАТА ---

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanExercise.workout)
    public var exercises: [TrainingPlanExercise] = []

    public var day: TrainingPlanDay?

    public init(workoutName: String) {
        self.id = UUID()
        self.workoutName = workoutName
    }
}
