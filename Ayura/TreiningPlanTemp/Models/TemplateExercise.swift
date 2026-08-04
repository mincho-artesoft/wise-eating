import Foundation
import SwiftData

@Model
final class TemplateExercise: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var exerciseName: String
    public var durationMinutes: Double

    @Relationship(deleteRule: .cascade, inverse: \TemplateSet.exercise)
    public var sets: [TemplateSet] = []

    public var workout: TemplateWorkout?

    public init(id: UUID = UUID(), exerciseName: String, durationMinutes: Double) {
        self.id = id
        self.exerciseName = exerciseName
        self.durationMinutes = durationMinutes
    }
}
