import Foundation
import SwiftData

@Model
final class TemplateSet: Identifiable {
    public var reps: Int?
    public var isToFailure: Bool
    public var isTimeBased: Bool
    public var timeUnitString: String
    public var orderIndex: Int

    public var exercise: TemplateExercise?

    public init(reps: Int?, isToFailure: Bool, isTimeBased: Bool, timeUnitString: String, orderIndex: Int) {
        self.reps = reps
        self.isToFailure = isToFailure
        self.isTimeBased = isTimeBased
        self.timeUnitString = timeUnitString
        self.orderIndex = orderIndex
    }
}
