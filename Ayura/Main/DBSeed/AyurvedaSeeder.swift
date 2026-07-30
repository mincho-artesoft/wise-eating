import Foundation
import SwiftData

@MainActor
enum AyurvedaSeeder {
  private static let reservedBand = 900_000..<1_002_000

  struct RunResult {
    var insertedFoods = 0
    var insertedProfiles = 0
    var updatedProfiles = 0
    var insertedLinks = 0
    var updatedLinks = 0
    var replacedIngredientSets = 0
    var updatedRecipeFoods = 0
    var updatedSafetyFoods = 0

    var insertedRows: Int {
      insertedFoods + insertedProfiles + insertedLinks
    }

    var changedSearchableFoods: Bool {
      insertedFoods > 0
        || updatedRecipeFoods > 0
        || updatedSafetyFoods > 0
        || replacedIngredientSets > 0
    }

    var isNoOp: Bool {
      insertedRows == 0
        && updatedProfiles == 0
        && updatedLinks == 0
        && replacedIngredientSets == 0
        && updatedRecipeFoods == 0
        && updatedSafetyFoods == 0
    }
  }

  static func bundleSeedVersion() throws -> Int {
    try JSONDecoder()
      .decode(AyurvedaSeedVersionDTO.self, from: loadSeedData())
      .seedVersion
  }

  static func run(context: ModelContext) throws -> RunResult {
    do {
      let seed = try loadSeed()
      try validate(seed: seed)

      let existingProfiles = try context.fetch(FetchDescriptor<AyurvedaProfile>())
      let profileByID = try makeProfileMap(existingProfiles)
      let existingLinks = try context.fetch(FetchDescriptor<AyurvedaLink>())
      let linkByFdcID = try makeLinkMap(existingLinks)
      let allFoods = try context.fetch(FetchDescriptor<FoodItem>())
      var foodByID = try makeFoodMap(allFoods)
      let allDiets = try context.fetch(FetchDescriptor<Diet>())
      let dietByName = Dictionary(
        uniqueKeysWithValues: allDiets.map { ($0.name, $0) }
      )

      try validateCanonicalOwnership(
        seed: seed,
        profileByID: profileByID,
        foodByID: foodByID
      )
      try validateSafetyDietTargets(seed: seed, dietByName: dietByName)

      if storeHasCurrentSeed(
        seed: seed,
        profileByID: profileByID,
        linkByFdcID: linkByFdcID,
        foodByID: foodByID
      ) {
        print(
          "   ✅ Ayurveda v\(seed.seedVersion) preseed stamp verified; "
            + "no inserts or updates."
        )
        return RunResult()
      }

      var result = RunResult()

      for dravya in seed.dravyas where dravya.foodIsPlaceholder {
        if foodByID[dravya.foodId] == nil {
          let food = FoodItem(
            id: dravya.foodId,
            name: dravya.name,
            isRecipe: false,
            isUserAdded: false
          )
          context.insert(food)
          foodByID[dravya.foodId] = food
          result.insertedFoods += 1
        }
      }
      try validateIngredientTargets(seed.recipes, foodByID: foodByID)

      for dravya in seed.dravyas {
        guard let food = foodByID[dravya.foodId] else {
          throw AyurvedaSeederError.missingIngredientFood(
            recipeId: dravya.id,
            foodId: dravya.foodId
          )
        }
        if try updateSafetyMetadata(
          dravya.safety,
          food: food,
          dietByName: dietByName
        ) {
          result.updatedSafetyFoods += 1
        }
      }

      for dravya in seed.dravyas {
        if let profile = profileByID[dravya.id] {
          if profile.seedVersion < seed.seedVersion {
            try apply(
              dravya: dravya,
              seedVersion: seed.seedVersion,
              to: profile
            )
            result.updatedProfiles += 1
          }
        } else {
          context.insert(try makeDravyaProfile(dravya, seedVersion: seed.seedVersion))
          result.insertedProfiles += 1
        }
      }

      for link in seed.links {
        if let existing = linkByFdcID[link.fdcId] {
          if existing.dravyaProfileId != link.dravyaId || existing.tier != link.tier {
            existing.dravyaProfileId = link.dravyaId
            existing.tier = link.tier
            result.updatedLinks += 1
          }
        } else {
          context.insert(
            AyurvedaLink(
              fdcId: link.fdcId,
              dravyaProfileId: link.dravyaId,
              tier: link.tier
            )
          )
          result.insertedLinks += 1
        }
      }

      for recipe in seed.recipes {
        let recipeFood: FoodItem
        if let existing = foodByID[recipe.foodId] {
          recipeFood = existing
          if updateRecipeFoodMetadata(recipe, food: recipeFood) {
            result.updatedRecipeFoods += 1
          }
          if try updateSafetyMetadata(
            recipe.safety,
            food: recipeFood,
            dietByName: dietByName
          ) {
            result.updatedSafetyFoods += 1
          }
          if !ingredientSetMatches(recipe, food: recipeFood) {
            try replaceIngredients(
              for: recipe,
              food: recipeFood,
              foodByID: foodByID,
              context: context
            )
            result.replacedIngredientSets += 1
          }
        } else {
          recipeFood = FoodItem(
            id: recipe.foodId,
            name: recipe.name,
            isRecipe: true,
            isUserAdded: false,
            prepTimeMinutes: recipe.prepMinutes + recipe.cookMinutes,
            itemDescription: recipeDescription(recipe)
          )
          context.insert(recipeFood)
          _ = try updateSafetyMetadata(
            recipe.safety,
            food: recipeFood,
            dietByName: dietByName
          )
          try replaceIngredients(
            for: recipe,
            food: recipeFood,
            foodByID: foodByID,
            context: context
          )
          foodByID[recipe.foodId] = recipeFood
          result.insertedFoods += 1
        }
      }

      for recipe in seed.recipes {
        if let profile = profileByID[recipe.id] {
          if profile.seedVersion < seed.seedVersion || profile.nutritionStatus == nil {
            try apply(
              recipe: recipe,
              seedVersion: seed.seedVersion,
              to: profile
            )
            result.updatedProfiles += 1
          }
        } else {
          context.insert(try makeRecipeProfile(recipe, seedVersion: seed.seedVersion))
          result.insertedProfiles += 1
        }
      }

      print(
        "   ✅ Ayurveda v\(seed.seedVersion) slug-keyed delta: "
          + "inserted \(result.insertedRows) rows "
          + "(\(result.insertedFoods) foods, \(result.insertedProfiles) profiles, "
          + "\(result.insertedLinks) links); updated \(result.updatedProfiles) profiles, "
          + "\(result.updatedLinks) links, \(result.updatedRecipeFoods) recipe foods, "
          + "\(result.updatedSafetyFoods) safety rows; "
          + "replaced \(result.replacedIngredientSets) ingredient sets."
      )
      return result
    } catch {
      context.rollback()
      throw error
    }
  }

  private static func loadSeedData() throws -> Data {
    guard
      let url = Bundle.main.url(
        forResource: "ayurveda_seed",
        withExtension: "json.gz"
      )
    else {
      throw AyurvedaSeederError.missingBundle
    }
    let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
    return try ZlibGzip.decompress(data: compressed)
  }

  private static func loadSeed() throws -> AyurvedaSeedDTO {
    try JSONDecoder().decode(AyurvedaSeedDTO.self, from: loadSeedData())
  }

  private static func validate(seed: AyurvedaSeedDTO) throws {
    guard seed.counts.dravyas == 705,
      seed.counts.recipes == 1_500,
      seed.counts.links == 2_336,
      seed.counts.derivedLinks == 1_966,
      seed.counts.placeholders == 376,
      seed.counts.categoryRules == 187,
      seed.counts.modifiers == 14,
      seed.counts.nutrition.full
        + seed.counts.nutrition.estimated
        + seed.counts.nutrition.none == seed.counts.recipes,
      seed.counts.safety.profiles == seed.counts.dravyas + seed.counts.recipes,
      seed.counts.safety.authoredAgeDravyas == 4,
      seed.counts.safety.legacyImportAgeDravyas == 701,
      seed.counts.safety.authoredAgeRecipes == 4,
      seed.counts.safety.legacyImportAgeRecipes == 1_496,
      seed.counts.safety.ageContributors == 10_571,
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
    let validNutritionStates = Set(["full", "estimated", "none"])
    guard seed.recipes.allSatisfy({
      validNutritionStates.contains($0.nutrition.status)
        && ($0.nutrition.status != "full" || $0.nutrition.missingIngredients.isEmpty)
      && $0.nutrition.totalWeightG > 0
    }) else {
      throw AyurvedaSeederError.invalidNutrition
    }
    let safetyRows = seed.dravyas.map(\.safety) + seed.recipes.map(\.safety)
    guard safetyRows.count == seed.counts.safety.profiles,
      safetyRows.allSatisfy({
        $0.provenance == "scaffold-default"
          && $0.reviewRequired
          && $0.minAgeMonths >= 0
          && $0.enforcedMinAgeMonths >= 0
          && $0.enforcedMinAgeMonths <= $0.minAgeMonths
          && ["authored", "legacyImport"].contains($0.ageProvenance)
          && !$0.ageContributors.isEmpty
          && $0.ageContributors.allSatisfy({
            $0.minAgeMonths >= 0
              && $0.enforcedMinAgeMonths >= 0
              && $0.enforcedMinAgeMonths <= $0.minAgeMonths
              && ["authored", "legacyImport"].contains($0.ageProvenance)
          })
          && Set($0.allergens).count == $0.allergens.count
          && Set($0.diets).count == $0.diets.count
          && !$0.rules.isEmpty
      })
    else {
      throw AyurvedaSeederError.invalidSafetyMetadata
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

  private static func makeProfileMap(
    _ profiles: [AyurvedaProfile]
  ) throws -> [String: AyurvedaProfile] {
    var profileByID: [String: AyurvedaProfile] = [:]
    profileByID.reserveCapacity(profiles.count)
    for profile in profiles {
      guard profileByID.updateValue(profile, forKey: profile.id) == nil else {
        throw AyurvedaSeederError.duplicateProfileId(profile.id)
      }
    }
    return profileByID
  }

  private static func makeLinkMap(
    _ links: [AyurvedaLink]
  ) throws -> [Int: AyurvedaLink] {
    var linkByFdcID: [Int: AyurvedaLink] = [:]
    linkByFdcID.reserveCapacity(links.count)
    for link in links {
      guard linkByFdcID.updateValue(link, forKey: link.fdcId) == nil else {
        throw AyurvedaSeederError.duplicateLinkFdcId(link.fdcId)
      }
    }
    return linkByFdcID
  }

  private static func validateCanonicalOwnership(
    seed: AyurvedaSeedDTO,
    profileByID: [String: AyurvedaProfile],
    foodByID: [Int: FoodItem]
  ) throws {
    for dravya in seed.dravyas {
      if let profile = profileByID[dravya.id] {
        guard profile.kind == "dravya", profile.foodId == dravya.foodId else {
          throw AyurvedaSeederError.canonicalOwnershipConflict(dravya.id)
        }
      } else if dravya.foodIsPlaceholder, foodByID[dravya.foodId] != nil {
        throw AyurvedaSeederError.reservedBandCollision(dravya.foodId)
      }
    }
    for recipe in seed.recipes {
      if let profile = profileByID[recipe.id] {
        guard profile.kind == "recipe", profile.foodId == recipe.foodId else {
          throw AyurvedaSeederError.canonicalOwnershipConflict(recipe.id)
        }
      } else if foodByID[recipe.foodId] != nil {
        throw AyurvedaSeederError.reservedBandCollision(recipe.foodId)
      }
    }

    let expectedReservedFoodIDs = Set(
      seed.dravyas.lazy.filter(\.foodIsPlaceholder).map(\.foodId)
    ).union(seed.recipes.map(\.foodId))
    for foodID in foodByID.keys where reservedBand.contains(foodID) {
      guard expectedReservedFoodIDs.contains(foodID) else {
        throw AyurvedaSeederError.reservedBandCollision(foodID)
      }
    }
  }

  private static func storeHasCurrentSeed(
    seed: AyurvedaSeedDTO,
    profileByID: [String: AyurvedaProfile],
    linkByFdcID: [Int: AyurvedaLink],
    foodByID: [Int: FoodItem]
  ) -> Bool {
    let dravyasAreCurrent = seed.dravyas.allSatisfy { dravya in
      guard let profile = profileByID[dravya.id] else {
        return false
      }
      return profile.kind == "dravya"
        && profile.foodId == dravya.foodId
        && profile.seedVersion >= seed.seedVersion
        && foodByID[dravya.foodId] != nil
    }
    guard dravyasAreCurrent else {
      return false
    }

    let recipesAreCurrent = seed.recipes.allSatisfy { recipe in
      guard
        let profile = profileByID[recipe.id],
        let food = foodByID[recipe.foodId]
      else {
        return false
      }
      return profile.kind == "recipe"
        && profile.foodId == recipe.foodId
        && profile.seedVersion >= seed.seedVersion
        && profile.nutritionStatus != nil
        && food.isRecipe
        && !food.isUserAdded
    }
    guard recipesAreCurrent else {
      return false
    }

    return seed.links.allSatisfy { link in
      guard let existing = linkByFdcID[link.fdcId] else {
        return false
      }
      return existing.dravyaProfileId == link.dravyaId
        && existing.tier == link.tier
    }
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

  private static func validateSafetyDietTargets(
    seed: AyurvedaSeedDTO,
    dietByName: [String: Diet]
  ) throws {
    let safetyRows = seed.dravyas.map(\.safety) + seed.recipes.map(\.safety)
    for safety in safetyRows {
      for diet in safety.diets where dietByName[diet] == nil {
        throw AyurvedaSeederError.missingSafetyDiet(diet)
      }
      for allergen in safety.allergens where Allergen(rawValue: allergen) == nil {
        throw AyurvedaSeederError.invalidSafetyAllergen(allergen)
      }
    }
  }

  private static func safetyMetadataMatches(
    _ safety: SafetyMetadataDTO,
    food: FoodItem
  ) -> Bool {
    let actualDiets = Set((food.diets ?? []).map(\.name))
    let actualAllergens = Set((food.allergens ?? []).map(\.rawValue))
    return actualDiets == Set(safety.diets)
      && actualAllergens == Set(safety.allergens)
      && food.minAgeMonths == safety.minAgeMonths
  }

  private static func updateSafetyMetadata(
    _ safety: SafetyMetadataDTO,
    food: FoodItem,
    dietByName: [String: Diet]
  ) throws -> Bool {
    guard !safetyMetadataMatches(safety, food: food) else {
      return false
    }
    food.diets = try safety.diets.map { dietName in
      guard let diet = dietByName[dietName] else {
        throw AyurvedaSeederError.missingSafetyDiet(dietName)
      }
      return diet
    }
    food.allergens = try safety.allergens.map { allergenName in
      guard let allergen = Allergen(rawValue: allergenName) else {
        throw AyurvedaSeederError.invalidSafetyAllergen(allergenName)
      }
      return allergen
    }
    food.minAgeMonths = safety.minAgeMonths
    return true
  }

  private static func recipeFoodMetadataMatches(
    _ recipe: RecipeDTO,
    food: FoodItem
  ) -> Bool {
    food.name == recipe.name
      && food.isRecipe
      && !food.isMenu
      && !food.isUserAdded
      && food.prepTimeMinutes == recipe.prepMinutes + recipe.cookMinutes
      && food.itemDescription == recipeDescription(recipe)
  }

  private static func updateRecipeFoodMetadata(
    _ recipe: RecipeDTO,
    food: FoodItem
  ) -> Bool {
    guard !recipeFoodMetadataMatches(recipe, food: food) else {
      return false
    }
    food.name = recipe.name
    food.isRecipe = true
    food.isMenu = false
    food.isUserAdded = false
    food.prepTimeMinutes = recipe.prepMinutes + recipe.cookMinutes
    food.itemDescription = recipeDescription(recipe)
    return true
  }

  private static func ingredientSetMatches(
    _ recipe: RecipeDTO,
    food: FoodItem
  ) -> Bool {
    let expected = recipe.ingredients.map {
      "\($0.foodId):\($0.grams.bitPattern)"
    }.sorted()
    let actual = (food.ingredients ?? []).compactMap { link -> String? in
      guard let foodID = link.food?.id else {
        return nil
      }
      return "\(foodID):\(link.grams.bitPattern)"
    }.sorted()
    return expected == actual && actual.count == (food.ingredients ?? []).count
  }

  private static func replaceIngredients(
    for recipe: RecipeDTO,
    food: FoodItem,
    foodByID: [Int: FoodItem],
    context: ModelContext
  ) throws {
    for existing in food.ingredients ?? [] {
      context.delete(existing)
    }
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
        owner: food
      )
    }
    food.ingredients = ingredients
    for ingredient in ingredients {
      context.insert(ingredient)
    }
  }

  private static func apply(
    dravya: DravyaDTO,
    seedVersion: Int,
    to profile: AyurvedaProfile
  ) throws {
    copyProfile(
      from: try makeDravyaProfile(dravya, seedVersion: seedVersion),
      to: profile
    )
  }

  private static func apply(
    recipe: RecipeDTO,
    seedVersion: Int,
    to profile: AyurvedaProfile
  ) throws {
    copyProfile(
      from: try makeRecipeProfile(recipe, seedVersion: seedVersion),
      to: profile
    )
  }

  private static func copyProfile(
    from source: AyurvedaProfile,
    to destination: AyurvedaProfile
  ) {
    destination.kind = source.kind
    destination.foodId = source.foodId
    destination.foodIsPlaceholder = source.foodIsPlaceholder
    destination.name = source.name
    destination.category = source.category
    destination.doshaVata = source.doshaVata
    destination.doshaPitta = source.doshaPitta
    destination.doshaKapha = source.doshaKapha
    destination.seasons = source.seasons
    destination.timeOfDay = source.timeOfDay
    destination.viruddha = source.viruddha
    destination.provenance = source.provenance
    destination.confidenceAyur = source.confidenceAyur
    destination.confidenceSci = source.confidenceSci
    destination.qualityState = source.qualityState
    destination.reviewNote = source.reviewNote
    destination.engineExcluded = source.engineExcluded
    destination.seedVersion = source.seedVersion
    destination.sanskrit = source.sanskrit
    destination.aliases = source.aliases
    destination.rasa = source.rasa
    destination.virya = source.virya
    destination.vipaka = source.vipaka
    destination.gunas = source.gunas
    destination.prabhava = source.prabhava
    destination.agniEffect = source.agniEffect
    destination.digestibility = source.digestibility
    destination.combinations = source.combinations
    destination.contraindications = source.contraindications
    destination.preparation = source.preparation
    destination.servingsJSON = source.servingsJSON
    destination.meal = source.meal
    destination.servingsCount = source.servingsCount
    destination.prepMinutes = source.prepMinutes
    destination.cookMinutes = source.cookMinutes
    destination.steps = source.steps
    destination.guidance = source.guidance
    destination.nutritionStatus = source.nutritionStatus
    destination.nutritionMissingIngredients = source.nutritionMissingIngredients
    destination.nutritionTotalWeightG = source.nutritionTotalWeightG
    destination.nutritionPerServingJSON = source.nutritionPerServingJSON
    destination.nutritionPer100gJSON = source.nutritionPer100gJSON
    destination.nutritionUnitsJSON = source.nutritionUnitsJSON
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
  ) throws -> AyurvedaProfile {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let perServing = try encodeNutritionJSON(
      recipe.nutrition.perServing,
      recipeId: recipe.id,
      encoder: encoder
    )
    let per100g = try encodeNutritionJSON(
      recipe.nutrition.per100g,
      recipeId: recipe.id,
      encoder: encoder
    )
    let units = try encodeNutritionJSON(
      recipe.nutrition.units,
      recipeId: recipe.id,
      encoder: encoder
    )
    return AyurvedaProfile(
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
      guidance: recipe.guidance,
      nutritionStatus: recipe.nutrition.status,
      nutritionMissingIngredients: recipe.nutrition.missingIngredients,
      nutritionTotalWeightG: recipe.nutrition.totalWeightG,
      nutritionPerServingJSON: perServing,
      nutritionPer100gJSON: per100g,
      nutritionUnitsJSON: units
    )
  }

  private static func encodeNutritionJSON<Value: Encodable>(
    _ value: Value,
    recipeId: String,
    encoder: JSONEncoder
  ) throws -> String {
    let data = try encoder.encode(value)
    guard let encoded = String(data: data, encoding: .utf8) else {
      throw AyurvedaSeederError.invalidNutritionJSON(recipeId)
    }
    return encoded
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
  case duplicateProfileId(String)
  case duplicateLinkFdcId(Int)
  case canonicalOwnershipConflict(String)
  case missingIngredientFood(recipeId: String, foodId: Int)
  case recipeIngredientReference(recipeId: String, foodId: Int)
  case invalidServings(String)
  case invalidNutrition
  case invalidNutritionJSON(String)
  case invalidSafetyMetadata
  case missingSafetyDiet(String)
  case invalidSafetyAllergen(String)

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
    case .duplicateProfileId(let profileId):
      return "the Ayurveda store contains duplicate profile slug \(profileId)"
    case .duplicateLinkFdcId(let fdcId):
      return "the Ayurveda store contains duplicate link fdcId \(fdcId)"
    case .canonicalOwnershipConflict(let profileId):
      return "canonical profile ownership conflicts at slug \(profileId)"
    case .missingIngredientFood(let recipeId, let foodId):
      return "recipe \(recipeId) references missing FoodItem \(foodId)"
    case .recipeIngredientReference(let recipeId, let foodId):
      return "recipe \(recipeId) references recipe FoodItem \(foodId) as an ingredient"
    case .invalidServings(let dravyaId):
      return "dravya \(dravyaId) has servings that cannot be encoded as JSON"
    case .invalidNutrition:
      return "the Ayurveda seed contains invalid recipe nutrition"
    case .invalidNutritionJSON(let recipeId):
      return "recipe \(recipeId) nutrition cannot be encoded as JSON"
    case .invalidSafetyMetadata:
      return "the Ayurveda seed contains invalid scaffold-default safety metadata"
    case .missingSafetyDiet(let diet):
      return "the Ayurveda seed references missing Diet \(diet)"
    case .invalidSafetyAllergen(let allergen):
      return "the Ayurveda seed references unsupported allergen \(allergen)"
    }
  }
}

private struct AyurvedaSeedVersionDTO: Decodable {
  let seedVersion: Int
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
  let nutrition: RecipeNutritionCountsDTO
  let safety: SafetyMetadataCountsDTO
}

private struct RecipeNutritionCountsDTO: Decodable {
  let full: Int
  let estimated: Int
  let none: Int
}

private struct SafetyMetadataCountsDTO: Decodable {
  let profiles: Int
  let allergenTaggedDravyas: Int
  let allergenTaggedRecipes: Int
  let honeyMinAgeDravyas: Int
  let honeyMinAgeRecipes: Int
  let authoredAgeDravyas: Int
  let legacyImportAgeDravyas: Int
  let authoredAgeRecipes: Int
  let legacyImportAgeRecipes: Int
  let ageContributors: Int
}

private struct SafetyMetadataDTO: Decodable {
  let allergens: [String]
  let diets: [String]
  let minAgeMonths: Int
  let enforcedMinAgeMonths: Int
  let ageProvenance: String
  let ageContributors: [AgeContributorDTO]
  let provenance: String
  let reviewRequired: Bool
  let rules: [String]
  let reviewFlags: [String]
}

private struct AgeContributorDTO: Decodable {
  let ingredientId: String
  let grams: Double?
  let minAgeMonths: Int
  let enforcedMinAgeMonths: Int
  let ageProvenance: String
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
  let safety: SafetyMetadataDTO
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
  let nutrition: RecipeNutritionDTO
  let safety: SafetyMetadataDTO
}

private struct RecipeNutritionDTO: Decodable {
  let status: String
  let missingIngredients: [String]
  let totalWeightG: Double
  let perServing: [String: Double]
  let per100g: [String: Double]
  let units: [String: String]
}

private struct AyurvedaLinkDTO: Decodable {
  let fdcId: Int
  let dravyaId: String
  let tier: String
}
