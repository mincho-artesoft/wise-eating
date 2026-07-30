import Foundation

// ПРОМЯНА: Добавяме Codable, CaseIterable, Identifiable
public enum ActivityLevel: Double, Codable, CaseIterable, Identifiable {
    case sedentary          = 1.2
    case lightlyActive      = 1.375
    case moderatelyActive   = 1.55
    case veryActive         = 1.725
    case extraActive        = 1.9

    // За Identifiable
    public var id: Double { self.rawValue }

    // За по-добър изглед в Picker-a
    public var description: String {
        switch self {
        case .sedentary:        return "Sedentary (little or no exercise)"
        case .lightlyActive:    return "Lightly Active (1-3 days/week)"
        case .moderatelyActive: return "Moderately Active (3-5 days/week)"
        case .veryActive:       return "Very Active (6-7 days/week)"
        case .extraActive:      return "Extra Active (very hard exercise & physical job)"
        }
    }
}
