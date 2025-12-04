import Foundation
import SwiftData

@Model
public final class TrainingPlan: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var creationDate: Date

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlanDay.plan)
    public var days: [TrainingPlanDay] = []

    @Relationship(inverse: \Profile.trainingPlans)
    public var profile: Profile?

    public var minAgeMonths: Int = 0

    public init(name: String, profile: Profile?, minAgeMonths: Int = 0) {
        self.id = UUID()
        self.name = name
        self.creationDate = Date()
        self.profile = profile
        self.minAgeMonths = minAgeMonths

    }
}
