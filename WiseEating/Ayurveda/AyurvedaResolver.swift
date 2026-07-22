import Foundation
import SwiftData

public enum AyurvedaResolution {
  case classical(AyurvedaProfile)
  case recipe(AyurvedaProfile)
  case user(AyurvedaProfile)
  case derived(
    AyurvedaProfile,
    via: AyurvedaLink,
    modifiers: [AppliedModifier],
    vpk: DoshaVPK
  )
  case estimated(EstimatedAyurveda)
  case none

  public var confidence: Double? {
    switch self {
    case .classical(let profile), .recipe(let profile), .user(let profile):
      return profile.confidenceAyur
    case .derived(let profile, let link, _, _):
      if link.tier == "derived" {
        return max(profile.confidenceAyur - 0.15, 0.1)
      }
      return profile.confidenceAyur
    case .estimated(let estimate):
      return estimate.confidence
    case .none:
      return nil
    }
  }
}

@MainActor
public enum AyurvedaResolver {
  public static func resolve(
    for foodItem: FoodItem,
    context: ModelContext
  ) throws -> AyurvedaResolution {
    if let direct = try profile(foodId: foodItem.id, context: context) {
      switch direct.kind {
      case "dravya":
        return .classical(direct)
      case "recipe":
        return .recipe(direct)
      case "user":
        return .user(direct)
      default:
        return .none
      }
    }

    if let link = try link(fdcId: foodItem.id, context: context),
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

    return estimated(for: foodItem)
  }

  private static func profile(
    foodId: Int,
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
    fdcId: Int,
    context: ModelContext
  ) throws -> AyurvedaLink? {
    var descriptor = FetchDescriptor<AyurvedaLink>(
      predicate: #Predicate<AyurvedaLink> { link in
        link.fdcId == fdcId
      }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private static func profile(
    id: String,
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
    guard let category = foodItem.category?.first?.rawValue else {
      return .none
    }
    return .estimated(
      AyurvedaRules.shared.estimated(category: category, name: foodItem.name)
    )
  }
}
