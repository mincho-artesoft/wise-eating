import Foundation

struct PlottableMetric: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let metricName: String
    let value: Double
}
