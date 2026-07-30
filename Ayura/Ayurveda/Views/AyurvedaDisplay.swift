import Foundation

enum AyurvedaDoshaTone: Sendable {
  case pacify
  case neutral
  case aggravate
}

struct AyurvedaDoshaEffectPresentation: Sendable {
  let value: Int

  private var boundedValue: Int {
    min(2, max(-2, value))
  }

  var tone: AyurvedaDoshaTone {
    if boundedValue < 0 { return .pacify }
    if boundedValue > 0 { return .aggravate }
    return .neutral
  }

  var effectWord: String {
    switch boundedValue {
    case -2:
      return "Strongly pacifies"
    case -1:
      return "Pacifies"
    case 1:
      return "Aggravates"
    case 2:
      return "Strongly aggravates"
    default:
      return "Neutral"
    }
  }

  var signedValue: String {
    if boundedValue < 0 { return "−\(abs(boundedValue))" }
    if boundedValue > 0 { return "+\(boundedValue)" }
    return "0"
  }

  var primaryText: String {
    "\(effectWord) \(signedValue)"
  }

  var systemImage: String {
    switch tone {
    case .pacify:
      return "leaf.fill"
    case .neutral:
      return "minus.circle.fill"
    case .aggravate:
      return "sun.max.fill"
    }
  }

  func accessibilityLabel(dosha name: String) -> String {
    "\(name): \(effectWord.lowercased()), \(spokenValue) of two"
  }

  private var spokenValue: String {
    switch boundedValue {
    case -2: return "minus two"
    case -1: return "minus one"
    case 1: return "plus one"
    case 2: return "plus two"
    default: return "zero"
    }
  }
}

struct AyurvedaDisplay: Sendable {
  let tierLabel: String
  let tierDetail: String?
  let vata: Int
  let pitta: Int
  let kapha: Int
  let rasa: [String]
  let virya: String?
  let vipaka: String?
  let gunas: [String]
  let modifierLabels: [String]
  let viruddha: [String]
  let contraindications: [String]
  let engineExcluded: Bool
  let confidence: Double?
  let qualityCaption: String?
  let sanskrit: String?

  static func make(from resolution: AyurvedaResolution) -> AyurvedaDisplay? {
    switch resolution {
    case .classical(let profile):
      return profileDisplay(
        profile,
        tier: .classical,
        detail: "from \(profile.name)",
        confidence: resolution.confidence
      )
    case .recipe(let profile):
      return profileDisplay(
        profile,
        tier: .recipe,
        detail: "computed from classical ingredients",
        confidence: resolution.confidence
      )
    case .user(let profile):
      return profileDisplay(
        profile,
        tier: .user,
        detail: "your entry",
        confidence: resolution.confidence
      )
    case .derived(let profile, let link, let modifiers, let vpk):
      let modifierLabels = modifiers.map(\.label)
      var detail = "from \(profile.name)"
      if !modifierLabels.isEmpty {
        let suffix = modifierLabels.count == 1 ? "modifier" : "modifiers"
        detail += " · \(modifierLabels.count) preparation \(suffix)"
      }
      return profileDisplay(
        profile,
        tier: .derived(linkTier: link.tier),
        detail: detail,
        confidence: resolution.confidence,
        vpk: vpk,
        modifierLabels: modifierLabels
      )
    case .computed(let computed):
      return AyurvedaDisplay(
        tierLabel: AyurvedaDisplayMath.tierLabel(.computed),
        tierDetail: "computed from your ingredients",
        vata: computed.vata,
        pitta: computed.pitta,
        kapha: computed.kapha,
        rasa: [],
        virya: computed.virya,
        vipaka: nil,
        gunas: [],
        modifierLabels: [],
        viruddha: [],
        contraindications: [],
        engineExcluded: false,
        confidence: resolution.confidence,
        qualityCaption: "AI-drafted Ayurvedic details, pending expert review. Informational only — not medical advice.",
        sanskrit: nil
      )
    case .estimated(let estimate):
      return AyurvedaDisplay(
        tierLabel: AyurvedaDisplayMath.tierLabel(.estimated),
        tierDetail: "category rule: \(estimate.categoryRule.category ?? "default")",
        vata: estimate.vpk.vata,
        pitta: estimate.vpk.pitta,
        kapha: estimate.vpk.kapha,
        rasa: [],
        virya: estimate.virya,
        vipaka: nil,
        gunas: estimate.gunas,
        modifierLabels: estimate.appliedModifiers.map(\.label),
        viruddha: [],
        contraindications: [],
        engineExcluded: false,
        confidence: resolution.confidence,
        qualityCaption: nil,
        sanskrit: nil
      )
    case .none:
      return nil
    }
  }

  private static func profileDisplay(
    _ profile: AyurvedaProfile,
    tier: AyurvedaDisplayMath.TierInput,
    detail: String,
    confidence: Double?,
    vpk: DoshaVPK? = nil,
    modifierLabels: [String] = []
  ) -> AyurvedaDisplay {
    let resolvedVPK = vpk ?? (
      vata: profile.doshaVata,
      pitta: profile.doshaPitta,
      kapha: profile.doshaKapha
    )
    let tierLabel = AyurvedaDisplayMath.tierLabel(tier)
    return AyurvedaDisplay(
      tierLabel: tierLabel,
      tierDetail: detail,
      vata: resolvedVPK.vata,
      pitta: resolvedVPK.pitta,
      kapha: resolvedVPK.kapha,
      rasa: profile.rasa,
      virya: profile.virya,
      vipaka: profile.vipaka,
      gunas: profile.gunas,
      modifierLabels: modifierLabels,
      viruddha: profile.viruddha,
      contraindications: profile.contraindications,
      engineExcluded: profile.engineExcluded,
      confidence: confidence,
      qualityCaption: qualityCaption(for: profile, tierLabel: tierLabel),
      sanskrit: profile.sanskrit
    )
  }

  private static func qualityCaption(
    for profile: AyurvedaProfile,
    tierLabel: String
  ) -> String? {
    guard tierLabel != "User" else {
      return nil
    }
    if profile.qualityState == "aiDraft" {
      return "AI-drafted Ayurvedic details, pending expert review. Informational only — not medical advice."
    }
    return nil
  }
}
