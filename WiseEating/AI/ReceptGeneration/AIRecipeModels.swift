// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/AI/ReceptGeneration/AIRecipeModels.swift ====
import Foundation
import SwiftData
import FoundationModels

// --- START OF CHANGE ---
/// Междинен резултат от стъпката за интелигентно резолвиране на съставки. Codable версия на tuple-а.
@available(iOS 26.0, *)
struct SmartResolutionResult: Codable, Sendable {
    let resolved: [ResolvedIngredient]
    let replacements: [Replacement]
    let generatedNames: [String]
    let nameByID: [Int: String]
    let unresolved: [String]

    struct Replacement: Codable, Sendable {
        let from: String
        let to: String
    }
}

/// Съхранява междинния прогрес на задача за генериране на рецепта.
@available(iOS 26.0, *)
struct RecipeGenerationProgress: Codable, Sendable {
    /// Резултатът от стъпка 1: концептуална рецепта.
    var conceptualRecipe: AIRecipeResponse?
    
    /// Резултатът от стъпка 2: резолвнати съставки.
    var smartResolutionResult: SmartResolutionResult?
}
// --- END OF CHANGE ---


// MARK: - AI Response Models for Recipe Generation
struct FoodItemCandidate: Sendable {
    let id: Int
    let name: String
}

@available(iOS 26.0, *)
@Generable
struct AIShortKeywords: Codable {
    @Guide(description: "2–4 lowercase tokens, headword first (e.g., 'chicken', then 'breast'/'grilled').")
    var priorityKeywords: [String]
    @Guide(description: "0–6 lowercase tokens to avoid, e.g., 'powder','sauce','dressing'.")
    var bannedKeywords: [String]
    @Guide(description: "Up to 3 lowercase synonyms for the headword seen in USDA-like names.")
    var headwordSynonyms: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIIngredientCandidatePick: Codable, Sendable {
    /// Index in the provided candidate array (0-based). Use -1 if none are suitable.
    var bestIndex: Int
    /// Brief explanation.
    var reason: String
}

@available(iOS 26.0, *)
@Generable
struct AIIngredientFilterResponse: Codable, Sendable {
    @Guide(description: "A list of candidate names that are poor or nonsensical fits for the recipe context.")
    var incompatibleCandidates: [String]
}

@available(iOS 26.0, *)
@Generable(description: "Return ONE ingredient entry with USDA-style canonical naming that is easy for Apple Intelligence to parse.")
struct AIRecipeIngredient: Codable, Sendable {
    @Guide(description: "A simple, generic name for the ingredient.")
    var name: String

    @Guide(description: "A realistic quantity for this ingredient in grams for a typical recipe serving 2-4 people.")
    var grams: Double

    // --- START OF CHANGE ---
    @Guide(description: "A short, lowercase food category to help disambiguate (e.g., 'vegetable', 'fruit', 'meat', 'dairy', 'spice').")
    var category: String
    // --- END OF CHANGE ---
}

@available(iOS 26.0, *)
@Generable
struct AIRecipeResponse: Codable, Sendable {
    @Guide(
      description:
      """
      A single plain-text string that starts with:
      "Summary: <1–2 short sentences>"
      
      Then a blank line, followed by numbered steps:
      "1) ...\n2) ...\n3) ..."
      with 5–12 steps total. No Markdown or extra commentary.
      """
    )
    var description: String

    @Guide(description: "A list of common ingredients for this recipe.")
    var ingredients: [AIRecipeIngredient]

    @Guide(description: "Estimated preparation time in minutes as an integer (between 5 and 240). Do not include long inactive marinating/resting times.")
    var prepTimeMinutes: Int
}


// MARK: - Resolution payloads

/// Represents a single ingredient already “resolved” to a concrete FoodItem in the database.
struct ResolvedIngredient: Codable, Sendable {
    let foodItemID: Int
    let grams: Double
}

/// JSON-safe payload we store/transport (Codable).
struct ResolvedRecipeResponseDTO: Codable, Sendable {
    /// Optional title/name for a recipe/menu. Safe to omit.
    var name: String? = nil

    let description: String
    let prepTimeMinutes: Int
    let ingredients: [ResolvedIngredient]

    init(
        name: String? = nil,
        description: String,
        prepTimeMinutes: Int,
        ingredients: [ResolvedIngredient]
    ) {
        self.name = name
        self.description = description
        self.prepTimeMinutes = prepTimeMinutes
        self.ingredients = ingredients
    }
}
/// In-memory result the app prefers to work with.
@MainActor
struct ResolvedRecipeResponse {
    let description: String
    let prepTimeMinutes: Int
    let ingredients: [FoodItem]
    let gramsByItem: [FoodItem: Double]
}

// MARK: - Generable Schema for USDA Naming Variants

@available(iOS 26.0, *)
@Generable
struct AINamingVariants: Codable, Sendable {
    @Guide(description: "USDA-style canonical base name for the ingredient (e.g., 'Cucumber, raw', 'Table salt').")
    var canonicalName: String

    @Guide(description: "Up to 6 preferred name variants likely to appear in the USDA database. Short, generic, no brands.")
    var preferForms: [String]

    @Guide(description: "Up to 8 forms/keywords to AVOID when searching (ambiguous, composite foods, flavored items, brand-like, or different foods). Examples: 'butter', 'with salt', 'salted butter'.")
    var avoidForms: [String]

    @Guide(description: "Up to 8 keywords indicating cooked/heat-processed states (e.g., 'cooked','boiled','grilled','roasted','fried','baked','steamed').")
    var cookedKeywords: [String]

    @Guide(description: "Up to 8 keywords indicating raw/fresh forms (e.g., 'raw','fresh','unpeeled','peeled').")
    var rawKeywords: [String]

    @Guide(description: "Lowercase category guess such as 'vegetable','fruit','meat','dairy','spice','herb','grain','legume','oil','condiment'.")
    var categoryGuess: String
}
