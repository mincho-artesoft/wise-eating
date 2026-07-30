import Foundation
import SwiftData

@Model
final class TemplateExercise: Identifiable {
    public var exerciseName: String
    public var durationMinutes: Double

    @Relationship(deleteRule: .cascade, inverse: \TemplateSet.exercise)
    public var sets: [TemplateSet] = []

    public var workout: TemplateWorkout?

    public init(exerciseName: String, durationMinutes: Double) {
        self.exerciseName = exerciseName
        self.durationMinutes = durationMinutes
    }
}
