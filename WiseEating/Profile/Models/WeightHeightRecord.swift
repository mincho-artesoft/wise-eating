import Foundation
import SwiftData

@Model
public final class WeightHeightRecord {
    public var id: UUID = UUID()
    public var date: Date
    public var weight: Double
    public var height: Double
    public var headCircumference: Double? // <-- ADD THIS LINE
    public var customMetrics: [String: Double] = [:]
    
    public var profile: Profile?
    
    // Update the initializer to include the new property
    public init(date: Date, weight: Double, height: Double, headCircumference: Double? = nil, customMetrics: [String: Double] = [:]) {
        self.date = date
        self.weight = weight
        self.height = height
        self.headCircumference = headCircumference // <-- ADD THIS LINE
        self.customMetrics = customMetrics
    }
}
