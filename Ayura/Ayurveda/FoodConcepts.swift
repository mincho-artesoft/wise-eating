import Foundation

public struct FoodConcepts: Sendable {
  public static let shared: FoodConcepts = {
    do {
      return try FoodConcepts()
    } catch {
      fatalError("Malformed food_concepts.json.gz: \(error)")
    }
  }()

  private let membership: [String: Set<Int32>]
  private let reverseMembership: [Int32: Set<String>]
  private let aliases: [String: String]

  private init(bundle: Bundle = .main) throws {
    guard
      let url = bundle.url(
        forResource: "food_concepts",
        withExtension: "json.gz"
      )
    else {
      throw FoodConceptError.missingBundle
    }
    let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
    let plain = try ZlibGzip.decompress(data: compressed)
    let document = try JSONDecoder().decode(
      FoodConceptDocument.self,
      from: plain
    )
    guard
      document.catalogCount == 14_488,
      document.conceptCount == 25,
      document.aliasCount == 75,
      document.membership.count == document.conceptCount,
      document.aliases.count == document.aliasCount
    else {
      throw FoodConceptError.invalidCounts
    }

    membership = document.membership.mapValues(Set.init)
    aliases = document.aliases
    reverseMembership = membership.reduce(into: [:]) { result, entry in
      for foodID in entry.value {
        result[foodID, default: []].insert(entry.key)
      }
    }
  }

  public func members(of concept: String) -> Set<Int32> {
    membership[concept] ?? []
  }

  public func concepts(for foodID: Int32) -> Set<String> {
    reverseMembership[foodID] ?? []
  }

  public func canonical(alias: String) -> String? {
    let key = AyurvedaRules.modifierTokens(alias).joined(separator: " ")
    return aliases[key]
  }

  public var resolutionAliases: [String: String] {
    aliases
  }

  public func conceptID(for value: String) -> String? {
    let normalized = AyurvedaRules.modifierTokens(value).joined(separator: " ")
    guard !normalized.isEmpty else { return nil }
    let candidate = normalized.replacingOccurrences(of: " ", with: "_")
    if membership[candidate] != nil {
      return candidate
    }
    if candidate.hasSuffix("s") {
      let singular = String(candidate.dropLast())
      if membership[singular] != nil {
        return singular
      }
    }
    return nil
  }

  public struct Requirement: Codable, Hashable, Sendable {
    public let concept: String
    public let count: Int
    public let scope: String
    public let meal: String?
    public let day: Int?

    public init(
      concept: String,
      count: Int,
      scope: String,
      meal: String? = nil,
      day: Int? = nil
    ) {
      self.concept = concept
      self.count = count
      self.scope = scope
      self.meal = meal
      self.day = day
    }
  }

  public struct Restriction: Codable, Hashable, Sendable {
    public enum Hardness: String, Codable, Sendable {
      case hard
      case soft
    }

    public let concept: String
    public let hardness: Hardness
    public let exceptions: [String]

    public init(
      concept: String,
      hardness: Hardness,
      exceptions: [String] = []
    ) {
      self.concept = concept
      self.hardness = hardness
      self.exceptions = exceptions
    }
  }
}

private struct FoodConceptDocument: Decodable, Sendable {
  let catalogCount: Int
  let conceptCount: Int
  let aliasCount: Int
  let membership: [String: [Int32]]
  let aliases: [String: String]
}

private enum FoodConceptError: Error {
  case missingBundle
  case invalidCounts
}
