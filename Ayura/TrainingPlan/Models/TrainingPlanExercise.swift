import Foundation
import SwiftData

@Model
public final class TrainingPlanExercise: Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(originalName: "durationMinutes")
    public var durationSeconds: Double

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

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanSet.exercise)
    public var sets: [TrainingPlanSet] = []

    // ✅ to-one без @Relationship
    public var workout: TrainingPlanWorkout?

    public init(exercise: ExerciseItem, durationSeconds: Double, workout: TrainingPlanWorkout? = nil) {
        self.id = UUID()
        let reference = CatalogReferenceResolver.storedExerciseReference(for: exercise)
        self.persistedExercise = reference.stored
        self.catalogExerciseID = reference.catalogID
        self.durationSeconds = durationSeconds
        self.workout = workout
    }
}
