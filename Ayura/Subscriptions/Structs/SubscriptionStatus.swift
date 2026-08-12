import SwiftUI

/// Represents the user's current subscription level.
enum SubscriptionStatus: String, CaseIterable {
    case base
    case removeAds = "No Ads"
    case advance = "Advanced"
    case premium = "Premium"

    var title: String {
        self.rawValue.capitalized
    }
}
