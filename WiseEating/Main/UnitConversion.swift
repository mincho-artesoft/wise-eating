import Foundation

// MARK: - UnitConversion
enum UnitConversion {

    // MARK: - Weight Conversions (for human body weight)
    static func kgToLbs(_ kg: Double) -> Double {
        kg * 2.20462
    }

    static func lbsToKg(_ lbs: Double) -> Double {
        lbs / 2.20462
    }

    // MARK: - Height Conversions
    static func cmToInches(_ cm: Double) -> Double {
        cm / 2.54
    }

    static func inchesToCm(_ inches: Double) -> Double {
        inches * 2.54
    }
    
    // MARK: - Mass Conversions (for food quantities in general, e.g. serving size)
    // Grams to Ounces
    static func gToOz(_ g: Double) -> Double {
        g * 0.035274
    }
    
    // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
    /// Конвертира грамове в унции и закръгля до 2 знака след запетаята за стабилно показване в UI.
    static func gToOz_display(_ g: Double) -> Double {
        let ounces = g * 0.035274
        // Закръгляме до 2-рия знак, за да избегнем артефакти като 3.99999...
        return (ounces * 100).rounded() / 100.0
    }
    // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----

    // Ounces to Grams
    static func ozToG(_ oz: Double) -> Double {
        oz / 0.035274
    }
    
    // Grams to Pounds
    static func gToLbsMass(_ g: Double) -> Double {
        g * 0.00220462 // 1 gram = 0.00220462 pounds
    }

    // Pounds to Grams
    static func lbsToGMass(_ lbs: Double) -> Double {
        lbs / 0.00220462
    }

    /// Converts grams to the appropriate display unit (g, kg, oz, lbs) based on GlobalState and quantity.
    /// This is specifically for food quantities where grams/kilograms are metric and ounces/pounds are imperial.
    static func formatGramsToFoodDisplay(_ grams: Double) -> (value: String, unit: String) {
        let isImperial = GlobalState.measurementSystem == "Imperial"

        if isImperial {
            let ounces = gToOz(grams)
            if ounces >= 16 { // If 16oz or more, display in pounds
                let pounds = ounces / 16.0
                return (UnitConversion.formatDecimal(pounds), "lbs")
            } else {
                return (UnitConversion.formatDecimal(ounces), "oz")
            }
        } else {
            if grams >= 1000 { // If 1000g or more, display in kg
                let kilograms = grams / 1000.0
                return (UnitConversion.formatDecimal(kilograms), "kg")
            } else {
                return (UnitConversion.formatDecimal(grams), "g")
            }
        }
    }

    /// Конвертира грамове само в грамове или унции, без да преминава към kg/lbs.
    static func formatGramsToGramsOrOunces(_ grams: Double) -> (value: String, unit: String) {
        let isImperial = GlobalState.measurementSystem == "Imperial"

        if isImperial {
            let ounces = gToOz(grams)
            return (UnitConversion.formatDecimal(ounces), "oz")
        } else {
            return (UnitConversion.formatDecimal(grams), "g")
        }
    }

    /// Formats a nutrient value that is *already in grams* to the appropriate display unit (g, kg, oz, lbs)
    /// based on GlobalState. This is for macro-nutrients (protein, fat, carbs) displayed in grams.
    static func formatNutrientGramsToDisplay(_ grams: Double) -> (value: String, unit: String) {
        let isImperial = GlobalState.measurementSystem == "Imperial"

        if isImperial {
            let ounces = gToOz(grams)
            if ounces >= 16 { // If 16oz or more, display in pounds
                let pounds = ounces / 16.0
                return (UnitConversion.formatDecimal(pounds), "lbs")
            } else {
                return (UnitConversion.formatDecimal(ounces), "oz")
            }
        } else {
            // For metric, scale to kg if large enough
            if grams >= 1000 {
                let kilograms = grams / 1000.0
                return (UnitConversion.formatDecimal(kilograms), "kg")
            } else {
                return (UnitConversion.formatDecimal(grams), "g")
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    /// Formats a Double value to a string, handling optional decimal places.
    /// Used for displaying weight (kg/lbs) or custom metrics.
    static func formatDecimal(_ value: Double) -> String {
        GlobalState.decimalFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    
    /// Formats a Double value to an integer string.
    /// Used for displaying height (cm/inches).
    static func formatInteger(_ value: Double) -> String {
        GlobalState.integerFormatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
    
    /// Parses a string to a Double, accounting for locale's decimal separator.
    static func parseDecimal(_ string: String) -> Double? {
        GlobalState.double(from: string)
    }
    
    /// Parses a string to an Int.
    static func parseInteger(_ string: String) -> Int? {
        GlobalState.integer(from: string)
    }
}
