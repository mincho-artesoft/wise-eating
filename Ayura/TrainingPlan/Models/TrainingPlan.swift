import Foundation
import SwiftData

@Model
public final class TrainingPlan: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var creationDate: Date
    public var minAgeMonths: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanDay.plan)
    public var days: [TrainingPlanDay] = []

    @Relationship(inverse: \Profile.trainingPlans)
    public var profile: Profile?

    public init(name: String, profile: Profile?, minAgeMonths: Int = 0) {
        self.id = UUID()
        self.name = name
        self.creationDate = Date()
        self.profile = profile
        self.minAgeMonths = minAgeMonths
    }
}
