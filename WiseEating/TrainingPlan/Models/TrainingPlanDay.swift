import Foundation
import SwiftData

@Model
public final class TrainingPlanDay: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var dayIndex: Int
    public var isRestDay: Bool

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanWorkout.day)
    public var workouts: [TrainingPlanWorkout] = []

    // ✅ оставяме to-one като нормален var (без @Relationship)
    public var plan: TrainingPlan?

    public init(dayIndex: Int, isRestDay: Bool = false, plan: TrainingPlan? = nil) {
        self.id = UUID()
        self.dayIndex = dayIndex
        self.isRestDay = isRestDay
        self.plan = plan
    }
}
