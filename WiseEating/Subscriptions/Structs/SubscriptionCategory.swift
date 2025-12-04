import Foundation

// MARK: - Category Enum
enum SubscriptionCategory: String, CaseIterable, Identifiable {
    case base     = "Base"
    case removeAds  = "Ads"
    case advance  = "Advanced"
    case premium  = "Premium"

    var id: String { rawValue }

    var title: String {
        rawValue
    }
}
