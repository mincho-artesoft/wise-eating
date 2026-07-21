import SwiftData

public enum AyurvedaResolution {
  case classical(AyurvedaProfile)
  case recipe(AyurvedaProfile)
  case derived(AyurvedaProfile, via: AyurvedaLink)
  case none
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
      default:
        return .none
      }
    }

    if let link = try link(fdcId: foodItem.id, context: context),
      let profile = try profile(id: link.dravyaProfileId, context: context)
    {
      return .derived(profile, via: link)
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

  /// D4 will add category-based estimation. Until then, unlinked foods resolve to `.none`.
  private static func estimated(for foodItem: FoodItem) -> AyurvedaResolution {
    _ = foodItem
    return .none
  }
}
