import Foundation

// MARK: – Configuration
struct BlurConfiguration: Codable, Equatable {
    var radius: Double            = 15
    var saturation: Double        = 0.8
    var brightness: Double        = 0.0          // no darkening
    var useScrim: Bool            = false
    var focusAmount: Double       = 0.95
    var useAppleMaterial: Bool    = false
    var customGlassOpacity: Double = 0.08        // lighter glass
    var distortion: Double        = 8.0
}

