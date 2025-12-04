import Foundation

struct CDCPoint {
    let ageMonths: Double
    let value: Double // cm or kg
}

struct CDCPercentileCurve {
    let percentile: String // e.g., "p50"
    let points: [CDCPoint]
}
