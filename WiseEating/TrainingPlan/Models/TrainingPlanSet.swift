import Foundation
import SwiftData

@Model
public final class TrainingPlanSet: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var reps: Int?
    public var weight: Double?
    public var isToFailure: Bool = false
    
    // ✅ НОВО: Флаг за време
    public var isTimeBased: Bool = false
    
    public var orderIndex: Int = 0
    
    public var exercise: TrainingPlanExercise?

    public init(reps: Int? = nil, weight: Double? = nil, isToFailure: Bool = false, isTimeBased: Bool = false, orderIndex: Int = 0) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.isToFailure = isToFailure
        self.isTimeBased = isTimeBased
        self.orderIndex = orderIndex
    }
}
