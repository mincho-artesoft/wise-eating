import Foundation
import SwiftData

@Model
public final class Node {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var textContent: String?
    public var calendarEventID: String?

    // Relationships
    @Relationship(deleteRule: .nullify, originalName: "linkedFoods")
    var persistedFoods: [FoodItem]? = []
    public var catalogFoodIDs: [UUID] = []

    public var linkedFoods: [FoodItem]? {
        get {
            CatalogReferenceResolver.resolveFoods(
                stored: persistedFoods ?? [],
                catalogIDs: catalogFoodIDs
            )
        }
        set {
            let split = CatalogReferenceResolver.splitFoods(newValue ?? [])
            persistedFoods = split.stored
            catalogFoodIDs = split.catalogIDs
        }
    }

    @Relationship(deleteRule: .nullify, originalName: "linkedExercises")
    var persistedExercises: [ExerciseItem]? = []
    public var catalogExerciseIDs: [UUID] = []

    public var linkedExercises: [ExerciseItem]? {
        get {
            CatalogReferenceResolver.resolveExercises(
                stored: persistedExercises ?? [],
                catalogIDs: catalogExerciseIDs
            )
        }
        set {
            let split = CatalogReferenceResolver.splitExercises(newValue ?? [])
            persistedExercises = split.stored
            catalogExerciseIDs = split.catalogIDs
        }
    }

    @Relationship(inverse: \Profile.nodes)
    public var profile: Profile?

    public init(textContent: String? = nil, profile: Profile?, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.textContent = textContent
        self.profile = profile
        self.calendarEventID = nil
    }
}
