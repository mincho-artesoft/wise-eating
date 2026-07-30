import Foundation
import SwiftData

@Model
final class TemplateDay: Identifiable {
    public var dayIndex: Int

    // ✅ НОВО: Почивен ден
    public var isRestDay: Bool

    @Relationship(deleteRule: .cascade, inverse: \TemplateWorkout.day)
    public var workouts: [TemplateWorkout] = []

    public var plan: TemplatePlan?

    public init(dayIndex: Int, isRestDay: Bool = false) {
        self.dayIndex = dayIndex
        self.isRestDay = isRestDay
    }
}
