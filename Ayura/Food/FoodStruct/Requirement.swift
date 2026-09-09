import SwiftData
import Foundation

@Model
public final class Requirement: Identifiable, Hashable {
    @Attribute(.unique) public var id: UUID
    public var demographic: String
    public var dailyNeed: Double
    public var upperLimit: Double?

    //-- reverse relationship (optional)
    @Relationship(inverse: \Vitamin.requirements) public var vitamin: Vitamin?

    public init(
         id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
         demographic: String,
         dailyNeed: Double,
         upperLimit: Double? = nil) {
        self.id          = id
        self.demographic = demographic
        self.dailyNeed    = dailyNeed
        self.upperLimit   = upperLimit
    }
}
