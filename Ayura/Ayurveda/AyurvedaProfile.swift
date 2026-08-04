import Foundation
import SwiftData

@Model public final class AyurvedaProfile {
  #Index<AyurvedaProfile>([\.foodId], [\.kind])

  @Attribute(.unique) public var id: UUID
  @Attribute(.unique) public var key: String
  public var kind: String
  public var foodId: UUID
  public var foodIsPlaceholder: Bool = false
  public var name: String
  public var doshaVata: Int
  public var doshaPitta: Int
  public var doshaKapha: Int
  public var seasons: [String]
  public var timeOfDay: [String]
  public var viruddha: [String]
  public var provenance: [String]
  public var confidenceAyur: Double
  public var confidenceSci: Double?
  public var qualityState: String = "aiDraft"
  public var reviewNote: String?
  public var engineExcluded: Bool = false
  public var edible: Bool = true
  public var inedibleReason: String?
  public var seedVersion: Int
  public var sanskrit: String?
  public var aliases: [String] = []
  public var rasa: [String] = []
  public var virya: String?
  public var vipaka: String?
  public var gunas: [String] = []
  public var prabhava: String?
  public var agniEffect: Int?
  public var digestibility: Int?
  public var combinations: [String] = []
  public var contraindications: [String] = []
  public var preparation: String?
  public var servingsJSON: String?
  public var meal: String?
  public var servingsCount: Int?
  public var prepMinutes: Int?
  public var cookMinutes: Int?
  public var steps: [String] = []
  public var guidance: String?
  public var nutritionStatus: String?
  public var nutritionMissingIngredients: [String] = []
  public var nutritionTotalWeightG: Double?
  public var nutritionPerServingJSON: String?
  public var nutritionPer100gJSON: String?
  public var nutritionUnitsJSON: String?

  public init(
    id: UUID,
    key: String,
    kind: String,
    foodId: UUID,
    foodIsPlaceholder: Bool = false,
    name: String,
    doshaVata: Int,
    doshaPitta: Int,
    doshaKapha: Int,
    seasons: [String],
    timeOfDay: [String],
    viruddha: [String],
    provenance: [String],
    confidenceAyur: Double,
    confidenceSci: Double?,
    qualityState: String = "aiDraft",
    reviewNote: String?,
    engineExcluded: Bool = false,
    edible: Bool = true,
    inedibleReason: String? = nil,
    seedVersion: Int,
    sanskrit: String?,
    aliases: [String] = [],
    rasa: [String] = [],
    virya: String?,
    vipaka: String?,
    gunas: [String] = [],
    prabhava: String?,
    agniEffect: Int?,
    digestibility: Int?,
    combinations: [String] = [],
    contraindications: [String] = [],
    preparation: String?,
    servingsJSON: String?,
    meal: String?,
    servingsCount: Int?,
    prepMinutes: Int?,
    cookMinutes: Int?,
    steps: [String] = [],
    guidance: String?,
    nutritionStatus: String? = nil,
    nutritionMissingIngredients: [String] = [],
    nutritionTotalWeightG: Double? = nil,
    nutritionPerServingJSON: String? = nil,
    nutritionPer100gJSON: String? = nil,
    nutritionUnitsJSON: String? = nil
  ) {
    self.id = id
    self.key = key
    self.kind = kind
    self.foodId = foodId
    self.foodIsPlaceholder = foodIsPlaceholder
    self.name = name
    self.doshaVata = doshaVata
    self.doshaPitta = doshaPitta
    self.doshaKapha = doshaKapha
    self.seasons = seasons
    self.timeOfDay = timeOfDay
    self.viruddha = viruddha
    self.provenance = provenance
    self.confidenceAyur = confidenceAyur
    self.confidenceSci = confidenceSci
    self.qualityState = qualityState
    self.reviewNote = reviewNote
    self.engineExcluded = engineExcluded
    self.edible = edible
    self.inedibleReason = inedibleReason
    self.seedVersion = seedVersion
    self.sanskrit = sanskrit
    self.aliases = aliases
    self.rasa = rasa
    self.virya = virya
    self.vipaka = vipaka
    self.gunas = gunas
    self.prabhava = prabhava
    self.agniEffect = agniEffect
    self.digestibility = digestibility
    self.combinations = combinations
    self.contraindications = contraindications
    self.preparation = preparation
    self.servingsJSON = servingsJSON
    self.meal = meal
    self.servingsCount = servingsCount
    self.prepMinutes = prepMinutes
    self.cookMinutes = cookMinutes
    self.steps = steps
    self.guidance = guidance
    self.nutritionStatus = nutritionStatus
    self.nutritionMissingIngredients = nutritionMissingIngredients
    self.nutritionTotalWeightG = nutritionTotalWeightG
    self.nutritionPerServingJSON = nutritionPerServingJSON
    self.nutritionPer100gJSON = nutritionPer100gJSON
    self.nutritionUnitsJSON = nutritionUnitsJSON
  }
}

@Model public final class AyurvedaLink {
  #Index<AyurvedaLink>([\.foodId])

  @Attribute(.unique) public var id: UUID
  @Attribute(.unique) public var foodId: UUID
  public var dravyaProfileId: UUID
  public var tier: String

  public init(id: UUID, foodId: UUID, dravyaProfileId: UUID, tier: String) {
    self.id = id
    self.foodId = foodId
    self.dravyaProfileId = dravyaProfileId
    self.tier = tier
  }
}
