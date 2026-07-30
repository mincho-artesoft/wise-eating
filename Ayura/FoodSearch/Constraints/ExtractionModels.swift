import Foundation

enum ComparisonOperator: String {
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case equal = "="
    case notEqual = "!="
    case unknown = "?"
}

struct DietaryConstraint: Identifiable, Hashable {
    let id = UUID()
    let originalText: String
    let subject: String
    let comparison: ComparisonOperator
    let value: Double?
    let value2: Double?
    let unit: String?
    
    var description: String {
        let unitStr = unit ?? ""
        if let v = value {
            if let v2 = value2 {
                // For ranges, we usually imply "Between" which is >= Min and <= Max
                return "\(subject): \(v) - \(v2)\(unitStr)"
            }
            // "Free of" maps to = 0
            if comparison == .equal && v == 0 {
                return "\(subject) is Zero / Free"
            }
            return "\(subject) \(comparison.rawValue) \(v)\(unitStr)"
        } else {
            return "\(subject) \(comparison.rawValue) [Abstract]"
        }
    }
}
