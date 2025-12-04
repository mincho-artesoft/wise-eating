import SwiftData
import Foundation
import FoundationModels

// --- START OF CHANGE ---
/// Stochează starea intermediară a unui job de generare a planului alimentar.
@available(iOS 26.0, *)
struct MealPlanGenerationProgress: Codable, Sendable {
    // Etapa de interpretare
    var atomicPrompts: [String]?
    var includedFoods: [String]?
    var excludedFoods: [String]?
    var interpretedPrompts: InterpretedPrompts?
    
    // Etapa de context și palete
    var contextTags: [(kind: String, tag: String)]?
    var foodPalettesByContext: [(kind: String, tag: String, foods: [String], associatedCuisine: String?)]?
    
    // Etapa de generare principală
    var conceptualPlan: AIConceptualPlanResponse?
    
    // Etapa de rezolvare (cea mai lungă)
    // [DayIndex: [MealName: [ResolvedFoodInfo]]]
    var resolvedItems: [Int: [String: [ResolvedFoodInfo]]]?
    
    // Adăugăm conformitate Codable manual pentru tupluri
    enum CodingKeys: String, CodingKey {
        case atomicPrompts, includedFoods, excludedFoods, interpretedPrompts, contextTags, foodPalettesByContext, conceptualPlan, resolvedItems
    }
    
    // Structuri helper pentru a face tuplurile Codable
    struct ContextTag: Codable, Sendable { let kind: String; let tag: String }
    struct Palette: Codable, Sendable { let kind: String; let tag: String; let foods: [String]; let associatedCuisine: String? }
    
    init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        atomicPrompts = try container.decodeIfPresent([String].self, forKey: .atomicPrompts)
        includedFoods = try container.decodeIfPresent([String].self, forKey: .includedFoods)
        excludedFoods = try container.decodeIfPresent([String].self, forKey: .excludedFoods)
        interpretedPrompts = try container.decodeIfPresent(InterpretedPrompts.self, forKey: .interpretedPrompts)
        
        if let tags = try container.decodeIfPresent([ContextTag].self, forKey: .contextTags) {
            contextTags = tags.map { ($0.kind, $0.tag) }
        }
        if let palettes = try container.decodeIfPresent([Palette].self, forKey: .foodPalettesByContext) {
            foodPalettesByContext = palettes.map { ($0.kind, $0.tag, $0.foods, $0.associatedCuisine) }
        }
        
        conceptualPlan = try container.decodeIfPresent(AIConceptualPlanResponse.self, forKey: .conceptualPlan)
        resolvedItems = try container.decodeIfPresent([Int: [String: [ResolvedFoodInfo]]].self, forKey: .resolvedItems)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(atomicPrompts, forKey: .atomicPrompts)
        try container.encodeIfPresent(includedFoods, forKey: .includedFoods)
        try container.encodeIfPresent(excludedFoods, forKey: .excludedFoods)
        try container.encodeIfPresent(interpretedPrompts, forKey: .interpretedPrompts)
        
        if let tags = contextTags {
            try container.encode(tags.map { ContextTag(kind: $0.kind, tag: $0.tag) }, forKey: .contextTags)
        }
        if let palettes = foodPalettesByContext {
            try container.encode(palettes.map { Palette(kind: $0.kind, tag: $0.tag, foods: $0.foods, associatedCuisine: $0.associatedCuisine) }, forKey: .foodPalettesByContext)
        }
        
        try container.encodeIfPresent(conceptualPlan, forKey: .conceptualPlan)
        try container.encodeIfPresent(resolvedItems, forKey: .resolvedItems)
    }
}
