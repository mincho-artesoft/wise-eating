import Foundation

/// A restriction or goal the person has stated for their own eating:
/// "protein at most 20 g a day" (from a doctor), "no tomatoes", "more protein".
/// The app stores what the person confirmed; it never invents one.
struct DietaryConstraint: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// The nutrient total must stay at or below `amount`.
        case nutrientMax
        /// The nutrient total should reach at least `amount`.
        case nutrientMin
        /// Foods whose name matches `foodTerm` are left out.
        case excludeFood
        /// Foods whose name matches `foodTerm` are preferred.
        case preferFood
    }

    enum Period: String, Codable, CaseIterable, Sendable {
        case day, meal
    }

    enum Source: String, Codable, CaseIterable, Sendable {
        case doctor, prescription, labReport, selfReported = "self"

        var displayName: String {
            switch self {
            case .doctor: String(localized: "Doctor")
            case .prescription: String(localized: "Prescription")
            case .labReport: String(localized: "Lab report")
            case .selfReported: String(localized: "My own choice")
            }
        }
    }

    var id: UUID
    var kind: Kind
    /// `NutrientType` raw value for the nutrient kinds.
    var nutrient: String?
    var amount: Double?
    /// "g", "mg", "µg" or "kcal".
    var unit: String?
    var period: Period
    /// Food word for the food kinds ("tomato").
    var foodTerm: String?
    var source: Source
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        nutrient: String? = nil,
        amount: Double? = nil,
        unit: String? = nil,
        period: Period = .day,
        foodTerm: String? = nil,
        source: Source = .selfReported,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.nutrient = nutrient
        self.amount = amount
        self.unit = unit
        self.period = period
        self.foodTerm = foodTerm
        self.source = source
        self.note = note
        self.createdAt = createdAt
    }

    var nutrientType: NutrientType? { nutrient.flatMap(NutrientType.init(rawValue:)) }

    var isNutrientRule: Bool { kind == .nutrientMax || kind == .nutrientMin }

    /// A nutrient rule needs a known nutrient and a positive amount; a food rule
    /// needs a food word.
    var isValid: Bool {
        switch kind {
        case .nutrientMax, .nutrientMin:
            guard let nutrientType, let amount, amount > 0 else { return false }
            let target = unit ?? FoodItem.canonicalUnit(for: nutrientType)
            return DietaryUnits.convert(1, from: target, to: FoodItem.canonicalUnit(for: nutrientType)) != nil
        case .excludeFood, .preferFood:
            return !(foodTerm ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The limit in the catalogue's own unit for this nutrient.
    var amountInCanonicalUnit: Double? {
        guard let nutrientType, let amount else { return nil }
        let canonical = FoodItem.canonicalUnit(for: nutrientType)
        return DietaryUnits.convert(amount, from: unit ?? canonical, to: canonical)
    }

    /// One line for lists and the model: "Protein at most 20 g a day".
    var summary: String {
        let periodText = period == .day
            ? String(localized: "a day")
            : String(localized: "per meal")
        switch kind {
        case .nutrientMax:
            return String(localized: "\(DietaryNutrientNames.displayName(nutrient)) at most \(DietaryUnits.format(amount ?? 0)) \(unit ?? "") \(periodText)")
        case .nutrientMin:
            return String(localized: "\(DietaryNutrientNames.displayName(nutrient)) at least \(DietaryUnits.format(amount ?? 0)) \(unit ?? "") \(periodText)")
        case .excludeFood:
            return String(localized: "Avoid \(foodTerm ?? "")")
        case .preferFood:
            return String(localized: "Prefer \(foodTerm ?? "")")
        }
    }
}

enum DietaryUnits {
    private static let grams: [String: Double] = [
        "g": 1, "mg": 0.001, "µg": 0.000_001, "ug": 0.000_001, "mcg": 0.000_001,
    ]

    static func normalized(_ unit: String) -> String {
        let u = unit.trimmingCharacters(in: .whitespaces).lowercased()
        switch u {
        case "gram", "grams", "gr": return "g"
        case "milligram", "milligrams": return "mg"
        case "microgram", "micrograms", "mcg", "ug", "μg": return "µg"
        case "calories", "calorie", "cal", "kilocalories": return "kcal"
        default: return u
        }
    }

    /// Converts between mass units, or returns the value for the same unit
    /// (kcal to kcal). Returns nil for units that do not convert.
    static func convert(_ value: Double, from: String, to: String) -> Double? {
        let f = normalized(from), t = normalized(to)
        if f == t { return value }
        guard let a = grams[f], let b = grams[t] else { return nil }
        return value * a / b
    }

    static func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}

enum DietaryNutrientNames {
    /// The nutrients a person is likely to be given a limit for. The model may
    /// use any `NutrientType` raw value; these are the ones the settings screen offers.
    static let common: [NutrientType] = [
        .protein, .energy, .carbs, .totalSugar, .totalFat, .saturatedFat, .fiber,
        .sodium, .potassium, .phosphorus, .calcium, .iron, .cholesterol, .vitaminK,
    ]

    static func displayName(_ raw: String?) -> String {
        guard let raw, let type = NutrientType(rawValue: raw) else { return raw ?? "" }
        return displayName(type)
    }

    static func displayName(_ type: NutrientType) -> String {
        switch type {
        case .protein: String(localized: "Protein")
        case .energy: String(localized: "Calories")
        case .carbs: String(localized: "Carbohydrates")
        case .totalSugar: String(localized: "Sugar")
        case .totalFat: String(localized: "Fat")
        case .saturatedFat: String(localized: "Saturated fat")
        case .fiber: String(localized: "Fiber")
        case .sodium: String(localized: "Sodium")
        case .potassium: String(localized: "Potassium")
        case .phosphorus: String(localized: "Phosphorus")
        case .calcium: String(localized: "Calcium")
        case .iron: String(localized: "Iron")
        case .cholesterol: String(localized: "Cholesterol")
        case .vitaminK: String(localized: "Vitamin K")
        default: type.rawValue
        }
    }
}

/// Constraints per profile, kept on the device next to the constitution records.
@MainActor
enum DietaryConstraintStore {
    private static let key = "ayurvedaasanayoga.assistant.dietaryConstraints.v1"

    static func constraints(for profileID: UUID, defaults: UserDefaults = .standard) -> [DietaryConstraint] {
        all(defaults)[profileID.uuidString] ?? []
    }

    static func save(_ constraints: [DietaryConstraint], for profileID: UUID, defaults: UserDefaults = .standard) {
        var map = all(defaults)
        map[profileID.uuidString] = constraints.filter(\.isValid)
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .dietaryConstraintsDidChange, object: profileID)
    }

    /// Adds new rules; a new nutrient rule replaces an older one for the same
    /// nutrient, direction and period, and food rules are not duplicated.
    static func merge(_ new: [DietaryConstraint], for profileID: UUID, defaults: UserDefaults = .standard) {
        var current = constraints(for: profileID, defaults: defaults)
        for rule in new where rule.isValid {
            current.removeAll { old in
                old.kind == rule.kind && old.period == rule.period
                    && (rule.isNutrientRule
                        ? old.nutrient == rule.nutrient
                        : old.foodTerm?.lowercased() == rule.foodTerm?.lowercased())
            }
            current.append(rule)
        }
        save(current, for: profileID, defaults: defaults)
    }

    static func remove(id: UUID, for profileID: UUID, defaults: UserDefaults = .standard) {
        save(constraints(for: profileID, defaults: defaults).filter { $0.id != id }, for: profileID, defaults: defaults)
    }

    private static func all(_ defaults: UserDefaults) -> [String: [DietaryConstraint]] {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode([String: [DietaryConstraint]].self, from: data)
        else { return [:] }
        return map
    }
}

extension Notification.Name {
    static let dietaryConstraintsDidChange = Notification.Name("DietaryConstraintsDidChange")
}
