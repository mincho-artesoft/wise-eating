import Foundation
import SwiftData

@Model
public final class TrainingPlanSet: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var reps: Int?
    public var weight: Double?
    public var isToFailure: Bool = false
    public var isTimeBased: Bool = false
    public var timeUnit: TimeUnit = TimeUnit.seconds
    public var orderIndex: Int = 0

    // ✅ to-one без @Relationship
    public var exercise: TrainingPlanExercise?

    public init(
        reps: Int? = nil,
        weight: Double? = nil,
        isToFailure: Bool = false,
        isTimeBased: Bool = false,
        timeUnit: TimeUnit = .seconds,
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.isToFailure = isToFailure
        self.isTimeBased = isTimeBased
        self.timeUnit = timeUnit
        self.orderIndex = orderIndex
    }
}
