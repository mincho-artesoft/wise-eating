import Foundation

public typealias DoshaVPK = (vata: Int, pitta: Int, kapha: Int)

public struct CategoryRule {
  public let category: String?
  public let vpk: DoshaVPK
  public let virya: String
  public let gunas: [String]
  public let note: String?
}

public struct AppliedModifier {
  public let id: String
  public let label: String
  public let vpk: DoshaVPK
  public let gunas: [String]
  public let note: String?
}

public struct EstimatedAyurveda {
  public let vpk: DoshaVPK
  public let virya: String
  public let gunas: [String]
  public let appliedModifiers: [AppliedModifier]
  public let categoryRule: CategoryRule
  public let confidence: Double
}

public struct AyurvedaRules {
  public static let shared: AyurvedaRules = {
    do {
      return try AyurvedaRules()
    } catch {
      fatalError("Malformed ayurveda_rules.json: \(error)")
    }
  }()

  public let rulesVersion: Int

  private let categories: [String: CategoryRule]
  private let defaultRule: CategoryRule
  private let modifierRules: [ModifierRule]

  private init() throws {
    guard
      let url = Bundle.main.url(
        forResource: "ayurveda_rules",
        withExtension: "json"
      )
    else {
      throw AyurvedaRulesError.missingBundle
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let envelope = try JSONDecoder().decode(RulesEnvelope.self, from: data)

    rulesVersion = envelope.rulesVersion
    defaultRule = try CategoryRule(dto: envelope.default)
    modifierRules = try envelope.modifiers.map { try ModifierRule(dto: $0) }

    var decodedCategories: [String: CategoryRule] = [:]
    decodedCategories.reserveCapacity(envelope.categories.count)
    for dto in envelope.categories {
      guard let category = dto.category else {
        throw AyurvedaRulesError.missingCategory
      }
      guard decodedCategories[category] == nil else {
        throw AyurvedaRulesError.duplicateCategory(category)
      }
      decodedCategories[category] = try CategoryRule(dto: dto)
    }
    categories = decodedCategories
  }

  public func rule(forCategory category: String) -> CategoryRule {
    categories[category] ?? defaultRule
  }

  public func modifiers(forName name: String) -> [AppliedModifier] {
    let foodTokens = Self.modifierTokens(name)
    return modifierRules.compactMap { modifier in
      guard modifier.phrases.contains(where: { Self.contains(foodTokens, phrase: $0) }) else {
        return nil
      }
      return modifier.applied
    }
  }

  public func estimated(category: String, name: String) -> EstimatedAyurveda {
    let categoryRule = rule(forCategory: category)
    let appliedModifiers = modifiers(forName: name)
    var gunas = categoryRule.gunas
    for modifier in appliedModifiers {
      for guna in modifier.gunas where !gunas.contains(guna) {
        gunas.append(guna)
      }
    }
    return EstimatedAyurveda(
      vpk: Self.adjustedVPK(base: categoryRule.vpk, modifiers: appliedModifiers),
      virya: categoryRule.virya,
      gunas: gunas,
      appliedModifiers: appliedModifiers,
      categoryRule: categoryRule,
      confidence: 0.25
    )
  }

  public static func adjustedVPK(
    base: DoshaVPK,
    modifiers: [AppliedModifier]
  ) -> DoshaVPK {
    let totals = modifiers.reduce((vata: 0, pitta: 0, kapha: 0)) { partial, modifier in
      (
        partial.vata + modifier.vpk.vata,
        partial.pitta + modifier.vpk.pitta,
        partial.kapha + modifier.vpk.kapha
      )
    }
    return (
      clamp(base.vata + totals.vata),
      clamp(base.pitta + totals.pitta),
      clamp(base.kapha + totals.kapha)
    )
  }

  private static func clamp(_ value: Int) -> Int {
    min(2, max(-2, value))
  }

  private static func normalized(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(
        of: "\\([^)]*\\)",
        with: "",
        options: .regularExpression
      )
      .replacingOccurrences(of: "&", with: " and ")
      .replacingOccurrences(
        of: "[^a-z0-9,;'\\- ]",
        with: " ",
        options: .regularExpression
      )
  }

  fileprivate static func modifierTokens(_ value: String) -> [String] {
    let normalizedName = normalized(value)
      .replacingOccurrences(of: ",", with: " ")
      .replacingOccurrences(of: ";", with: " ")
    let separators = CharacterSet.whitespacesAndNewlines.union(
      CharacterSet(charactersIn: "-'/")
    )
    return normalizedName.components(separatedBy: separators).filter { !$0.isEmpty }
  }

  private static func contains(_ tokens: [String], phrase: [String]) -> Bool {
    guard !phrase.isEmpty, phrase.count <= tokens.count else {
      return false
    }
    for start in 0...(tokens.count - phrase.count) {
      if Array(tokens[start..<(start + phrase.count)]) == phrase {
        return true
      }
    }
    return false
  }
}

private extension CategoryRule {
  init(dto: RuleDTO) throws {
    category = dto.category
    vpk = try dto.vpk.doshaVPK()
    virya = dto.virya
    gunas = dto.gunas
    note = dto.note
  }
}

private struct ModifierRule {
  let applied: AppliedModifier
  let phrases: [[String]]

  init(dto: ModifierDTO) throws {
    applied = AppliedModifier(
      id: dto.id,
      label: dto.label,
      vpk: try dto.vpk.doshaVPK(),
      gunas: dto.gunas,
      note: dto.note
    )
    phrases = dto.phrases.map(AyurvedaRules.modifierTokens)
  }
}

private struct RulesEnvelope: Decodable {
  let rulesVersion: Int
  let categories: [RuleDTO]
  let `default`: RuleDTO
  let modifiers: [ModifierDTO]
}

private struct RuleDTO: Decodable {
  let category: String?
  let vpk: [Int]
  let virya: String
  let gunas: [String]
  let note: String?
}

private struct ModifierDTO: Decodable {
  let id: String
  let label: String
  let phrases: [String]
  let vpk: [Int]
  let gunas: [String]
  let note: String?
}

private extension Array where Element == Int {
  func doshaVPK() throws -> DoshaVPK {
    guard count == 3 else {
      throw AyurvedaRulesError.invalidVPK(self)
    }
    return (self[0], self[1], self[2])
  }
}

private enum AyurvedaRulesError: Error {
  case missingBundle
  case missingCategory
  case duplicateCategory(String)
  case invalidVPK([Int])
}
