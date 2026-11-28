import Foundation

/// What the person's profile looks like to the assistant. No name, no photo.
struct AssistantProfileSnapshot: Equatable, Sendable {
    var profileID: UUID
    var age: Int
    var sex: String
    var heightCm: Double
    var weightKg: Double
    var allergens: [Allergen]
    var constitutionLabel: String?
    var constitution: AyurvedaDoshaDistribution?
    var priorityNutrients: [String]
    /// Meal names from the profile's schedule, earliest first.
    var mealNames: [String]
}

struct AssistantLoggedItem: Equatable, Sendable, Codable {
    var name: String
    var grams: Double
}

/// One meal of one day: the calendar event (if any) and what it holds.
struct AssistantMealRecord: Equatable, Sendable {
    var name: String
    var start: Date
    var end: Date
    var eventID: String?
    var items: [AssistantLoggedItem]
}

struct AssistantPracticeHit: Equatable, Sendable {
    var id: UUID
    var title: String
    var kind: String
    var minutes: Int
    var goals: [String]
    var dosha: String
}

struct AssistantPoseHit: Equatable, Sendable {
    var id: UUID
    var name: String
    var sanskrit: String?
    var level: Int?
    var contraindications: [String]
}

/// Everything the tools read or write, behind one seam so the tools can be
/// tested without the calendar, the catalogue or Foundation Models.
@MainActor
protocol AssistantDataSource: AnyObject {
    var profile: AssistantProfileSnapshot { get }

    func searchFoods(_ query: String, limit: Int) async -> [CompactFoodItem]
    func food(id: UUID) async -> CompactFoodItem?
    func food(named name: String) async -> CompactFoodItem?

    /// The day's meals: every meal of the profile's schedule, with what was
    /// logged, plus any other meal events of that day.
    func meals(on day: Date) async -> [AssistantMealRecord]
    /// Writes the meal's items; an empty list removes the event. Returns the
    /// record as saved (with its event id), or nil when the write failed.
    func save(_ meal: AssistantMealRecord, on day: Date) async -> AssistantMealRecord?

    func constraints() -> [DietaryConstraint]
    func mergeConstraints(_ constraints: [DietaryConstraint])
    func saveConstitution(answers: [AyurvedaDosha])

    /// Whether the app's own generators can run here (Apple Intelligence).
    var canGeneratePlans: Bool { get }

    /// Starts the app's own generators; output appears in the Generate tab.
    func startRecipe(named name: String) -> Bool
    func startFood(named name: String) -> Bool
    func startMealPlan(days: Int, notes: [String]) -> Bool

    func findPractices(_ query: String, limit: Int) -> [AssistantPracticeHit]
    func findPoses(_ query: String, limit: Int) -> [AssistantPoseHit]
}

extension CompactFoodItem {
    /// Nutrients per 100 g in the catalogue's canonical units.
    var per100g: [NutrientType: Double] {
        let ref = referenceWeightG > 0 ? referenceWeightG : 100
        return nutrientValues.mapValues { $0 / ref * 100 }
    }

    func checked(grams: Double, meal: String) -> CheckedFood {
        CheckedFood(name: name, grams: grams, meal: meal, per100g: per100g, allergens: allergens)
    }
}
