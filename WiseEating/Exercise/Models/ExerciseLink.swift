import Foundation
import SwiftData

@Model
public final class ExerciseLink: Identifiable {
    /// Конкретното упражнение, което е част от тренировката.
    @Relationship(deleteRule: .nullify)
    public var exercise: ExerciseItem?

    /// Колко минути да се изпълнява това упражнение в рамките на тренировката.
    public var durationMinutes: Double = 0

    /// Тренировката, която притежава тази връзка.
    @Relationship(inverse: \ExerciseItem.exercises)
    public var owner: ExerciseItem?

    public init(exercise: ExerciseItem, durationMinutes: Double = 0, owner: ExerciseItem? = nil) {
        self.exercise = exercise
        self.durationMinutes = durationMinutes
        self.owner = owner
    }
}
