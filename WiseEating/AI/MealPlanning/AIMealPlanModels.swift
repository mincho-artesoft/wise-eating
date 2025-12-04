import SwiftData
import Foundation
import FoundationModels

struct ResolvedFoodInfo: Sendable, Codable {
    let persistentID: PersistentIdentifier
    let resolvedName: String
}

public struct MealPlanPreviewItem: Sendable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let grams: Double
    public let kcal: Double

    public init(id: UUID = UUID(), name: String, grams: Double, kcal: Double) {
        self.id = id
        self.name = name
        self.grams = grams
        self.kcal = kcal
    }
}

public struct MealPlanPreviewMeal: Sendable, Hashable, Codable, Identifiable {
    public let id = UUID()
    public let name: String
    public let descriptiveTitle: String?
    public var items: [MealPlanPreviewItem]
    public let startTime: Date?
    public var kcalTotal: Double { items.reduce(0) { $0 + $1.kcal } }
    public static func == (lhs: MealPlanPreviewMeal, rhs: MealPlanPreviewMeal) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct MealPlanPreviewDay: Sendable, Codable, Identifiable {
    public var id: Int { dayIndex }
    public let dayIndex: Int
    public var meals: [MealPlanPreviewMeal]
}
public struct MealPlanPreview: Sendable, Codable, Identifiable {
    public var id: Date { startDate }
    public let startDate: Date
    public let prompt: String
    public let days: [MealPlanPreviewDay]
    public let minAgeMonths: Int
}

// MARK: - AI Response Models

@available(iOS 26.0, *)
@Generable
struct ConceptualComponent: Codable {
    var name: String
    @Guide(description: "Realistic per-person portion in grams. STRICT RULES: Spices/herbs/powders (like turmeric, ginger, garlic powder) MUST be 1-5g. Condiments/sauces 10-30g. Mains (meat/fish/tofu) 120-200g. Carb sides (rice, potatoes) 100-180g. Vegetables/salads 80-200g. Liquids 150-300g. Adhere to these ranges.")
    var grams: Double
}

@available(iOS 26.0, *)
@Generable
struct ConceptualMeal: Codable {
    @Guide(description: "MUST be exactly one of the meal names provided in the Plan Structure (e.g., 'Breakfast', 'Lunch', 'Dinner'). Use the exact casing and spelling. Do NOT prefix or suffix anything (no cuisine tags or headwords). This is a strict structural requirement.")
    let name: String
    
    @Guide(description: "A short, user-friendly title. Do NOT include cuisine names or specific food names from these instructions or examples.")
    let descriptiveTitle: String
    
    @Guide(description: "A list of 3 to 8 food components for this meal, following all composition rules.")
    var components: [ConceptualComponent]
}

@available(iOS 26.0, *)
@Generable
struct ConceptualDay: Codable {
    @Guide(description: "Must match one of the exact day indices requested by the user (e.g., 1, 2, 3). No extras and no duplicates.")
    let day: Int
    var meals: [ConceptualMeal]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse: Codable {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "Return days ONLY for the exact day indices requested by the user (PLAN STRUCTURE). Preserve their order and include each exactly once. Do not invent, drop, or reorder days.")
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIFoodPaletteResponse: Codable {
    @Guide(description: "Based on the user's profile and requests, return 20-25 specific, USDA‑like food names that are culturally consistent. Include a balanced mix of (a) variants of requested foods only if the user asked for different types/varieties, and (b) compatible pairings that are commonly served with those foods in the cuisine (e.g., traditional drinks, dairy accompaniments, breads, salads, spreads, soups, or sweets). Do not fabricate hybrids by prefixing the requested food name to generic nouns. Names must be stand‑alone dishes/items, not condiments alone.", .count(20...25))
    let foodExamples: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIHeadwordPaletteResponse: Codable {
    @Guide(description: "The single, dominant, lowercase cuisine tag associated with the headword (e.g., for 'sushi', return 'japanese').")
    let inferredCuisine: String
    
    @Guide(description: "16–25 standalone, USDA-like items that are culturally consistent with the inferred cuisine and pair well with the headword. Do not include the headword itself.", .count(16...25))
    let foodExamples: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIHeadwordVariantsResponse: Codable {
    @Guide(description: "The single, dominant, lowercase cuisine tag associated with the headword.")
    let inferredCuisine: String
    
    @Guide(description: "4-7 standalone, USDA-like items that are popular variants or different types of the headword. This list can include the headword itself if it is a primary example of its category.", .count(4...7))
    let foodExamples: [String]
}

@available(iOS 26.0, *)
@Generable
struct AINutritionInfo: Codable {
    let name: String
    let protein_g: Double
    let fat_g: Double
    let carbohydrates_g: Double
}

@available(iOS 26.0, *)
@Generable
struct AINutritionResponse: Codable {
    let nutritionData: [AINutritionInfo]
}

@available(iOS 26.0, *)
@Generable
struct AINumericalGoal: Codable {
    let nutrient: String
    let constraint: String
    let value: Double
}

@available(iOS 26.0, *)
@Generable
struct AIFrequencyRequest: Codable {
    let topic: String
    let frequency: String // 'daily', 'per_n_days', 'once'
    let n: Int
    let meal: String?
}

@available(iOS 26.0, *)
@Generable
struct AIAtomicPromptsResponse: Codable {
    @Guide(description: "Atomic, standalone directives split from the user's raw prompts. Each item encodes exactly one requirement, preserves negation/frequency/meal context, and is understandable on its own.")
    let directives: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIVariantListResponse: Codable {
    @Guide(description: "Return exactly N distinct, realistic variants for the given base dish, formatted as full dish names. Avoid using banned/excluded ingredients. Do not include numbering, bullets, or extra text.")
    let variants: [String]
}


@available(iOS 26.0, *)
@Generable
struct AIInterpretedPrompt: Codable {
    @Guide(description: "The single, specific numerical goal extracted from the prompt, if any.")
    let numericalGoal: AINumericalGoal?
    @Guide(description: "The single, specific frequency request extracted from the prompt, if any.")
    let frequencyRequest: AIFrequencyRequest?
    @Guide(description: "A simple compositional request, if any (e.g., 'add a dessert to every lunch').")
    let structuralRequest: String?
    @Guide(description: "The cleaned-up qualitative goal if no other category fits.")
    let qualitativeGoal: String?
}

@available(iOS 26.0, *)
@Generable
struct AIBestCandidateChoice: Codable {
    let reason: String
    let bestCandidateIndex: Int
}

enum MacronutrientType: String, Codable, Sendable {
    case protein, fat, carbohydrates
    
    init?(map s: String) {
        switch s {
        case "protein": self = .protein
        case "fat", "fats": self = .fat
        case "carbohydrates", "carbs", "carb": self = .carbohydrates
        default: return nil
        }
    }
}
enum Constraint: String, Codable, Sendable {
    case exactly, lessThan, moreThan
}

struct NumericalGoal: Codable, Sendable {
    let nutrient: MacronutrientType
    let constraint: Constraint
    let value: Double
}

struct InterpretedPrompts: Codable, Sendable {
    var qualitativeGoals: [String] = []
    var structuralRequests: [String] = []
    var numericalGoals: [NumericalGoal] = []
}

@available(iOS 26.0, *)
@Generable
struct AIFoodExtractionResponse: Codable {
    @Guide(description: "List ONLY the concrete food names the user explicitly asked to INCLUDE. Keep them as simple USDA-like names without portions")
    let includedFoods: [String]
    @Guide(description: "List ONLY the concrete food names the user explicitly asked to EXCLUDE. Keep them as simple USDA-like names.")
    let excludedFoods: [String]
}

@available(iOS 26.0, *)
@Generable
struct AISearchKeywordResponse: Codable {
    @Guide(description: "2–4 short, lowercase tokens ordered by importance. First MUST be the headword (core ingredient). Prefer cut/method/dish-type terms. No filler words.")
    let priorityKeywords: [String]
    @Guide(description: "Words that should NOT appear in candidate names (e.g., powders, sauces, dressings). Keep 0–6 items, lowercase.")
    let bannedKeywords: [String]
    @Guide(description: "Up to 3 synonyms for the headword that often appear in USDA-like names. Lowercase, no duplicates.")
    let headwordSynonyms: [String]
}

@available(iOS 26.0, *)
@Generable
struct CuisineGuess: Codable, Sendable {
    let cuisine: String
}

@available(iOS 26.0, *)
@Generable
struct CuisineTagsGuess: Codable, Sendable {
    @Guide(description: "Up to 3 short, lowercase cuisine tags. Order by dominance; no duplicates.")
    let cuisines: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIContextTag: Codable, Sendable {
    @Guide(description: "Either 'cuisine' for a culinary tradition/dietary system, or 'headword' for a specific dish/ingredient.")
    let kind: String
    @Guide(description: "A concise, lowercase tag. If a tradition has a modality/qualifier, return a single composite tag.")
    let tag: String
}

@available(iOS 26.0, *)
@Generable
struct AIContextTagsResponse: Codable, Sendable {
    @Guide(description: "1–4 context tags ordered by relevance; no duplicates.")
    let tags: [AIContextTag]
}

@available(iOS 26.0, *)
@Generable
struct MealCuisineFocus: Codable {
    @Guide(description: "Exact meal name from the plan structure (e.g., 'Breakfast', 'Lunch', 'Dinner'). Use original casing.")
    let meal: String
    @Guide(description: "A single, lowercase cuisine tag for that meal. No mixing within a meal.")
    let cuisine: String
}

@available(iOS 26.0, *)
@Generable
struct AIPerMealCuisineFocusResponse: Codable {
    @Guide(description: "Return each requested meal exactly once with an assigned cuisine tag. Do not invent meals; do not duplicate meals. If the global tag should apply, use 'any'.")
    let focus: [MealCuisineFocus]
}

@available(iOS 26.0, *)
protocol _AIPlanConvertible: Codable {
    var planName: String { get }
    var minAgeMonths: Int { get }
    var days: [ConceptualDay] { get }
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse1D: _AIPlanConvertible {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "EXACTLY 1 day. Use only the provided day index and exact meal names in their original order.", .count(1))
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse2D: _AIPlanConvertible {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "EXACTLY 2 days. Use only the provided day indices and the exact meal names in their original order.", .count(2))
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse3D: _AIPlanConvertible {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "EXACTLY 3 days. Use only the provided day indices and meal names; keep meal order per day unchanged.", .count(3))
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse4D: _AIPlanConvertible {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "EXACTLY 4 days. Only use the user's day indices and exact meal names in their original order. No extra days.", .count(4))
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse5D: _AIPlanConvertible {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "EXACTLY 5 days. Use only the provided days and exact meal names; keep ordering intact.", .count(5))
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse6D: _AIPlanConvertible {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "EXACTLY 6 days. Use only the provided day indices and exact meal names; preserve meal order per day.", .count(6))
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIConceptualPlanResponse7D: _AIPlanConvertible {
    let planName: String
    let minAgeMonths: Int
    @Guide(description: "EXACTLY 7 days. Use only the provided day indices and exact meal names; do not add, drop, or reorder days or meals.", .count(7))
    var days: [ConceptualDay]
}

@available(iOS 26.0, *)
@Generable
struct AIAtomsAndFoodsFixResponse: Codable {
    @Guide(description: "The corrected list of atomic directives (≤16), consistent with the raw prompts and food lists. Keep each directive concise and self-contained.")
    let fixedDirectives: [String]
    @Guide(description: "Concrete foods explicitly requested to be INCLUDED after reconciliation. Simple USDA-like names, de-duplicated.")
    let includedFoods: [String]
    @Guide(description: "Concrete foods explicitly requested to be EXCLUDED after reconciliation. Simple USDA-like names, de-duplicated and not overlapping with includedFoods.")
    let excludedFoods: [String]
}

