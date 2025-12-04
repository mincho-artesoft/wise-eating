import Foundation

/// Изчислява препоръчителния дневен прием на калории (TDEE).
public struct TDEECalculator {

    /// Изчислява TDEE по формулата на Mifflin-St Jeor.
    public static func calculate(for profile: Profile, activityLevel: ActivityLevel) -> Double {
        let weightInKg = profile.weight
        let heightInCm = profile.height
        let ageInYears = Double(profile.age)

        let bmr: Double
        let isFemale = profile.gender.lowercased().hasPrefix("f")

        if isFemale {
            // Формула за жени
            bmr = (10 * weightInKg) + (6.25 * heightInCm) - (5 * ageInYears) - 161
        } else {
            // Формула за мъже
            bmr = (10 * weightInKg) + (6.25 * heightInCm) - (5 * ageInYears) + 5
        }

        let tdee = bmr * activityLevel.rawValue
        
        return tdee
    }
}
