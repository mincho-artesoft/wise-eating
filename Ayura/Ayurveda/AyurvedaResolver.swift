import Foundation
import SwiftData

public enum AyurvedaResolution {
  case classical(AyurvedaProfile)
  case catalog(AyurvedaProfile)
  case recipe(AyurvedaProfile)
  case user(AyurvedaProfile)
  case derived(
    AyurvedaProfile,
    via: AyurvedaLink,
    modifiers: [AppliedModifier],
    vpk: DoshaVPK
  )
  case computed(AyurvedaDisplayMath.Computed)
  case estimated(EstimatedAyurveda)
  case none

  public var confidence: Double? {
    switch self {
    case .classical(let profile), .catalog(let profile),
      .recipe(let profile), .user(let profile):
      return profile.confidenceAyur
    case .derived(let profile, let link, _, _):
      if link.tier == "derived" {
        return max(profile.confidenceAyur - 0.15, 0.1)
      }
      return profile.confidenceAyur
    case .computed(let computed):
      return computed.confidence
    case .estimated(let estimate):
      return estimate.confidence
    case .none:
      return nil
    }
  }
}

public struct AyurvedaIngredientAmount: Sendable {
  public let foodId: UUID
  public let grams: Double

  public init(foodId: UUID, grams: Double) {
    self.foodId = foodId
    self.grams = grams
  }
}

public struct AyurvedaIngredientComputation: Sendable {
  public let computed: AyurvedaDisplayMath.Computed?
  public let coverage: Double
  public let hasIngredients: Bool

  public static let empty = AyurvedaIngredientComputation(
    computed: nil,
    coverage: 0,
    hasIngredients: false
  )

  public init(
    computed: AyurvedaDisplayMath.Computed?,
    coverage: Double,
    hasIngredients: Bool
  ) {
    self.computed = computed
    self.coverage = coverage
    self.hasIngredients = hasIngredients
  }
}

@MainActor
public enum AyurvedaResolver {
  private static let maximumIngredientDepth = 3

  private struct IngredientCandidate {
    let food: FoodItem?
    let grams: Double
  }

  public static func resolve(
    for foodItem: FoodItem,
    context: ModelContext
  ) throws -> AyurvedaResolution {
    try resolve(
      for: foodItem,
      context: context,
      depth: 0,
      visited: []
    )
  }

  public static func computeIngredients(
    _ ingredients: [AyurvedaIngredientAmount],
    context: ModelContext
  ) throws -> AyurvedaIngredientComputation {
    let candidates = try ingredients.map { ingredient in
      IngredientCandidate(
        food: try food(id: ingredient.foodId, context: context),
        grams: ingredient.grams
      )
    }
    return try computeIngredients(
      candidates,
      context: context,
      depth: 0,
      visited: []
    )
  }

  private static func resolve(
    for foodItem: FoodItem,
    context: ModelContext,
    depth: Int,
    visited: Set<UUID>
  ) throws -> AyurvedaResolution {
    if let direct = try profile(foodId: foodItem.id, context: context) {
      switch direct.kind {
      case "dravya":
        return .classical(direct)
      case "recipe":
        return .recipe(direct)
      case "catalog":
        return .catalog(direct)
      case "user":
        return .user(direct)
      default:
        break
      }
    }

    if let link = try link(foodId: foodItem.id, context: context),
      let profile = try profile(id: link.dravyaProfileId, context: context)
    {
      let baseVPK: DoshaVPK = (
        profile.doshaVata,
        profile.doshaPitta,
        profile.doshaKapha
      )
      guard link.tier == "derived" else {
        return .derived(profile, via: link, modifiers: [], vpk: baseVPK)
      }
      let modifiers = AyurvedaRules.shared.modifiers(forName: foodItem.name)
      return .derived(
        profile,
        via: link,
        modifiers: modifiers,
        vpk: AyurvedaRules.adjustedVPK(base: baseVPK, modifiers: modifiers)
      )
    }

    guard !visited.contains(foodItem.id) else {
      return estimated(for: foodItem)
    }
    var nextVisited = visited
    nextVisited.insert(foodItem.id)

    if depth < maximumIngredientDepth,
      let computed = try ingredientComputation(
        for: foodItem,
        context: context,
        depth: depth,
        visited: nextVisited
      ).computed
    {
      return .computed(computed)
    }

    return estimated(for: foodItem)
  }

  private static func ingredientComputation(
    for foodItem: FoodItem,
    context: ModelContext,
    depth: Int,
    visited: Set<UUID>
  ) throws -> AyurvedaIngredientComputation {
    let ingredientLinks = foodItem.ingredients ?? []
    let hasIngredients = foodItem.isRecipe
      || foodItem.isMenu
      || !ingredientLinks.isEmpty
    guard hasIngredients, !ingredientLinks.isEmpty else {
      return .empty
    }

    let candidates = ingredientLinks.map { ingredientLink in
      IngredientCandidate(
        food: ingredientLink.food,
        grams: ingredientLink.grams
      )
    }
    return try computeIngredients(
      candidates,
      context: context,
      depth: depth,
      visited: visited
    )
  }

  private static func computeIngredients(
    _ ingredients: [IngredientCandidate],
    context: ModelContext,
    depth: Int,
    visited: Set<UUID>
  ) throws -> AyurvedaIngredientComputation {
    var totalGrams = 0.0
    var resolvedIngredients: [AyurvedaDisplayMath.WeightedIngredient] = []
    for ingredient in ingredients {
      let grams = ingredient.grams
      guard grams.isFinite, grams > 0 else {
        continue
      }
      totalGrams += grams
      guard let ingredientFood = ingredient.food else {
        continue
      }
      let ingredientResolution = try resolve(
        for: ingredientFood,
        context: context,
        depth: depth + 1,
        visited: visited
      )
      guard let components = components(from: ingredientResolution) else {
        continue
      }
      resolvedIngredients.append(
        AyurvedaDisplayMath.WeightedIngredient(
          vata: components.vpk.vata,
          pitta: components.vpk.pitta,
          kapha: components.vpk.kapha,
          grams: grams,
          virya: components.virya
        )
      )
    }

    let resolvedGrams = resolvedIngredients.reduce(0.0) { $0 + $1.grams }
    let coverage = totalGrams > 0 ? resolvedGrams / totalGrams : 0
    return AyurvedaIngredientComputation(
      computed: AyurvedaDisplayMath.computed(
        totalGrams: totalGrams,
        resolved: resolvedIngredients
      ),
      coverage: coverage,
      hasIngredients: totalGrams > 0
    )
  }

  private static func food(
    id: UUID,
    context: ModelContext
  ) throws -> FoodItem? {
    let foodId = id
    var descriptor = FetchDescriptor<FoodItem>(
      predicate: #Predicate<FoodItem> { food in
        food.id == foodId
      }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private static func components(
    from resolution: AyurvedaResolution
  ) -> (vpk: DoshaVPK, virya: String?)? {
    switch resolution {
    case .classical(let profile), .catalog(let profile),
      .recipe(let profile), .user(let profile):
      return (
        (profile.doshaVata, profile.doshaPitta, profile.doshaKapha),
        profile.virya
      )
    case .derived(let profile, _, _, let vpk):
      return (vpk, profile.virya)
    case .computed(let computed):
      return (
        (computed.vata, computed.pitta, computed.kapha),
        computed.virya
      )
    case .estimated(let estimate):
      return (estimate.vpk, estimate.virya)
    case .none:
      return nil
    }
  }

  private static func profile(
    foodId: UUID,
    context: ModelContext
  ) throws -> AyurvedaProfile? {
    var descriptor = FetchDescriptor<AyurvedaProfile>(
      predicate: #Predicate<AyurvedaProfile> { profile in
        profile.foodId == foodId
      }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private static func link(
    foodId: UUID,
    context: ModelContext
  ) throws -> AyurvedaLink? {
    var descriptor = FetchDescriptor<AyurvedaLink>(
      predicate: #Predicate<AyurvedaLink> { link in
        link.foodId == foodId
      }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private static func profile(
    id: UUID,
    context: ModelContext
  ) throws -> AyurvedaProfile? {
    var descriptor = FetchDescriptor<AyurvedaProfile>(
      predicate: #Predicate<AyurvedaProfile> { profile in
        profile.id == id
      }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private static func estimated(for foodItem: FoodItem) -> AyurvedaResolution {
    return .estimated(
      AyurvedaRules.shared.estimated(
        name: foodItem.name
      )
    )
  }
}
