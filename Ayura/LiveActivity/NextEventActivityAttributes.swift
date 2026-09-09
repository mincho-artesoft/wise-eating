import ActivityKit
import Foundation

struct NextEventActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let events: [NextEventItem]
        let generatedAt: Date
    }

    let profileID: String
    let profileName: String
}

struct NextEventItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case meal
        case workout
        case practice
    }

    let id: String
    let kind: Kind
    let title: String
    let startDate: Date
    let endDate: Date?
}
