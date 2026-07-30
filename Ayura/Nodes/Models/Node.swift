import Foundation
import SwiftData

@Model
public final class Node {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var textContent: String?
    public var calendarEventID: String?

    // Relationships
    @Relationship(deleteRule: .nullify)
    public var linkedFoods: [FoodItem]? = []

    @Relationship(deleteRule: .nullify)
    public var linkedExercises: [ExerciseItem]? = []

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
