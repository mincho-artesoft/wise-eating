// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/AI/DietGeneration/AIDietModels.swift ====
import Foundation
import SwiftData
import FoundationModels

struct DietGenerationProgress: Codable, Sendable {
    /// Резултатът от стъпката за генериране на име. nil, ако все още не е изпълнена.
    var suggestedName: String?
    
    /// Резултатът от стъпката за извличане на ключови думи за изключване. nil, ако все още не е изпълнена.
    var exclusionKeywords: [String]?

    /// Набор от `FoodItem.id`-та на **всички** храни, които са били обработени от AI, независимо от резултата.
    var processedFoodItemIDs: Set<Int>

    /// Речник, който съхранява само резултатите на храните, които са получили оценка над прага. [FoodItem.ID: Score]
    var scoredResults: [Int: Double]
}


// MARK: - Compact payload & responses
@available(iOS 26.0, *)
@Generable
struct FoodFacts: Codable {
    @Guide(description: "Protein per 100 g in grams.")
    var p: Double?

    @Guide(description: "Carbs per 100 g in grams.")
    var c: Double?

    @Guide(description: "Fat per 100 g in grams.")
    var f: Double?

    @Guide(description: "1 if recipe/menu, 0 if not.")
    var r: Int?
}

@available(iOS 26.0, *)
@Generable
struct FoodForBatchEvaluation: Codable {
    @Guide(description: "Opaque short ID to echo back verbatim.")
    var sid: String

    @Guide(description: "Canonical display name (for awareness only).")
    var name: String

    @Guide(description: "Minimal numeric facts; omit fields if unavailable.")
    var facts: FoodFacts?
}

@available(iOS 26.0, *)
@Generable
struct AIFoodSuitabilityScoreResponse: Codable {
    @Guide(description: "Echo the input 'sid' here.")
    var sid: String?

    @Guide(description: "Suitability 0.0–1.0")
    var suitabilityScore: Double

    @Guide(description: "≤10 words justification.")
    var reason: String
}

@available(iOS 26.0, *)
@Generable
struct AIBatchEvaluationResponse: Codable {
    var evaluations: [AIFoodSuitabilityScoreResponse]
}

// MARK: - Name response (kept for parity when decoding JSON if needed)
@available(iOS 26.0, *)
@Generable
struct AIDietNameResponse: Codable {
    @Guide(description: "A concise and fitting name for the diet based on the user's prompts (e.g., 'Low-Carb High-Protein').")
    var name: String
}

// MARK: - DTOs
struct AIDietResponseDTO {
    var suggestedName: String
    var foodItemIDs: [FoodItem]
}

public struct AIDietResponseWireDTO: Codable, Sendable {
    public var suggestedName: String
    public var foodItemIDs: [Int]
}

extension AIDietResponseDTO {
    func toWireDTO() -> AIDietResponseWireDTO {
        .init(suggestedName: suggestedName, foodItemIDs: foodItemIDs.map { $0.id })
    }
}

@available(iOS 26.0, *)
@Generable
struct ExclusionKeywordsResponse: Codable {
    @Guide(description: "Short exclusion keywords (1–3 words), ASCII only.")
    var keywords: [String]
}
