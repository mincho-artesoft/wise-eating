import Foundation

public struct TrainingPlanDayDraft: Codable, Sendable {
    public let dayIndex: Int
    public let trainings: [Training]
}

public struct TrainingPlanDraft: Identifiable, Codable, Sendable {
    public let id = UUID()
    public let name: String
    public var days: [TrainingPlanDayDraft]

    public init(name: String, days: [TrainingPlanDayDraft]) {
        self.name = name
        self.days = days
    }
}
