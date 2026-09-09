import Foundation
import SwiftData

@Model
public final class ExerciseLink: Identifiable {
    @Attribute(.unique) public var id: UUID

    /// Конкретното упражнение, което е част от тренировката.
    @Relationship(deleteRule: .nullify, originalName: "exercise")
    var persistedExercise: ExerciseItem?
    public var catalogExerciseID: UUID?

    public var exercise: ExerciseItem? {
        get {
            CatalogReferenceResolver.resolveExercise(
                stored: persistedExercise,
                catalogID: catalogExerciseID
            )
        }
        set {
            let reference = CatalogReferenceResolver.storedExerciseReference(
                for: newValue
            )
            persistedExercise = reference.stored
            catalogExerciseID = reference.catalogID
        }
    }

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
        let reference = CatalogReferenceResolver.storedExerciseReference(for: exercise)
        self.persistedExercise = reference.stored
        self.catalogExerciseID = reference.catalogID
        self.durationSeconds = durationSeconds
        self.owner = owner
    }

    /// Creates a link whose reference has already been routed to the correct
    /// store. Catalogue exercises use only `catalogExerciseID`; user exercises
    /// use the relationship from the user-only write context.
    public init(
        id: UUID = UUID(),
        persistedExercise: ExerciseItem?,
        catalogExerciseID: UUID?,
        durationSeconds: Double = 0,
        owner: ExerciseItem? = nil
    ) {
        self.id = id
        self.persistedExercise = persistedExercise
        self.catalogExerciseID = catalogExerciseID
        self.durationSeconds = durationSeconds
        self.owner = owner
    }
}
