import Foundation
import SwiftData

@Model
final class TemplateWorkout: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var workoutName: String = "Workout"

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.workout)
    public var exercises: [TemplateExercise] = []

    public var day: TemplateDay?

    public init(id: UUID = UUID(), workoutName: String = "Workout") {
        self.id = id
        self.workoutName = workoutName
    }
}
