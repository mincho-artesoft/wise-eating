import Foundation
import SwiftData

@Model
public final class TrainingPlanSet: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var reps: Int?
    public var weight: Double?
    
    public var exercise: TrainingPlanExercise?

    public init(reps: Int? = nil, weight: Double? = nil) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
    }
}
