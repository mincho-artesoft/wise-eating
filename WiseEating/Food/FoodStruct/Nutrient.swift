public struct Nutrient: Codable, Hashable, Sendable {
    public var value: Double?
    public var unit: String?
    
    var stringValue: String {
           return String(describing: value)
       }
    
    // Initializer to handle optional values from AI response
    init(value: Double?, unit: String?) {
        // Only create a nutrient if there's a value
        if let value = value {
            self.value = value
            self.unit = unit
        } else {
            self.value = nil
            self.unit = nil
        }
    }
}
