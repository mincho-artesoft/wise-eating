import Foundation
import SwiftData

@MainActor
enum AyurvedaSeeder {
  private static let batchSize = 200
  private static let reservedBand = 900_000..<1_002_000

  static func bundleSeedVersion() throws -> Int {
    try loadSeed().seedVersion
  }

  static func run(context: ModelContext) throws {
    do {
      let seed = try loadSeed()
      try validate(seed: seed)

      if try context.fetchCount(FetchDescriptor<AyurvedaProfile>()) > 0 {
        let inserted = try topUpLinks(seed.links, context: context)
        print(
          "   ✅ Ayurveda v\(seed.seedVersion) link top-up inserted "
            + "\(inserted) missing links."
        )
        return
      }

      try verifyReservedBandIsFree(context: context)

      try insertInBatches(
        seed.dravyas.filter(\.foodIsPlaceholder),
        context: context
      ) { dravya in
        context.insert(
          FoodItem(
            id: dravya.foodId,
            name: dravya.name,
            isRecipe: false,
            isUserAdded: false
          )
        )
      }

      let allFoods = try context.fetch(FetchDescriptor<FoodItem>())
      let foodByID = try makeFoodMap(allFoods)
      try validateIngredientTargets(seed.recipes, foodByID: foodByID)

      try insertInBatches(seed.dravyas, context: context) { dravya in
        context.insert(try makeDravyaProfile(dravya, seedVersion: seed.seedVersion))
      }

      try insertInBatches(seed.links, context: context) { link in
        context.insert(
          AyurvedaLink(
            fdcId: link.fdcId,
            dravyaProfileId: link.dravyaId,
            tier: link.tier
          )
        )
      }

      try insertInBatches(seed.recipes, context: context) { recipe in
        let recipeFood = FoodItem(
          id: recipe.foodId,
          name: recipe.name,
          isRecipe: true,
          isUserAdded: false,
          prepTimeMinutes: recipe.prepMinutes + recipe.cookMinutes,
          itemDescription: recipeDescription(recipe)
        )
        let ingredients = try recipe.ingredients.map { ingredient in
          guard let ingredientFood = foodByID[ingredient.foodId] else {
            throw AyurvedaSeederError.missingIngredientFood(
              recipeId: recipe.id,
              foodId: ingredient.foodId
            )
          }
          return IngredientLink(
            food: ingredientFood,
            grams: ingredient.grams,
            owner: recipeFood
          )
        }
        recipeFood.ingredients = ingredients
        context.insert(recipeFood)
        for ingredient in ingredients {
          context.insert(ingredient)
        }
      }

      try insertInBatches(seed.recipes, context: context) { recipe in
        context.insert(makeRecipeProfile(recipe, seedVersion: seed.seedVersion))
      }

      print(
        "   ✅ Seeded \(seed.dravyas.count) dravya profiles, "
          + "\(seed.recipes.count) recipe profiles, and \(seed.links.count) Ayurveda links."
      )
    } catch {
      context.rollback()
      throw error
    }
  }

  private static func loadSeed() throws -> AyurvedaSeedDTO {
    guard
      let url = Bundle.main.url(
        forResource: "ayurveda_seed",
        withExtension: "json.gz"
      )
    else {
      throw AyurvedaSeederError.missingBundle
    }
    let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
    let plain = try ZlibGzip.decompress(data: compressed)
    return try JSONDecoder().decode(AyurvedaSeedDTO.self, from: plain)
  }

  private static func validate(seed: AyurvedaSeedDTO) throws {
    guard seed.counts.dravyas == 714,
      seed.counts.recipes == 1_500,
      seed.counts.links == 2_305,
      seed.counts.derivedLinks == 1_969,
      seed.counts.placeholders == 383,
      seed.counts.categoryRules == 187,
      seed.counts.modifiers == 14,
      seed.dravyas.count == seed.counts.dravyas,
      seed.recipes.count == seed.counts.recipes,
      seed.links.count == seed.counts.links,
      seed.links.filter({ $0.tier == "derived" }).count == seed.counts.derivedLinks,
      seed.dravyas.filter(\.foodIsPlaceholder).count == seed.counts.placeholders
    else {
      throw AyurvedaSeederError.invalidCounts
    }
    guard seed.recipes.allSatisfy({ !$0.ingredients.isEmpty }) else {
      throw AyurvedaSeederError.emptyRecipeIngredients
    }
  }

  private static func topUpLinks(
    _ links: [AyurvedaLinkDTO],
    context: ModelContext
  ) throws -> Int {
    let existingLinks = try context.fetch(FetchDescriptor<AyurvedaLink>())
    let existingFdcIds = Set(existingLinks.map(\.fdcId))
    let missingLinks = links.filter { !existingFdcIds.contains($0.fdcId) }
    try insertInBatches(missingLinks, context: context) { link in
      context.insert(
        AyurvedaLink(
          fdcId: link.fdcId,
          dravyaProfileId: link.dravyaId,
          tier: link.tier
        )
      )
    }
    return missingLinks.count
  }

  private static func verifyReservedBandIsFree(context: ModelContext) throws {
    let lowerBound = reservedBand.lowerBound
    let upperBound = reservedBand.upperBound
    var descriptor = FetchDescriptor<FoodItem>(
      predicate: #Predicate<FoodItem> { food in
        food.id >= lowerBound && food.id < upperBound
      }
    )
    descriptor.fetchLimit = 1
    if let collision = try context.fetch(descriptor).first {
      print("   ⚠️ Ayurveda seed id band collision at FoodItem \(collision.id).")
      throw AyurvedaSeederError.reservedBandCollision(collision.id)
    }
  }

  private static func makeFoodMap(_ foods: [FoodItem]) throws -> [Int: FoodItem] {
    var foodByID: [Int: FoodItem] = [:]
    foodByID.reserveCapacity(foods.count)
    for food in foods {
      guard foodByID.updateValue(food, forKey: food.id) == nil else {
        throw AyurvedaSeederError.duplicateFoodId(food.id)
      }
    }
    return foodByID
  }

  private static func validateIngredientTargets(
    _ recipes: [RecipeDTO],
    foodByID: [Int: FoodItem]
  ) throws {
    let recipeIDs = Set(recipes.map(\.foodId))
    for recipe in recipes {
      for ingredient in recipe.ingredients {
        guard !recipeIDs.contains(ingredient.foodId) else {
          throw AyurvedaSeederError.recipeIngredientReference(
            recipeId: recipe.id,
            foodId: ingredient.foodId
          )
        }
        guard foodByID[ingredient.foodId] != nil else {
          throw AyurvedaSeederError.missingIngredientFood(
            recipeId: recipe.id,
            foodId: ingredient.foodId
          )
        }
      }
    }
  }

  private static func insertInBatches<Element>(
    _ elements: [Element],
    context: ModelContext,
    insert: (Element) throws -> Void
  ) throws {
    for start in stride(from: 0, to: elements.count, by: batchSize) {
      let end = min(start + batchSize, elements.count)
      try context.transaction {
        for element in elements[start..<end] {
          try insert(element)
        }
      }
    }
  }

  private static func makeDravyaProfile(
    _ dravya: DravyaDTO,
    seedVersion: Int
  ) throws -> AyurvedaProfile {
    let servingData = try JSONEncoder().encode(dravya.servings)
    guard let servingsJSON = String(data: servingData, encoding: .utf8) else {
      throw AyurvedaSeederError.invalidServings(dravya.id)
    }
    return AyurvedaProfile(
      id: dravya.id,
      kind: "dravya",
      foodId: dravya.foodId,
      foodIsPlaceholder: dravya.foodIsPlaceholder,
      name: dravya.name,
      category: dravya.category,
      doshaVata: dravya.dosha.vata,
      doshaPitta: dravya.dosha.pitta,
      doshaKapha: dravya.dosha.kapha,
      seasons: dravya.seasons,
      timeOfDay: dravya.timeOfDay,
      viruddha: dravya.viruddha,
      provenance: dravya.provenance,
      confidenceAyur: dravya.confidence.ayur,
      confidenceSci: dravya.confidence.sci,
      qualityState: dravya.qualityState,
      reviewNote: dravya.reviewNote,
      engineExcluded: dravya.engineExcluded,
      seedVersion: seedVersion,
      sanskrit: dravya.sanskrit,
      aliases: dravya.aliases,
      rasa: dravya.rasa,
      virya: dravya.virya,
      vipaka: dravya.vipaka,
      gunas: dravya.gunas,
      prabhava: dravya.prabhava,
      agniEffect: dravya.agniEffect,
      digestibility: dravya.digestibility,
      combinations: dravya.combinations,
      contraindications: dravya.contraindications,
      preparation: dravya.preparation,
      servingsJSON: servingsJSON,
      meal: nil,
      servingsCount: nil,
      prepMinutes: nil,
      cookMinutes: nil,
      steps: [],
      guidance: nil
    )
  }

  private static func makeRecipeProfile(
    _ recipe: RecipeDTO,
    seedVersion: Int
  ) -> AyurvedaProfile {
    AyurvedaProfile(
      id: recipe.id,
      kind: "recipe",
      foodId: recipe.foodId,
      foodIsPlaceholder: false,
      name: recipe.name,
      category: recipe.category,
      doshaVata: recipe.dosha.vata,
      doshaPitta: recipe.dosha.pitta,
      doshaKapha: recipe.dosha.kapha,
      seasons: recipe.seasons,
      timeOfDay: recipe.timeOfDay,
      viruddha: recipe.viruddhaFlags,
      provenance: recipe.provenance,
      confidenceAyur: recipe.confidence.ayur,
      confidenceSci: recipe.confidence.sci,
      qualityState: recipe.qualityState,
      reviewNote: recipe.reviewNote,
      engineExcluded: false,
      seedVersion: seedVersion,
      sanskrit: nil,
      aliases: [],
      rasa: [],
      virya: nil,
      vipaka: nil,
      gunas: [],
      prabhava: nil,
      agniEffect: nil,
      digestibility: nil,
      combinations: [],
      contraindications: [],
      preparation: nil,
      servingsJSON: nil,
      meal: recipe.meal,
      servingsCount: recipe.servings,
      prepMinutes: recipe.prepMinutes,
      cookMinutes: recipe.cookMinutes,
      steps: recipe.steps,
      guidance: recipe.guidance
    )
  }

  private static func recipeDescription(_ recipe: RecipeDTO) -> String {
    let numberedSteps = recipe.steps.enumerated().map { index, step in
      "\(index + 1). \(step)"
    }.joined(separator: "\n")
    return numberedSteps + "\n\n" + recipe.guidance
  }
}

private enum AyurvedaSeederError: Error, LocalizedError {
  case missingBundle
  case invalidCounts
  case emptyRecipeIngredients
  case reservedBandCollision(Int)
  case duplicateFoodId(Int)
  case missingIngredientFood(recipeId: String, foodId: Int)
  case recipeIngredientReference(recipeId: String, foodId: Int)
  case invalidServings(String)

  var errorDescription: String? {
    switch self {
    case .missingBundle:
      return "ayurveda_seed.json.gz is missing from the app bundle"
    case .invalidCounts:
      return "the Ayurveda seed counts do not match the approved D34 counts"
    case .emptyRecipeIngredients:
      return "the Ayurveda seed contains a recipe without ingredients"
    case .reservedBandCollision(let foodId):
      return "the reserved Ayurveda FoodItem band collides at id \(foodId)"
    case .duplicateFoodId(let foodId):
      return "the FoodItem store contains duplicate id \(foodId)"
    case .missingIngredientFood(let recipeId, let foodId):
      return "recipe \(recipeId) references missing FoodItem \(foodId)"
    case .recipeIngredientReference(let recipeId, let foodId):
      return "recipe \(recipeId) references recipe FoodItem \(foodId) as an ingredient"
    case .invalidServings(let dravyaId):
      return "dravya \(dravyaId) has servings that cannot be encoded as JSON"
    }
  }
}

private struct AyurvedaSeedDTO: Decodable {
  let seedVersion: Int
  let generatedAt: String
  let counts: AyurvedaSeedCountsDTO
  let dravyas: [DravyaDTO]
  let recipes: [RecipeDTO]
  let links: [AyurvedaLinkDTO]
}

private struct AyurvedaSeedCountsDTO: Decodable {
  let dravyas: Int
  let recipes: Int
  let links: Int
  let derivedLinks: Int
  let placeholders: Int
  let categoryRules: Int
  let modifiers: Int
}

private struct DoshaDTO: Decodable {
  let vata: Int
  let pitta: Int
  let kapha: Int
}

private struct ConfidenceDTO: Decodable {
  let ayur: Double
  let sci: Double?
}

private struct ServingDTO: Codable {
  let label: String
  let grams: Double
}

private struct DravyaDTO: Decodable {
  let id: String
  let name: String
  let sanskrit: String?
  let aliases: [String]
  let category: String
  let rasa: [String]
  let virya: String?
  let vipaka: String?
  let gunas: [String]
  let prabhava: String?
  let dosha: DoshaDTO
  let agniEffect: Int?
  let digestibility: Int?
  let seasons: [String]
  let timeOfDay: [String]
  let combinations: [String]
  let viruddha: [String]
  let contraindications: [String]
  let preparation: String?
  let servings: [ServingDTO]
  let provenance: [String]
  let confidence: ConfidenceDTO
  let qualityState: String
  let reviewNote: String?
  let foodId: Int
  let foodIsPlaceholder: Bool
  let engineExcluded: Bool
}

private struct RecipeIngredientDTO: Decodable {
  let foodId: Int
  let grams: Double
  let name: String
}

private struct RecipeDTO: Decodable {
  let id: String
  let name: String
  let category: String
  let meal: String
  let servings: Int
  let prepMinutes: Int
  let cookMinutes: Int
  let ingredients: [RecipeIngredientDTO]
  let steps: [String]
  let dosha: DoshaDTO
  let seasons: [String]
  let timeOfDay: [String]
  let viruddhaFlags: [String]
  let guidance: String
  let provenance: [String]
  let confidence: ConfidenceDTO
  let qualityState: String
  let reviewNote: String?
  let foodId: Int
}

private struct AyurvedaLinkDTO: Decodable {
  let fdcId: Int
  let dravyaId: String
  let tier: String
}
