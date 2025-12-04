import Foundation
import SwiftData

@Model
public final class TrainingPlanDay: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var dayIndex: Int
    public var isRestDay: Bool // <-- НОВО СВОЙСТВО

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanWorkout.day)
    public var workouts: [TrainingPlanWorkout] = []

    public var plan: TrainingPlan?

    // Актуализиран инициализатор
    public init(dayIndex: Int, isRestDay: Bool = false) {
        self.id = UUID()
        self.dayIndex = dayIndex
        self.isRestDay = isRestDay
    }
}
