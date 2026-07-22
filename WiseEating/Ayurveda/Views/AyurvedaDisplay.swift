import Foundation

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
        qualityCaption: "Estimated from food category and preparation — not a classical source.",
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
