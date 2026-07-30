import Foundation

enum PhSearchSemantics {
    static let directionalBoundary = 7.0
    static let neutralLowerBound = 6.5
    static let neutralUpperBound = 7.5

    static func hasData(_ ph: Double) -> Bool {
        ph.isFinite && ph != 0.0
    }

    static func matches(_ ph: Double, constraint: ConstraintValue) -> Bool {
        guard hasData(ph) else { return false }

        switch constraint {
        case .min(let value):
            return ph >= value
        case .max(let value):
            return ph <= value
        case .strictMin(let value):
            return ph > value
        case .strictMax(let value):
            return ph < value
        case .range(let lower, let upper):
            return ph >= lower && ph <= upper
        case .notEqual(let value):
            return abs(ph - value) >= 0.1
        case .high:
            return ph > directionalBoundary
        case .low:
            return ph < directionalBoundary
        case .lowest, .highest:
            return true
        }
    }

    static func prefersLowValues(for constraint: ConstraintValue) -> Bool {
        switch constraint {
        case .max, .strictMax, .low, .lowest:
            return true
        default:
            return false
        }
    }
}
