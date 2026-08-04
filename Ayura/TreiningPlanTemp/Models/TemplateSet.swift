import Foundation
import SwiftData

@Model
final class TemplateSet: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var reps: Int?
    public var isToFailure: Bool
    public var isTimeBased: Bool
    public var timeUnitString: String
    public var orderIndex: Int

    public var exercise: TemplateExercise?

    public init(id: UUID = UUID(), reps: Int?, isToFailure: Bool, isTimeBased: Bool, timeUnitString: String, orderIndex: Int) {
        self.id = id
        self.reps = reps
        self.isToFailure = isToFailure
        self.isTimeBased = isTimeBased
        self.timeUnitString = timeUnitString
        self.orderIndex = orderIndex
    }
}
