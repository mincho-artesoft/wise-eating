import Foundation
import SwiftData

@Model
final class TemplateDay: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var dayIndex: Int

    // ✅ НОВО: Почивен ден
    public var isRestDay: Bool

    @Relationship(deleteRule: .cascade, inverse: \TemplateWorkout.day)
    public var workouts: [TemplateWorkout] = []

    public var plan: TemplatePlan?

    public init(id: UUID = UUID(), dayIndex: Int, isRestDay: Bool = false) {
        self.id = id
        self.dayIndex = dayIndex
        self.isRestDay = isRestDay
    }
}
