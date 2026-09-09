import Foundation
import SwiftData

@Model
public final class WeightHeightRecord {
    public var id: UUID = UUID()
    public var date: Date
    public var weight: Double
    public var height: Double
    public var customMetrics: [String: Double] = [:]

    public var profile: Profile?

    public init(
        date: Date,
        weight: Double,
        height: Double,
        customMetrics: [String: Double] = [:]
    ) {
        self.date = date
        self.weight = weight
        self.height = height
        self.customMetrics = customMetrics
    }
}
