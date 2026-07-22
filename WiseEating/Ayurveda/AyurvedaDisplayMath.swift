import Foundation

public enum AyurvedaDisplayMath {
  public enum TierInput {
    case classical
    case recipe
    case derived(linkTier: String)
    case estimated
    case user
  }

  public static func tierLabel(_ tier: TierInput) -> String {
    switch tier {
    case .classical:
      return "Classical"
    case .recipe:
      return "Recipe"
    case .derived(let linkTier):
      return linkTier == "exact" || linkTier == "near" ? "Classical" : "Derived"
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
}
