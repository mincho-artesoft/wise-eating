import Foundation
import SwiftData

@MainActor
public enum AyurvedaRecommendationGate {
  private struct Cache {
    let foodIds: Set<Int>
    let excludedNameTerms: Set<String>
  }

  private static var cache: Cache?

  /// All foodIds that must never be recommended: direct profiles with
  /// engineExcluded == true, plus any fdcIds whose AyurvedaLink resolves to
  /// an excluded dravya profile.
  public static func excludedFoodIds(context: ModelContext) -> Set<Int> {
    load(context: context).foodIds
  }

  public static func isExcluded(foodId: Int, context: ModelContext) -> Bool {
    excludedFoodIds(context: context).contains(foodId)
  }

  public static func invalidate() {
    cache = nil
  }

  /// Case-insensitive screen for AI-generated free-text food names. Terms are
  /// derived exclusively from excluded profile names and aliases.
  public static func nameIsExcluded(
    _ name: String,
    context: ModelContext
  ) -> Bool {
    let candidate = normalize(name)
    guard !candidate.isEmpty else { return false }
    return load(context: context).excludedNameTerms.contains { term in
      candidate == term || candidate.contains(" \(term) ")
        || candidate.hasPrefix("\(term) ") || candidate.hasSuffix(" \(term)")
    }
  }

  private static func load(context: ModelContext) -> Cache {
    if let cache { return cache }

    do {
      let profiles = try context.fetch(FetchDescriptor<AyurvedaProfile>())
      let excludedProfiles = profiles.filter(\.engineExcluded)
      let excludedProfileIds = Set(excludedProfiles.map(\.id))
      let links = try context.fetch(FetchDescriptor<AyurvedaLink>())

      var foodIds = Set(excludedProfiles.map(\.foodId))
      foodIds.formUnion(
        links.lazy
          .filter { excludedProfileIds.contains($0.dravyaProfileId) }
          .map(\.fdcId)
      )

      var nameTerms = Set<String>()
      for profile in excludedProfiles {
        addNameTerms(profile.name, to: &nameTerms)
        for alias in profile.aliases {
          addNameTerms(alias, to: &nameTerms)
        }
      }

      let loaded = Cache(foodIds: foodIds, excludedNameTerms: nameTerms)
      cache = loaded
      return loaded
    } catch {
      print("🚫 AyurvedaGate: failed to load exclusion data: \(error)")
      return Cache(foodIds: [], excludedNameTerms: [])
    }
  }

  private static func addNameTerms(_ value: String, to terms: inout Set<String>) {
    let full = normalize(value)
    if !full.isEmpty { terms.insert(full) }

    if let parenthesis = value.firstIndex(of: "(") {
      let base = normalize(String(value[..<parenthesis]))
      if !base.isEmpty { terms.insert(base) }
    }
  }

  private static func normalize(_ value: String) -> String {
    let folded = value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
      .joined()
    return folded
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
      .joined(separator: " ")
  }
}
