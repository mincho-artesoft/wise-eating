import Foundation
import SwiftData

@Model
public final class ExerciseLink: Identifiable {
    @Attribute(.unique) public var id: UUID

    /// Конкретното упражнение, което е част от тренировката.
    @Relationship(deleteRule: .nullify)
    public var exercise: ExerciseItem?

    /// Колко секунди да се изпълнява това упражнение в рамките на тренировката.
    @Attribute(originalName: "durationMinutes")
    public var durationSeconds: Double = 0

    /// Тренировката, която притежава тази връзка.
    @Relationship(inverse: \ExerciseItem.exercises)
    public var owner: ExerciseItem?

    public init(
        id: UUID = UUID(),
        exercise: ExerciseItem,
        durationSeconds: Double = 0,
        owner: ExerciseItem? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.durationSeconds = durationSeconds
        self.owner = owner
    }
}
