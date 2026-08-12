import Foundation
import StoreKit
import SwiftUI

extension Product.SubscriptionPeriod.Unit {
    func noun(plural: Bool) -> String {
        switch self {
        case .day: return plural ? "days" : "day"
        case .week: return plural ? "weeks" : "week"
        case .month: return plural ? "months" : "month"
        case .year: return plural ? "years" : "year"
        @unknown default: return plural ? "periods" : "period"
        }
    }

}

extension Product {
    var periodUnitOnly: String {
        guard let unit = subscription?.subscriptionPeriod.unit else { return "" }
        switch unit {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Yearly"
        @unknown default: return "Recurring"
        }
    }
}
