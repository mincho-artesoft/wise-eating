import SwiftUI

// CORRECTED Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b: Double
        var a: Double = 1.0 // Default alpha is 1.0 (opaque)
        
        switch hex.count {
        case 6: // RRGGBB
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        case 8: // RRGGBBAA
            r = Double((int >> 24) & 0xFF) / 255.0
            g = Double((int >> 16) & 0xFF) / 255.0
            b = Double((int >> 8) & 0xFF) / 255.0
            a = Double(int & 0xFF) / 255.0
        default:
            // Invalid format, default to black
            (r, g, b) = (0, 0, 0)
        }
        
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
    
    func isLight() -> Bool {
        // We need to convert the SwiftUI Color to a UIColor to access its components.
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            // Default to assuming dark for safety if conversion fails.
            return false
        }
        
        // Extract RGB components.
        let red = components[0]
        let green = components[1]
        let blue = components[2]
        
        // Calculate luminance using the standard formula (perceived brightness).
        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        
        // A luminance value greater than 0.5 is generally considered light.
        return luminance > 0.5
    }
}
