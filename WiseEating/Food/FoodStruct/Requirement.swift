import SwiftData
import Foundation

@Model
public final class Requirement: Identifiable, Hashable {
    @Attribute(.unique) public var id = UUID()          // primary key
    public var demographic: String
    public var dailyNeed: Double
    public var upperLimit: Double?

    //-- reverse relationship (optional)
    @Relationship(inverse: \Vitamin.requirements) public var vitamin: Vitamin?

    public init(demographic: String,
         dailyNeed: Double,
         upperLimit: Double? = nil) {
        self.demographic = demographic
        self.dailyNeed    = dailyNeed
        self.upperLimit   = upperLimit
    }
}
