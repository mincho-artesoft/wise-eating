import Foundation
import SwiftData

@Model
final class TemplateWorkout: Identifiable {
    public var workoutName: String = "Workout"

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.workout)
    public var exercises: [TemplateExercise] = []

    public var day: TemplateDay?

    public init(workoutName: String = "Workout") {
        self.workoutName = workoutName
    }
}
