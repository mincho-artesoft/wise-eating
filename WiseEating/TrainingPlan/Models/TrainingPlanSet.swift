import Foundation
import SwiftData

@Model
public final class TrainingPlanSet: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var reps: Int?
    public var weight: Double?
    
    // ✅ НОВО: Флаг за отказ
    public var isToFailure: Bool = false
    
    public var exercise: TrainingPlanExercise?

    // ✅ Актуализиран init
    public init(reps: Int? = nil, weight: Double? = nil, isToFailure: Bool = false) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.isToFailure = isToFailure
    }
}
