import SwiftUI

enum BannerBucket {
    case small   // ~50pt
    case large   // ~120pt

    var height: CGFloat {
        switch self {
        case .small: return 50
        case .large: return 120
        }
    }
}
