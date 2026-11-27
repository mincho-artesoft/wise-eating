import Foundation
import StoreKit
import SwiftUI

extension Product.SubscriptionPeriod.Unit {
    func noun(plural: Bool) -> String {
        switch self {
        case .day: return plural ? String(localized: "days") : String(localized: "day")
        case .week: return plural ? String(localized: "weeks") : String(localized: "week")
        case .month: return plural ? String(localized: "months") : String(localized: "month")
        case .year: return plural ? String(localized: "years") : String(localized: "year")
        @unknown default: return plural ? String(localized: "periods") : String(localized: "period")
        }
    }

}

extension Product {
    var periodUnitOnly: String {
        guard let unit = subscription?.subscriptionPeriod.unit else { return "" }
        switch unit {
        case .day: return String(localized: "Daily")
        case .week: return String(localized: "Weekly")
        case .month: return String(localized: "Monthly")
        case .year: return String(localized: "Yearly")
        @unknown default: return String(localized: "Recurring")
        }
    }
}
