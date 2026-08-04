import Foundation
import SwiftData

/// Read-only display projection for recipe nutrition that is canonically stored
/// on `AyurvedaProfile`. Food list rows receive only a `FoodItem`, so they cannot
/// otherwise see the already-computed per-100 g payload without duplicating it
/// into the food database.
struct RecipeNutritionSnapshot: Sendable {
  let values: [String: Double]
  let units: [String: String]

  func nutrient(_ key: String, multiplier: Double = 1) -> Nutrient? {
    guard let value = values[key], let unit = units[key] else { return nil }
    return Nutrient(value: value * multiplier, unit: unit)
  }
}

final class RecipeNutritionProjection: @unchecked Sendable {
  static let shared = RecipeNutritionProjection()

  private let lock = NSLock()
  private var snapshots: [Int: RecipeNutritionSnapshot] = [:]

  private init() {}

  /// Loads all recipe payloads in one fetch after seeding. Keeping only decoded
  /// value types makes subsequent row rendering independent of ModelContext
  /// lifetime and avoids one SwiftData query per visible row.
  @discardableResult
  func load(context: ModelContext) throws -> Int {
    let profiles = try context.fetch(
      FetchDescriptor<AyurvedaProfile>(
        predicate: #Predicate<AyurvedaProfile> { profile in
          profile.kind == "recipe"
        }
      )
    )
    var loaded: [Int: RecipeNutritionSnapshot] = [:]
    loaded.reserveCapacity(profiles.count)
    let decoder = JSONDecoder()

    for profile in profiles {
      guard let valuesJSON = profile.nutritionPer100gJSON,
            let unitsJSON = profile.nutritionUnitsJSON,
            let valuesData = valuesJSON.data(using: .utf8),
            let unitsData = unitsJSON.data(using: .utf8) else {
        throw RecipeNutritionProjectionError.missingPayload(profile.id)
      }
      guard loaded[profile.foodId] == nil else {
        throw RecipeNutritionProjectionError.duplicateFoodID(profile.foodId)
      }
      loaded[profile.foodId] = RecipeNutritionSnapshot(
        values: try decoder.decode([String: Double].self, from: valuesData),
        units: try decoder.decode([String: String].self, from: unitsData)
      )
    }

    lock.lock()
    snapshots = loaded
    lock.unlock()
    return loaded.count
  }

  func snapshot(foodID: Int) -> RecipeNutritionSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return snapshots[foodID]
  }
}

private enum RecipeNutritionProjectionError: LocalizedError {
  case missingPayload(String)
  case duplicateFoodID(Int)

  var errorDescription: String? {
    switch self {
    case .missingPayload(let profileID):
      return "Recipe nutrition payload is missing for \(profileID)"
    case .duplicateFoodID(let foodID):
      return "More than one recipe nutrition profile uses food id \(foodID)"
    }
  }
}
