import Foundation

public enum AyurvedaDisplayMath {
  public enum TierInput {
    case classical
    case recipe
    case derived(linkTier: String)
    case computed
    case estimated
    case user
  }

  public struct WeightedIngredient: Sendable {
    public let vata: Int
    public let pitta: Int
    public let kapha: Int
    public let grams: Double
    public let virya: String?

    public init(
      vata: Int,
      pitta: Int,
      kapha: Int,
      grams: Double,
      virya: String? = nil
    ) {
      self.vata = vata
      self.pitta = pitta
      self.kapha = kapha
      self.grams = grams
      self.virya = virya
    }
  }

  public struct Computed: Sendable {
    public let vata: Int
    public let pitta: Int
    public let kapha: Int
    public let virya: String
    public let coverage: Double
    public let confidence: Double
  }

  public static func tierLabel(_ tier: TierInput) -> String {
    switch tier {
    case .classical:
      return "Classical"
    case .recipe:
      return "Recipe"
    case .derived(let linkTier):
      return linkTier == "exact" || linkTier == "near" ? "Classical" : "Derived"
    case .computed:
      return "Computed"
    case .estimated:
      return "Estimated"
    case .user:
      return "User"
    }
  }

  public static func effectLabel(_ value: Int) -> String {
    switch value {
    case ...(-2):
      return "strongly pacifies"
    case -1:
      return "pacifies"
    case 0:
      return "neutral"
    case 1:
      return "aggravates"
    default:
      return "strongly aggravates"
    }
  }

  public static func valueString(_ value: Int) -> String {
    value > 0 ? "+\(value)" : "\(value)"
  }

  public static func barFraction(_ value: Int) -> Double {
    Double(min(abs(value), 2)) / 2.0
  }

  public static func percentages(
    vata: Int,
    pitta: Int,
    kapha: Int
  ) -> (v: Int, p: Int, k: Int) {
    let weights = [vata + 2, pitta + 2, kapha + 2]
    let total = weights.reduce(0, +)
    guard total > 0 else {
      return (33, 33, 34)
    }

    let exact = weights.map { Double($0) * 100.0 / Double(total) }
    var result = exact.map { Int(floor($0)) }
    var remainder = 100 - result.reduce(0, +)
    let order = exact.indices.sorted { left, right in
      let leftFraction = exact[left] - floor(exact[left])
      let rightFraction = exact[right] - floor(exact[right])
      if leftFraction == rightFraction {
        return left < right
      }
      return leftFraction > rightFraction
    }

    var orderIndex = 0
    while remainder > 0 {
      result[order[orderIndex]] += 1
      remainder -= 1
      orderIndex = (orderIndex + 1) % order.count
    }
    return (result[0], result[1], result[2])
  }

  public static func computed(
    totalGrams: Double,
    resolved ingredients: [WeightedIngredient]
  ) -> Computed? {
    guard totalGrams.isFinite, totalGrams > 0 else {
      return nil
    }

    let ingredients = ingredients.filter { ingredient in
      ingredient.grams.isFinite && ingredient.grams > 0
    }
    let resolvedGrams = ingredients.reduce(0.0) { $0 + $1.grams }
    guard resolvedGrams > 0 else {
      return nil
    }

    let coverage = resolvedGrams / totalGrams
    guard coverage >= 0.5 else {
      return nil
    }

    let vataTotal = ingredients.reduce(0.0) { $0 + Double($1.vata) * $1.grams }
    let pittaTotal = ingredients.reduce(0.0) { $0 + Double($1.pitta) * $1.grams }
    let kaphaTotal = ingredients.reduce(0.0) { $0 + Double($1.kapha) * $1.grams }
    let heatingGrams = ingredients
      .filter { $0.virya == "heating" }
      .reduce(0.0) { $0 + $1.grams }
    let coolingGrams = ingredients
      .filter { $0.virya == "cooling" }
      .reduce(0.0) { $0 + $1.grams }
    let viryaMargin = abs(heatingGrams - coolingGrams)
    let virya: String
    if viryaMargin < resolvedGrams * 0.15 {
      virya = "neutral"
    } else {
      virya = heatingGrams > coolingGrams ? "heating" : "cooling"
    }

    return Computed(
      vata: roundedDosha(vataTotal / resolvedGrams),
      pitta: roundedDosha(pittaTotal / resolvedGrams),
      kapha: roundedDosha(kaphaTotal / resolvedGrams),
      virya: virya,
      coverage: coverage,
      confidence: min(0.5 * coverage, 0.6)
    )
  }

  private static func roundedDosha(_ value: Double) -> Int {
    let rounded = Int(value.rounded(.toNearestOrAwayFromZero))
    return min(2, max(-2, rounded))
  }
}
