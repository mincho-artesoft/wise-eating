import Foundation
import SwiftData

@MainActor
enum AyurvedaSeeder {

  struct RunResult {
    var insertedFoods = 0
    var insertedProfiles = 0
    var updatedProfiles = 0
    var insertedLinks = 0
    var updatedLinks = 0
    var deletedFoods = 0
    var deletedProfiles = 0
    var deletedLinks = 0
    var remappedFoodIDs = 0
    var remappedFoodReferences = 0
    var replacedIngredientSets = 0
    var updatedRecipeFoods = 0
    var updatedDravyaFoods = 0
    var nutritionAppliedFoods = 0
    var updatedSafetyFoods = 0
    var rebuiltSearchIndex = false

    var insertedRows: Int {
      insertedFoods + insertedProfiles + insertedLinks
    }

    var deletedRows: Int {
      deletedFoods + deletedProfiles + deletedLinks
    }

    var changedSearchableFoods: Bool {
      insertedFoods > 0
        || insertedProfiles > 0
        || updatedProfiles > 0
        || insertedLinks > 0
        || updatedLinks > 0
        || deletedRows > 0
        || remappedFoodIDs > 0
        || updatedRecipeFoods > 0
        || updatedDravyaFoods > 0
        || nutritionAppliedFoods > 0
        || updatedSafetyFoods > 0
        || replacedIngredientSets > 0
    }

    var isNoOp: Bool {
      insertedRows == 0
        && deletedRows == 0
        && updatedProfiles == 0
        && updatedLinks == 0
        && remappedFoodIDs == 0
        && remappedFoodReferences == 0
        && replacedIngredientSets == 0
        && updatedRecipeFoods == 0
        && updatedDravyaFoods == 0
        && nutritionAppliedFoods == 0
        && updatedSafetyFoods == 0
    }

    var requiresSearchIndexRebuild: Bool {
      changedSearchableFoods && !rebuiltSearchIndex
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
      let seedDravyaByID = Dictionary(
        uniqueKeysWithValues: seed.dravyas.map { ($0.id, $0) }
      )

      var result = RunResult()
      var existingProfiles = try context.fetch(FetchDescriptor<AyurvedaProfile>())
      var existingLinks = try context.fetch(FetchDescriptor<AyurvedaLink>())
      var allFoods = try context.fetch(FetchDescriptor<FoodItem>())

      let profileByID = try makeProfileMap(existingProfiles)
      let linkByFoodID = try makeLinkMap(existingLinks)
      var foodByID = try makeFoodMap(allFoods)
      try validateCanonicalOwnership(
        seed: seed,
        profileByID: profileByID,
        foodByID: foodByID
      )
      if storeHasCurrentSeed(
        seed: seed,
        profileByID: profileByID,
        linkByFoodID: linkByFoodID,
        foodByID: foodByID
      ) {
        print(
          "   ✅ Ayurveda v\(seed.seedVersion) preseed stamp verified; "
            + "no inserts or updates."
        )
        return result
      }

      for dravya in seed.dravyas where dravya.foodIsPlaceholder {
        if foodByID[dravya.foodId] == nil {
          let food = FoodItem(
            id: dravya.foodId,
            name: dravya.name,
            isRecipe: false,
            isUserAdded: false,
            itemDescription: dravyaDescription(dravya)
          )
          context.insert(food)
          foodByID[dravya.foodId] = food
          result.insertedFoods += 1
        } else if let food = foodByID[dravya.foodId],
                  food.itemDescription != dravyaDescription(dravya) {
          // A placeholder row seeded before descriptions existed keeps its empty
          // one otherwise, and there are 375 of them.
          food.itemDescription = dravyaDescription(dravya)
          result.updatedDravyaFoods += 1
        }
        if let food = foodByID[dravya.foodId],
           applyDravyaNutrition(dravya.nutrition, to: food) {
          result.nutritionAppliedFoods += 1
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
        if try updateSafetyMetadata(dravya.safety, food: food) {
          result.updatedSafetyFoods += 1
        }
        if updateEdibilityMetadata(dravya, food: food) {
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

      for catalogProfile in seed.catalogProfiles {
        guard foodByID[catalogProfile.foodId] != nil else {
          throw AyurvedaSeederError.missingCatalogFood(catalogProfile.foodId)
        }
        if let profile = profileByID[catalogProfile.id] {
          if profile.seedVersion < seed.seedVersion {
            apply(
              catalogProfile: catalogProfile,
              seedVersion: seed.seedVersion,
              to: profile
            )
            result.updatedProfiles += 1
          }
        } else {
          context.insert(
            makeCatalogProfile(
              catalogProfile,
              seedVersion: seed.seedVersion
            )
          )
          result.insertedProfiles += 1
        }
      }

      for link in seed.links {
        if let existing = linkByFoodID[link.foodId] {
          if existing.dravyaProfileId != link.dravyaProfileId || existing.tier != link.tier {
            existing.dravyaProfileId = link.dravyaProfileId
            existing.tier = link.tier
            result.updatedLinks += 1
          }
        } else {
          context.insert(
            AyurvedaLink(
              id: link.id,
              foodId: link.foodId,
              dravyaProfileId: link.dravyaProfileId,
              tier: link.tier
            )
          )
          result.insertedLinks += 1
        }
        guard let sourceDravya = seedDravyaByID[link.dravyaProfileId],
              let linkedFood = foodByID[link.foodId] else {
          throw AyurvedaSeederError.missingIngredientFood(
            recipeId: link.dravyaProfileId,
            foodId: link.foodId
          )
        }
        if updateEdibilityMetadata(sourceDravya, food: linkedFood) {
          result.updatedSafetyFoods += 1
        }
      }

      for recipe in seed.recipes {
        let recipeFood: FoodItem
        if let existing = foodByID[recipe.foodId] {
          recipeFood = existing
          if updateRecipeFoodMetadata(recipe, food: recipeFood) {
            result.updatedRecipeFoods += 1
          }
          if try updateSafetyMetadata(recipe.safety, food: recipeFood) {
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
          _ = try updateSafetyMetadata(recipe.safety, food: recipeFood)
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
          + "\(result.updatedSafetyFoods) safety rows; applied nutrition to "
          + "\(result.nutritionAppliedFoods) dravya foods; "
          + "deleted \(result.deletedRows) rows "
          + "(\(result.deletedFoods) foods, \(result.deletedProfiles) profiles, "
          + "\(result.deletedLinks) links); remapped \(result.remappedFoodIDs) food ids "
          + "and \(result.remappedFoodReferences) references; "
          + "replaced \(result.replacedIngredientSets) ingredient sets."
      )
      return result
    } catch {
      context.rollback()
      throw error
    }
  }

  /// Writes a sourced per-100 g panel onto a placeholder FoodItem.
  ///
  /// The Python builder has already omitted every source null. Missing keys
  /// therefore remain absent here; they must never be materialized as zero.
  /// A non-recipe FoodItem without an explicit weight is already interpreted
  /// per 100 g, so these values are written without scaling or a weight value.
  @discardableResult
  private static func applyDravyaNutrition(
    _ nutrition: DravyaDTO.Nutrition?,
    to food: FoodItem
  ) -> Bool {
    guard let nutrition, !nutrition.per100g.isEmpty else { return false }

    func nutrient(_ key: String) -> Nutrient? {
      guard let value = nutrition.per100g[key],
            let unit = nutrition.units[key] else { return nil }
      return Nutrient(value: value, unit: unit)
    }

    let macros = MacronutrientsData(
      id: nutrition.payloadIds.macronutrients,
      carbohydrates: nutrient("carbohydrates"),
      protein: nutrient("protein"),
      fat: nutrient("fat"),
      fiber: nutrient("fiber"),
      totalSugars: nutrient("totalSugars")
    )
    let vitamins = VitaminsData(
      id: nutrition.payloadIds.vitamins,
      vitaminA_RAE: nutrient("vitaminA_RAE"),
      retinol: nutrient("retinol"),
      caroteneAlpha: nutrient("caroteneAlpha"),
      caroteneBeta: nutrient("caroteneBeta"),
      cryptoxanthinBeta: nutrient("cryptoxanthinBeta"),
      luteinZeaxanthin: nutrient("luteinZeaxanthin"),
      lycopene: nutrient("lycopene"),
      vitaminB1_Thiamin: nutrient("vitaminB1_Thiamin"),
      vitaminB2_Riboflavin: nutrient("vitaminB2_Riboflavin"),
      vitaminB3_Niacin: nutrient("vitaminB3_Niacin"),
      vitaminB5_PantothenicAcid: nutrient("vitaminB5_PantothenicAcid"),
      vitaminB6: nutrient("vitaminB6"),
      folateDFE: nutrient("folateDFE"),
      folateFood: nutrient("folateFood"),
      folateTotal: nutrient("folateTotal"),
      folicAcid: nutrient("folicAcid"),
      vitaminB12: nutrient("vitaminB12"),
      vitaminC: nutrient("vitaminC"),
      vitaminD: nutrient("vitaminD"),
      vitaminE: nutrient("vitaminE"),
      vitaminK: nutrient("vitaminK"),
      choline: nutrient("choline")
    )
    let minerals = MineralsData(
      id: nutrition.payloadIds.minerals,
      calcium: nutrient("calcium"),
      iron: nutrient("iron"),
      magnesium: nutrient("magnesium"),
      phosphorus: nutrient("phosphorus"),
      potassium: nutrient("potassium"),
      sodium: nutrient("sodium"),
      selenium: nutrient("selenium"),
      zinc: nutrient("zinc"),
      copper: nutrient("copper"),
      manganese: nutrient("manganese"),
      fluoride: nutrient("fluoride")
    )

    food.macronutrients = macros
    food.vitamins = vitamins
    food.minerals = minerals
    food.other = OtherCompoundsData(
      id: nutrition.payloadIds.other,
      energyKcal: nutrient("energyKcal")
    )
    return true
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
    guard seed.counts.dravyas == 704,
      seed.counts.recipes == 1_511,
      seed.counts.catalogProfiles == 10_265,
      seed.counts.links == 2_336,
      seed.counts.derivedLinks == 1_966,
      seed.counts.placeholders == 375,
      seed.counts.categoryRules == 187,
      seed.counts.modifiers == 14,
      seed.counts.nutrition.full
        + seed.counts.nutrition.estimated
        + seed.counts.nutrition.none == seed.counts.recipes,
      seed.counts.safety.profiles == seed.counts.dravyas + seed.counts.recipes,
      seed.counts.safety.authoredAgeDravyas == 390,
      seed.counts.safety.legacyImportAgeDravyas == 314,
      seed.counts.safety.authoredAgeRecipes == 1_457,
      seed.counts.safety.legacyImportAgeRecipes == 54,
      seed.counts.safety.ageContributors == 10_644,
      seed.dravyas.count == seed.counts.dravyas,
      seed.recipes.count == seed.counts.recipes,
      seed.catalogProfiles.count == seed.counts.catalogProfiles,
      seed.links.count == seed.counts.links,
      seed.links.filter({ $0.tier == "derived" }).count == seed.counts.derivedLinks,
      seed.dravyas.filter(\.foodIsPlaceholder).count == seed.counts.placeholders
    else {
      throw AyurvedaSeederError.invalidCounts
    }
    guard seed.recipes.allSatisfy({ !$0.ingredients.isEmpty }) else {
      throw AyurvedaSeederError.emptyRecipeIngredients
    }
    guard seed.catalogProfiles.allSatisfy({
      $0.key.hasPrefix("catalog.usda.")
        && (-2...2).contains($0.dosha.vata)
        && (-2...2).contains($0.dosha.pitta)
        && (-2...2).contains($0.dosha.kapha)
        && $0.confidenceAyur > 0
        && $0.confidenceAyur <= 1
        && $0.enforcedMinAgeMonths >= 0
    }) else {
      throw AyurvedaSeederError.invalidCatalogProfiles
    }
    let inedibleDravyas = seed.dravyas.filter { !$0.edible }
    guard inedibleDravyas.count == 6,
      inedibleDravyas.allSatisfy({
        $0.engineExcluded
          && ($0.inedibleReason?.isEmpty == false)
          && !$0.servings.isEmpty
      }),
      seed.dravyas.filter(\.engineExcluded).count == 11
    else {
      throw AyurvedaSeederError.invalidSafetyMetadata
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
          && !$0.rules.isEmpty
      })
    else {
      throw AyurvedaSeederError.invalidSafetyMetadata
    }
  }

  private static func makeFoodMap(_ foods: [FoodItem]) throws -> [UUID: FoodItem] {
    var foodByID: [UUID: FoodItem] = [:]
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
  ) throws -> [UUID: AyurvedaProfile] {
    var profileByID: [UUID: AyurvedaProfile] = [:]
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
  ) throws -> [UUID: AyurvedaLink] {
    var linkByFoodID: [UUID: AyurvedaLink] = [:]
    linkByFoodID.reserveCapacity(links.count)
    for link in links {
      guard linkByFoodID.updateValue(link, forKey: link.foodId) == nil else {
        throw AyurvedaSeederError.duplicateLinkFoodId(link.foodId)
      }
    }
    return linkByFoodID
  }

  private static func validateCanonicalOwnership(
    seed: AyurvedaSeedDTO,
    profileByID: [UUID: AyurvedaProfile],
    foodByID: [UUID: FoodItem]
  ) throws {
    for dravya in seed.dravyas {
      if let profile = profileByID[dravya.id] {
        guard profile.kind == "dravya", profile.foodId == dravya.foodId else {
          throw AyurvedaSeederError.canonicalOwnershipConflict(dravya.id)
        }
      }
    }
    for recipe in seed.recipes {
      if let profile = profileByID[recipe.id] {
        guard profile.kind == "recipe", profile.foodId == recipe.foodId else {
          throw AyurvedaSeederError.canonicalOwnershipConflict(recipe.id)
        }
      }
    }
    for catalogProfile in seed.catalogProfiles {
      if let profile = profileByID[catalogProfile.id] {
        guard profile.kind == "catalog",
          profile.foodId == catalogProfile.foodId
        else {
          throw AyurvedaSeederError.canonicalOwnershipConflict(
            catalogProfile.id
          )
        }
      } else if foodByID[catalogProfile.foodId] == nil {
        throw AyurvedaSeederError.missingCatalogFood(catalogProfile.foodId)
      }
    }
  }

  private static func storeHasCurrentSeed(
    seed: AyurvedaSeedDTO,
    profileByID: [UUID: AyurvedaProfile],
    linkByFoodID: [UUID: AyurvedaLink],
    foodByID: [UUID: FoodItem]
  ) -> Bool {
    let dravyasAreCurrent = seed.dravyas.allSatisfy { dravya in
      guard let profile = profileByID[dravya.id] else {
        return false
      }
      return profile.kind == "dravya"
        && profile.foodId == dravya.foodId
        && profile.seedVersion >= seed.seedVersion
        && profile.edible == dravya.edible
        && profile.inedibleReason == dravya.inedibleReason
        && foodByID[dravya.foodId].map {
          edibilityMetadataMatches(dravya, food: $0)
        } == true
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

    let catalogProfilesAreCurrent = seed.catalogProfiles.allSatisfy {
      catalogProfile in
      guard
        let profile = profileByID[catalogProfile.id],
        foodByID[catalogProfile.foodId] != nil
      else {
        return false
      }
      return profile.kind == "catalog"
        && profile.foodId == catalogProfile.foodId
        && profile.seedVersion >= seed.seedVersion
    }
    guard catalogProfilesAreCurrent else {
      return false
    }

    let seedDravyaByID = Dictionary(
      uniqueKeysWithValues: seed.dravyas.map { ($0.id, $0) }
    )
    return seed.links.allSatisfy { link in
      guard let existing = linkByFoodID[link.foodId] else {
        return false
      }
      return existing.dravyaProfileId == link.dravyaProfileId
        && existing.tier == link.tier
        && seedDravyaByID[link.dravyaProfileId].map { dravya in
          foodByID[link.foodId].map {
            edibilityMetadataMatches(dravya, food: $0)
          } == true
        } == true
    }
  }

  private static func validateIngredientTargets(
    _ recipes: [RecipeDTO],
    foodByID: [UUID: FoodItem]
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

  private static func safetyMetadataMatches(
    _ safety: SafetyMetadataDTO,
    food: FoodItem
  ) -> Bool {
    let actualAllergens = Set((food.allergens ?? []).map(\.rawValue))
    return actualAllergens == Set(safety.allergens)
      && food.minAgeMonths == safety.minAgeMonths
      && food.ageProvenance == safety.ageProvenance
      && food.ageSource == safety.ageSource
  }

  private static func updateSafetyMetadata(
    _ safety: SafetyMetadataDTO,
    food: FoodItem
  ) throws -> Bool {
    guard !safetyMetadataMatches(safety, food: food) else {
      return false
    }
    food.allergens = try safety.allergens.map { allergenName in
      guard let allergen = Allergen(rawValue: allergenName) else {
        throw AyurvedaSeederError.invalidSafetyAllergen(allergenName)
      }
      return allergen
    }
    food.minAgeMonths = safety.minAgeMonths
    food.ageProvenance = safety.ageProvenance
    food.ageSource = safety.ageSource
    return true
  }

  private static func edibilityMetadataMatches(
    _ dravya: DravyaDTO,
    food: FoodItem
  ) -> Bool {
    food.isEdible == dravya.edible
      && food.inedibleReason == dravya.inedibleReason
      && food.inedibleContraindications
        == (dravya.edible ? [] : dravya.contraindications)
  }

  private static func updateEdibilityMetadata(
    _ dravya: DravyaDTO,
    food: FoodItem
  ) -> Bool {
    guard !edibilityMetadataMatches(dravya, food: food) else {
      return false
    }
    food.isEdible = dravya.edible
    food.inedibleReason = dravya.inedibleReason
    food.inedibleContraindications = dravya.edible
      ? []
      : dravya.contraindications
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
      && food.isEdible
      && food.inedibleReason == nil
      && food.inedibleContraindications.isEmpty
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
    food.isEdible = true
    food.inedibleReason = nil
    food.inedibleContraindications = []
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
    foodByID: [UUID: FoodItem],
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
        id: ingredient.id,
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

  private static func apply(
    catalogProfile: CatalogProfileDTO,
    seedVersion: Int,
    to profile: AyurvedaProfile
  ) {
    copyProfile(
      from: makeCatalogProfile(
        catalogProfile,
        seedVersion: seedVersion
      ),
      to: profile
    )
  }

  private static func copyProfile(
    from source: AyurvedaProfile,
    to destination: AyurvedaProfile
  ) {
    destination.key = source.key
    destination.kind = source.kind
    destination.foodId = source.foodId
    destination.foodIsPlaceholder = source.foodIsPlaceholder
    destination.name = source.name
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
    destination.edible = source.edible
    destination.inedibleReason = source.inedibleReason
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
      key: dravya.key,
      kind: "dravya",
      foodId: dravya.foodId,
      foodIsPlaceholder: dravya.foodIsPlaceholder,
      name: dravya.name,
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
      edible: dravya.edible,
      inedibleReason: dravya.inedibleReason,
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
      servingsJSON: dravya.edible ? servingsJSON : nil,
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
      key: recipe.key,
      kind: "recipe",
      foodId: recipe.foodId,
      foodIsPlaceholder: false,
      name: recipe.name,
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
      edible: true,
      inedibleReason: nil,
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

  private static func makeCatalogProfile(
    _ profile: CatalogProfileDTO,
    seedVersion: Int
  ) -> AyurvedaProfile {
    AyurvedaProfile(
      id: profile.id,
      key: profile.key,
      kind: "catalog",
      foodId: profile.foodId,
      foodIsPlaceholder: false,
      name: profile.name,
      doshaVata: profile.dosha.vata,
      doshaPitta: profile.dosha.pitta,
      doshaKapha: profile.dosha.kapha,
      seasons: [],
      timeOfDay: [],
      viruddha: [],
      provenance: profile.provenance,
      confidenceAyur: profile.confidenceAyur,
      confidenceSci: nil,
      qualityState: profile.qualityState,
      reviewNote: profile.reviewNote,
      engineExcluded: false,
      seedVersion: seedVersion,
      sanskrit: nil,
      aliases: [],
      rasa: [],
      virya: profile.virya,
      vipaka: nil,
      gunas: profile.gunas,
      prabhava: nil,
      agniEffect: nil,
      digestibility: nil,
      combinations: [],
      contraindications: [],
      preparation: nil,
      servingsJSON: nil,
      meal: nil,
      servingsCount: nil,
      prepMinutes: nil,
      cookMinutes: nil,
      steps: [],
      guidance: nil
    )
  }

  private static func encodeNutritionJSON<Value: Encodable>(
    _ value: Value,
    recipeId: UUID,
    encoder: JSONEncoder
  ) throws -> String {
    let data = try encoder.encode(value)
    guard let encoded = String(data: data, encoding: .utf8) else {
      throw AyurvedaSeederError.invalidNutritionJSON(recipeId)
    }
    return encoded
  }

  /// A placeholder dravya has no USDA row to inherit a description from — that
  /// is precisely why it is a placeholder — so it was shipping with an empty
  /// one. The text already exists on the dravya itself: 288 of the 376 carry a
  /// prabhava, and all 376 carry preparation guidance. This surfaces what is
  /// already authored rather than inventing anything.
  private static func dravyaDescription(_ dravya: DravyaDTO) -> String {
    var parts: [String] = []
    if let prabhava = dravya.prabhava?.trimmingCharacters(in: .whitespacesAndNewlines),
       !prabhava.isEmpty {
      parts.append(prabhava)
    }
    if let preparation = dravya.preparation?.trimmingCharacters(in: .whitespacesAndNewlines),
       !preparation.isEmpty {
      parts.append(preparation)
    }
    return parts.joined(separator: "\n\n")
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
  case reservedBandCollision(UUID)
  case duplicateFoodId(UUID)
  case duplicateProfileId(UUID)
  case duplicateLinkFoodId(UUID)
  case canonicalOwnershipConflict(UUID)
  case missingIngredientFood(recipeId: UUID, foodId: UUID)
  case recipeIngredientReference(recipeId: UUID, foodId: UUID)
  case invalidServings(UUID)
  case invalidNutrition
  case invalidCatalogProfiles
  case invalidNutritionJSON(UUID)
  case invalidSafetyMetadata
  case invalidSafetyAllergen(String)
  case missingCatalogFood(UUID)
  case v5MigrationConflict(String)
  case placeholderMigrationConflict(String)
  case placeholderIdentityChanged(String)
  case placeholderCacheCount(expected: Int, actual: Int)

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
    case .duplicateLinkFoodId(let foodId):
      return "the Ayurveda store contains duplicate link foodId \(foodId)"
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
    case .invalidCatalogProfiles:
      return "the Ayurveda seed contains invalid catalogue profiles"
    case .invalidNutritionJSON(let recipeId):
      return "recipe \(recipeId) nutrition cannot be encoded as JSON"
    case .invalidSafetyMetadata:
      return "the Ayurveda seed contains invalid scaffold-default safety metadata"
    case .invalidSafetyAllergen(let allergen):
      return "the Ayurveda seed references unsupported allergen \(allergen)"
    case .missingCatalogFood(let foodId):
      return "catalogue profile references missing FoodItem \(foodId)"
    case .v5MigrationConflict(let profileId):
      return "the Ayurveda v5 migration cannot reconcile profile \(profileId)"
    case .placeholderMigrationConflict(let profileId):
      return "the placeholder migration cannot reconcile profile \(profileId)"
    case .placeholderIdentityChanged(let profileId):
      return "the placeholder migration replaced FoodItem identity for \(profileId)"
    case .placeholderCacheCount(let expected, let actual):
      return "the placeholder migration rebuilt a search cache for \(actual) foods; expected \(expected)"
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
  let catalogProfiles: [CatalogProfileDTO]
  let links: [AyurvedaLinkDTO]
}

private struct AyurvedaSeedCountsDTO: Decodable {
  let dravyas: Int
  let recipes: Int
  let catalogProfiles: Int
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
  let minAgeMonths: Int
  let enforcedMinAgeMonths: Int
  let ageProvenance: String
  let ageSource: String?
  let ageContributors: [AgeContributorDTO]
  let provenance: String
  let reviewRequired: Bool
  let rules: [String]
  let reviewFlags: [String]
}

private struct AgeContributorDTO: Decodable {
  let ingredientId: UUID
  let grams: Double?
  let minAgeMonths: Int
  let enforcedMinAgeMonths: Int
  let ageProvenance: String
  let ageSource: String?
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
  struct Nutrition: Decodable {
    struct PayloadIDs: Decodable {
      let macronutrients: UUID
      let vitamins: UUID
      let minerals: UUID
      let other: UUID
    }

    let status: String
    let per100g: [String: Double]
    let units: [String: String]
    let payloadIds: PayloadIDs
  }

  let id: UUID
  let key: String
  let name: String
  let sanskrit: String?
  let aliases: [String]
  let category: String
  let edible: Bool
  let inedibleReason: String?
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
  let foodId: UUID
  let foodIsPlaceholder: Bool
  let engineExcluded: Bool
  let nutrition: Nutrition?
  let safety: SafetyMetadataDTO
}

private struct RecipeIngredientDTO: Decodable {
  let id: UUID
  let foodId: UUID
  let grams: Double
  let name: String
  let portioned: Bool?
  let contraindications: [String]?
}

private struct RecipeDTO: Decodable {
  let id: UUID
  let key: String
  let name: String
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
  let foodId: UUID
  let nutrition: RecipeNutritionDTO
  let safety: SafetyMetadataDTO
}

private struct CatalogProfileDTO: Decodable {
  let id: UUID
  let key: String
  let name: String
  let foodId: UUID
  let category: String
  let dosha: DoshaDTO
  let virya: String
  let gunas: [String]
  let modifierIds: [String]
  let provenance: [String]
  let confidenceAyur: Double
  let qualityState: String
  let reviewNote: String
  let enforcedMinAgeMonths: Int
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
  let id: UUID
  let foodId: UUID
  let dravyaProfileId: UUID
  let tier: String
}
