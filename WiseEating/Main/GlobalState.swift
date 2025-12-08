import Foundation
import FoundationModels
import SwiftData

struct GlobalState {
  
    nonisolated(unsafe) static var modelContext: ModelContext?

    private static let emailKey = "PrimaryEmail"
    private static let regionKey           = "GlobalRegion"
    private static let calendarKey         = "GlobalCalendar"
    private static let temperatureKey      = "GlobalTemperatureUnit"
    private static let measureKey          = "GlobalMeasurementSystem"
    private static let firstWeekdayKey     = "GlobalFirstWeekday"
    private static let dateFormatKey       = "GlobalDateFormat"
    private static let numberFormatKey     = "GlobalNumberFormat"
    private static let currencyCodeKey     = "GlobalCurrencyCode"
    
    
    static func refreshSystemSettings() {
          let locale = Locale.current
          let calendar = Calendar.current
          
          // 1. Region
          if let regionCode = locale.region?.identifier {
              self.region = regionCode
          }
          
          // 2. Calendar Identifier
          self.calendar = String(describing: calendar.identifier)
          
          // 3. Temperature Unit (чрез симулация на форматиране)
          let temp = Measurement(value: 9, unit: UnitTemperature.celsius)
          let formattedTemp = temp.formatted(.measurement(width: .abbreviated, usage: .person, numberFormatStyle: .number))
          let unit = formattedTemp.contains("F") ? UnitTemperature.fahrenheit : UnitTemperature.celsius
          self.temperatureUnit = unit.symbol
          
          // 4. Measurement System (Metric/Imperial)
          self.measurementSystem = (locale.measurementSystem == .metric) ? "Metric" : "Imperial"
          
          // 5. First Weekday
          self.firstWeekday = calendar.firstWeekday
          
          // 6. Date Format
          let df = DateFormatter()
          df.locale = locale
          df.dateStyle = .short
          self.dateFormat = df.dateFormat ?? ""
          
          // 7. Number Format (примерно 1,234,567.89)
          let nf = NumberFormatter()
          nf.locale = locale
          nf.numberStyle = .decimal
          let num = 1234567.89 as NSNumber
          self.numberFormat = nf.string(from: num) ?? ""
          
          // 8. Currency Code
          if let currencyCode = locale.currency?.identifier {
              self.currencyCode = currencyCode
          }
      }
    
    nonisolated(unsafe) static var email: String = {
        UserDefaults.standard.string(forKey: emailKey) ?? ""
    }() {
        didSet {
            UserDefaults.standard.set(email, forKey: emailKey)
        }
    }
    
    nonisolated(unsafe) static var region: String =
        UserDefaults.standard.string(forKey: regionKey) ?? "" {
        didSet {
            UserDefaults.standard.set(region, forKey: regionKey)
            print("🌍 Region: \(region)")
        }
    }

    nonisolated(unsafe) static var calendar: String =
        UserDefaults.standard.string(forKey: calendarKey) ?? "" {
        didSet {
            UserDefaults.standard.set(calendar, forKey: calendarKey)
            print("📆 Calendar: \(calendar)")
        }
    }

    nonisolated(unsafe) static var temperatureUnit: String =
        UserDefaults.standard.string(forKey: temperatureKey) ?? "" {
        didSet {
            UserDefaults.standard.set(temperatureUnit, forKey: temperatureKey)
            print("🌡 Temperature Unit: \(temperatureUnit)")
        }
    }

    nonisolated(unsafe) static var measurementSystem: String =
        UserDefaults.standard.string(forKey: measureKey) ?? "" {
        didSet {
            UserDefaults.standard.set(measurementSystem, forKey: measureKey)
            print("📏 Measurement Units: \(measurementSystem)")
        }
    }

    nonisolated(unsafe) static var firstWeekday: Int =
        UserDefaults.standard.integer(forKey: firstWeekdayKey) {
        didSet {
            UserDefaults.standard.set(firstWeekday, forKey: firstWeekdayKey)
            print("📅 First Day of Week: \(firstWeekday)")
        }
    }

    nonisolated(unsafe) static var dateFormat: String =
        UserDefaults.standard.string(forKey: dateFormatKey) ?? "" {
        didSet {
            UserDefaults.standard.set(dateFormat, forKey: dateFormatKey)
            print("🗓 Date Format: \(dateFormat)")
        }
    }

    nonisolated(unsafe) static var numberFormat: String =
        UserDefaults.standard.string(forKey: numberFormatKey) ?? "" {
        didSet {
            UserDefaults.standard.set(numberFormat, forKey: numberFormatKey)
            print("🔢 Number Format: \(numberFormat)")
        }
    }
    
    nonisolated(unsafe) static var currencyCode: String =
        UserDefaults.standard.string(forKey: currencyCodeKey) ?? "USD" {
        didSet {
            UserDefaults.standard.set(currencyCode, forKey: currencyCodeKey)
            print("💵 Currency Code: \(currencyCode)")
        }
    }

    static var temperatureUnitSymbol: String {
        if temperatureUnit == UnitTemperature.fahrenheit.symbol {
            return "°F"
        } else {
            return "°C"
        }
    }

    static var speedUnitLabel: String {
        if measurementSystem == "Imperial" {
            return NSLocalizedString("Unit_Speed_mph", comment: "miles per hour")
        } else {
            return NSLocalizedString("Unit_Speed_kmh", comment: "kilometers per hour")
        }
    }

    static var distanceUnitLabel: String {
        if measurementSystem == "Imperial" {
            return NSLocalizedString("Unit_Distance_mi", comment: "miles")
        } else {
            return NSLocalizedString("Unit_Distance_km", comment: "kilometers")
        }
    }

    static var precipitationUnitLabel: String {
        if measurementSystem == "Imperial" {
            return NSLocalizedString("Unit_Precipitation_in", comment: "inches")
        } else {
            return NSLocalizedString("Unit_Precipitation_mm", comment: "millimeters")
        }
    }

    static var pressureUnitLabel: String {
        if measurementSystem == "Imperial" {
            return NSLocalizedString("Unit_Pressure_inHg", comment: "inches of mercury")
        } else {
            return NSLocalizedString("Unit_Pressure_hPa", comment: "hectopascals")
        }
    }
    
    /// Форматер за **показване** на десетични числа (БЕЗ разделители за хиляди).
    static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false   // 👈 важно
        return formatter
    }()

    /// Форматер за **показване** на мерни единици (БЕЗ разделители за хиляди).
    static let unitFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false   // 👈 важно
        return formatter
    }()

    /// Форматер за **показване** на цели числа (БЕЗ разделители за хиляди).
    static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = false   // 👈 важно
        return formatter
    }()

      
    private static func sanitizeForParsing(_ input: String, locale: Locale = .current) -> String {
          var result = input
          
          // 1) Премахваме всички "space-like" символи:
          // " " (space), U+00A0 (non-breaking), U+202F (narrow NBSP),
          // U+2007 (figure space), U+2009 (thin space)
          let spaceLikeScalars: [UnicodeScalar] = [
              " ".unicodeScalars.first!,
              UnicodeScalar(0x00A0)!, // NBSP
              UnicodeScalar(0x202F)!, // narrow NBSP
              UnicodeScalar(0x2007)!, // figure space
              UnicodeScalar(0x2009)!  // thin space
          ]
          
          result.unicodeScalars.removeAll { spaceLikeScalars.contains($0) }
          
          // 2) Премахваме апостроф (пример: 1'234'567.89)
          result.removeAll { $0 == "'" }
          
          // 3) Държим само правилния decimal separator за текущия locale.
          let decimalSeparator = locale.decimalSeparator ?? "."
          let otherDecimal = (decimalSeparator == ",") ? "." : ","
          result = result.replacingOccurrences(of: otherDecimal, with: "")
          
          return result
      }
      
      static func double(from input: String) -> Double? {
          let locale = Locale.current
          
          // Нормализираме стринга
          let cleaned = sanitizeForParsing(input, locale: locale)
          guard !cleaned.isEmpty else { return nil }
          
          let parser = NumberFormatter()
          parser.locale = locale
          parser.numberStyle = .decimal
          parser.allowsFloats = true
          
          return parser.number(from: cleaned)?.doubleValue
      }
        
      static func integerAsDouble(from input: String) -> Double? {
          return integer(from: input).map(Double.init)
      }

      static func integer(from input: String) -> Int? {
          let locale = Locale.current
          let cleaned = sanitizeForParsing(input, locale: locale)
          guard !cleaned.isEmpty else { return nil }
          
          let parser = NumberFormatter()
          parser.locale = locale
          parser.numberStyle = .decimal
          parser.allowsFloats = false
          
          return parser.number(from: cleaned)?.intValue
      }
        
      static func isValidDecimal(_ input: String) -> Bool {
          // Празно поле винаги е валидно
          if input.isEmpty { return true }
          
          let locale = Locale.current
          let decimalSeparator = locale.decimalSeparator ?? "."
          
          // Нормализирана стойност (без хилядни разделители, с един правилен decimal)
          let cleaned = sanitizeForParsing(input, locale: locale)
          
          // Междинни състояния, докато потребителят пише:
          // само "-", само decimalSeparator или "-<decimalSeparator>"
          if cleaned == "-" || cleaned == decimalSeparator || cleaned == "-\(decimalSeparator)" {
              return true
          }
          
          // Ако завършва на decimalSeparator (пример: "1," или "123.")
          if cleaned.hasSuffix(decimalSeparator) {
              let withoutSep = String(cleaned.dropLast())
              // Празно + decimal сепаратор ("." или ",") вече е хванато по-горе
              if withoutSep.isEmpty { return true }
              return double(from: withoutSep) != nil
          }
          
          // Нормален случай – опитваме да го парснем като Double
          return double(from: cleaned) != nil
      }
        
      static func isValidInteger(_ input: String) -> Bool {
          if input.isEmpty { return true }
          
          let locale = Locale.current
          let decimalSeparator = locale.decimalSeparator ?? "."
          let cleaned = sanitizeForParsing(input, locale: locale)
          
          // Позволяваме само "-", докато се пише
          if cleaned == "-" {
              return true
          }
          
          // Ако има decimal separator → не е валидно цяло число
          if cleaned.contains(decimalSeparator) {
              return false
          }
          
          return integer(from: cleaned) != nil
      }
    
    static func formatDecimalString(_ stringValue: String) -> String {
        if let numberValue = GlobalState.double(from: stringValue), !stringValue.isEmpty {
            return GlobalState.decimalFormatter.string(from: NSNumber(value: numberValue)) ?? stringValue
        }
        return stringValue
    }
    
    static func formatIntegerString(_ stringValue: String) -> String {
        if let numberValue = GlobalState.integer(from: stringValue), !stringValue.isEmpty {
            return GlobalState.integerFormatter.string(from: NSNumber(value: numberValue)) ?? stringValue
        }
        return stringValue
    }
    
    
    enum AIAvailabilityStatus: String, Sendable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unavailableOther
        case unavailableUnsupportedOS
    }

    nonisolated(unsafe) static var aiAvailability: AIAvailabilityStatus = {
        if #available(iOS 26.0, *) {
            return .unavailableOther // ще се изчисли реално при първото update
        } else {
            return .unavailableUnsupportedOS
        }
    }() {
        didSet {
            guard oldValue != aiAvailability else { return }
            print("🧠 AI Availability changed -> \(aiAvailability)")
            NotificationCenter.default.post(name: .aiAvailabilityDidChange, object: aiAvailability)
        }
    }

    static var isAppleIntelligenceAvailable: Bool { aiAvailability == .available }

    @MainActor
    static func updateAIAvailability() {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                aiAvailability = .available
            case .unavailable(.deviceNotEligible):
                aiAvailability = .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                aiAvailability = .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                aiAvailability = .modelNotReady
            case .unavailable(_):
                aiAvailability = .unavailableOther
            }
        } else {
            aiAvailability = .unavailableUnsupportedOS
        }
        #else
        aiAvailability = .unavailableUnsupportedOS
        #endif
    }
}


