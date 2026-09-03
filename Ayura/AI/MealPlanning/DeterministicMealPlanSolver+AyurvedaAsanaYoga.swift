import Foundation
import SwiftData

struct MP5PlannerAssembly {
    let preview: MealPlanPreview
    let narrationFacts: [MP6NarrationFact]
}

@MainActor
struct MP5PlannerAdapter {
    let container: ModelContainer

    func solve(
        profile: Profile,
        daysAndMeals: [Int: [String]],
        prompts: [String],
        interpretedPrompts: InterpretedPrompts,
        exclusions: PlannerConceptExclusions,
        placements: [MP5MustContainRule],
        mealTimings: [String: Date]?,
        onLog: (@Sendable (String) -> Void)?
    ) async throws -> MP5PlannerAssembly {
        await SearchIndexStore.shared.ensureLoaded(container: container)
        let context = ModelContext(container)
        let text = (prompts
            + interpretedPrompts.qualitativeGoals
            + interpretedPrompts.structuralRequests)
            .joined(separator: " ")
            .lowercased()
        let storedTarget = AyurvedaConstitutionStore
            .record(for: profile.id)?
            .target()
        let promptDosha = inferredDosha(from: text)
        let isAyurvedicRequest = storedTarget != nil
            || promptDosha != nil
            || text.contains("ayurved")
        let foods = try context.fetch(FetchDescriptor<FoodItem>())
        let profiles = try context.fetch(FetchDescriptor<AyurvedaProfile>())
        let links = try context.fetch(FetchDescriptor<AyurvedaLink>())
        let excludedByGate = AyurvedaRecommendationGate.excludedFoodIds(
            context: context
        )
        let compactMap = SearchIndexStore.shared.compactMap
        let profileByFoodID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.foodId, $0) }
        )
        let profileByID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.id, $0) }
        )
        let linkByFoodID = Dictionary(
            uniqueKeysWithValues: links.map { ($0.foodId, $0) }
        )
        let priorityNutrientTypes = Set(
            profile.priorityVitamins.compactMap {
                NutrientType.fromID($0.key)
            } + profile.priorityMinerals.compactMap {
                NutrientType.fromID($0.key)
            }
        )

        var flattened: [MP5Candidate] = []
        var thermalByFoodID: [UUID: String] = [:]
        flattened.reserveCapacity(foods.count)
        for food in foods.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let compact = compactMap[food.id],
                  !exclusions.excludes(compact)
            else {
                continue
            }
            guard let resolved = makeCandidate(
                food: food,
                compact: compact,
                directProfile: profileByFoodID[food.id],
                linkedProfile: linkByFoodID[food.id].flatMap {
                    profileByID[$0.dravyaProfileId]
                },
                link: linkByFoodID[food.id],
                engineExcluded: excludedByGate.contains(food.id),
                priorityNutrientTypes: priorityNutrientTypes,
                requestText: text
            ) else {
                continue
            }
            flattened.append(resolved.candidate)
            thermalByFoodID[food.id] = resolved.thermalCharacter
        }

        let fullDailyKcal = estimatedDailyCalories(for: profile)
        let fullDailyProtein = estimatedDailyProtein(for: profile)
        let largestDaySlotCount = daysAndMeals.values.map(\.count).max() ?? 0
        let singleSlotFraction = mealTargetFraction(
            for: daysAndMeals.values.first?.first ?? ""
        )
        let requestedKcal = largestDaySlotCount <= 1
            ? fullDailyKcal * singleSlotFraction
            : fullDailyKcal
        let requestedProtein = largestDaySlotCount <= 1
            ? fullDailyProtein * singleSlotFraction
            : fullDailyProtein
        let profileRequest = MP5SolverProfile(
            dailyKcal: requestedKcal,
            dailyProteinTarget: requestedProtein,
            ageInMonths: profile.ageInMonths,
            allergenConcepts: allergenConcepts(for: profile),
            excludedFoodIDs: exclusions.explicitFoodIDs.union(excludedByGate),
            dosha: storedTarget?.ordered.first.flatMap {
                MP5Dosha(rawValue: $0.dosha.rawValue)
            } ?? promptDosha,
            agni: inferredAgni(from: text),
            season: currentRitu(),
            enableAyurvedicScoring: MP5FeatureFlags.ayurvedicSolverEnabled
                || isAyurvedicRequest,
            requestText: text,
            doshaTarget: storedTarget.map {
                MP5DoshaTarget(
                    vata: $0.vata,
                    pitta: $0.pitta,
                    kapha: $0.kapha
                )
            }
        )
        let slots = daysAndMeals.keys.sorted().flatMap { day in
            (daysAndMeals[day] ?? []).map {
                MP5MealSlot(day: day, name: $0)
            }
        }
        let seed = deterministicSeed(
            prompts: prompts,
            daysAndMeals: daysAndMeals
        )
        let request = MP5SolverRequest(
            profile: profileRequest,
            slots: slots,
            mustContain: placements,
            seed: seed
        )
        onLog?(
            "🧭 MP-5 assembly: flag "
                + "\(MP5FeatureFlags.ayurvedicSolverFlagName)="
                + "\(profileRequest.enableAyurvedicScoring); "
                + "\(flattened.count) safe candidates; seed \(seed)"
        )
        let priorities = (profile.priorityVitamins.map(\.name)
            + profile.priorityMinerals.map(\.name)).sorted()
        let prioritySummary = priorities.isEmpty ? ["none"] : priorities
        onLog?(
            "👤 Meal profile context: age \(profile.age), gender \(profile.gender), "
                + String(format: "%.1f kg, %.1f cm; ", profile.weight, profile.height)
                + "allergens: \(profile.allergens.map(\.rawValue).sorted()); "
                + "priority nutrients: \(prioritySummary)"
        )

        let startedAt = DispatchTime.now().uptimeNanoseconds
        var solved: MP5SolvedPlan
        do {
            solved = try DeterministicMealPlanSolver(
                candidates: flattened
            ).solve(request)
        } catch let failure as MP5SolverFailure {
            onLog?("❌ \(failure.description)")
            throw failure
        }
        solved = enrichSparseMeals(
            solved,
            candidates: flattened,
            profile: profileRequest
        )
        let elapsedMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - startedAt
        ) / 1_000_000
        onLog?(
            String(
                format: "✅ MP-5 deterministic assembly completed in %.3f ms",
                elapsedMilliseconds
            )
        )

        let days = solved.days.map { day in
            MealPlanPreviewDay(
                dayIndex: day.day,
                meals: day.meals.map { meal in
                    MealPlanPreviewMeal(
                        name: meal.name,
                        descriptiveTitle: meal.name,
                        items: meal.components.enumerated().map {
                            componentIndex,
                            component in
                            MealPlanPreviewItem(
                                id: deterministicUUID(
                                    seed: seed,
                                    day: day.day,
                                    meal: meal.name,
                                    componentIndex: componentIndex,
                                    foodID: component.foodID
                                ),
                                name: component.name,
                                grams: component.grams,
                                kcal: component.kcal
                            )
                        },
                        startTime: mealTimings?.first {
                            $0.key.caseInsensitiveCompare(meal.name)
                                == .orderedSame
                        }?.value
                    )
                }
            )
        }
        let minAgeMonths = solved.components.compactMap {
            compactMap[$0.foodID]?.enforcedMinAgeMonths
        }.max() ?? 0
        let facts = solved.days.flatMap { day in
            day.meals.enumerated().map { slotIndex, meal in
                let thermalValues = Set(
                    meal.components.compactMap {
                        thermalByFoodID[$0.foodID]
                    }.filter { $0 != "unrecorded" }
                )
                let thermalCharacter: String
                if thermalValues.isEmpty {
                    thermalCharacter = "unrecorded"
                } else if thermalValues.count == 1 {
                    thermalCharacter = thermalValues.first ?? "unrecorded"
                } else {
                    thermalCharacter = "mixed"
                }
                return MP6NarrationFact(
                    day: day.day,
                    slotIndex: slotIndex,
                    slotName: meal.name,
                    dishNames: meal.components.map(\.name),
                    kcal: meal.kcal,
                    proteinGrams: meal.protein,
                    tastes: Set(
                        meal.components.flatMap(\.rasa)
                    ).sorted(),
                    thermalCharacter: thermalCharacter,
                    agni: profileRequest.agni.rawValue
                )
            }
        }
        return MP5PlannerAssembly(
            preview: MealPlanPreview(
                startDate: Calendar.current.startOfDay(for: Date()),
                prompt: isAyurvedicRequest
                    ? "Deterministic Ayurvedic meal plan"
                    : "Deterministic meal plan",
                days: days,
                minAgeMonths: minAgeMonths
            ),
            narrationFacts: facts
        )
    }

    private func makeCandidate(
        food: FoodItem,
        compact: CompactFoodItem,
        directProfile: AyurvedaProfile?,
        linkedProfile: AyurvedaProfile?,
        link: AyurvedaLink?,
        engineExcluded: Bool,
        priorityNutrientTypes: Set<NutrientType>,
        requestText: String
    ) -> (candidate: MP5Candidate, thermalCharacter: String)? {
        guard !isLowQualityPlannerCandidate(food.name),
              isCompatibleWithRequestedTradition(
                food.name,
                requestText: requestText
              )
        else {
            return nil
        }
        let referenceWeight = compact.referenceWeightG
        guard referenceWeight > 0,
              compact.isEdible,
              let enforcedMinAgeMonths = compact.enforcedMinAgeMonths,
              let rawEnergy = compact.nutrientValues[.energy],
              rawEnergy > 0
        else {
            return nil
        }
        let scale = 100 / referenceWeight
        let resolution = ayurvedicResolution(
            food: food,
            directProfile: directProfile,
            linkedProfile: linkedProfile,
            link: link
        )
        let concepts = FoodConcepts.shared.concepts(for: food.id)
            .union(safetyConcepts(from: compact))
        let roleResolution = FoodRoleResolver.shared.resolution(
            for: food.id
        )
        let tokens = Set(AyurvedaRules.modifierTokens(food.name))
        let correctedRole = correctedRole(
            name: food.name,
            nameTokens: tokens,
            resolved: roleResolution.role
        )
        let roleDefinition = FoodRoleResolver.shared.definition(
            for: correctedRole
        )
        let correctedPortion = correctedPortionLimits(
            name: food.name,
            nameTokens: tokens,
            definition: roleDefinition
        )
        let isHoney = concepts.contains("honey") || tokens.contains("honey")
        let isGhee = tokens.contains("ghee")
            || (tokens.contains("clarified") && tokens.contains("butter"))
        let isHeatedHoney = isHoney && !tokens.isDisjoint(
            with: ["heated", "cooked", "baked", "boiled", "warmed"]
        )

        return (
            MP5Candidate(
                id: food.id,
                name: food.name,
                kcalPer100g: rawEnergy * scale,
                proteinPer100g: (compact.nutrientValues[.protein] ?? 0) * scale,
                carbsPer100g: (compact.nutrientValues[.carbs] ?? 0) * scale,
                fatPer100g: (compact.nutrientValues[.totalFat] ?? 0) * scale,
                fiberPer100g: (compact.nutrientValues[.fiber] ?? 0) * scale,
                concepts: concepts,
                enforcedMinAgeMonths: enforcedMinAgeMonths,
                engineExcluded: engineExcluded,
                role: correctedRole,
                roleAnchor: roleDefinition.anchor,
                roleMaxPerMeal: roleDefinition.maxPerMeal,
                roleEligibleAsComponent: roleDefinition.eligibleAsComponent,
                notReadyToEat: roleResolution.notReadyToEat,
                roleHeadword: normalizedPlannerHeadword(
                    name: food.name,
                    fallback: roleResolution.headword
                ),
                minimumGrams: correctedPortion.minimum,
                maximumGrams: correctedPortion.maximum,
                doshaVata: resolution.vpk.vata,
                doshaPitta: resolution.vpk.pitta,
                doshaKapha: resolution.vpk.kapha,
                rasa: resolution.rasa,
                hasVipaka: resolution.hasVipaka,
                hasVirya: resolution.hasVirya,
                hasPrabhava: resolution.hasPrabhava,
                heaviness: resolution.heaviness,
                seasons: resolution.seasons,
                tier: resolution.tier,
                isHoney: isHoney,
                isGhee: isGhee,
                isHeatedHoney: isHeatedHoney,
                priorityNutrientScore: priorityNutrientScore(
                    values: compact.nutrientValues,
                    referenceWeight: referenceWeight,
                    priorities: priorityNutrientTypes
                )
            ),
            resolution.thermalCharacter
        )
    }

    private func correctedRole(
        name: String,
        nameTokens: Set<String>,
        resolved: FoodRole
    ) -> FoodRole {
        let lower = name.lowercased()
        let seasoningTokens: Set<String> = [
            "seed", "seeds", "spice", "spices", "seasoning", "tempering",
            "cumin", "pepper", "turmeric", "masala", "radhuni", "posto",
            "sesame", "poppy", "mustard", "garlic"
        ]
        let concentratedSeasoning = lower.contains("dried")
            || lower.contains("powder")
            || lower.contains("ground")
        let seasoningPlantTokens: Set<String> = [
            "garlic", "basil", "tulsi", "thyme", "methi", "coriander",
            "parsley", "oregano", "rosemary", "sage", "mint"
        ]
        let dishTokens: Set<String> = [
            "khichdi", "kitchari", "stew", "soup", "curry", "salad",
            "rice", "chicken", "fish", "bowl", "meal", "stir", "fry",
            "roast", "pot", "sabzi", "chivda"
        ]
        let isDirectSeasoning = nameTokens.isDisjoint(with: dishTokens)
            && nameTokens.count <= 5
        let directSeasoningMarkers = [
            "black pepper", "white pepper", "cayenne", "paprika", "cumin",
            "turmeric", "coriander", "cinnamon", "cardamom", "clove",
            "nutmeg", "ginger, ground", "garlic powder", "onion powder"
        ]
        let isPepperVegetable = lower.contains("peppers, sweet")
            || lower.contains("sweet pepper")
            || lower.contains("bell pepper")
        if !isPepperVegetable
            && (directSeasoningMarkers.contains(where: lower.contains)
            || (isDirectSeasoning
                && !nameTokens.isDisjoint(with: seasoningTokens))
            || (concentratedSeasoning
                && !nameTokens.isDisjoint(with: seasoningPlantTokens))) {
            return .spice
        }
        if ["sauce", "dressing", "ketchup", "chutney", "relish"]
            .contains(where: lower.contains) {
            return .condiment
        }
        let fatTokens: Set<String> = ["oil", "butter", "ghee", "margarine", "spread"]
        if !nameTokens.isDisjoint(with: fatTokens) {
            return .fat
        }
        return resolved
    }

    private func correctedPortionLimits(
        name: String,
        nameTokens: Set<String>,
        definition: FoodRoleDefinition
    ) -> (minimum: Double, maximum: Double) {
        let lower = name.lowercased()
        let seedTokens: Set<String> = [
            "seed", "seeds", "radhuni", "posto", "sesame", "poppy", "mustard"
        ]
        let dishTokens: Set<String> = [
            "khichdi", "kitchari", "stew", "soup", "curry", "salad",
            "rice", "chicken", "fish", "bowl", "meal", "stir", "fry",
            "roast", "pot", "sabzi", "chivda"
        ]
        let seasoningMarkers = [
            "pepper", "paprika", "cumin", "turmeric", "coriander", "cinnamon",
            "cardamom", "clove", "nutmeg", "ginger, ground", "garlic powder",
            "onion powder", "seasoning", "spice"
        ]
        let isPepperVegetable = lower.contains("peppers, sweet")
            || lower.contains("sweet pepper")
            || lower.contains("bell pepper")
        if nameTokens.isDisjoint(with: dishTokens),
           !isPepperVegetable,
           seasoningMarkers.contains(where: lower.contains) {
            return (0.5, 10)
        }
        if lower.contains("garlic"),
           (lower.contains("dried") || lower.contains("powder")) {
            return (0.5, 10)
        }
        if lower.contains("dehydrated") {
            return (1, 20)
        }
        if nameTokens.isDisjoint(with: dishTokens),
           (!nameTokens.isDisjoint(with: seedTokens)
                || lower.contains("seed")) {
            return (0.5, 15)
        }
        let legumeTokens: Set<String> = [
            "bean", "beans", "lentil", "lentils", "chickpea", "chickpeas",
            "cowpea", "cowpeas", "pea", "peas", "dal", "mung", "moong"
        ]
        let concentratedMarkers = [
            "dried", "powder", "flour", "starch", "extract", "protein"
        ]
        if (!nameTokens.isDisjoint(with: legumeTokens)
                || ["bean", "lentil", "chickpea", "cowpea", "pea"]
                    .contains(where: lower.contains)),
           !concentratedMarkers.contains(where: lower.contains) {
            return (
                max(50, definition.portionGrams.min),
                max(250, definition.portionGrams.max)
            )
        }
        let grainTokens: Set<String> = [
            "oat", "oats", "rice", "quinoa", "barley", "millet", "bulgur"
        ]
        if !nameTokens.isDisjoint(with: grainTokens),
           nameTokens.isDisjoint(with: dishTokens),
           !lower.contains("cracker"),
           !lower.contains("flour") {
            let minimum = min(80, max(30, definition.portionGrams.min))
            return (minimum, max(minimum, min(120, definition.portionGrams.max)))
        }
        let vegetableTokens: Set<String> = [
            "broccoli", "spinach", "carrot", "tomato", "tomatoes", "pepper",
            "peppers", "zucchini", "cauliflower", "pumpkin", "turnip",
            "cucumber", "cabbage", "eggplant", "okra", "asparagus"
        ]
        let preparedDishMarkers = [
            "salsa", "raita", "sauce", "dressing", "soup", "stew", "curry"
        ]
        if !nameTokens.isDisjoint(with: vegetableTokens),
           !concentratedMarkers.contains(where: lower.contains),
           !preparedDishMarkers.contains(where: lower.contains) {
            return (
                max(50, definition.portionGrams.min),
                max(300, definition.portionGrams.max)
            )
        }
        return (
            definition.portionGrams.min,
            definition.portionGrams.max
        )
    }

    private func isLowQualityPlannerCandidate(_ name: String) -> Bool {
        let lower = name.lowercased()
        let blockedMarkers = [
            "snacks,", "fast foods", "hot pocket", "turnover", "cookie",
            "cake", "candy", "marshmallow", "egg roll", "extruded",
            "nacho cheese", "heavy syrup", "sweet, fluid", "margarine-like",
            "vegetable oil-butter spread", "breadfruit leaf", "corn-based cones",
            "canned, vacuum pack", "alcohol", "liqueur", "cocktail",
            "distilled beverage", "candied", "confection", "popcorn",
            "gelatin dessert", "ice cream", "pudding", "doughnut", "donut",
            "pastry", "pie filling", "soft drink", "energy drink", "sandwich",
            "fries", "wonton", "dumpling", "pot sticker", "pupusa", "pizza",
            "burger", "sausage", "bacon", "rotisserie", "barbecue", "bbq",
            "halwa", "fritter", "breaded", "battered", "sweet and sour",
            "pasta with tomato-based sauce and cheese", "variety meats",
            "brain", "tripe", "sweetbread", "pork hash", "corned beef hash",
            "cereal bar", "protein bar", "pretzel", "dry mix", "from frozen",
            "gravy", "macaroni and cheese", "fried", "coated",
            "with added sugar", "yolk only", "pokeberry", "poke shoots",
            "raw banana (plantain)"
        ]
        let rawAnimalMarkers = [
            "beef", "pork", "chicken", "turkey", "lamb", "goat", "duck",
            "fish", "salmon", "tuna", "cod", "meat"
        ]
        if lower.contains("raw"),
           rawAnimalMarkers.contains(where: lower.contains) {
            return true
        }
        return blockedMarkers.contains(where: lower.contains)
    }

    private func isCompatibleWithRequestedTradition(
        _ name: String,
        requestText: String
    ) -> Bool {
        let lower = name.lowercased()
        if requestText.contains("balanced") {
            let simplePreparationMarkers = [
                "raw", "cooked", "boiled", "steamed", "baked", "grilled",
                "roasted"
            ]
            let wholeFoodMarkers = [
                "rice", "oat", "lentil", "bean", "chickpea",
                "pea", "yogurt", "tofu", "egg", "chicken", "turkey", "fish",
                "beef", "pork", "milk", "cheese", "bread", "pasta", "potato",
                "tomato", "cucumber", "carrot", "spinach", "broccoli",
                "zucchini", "pepper", "cabbage", "cauliflower", "pumpkin",
                "apple", "pear", "orange", "banana", "berry", "berries",
                "peach", "nectarine", "plum", "pomegranate", "avocado"
            ]
            let wholesomeDishMarkers = [
                "stew", "curry", "sabzi", "pilaf", "kitchari", "khichdi",
                " dal", "roast", "toor", "bowl"
            ]
            let isSimpleWholeFood = simplePreparationMarkers.contains(
                where: lower.contains
            ) && wholeFoodMarkers.contains(where: lower.contains)
            guard isSimpleWholeFood
                    || wholesomeDishMarkers.contains(where: lower.contains)
            else {
                return false
            }
        }
        guard requestText.contains("vata") else { return true }
        let unsuitableMarkers = [
            "cooking spray", "creamed", "omelet", "scrambled", "fried",
            "salsa", "raita", "duck", "beef", "pork", "cold", "raw",
            "dehydrated", "puffed", "makhana", "wasabi", "cracker", "bran",
            "crude", "chicken", "turkey", "fish", "meat", "puerto rican",
            "veal", "lamb", "goat", "shellfish", "seafood"
        ]
        guard !unsuitableMarkers.contains(where: lower.contains) else {
            return false
        }
        let tokens = Set(AyurvedaRules.modifierTokens(name))
        let tokenMarkers: Set<String> = [
            "rice", "mung", "moong", "dal", "lentil", "lentils", "oat",
            "oats", "ghee", "ginger", "garlic", "cumin", "turmeric",
            "coriander", "yam", "pumpkin", "carrot", "zucchini", "turnip",
            "spinach", "pea", "peas", "khichdi", "kitchari",
            "stew"
        ]
        return !tokens.isDisjoint(with: tokenMarkers)
            || lower.contains("sweet potato")
    }

    private func normalizedPlannerHeadword(
        name: String,
        fallback: String
    ) -> String {
        let lower = name.lowercased()
        let groups: [(key: String, markers: [String])] = [
            ("sweet-potato", ["sweet potato"]),
            ("oat", ["oat"]),
            ("rice", ["rice"]),
            ("mung", ["mung", "moong"]),
            ("lentil", ["lentil", "dal"]),
            ("chickpea", ["chickpea", "garbanzo"]),
            ("bean", ["bean", "cowpea"]),
            ("egg", ["egg"]),
            ("chicken", ["chicken"]),
            ("beef", ["beef", "steak"]),
            ("fish", ["fish", "salmon", "tuna", "cod"]),
            ("yogurt", ["yogurt", "yoghurt"]),
            ("tomato", ["tomato"]),
            ("carrot", ["carrot"]),
            ("spinach", ["spinach"]),
            ("broccoli", ["broccoli"]),
            ("cauliflower", ["cauliflower"]),
            ("pumpkin", ["pumpkin"]),
            ("apple", ["apple"])
        ]
        return groups.first(where: { group in
            group.markers.contains(where: lower.contains)
        })?.key ?? fallback
    }

    private func mealTargetFraction(for slotName: String) -> Double {
        let lower = slotName.lowercased()
        if lower.contains("breakfast") { return 0.25 }
        if lower.contains("snack") { return 0.15 }
        if lower.contains("lunch") || lower.contains("dinner") { return 0.35 }
        return 0.33
    }

    private func enrichSparseMeals(
        _ input: MP5SolvedPlan,
        candidates: [MP5Candidate],
        profile: MP5SolverProfile
    ) -> MP5SolvedPlan {
        var output = input
        var usedIDs = Set(output.components.map(\.foodID))
        let preferredMarkers: [String]
        if profile.requestText.contains("mediterranean") {
            preferredMarkers = [
                "tomato", "cucumber", "zucchini", "pepper", "spinach"
            ]
        } else if profile.requestText.contains("vata") {
            preferredMarkers = [
                "pumpkin", "carrot", "turnip", "spinach", "zucchini",
                "sweet potato"
            ]
        } else {
            preferredMarkers = [
                "broccoli", "spinach", "carrot", "tomato", "pepper",
                "zucchini", "cauliflower"
            ]
        }
        let sideCandidates = candidates.filter { candidate in
            !usedIDs.contains(candidate.id)
                && candidate.role == .side
                && candidate.roleEligibleAsComponent
                && !candidate.notReadyToEat
                && !candidate.engineExcluded
                && candidate.enforcedMinAgeMonths <= profile.ageInMonths
                && candidate.concepts.isDisjoint(with: profile.allergenConcepts)
                && preferredMarkers.contains(where: {
                    candidate.name.lowercased().contains($0)
                })
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        for dayIndex in output.days.indices {
            for mealIndex in output.days[dayIndex].meals.indices {
                var meal = output.days[dayIndex].meals[mealIndex]
                guard meal.components.count < 3,
                      let side = sideCandidates.first(where: {
                          !usedIDs.contains($0.id)
                      })
                else { continue }
                let sideGrams = min(
                    side.maximumGrams,
                    max(side.minimumGrams, 100)
                )
                let sideKcal = side.kcalPerGram * sideGrams
                guard let anchorIndex = meal.components.indices.max(by: {
                    meal.components[$0].kcal < meal.components[$1].kcal
                }),
                let anchor = candidates.first(where: {
                    $0.id == meal.components[anchorIndex].foodID
                }), anchor.kcalPerGram > 0
                else { continue }
                let adjustedAnchorGrams = meal.components[anchorIndex].grams
                    - sideKcal / anchor.kcalPerGram
                guard adjustedAnchorGrams >= anchor.minimumGrams else {
                    continue
                }
                meal.components[anchorIndex] = solvedComponent(
                    anchor,
                    grams: adjustedAnchorGrams,
                    dosha: profile.dosha
                )
                meal.components.append(
                    solvedComponent(
                        side,
                        grams: sideGrams,
                        dosha: profile.dosha
                    )
                )
                output.days[dayIndex].meals[mealIndex] = meal
                usedIDs.insert(side.id)
            }
        }
        return output
    }

    private func solvedComponent(
        _ candidate: MP5Candidate,
        grams: Double,
        dosha: MP5Dosha?
    ) -> MP5SolvedComponent {
        let factor = grams / 100
        return MP5SolvedComponent(
            foodID: candidate.id,
            name: candidate.name,
            grams: grams,
            kcal: candidate.kcalPer100g * factor,
            protein: candidate.proteinPer100g * factor,
            carbs: candidate.carbsPer100g * factor,
            fat: candidate.fatPer100g * factor,
            fiber: candidate.fiberPer100g * factor,
            doshaEffect: candidate.doshaEffect(dosha),
            heaviness: candidate.heaviness,
            rasa: candidate.rasa,
            tier: candidate.tier
        )
    }

    private func priorityNutrientScore(
        values: [NutrientType: Double],
        referenceWeight: Double,
        priorities: Set<NutrientType>
    ) -> Double {
        guard referenceWeight > 0, !priorities.isEmpty else { return 0 }
        let per100Scale = 100 / referenceWeight
        let scores = priorities.compactMap { nutrient -> Double? in
            guard let amount = values[nutrient], amount > 0,
                  let dailyReference = priorityDailyReference[nutrient]
            else { return nil }
            return min(2, amount * per100Scale / dailyReference)
        }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(priorities.count)
    }

    private var priorityDailyReference: [NutrientType: Double] {
        [
            .vitaminA: 900, .vitaminC: 90, .vitaminD: 20,
            .vitaminE: 15, .vitaminK: 120, .thiamin: 1.2,
            .riboflavin: 1.3, .niacin: 16, .pantothenicAcid: 5,
            .vitaminB6: 1.7, .vitaminB12: 2.4, .folateDFE: 400,
            .folateFood: 400, .folateTotal: 400, .folicAcid: 400,
            .choline: 550, .calcium: 1_000, .iron: 18,
            .magnesium: 420, .phosphorus: 700, .potassium: 4_700,
            .sodium: 2_300, .selenium: 55, .zinc: 11,
            .copper: 0.9, .manganese: 2.3, .fluoride: 4
        ]
    }

    private func ayurvedicResolution(
        food: FoodItem,
        directProfile: AyurvedaProfile?,
        linkedProfile: AyurvedaProfile?,
        link: AyurvedaLink?
    ) -> (
        vpk: DoshaVPK,
        rasa: Set<String>,
        hasVipaka: Bool,
        hasVirya: Bool,
        hasPrabhava: Bool,
        thermalCharacter: String,
        heaviness: Double,
        seasons: Set<String>,
        tier: MP5AyurvedaTier
    ) {
        if let profile = directProfile {
            return profileComponents(
                profile,
                vpk: (
                    profile.doshaVata,
                    profile.doshaPitta,
                    profile.doshaKapha
                ),
                tier: profile.kind == "catalog" ? .derived : .classical
            )
        }
        if let profile = linkedProfile, let link {
            let base: DoshaVPK = (
                profile.doshaVata,
                profile.doshaPitta,
                profile.doshaKapha
            )
            let vpk = link.tier == "derived"
                ? AyurvedaRules.adjustedVPK(
                    base: base,
                    modifiers: AyurvedaRules.shared.modifiers(forName: food.name)
                )
                : base
            return profileComponents(
                profile,
                vpk: vpk,
                tier: link.tier == "derived" ? .derived : .classical
            )
        }
        let estimate = AyurvedaRules.shared.estimated(
            name: food.name
        )
        return (
            estimate.vpk,
            [],
            false,
            !estimate.virya.isEmpty,
            false,
            normalizedThermalCharacter(estimate.virya),
            heaviness(from: estimate.gunas, digestibility: nil),
            [],
            .estimated
        )
    }

    private func profileComponents(
        _ profile: AyurvedaProfile,
        vpk: DoshaVPK,
        tier: MP5AyurvedaTier
    ) -> (
        vpk: DoshaVPK,
        rasa: Set<String>,
        hasVipaka: Bool,
        hasVirya: Bool,
        hasPrabhava: Bool,
        thermalCharacter: String,
        heaviness: Double,
        seasons: Set<String>,
        tier: MP5AyurvedaTier
    ) {
        (
            vpk,
            Set(profile.rasa.map { AyurvedaFacet.normalize($0) }),
            !(profile.vipaka ?? "").isEmpty,
            !(profile.virya ?? "").isEmpty,
            !(profile.prabhava ?? "").isEmpty,
            normalizedThermalCharacter(profile.virya ?? ""),
            heaviness(
                from: profile.gunas,
                digestibility: profile.digestibility
            ),
            Set(profile.seasons.map { AyurvedaFacet.normalize($0) }),
            tier
        )
    }

    private func normalizedThermalCharacter(_ raw: String) -> String {
        let normalized = AyurvedaFacet.normalize(raw)
        if ["heating", "hot", "ushna"].contains(normalized) {
            return "heating"
        }
        if ["cooling", "cold", "sheeta", "shita"].contains(normalized) {
            return "cooling"
        }
        if ["neutral", "balanced"].contains(normalized) {
            return "neutral"
        }
        return normalized.isEmpty ? "unrecorded" : normalized
    }

    private func heaviness(
        from gunas: [String],
        digestibility: Int?
    ) -> Double {
        if let digestibility {
            return min(1, max(0, Double(5 - digestibility) / 4))
        }
        let normalized = Set(gunas.map { AyurvedaFacet.normalize($0) })
        if normalized.contains("guru") || normalized.contains("heavy") {
            return 0.85
        }
        if normalized.contains("laghu") || normalized.contains("light") {
            return 0.2
        }
        return 0.5
    }

    private func safetyConcepts(
        from compact: CompactFoodItem
    ) -> Set<String> {
        var concepts = Set<String>()
        for allergen in compact.allergens {
            let lower = allergen.lowercased()
            if lower.contains("milk") { concepts.insert("dairy") }
            if lower.contains("egg") { concepts.insert("egg") }
            if lower.contains("cereals containing gluten") {
                concepts.insert("gluten")
            }
            if lower.contains("soy") { concepts.insert("soy") }
            if lower.contains("sesame") { concepts.insert("sesame") }
            if lower.contains("peanut") { concepts.insert("peanut") }
            if lower == "nuts" || lower.hasPrefix("nuts (") {
                concepts.insert("tree_nuts")
            }
            if lower.contains("fish") { concepts.insert("fish") }
            if lower.contains("crustacean") {
                concepts.formUnion(["crustacean", "shellfish"])
            }
            if lower.contains("mollusc") {
                concepts.formUnion(["mollusc", "shellfish"])
            }
        }
        return concepts
    }

    private func allergenConcepts(for profile: Profile) -> Set<String> {
        var concepts = Set<String>()
        for allergen in profile.allergens {
            let lower = allergen.rawValue.lowercased()
            if lower.contains("milk") { concepts.insert("dairy") }
            if lower.contains("egg") { concepts.insert("egg") }
            if lower.contains("cereals containing gluten") {
                concepts.insert("gluten")
            }
            if lower.contains("soy") { concepts.insert("soy") }
            if lower.contains("sesame") { concepts.insert("sesame") }
            if lower.contains("peanut") { concepts.insert("peanut") }
            if lower == "nuts" || lower.hasPrefix("nuts (") {
                concepts.insert("tree_nuts")
            }
            if lower.contains("fish") { concepts.insert("fish") }
            if lower.contains("crustacean") {
                concepts.formUnion(["crustacean", "shellfish"])
            }
            if lower.contains("mollusc") {
                concepts.formUnion(["mollusc", "shellfish"])
            }
        }
        return concepts
    }

    private func inferredDosha(from text: String) -> MP5Dosha? {
        let tokens = Set(AyurvedaRules.modifierTokens(text))
        if tokens.contains("vata") { return .vata }
        if tokens.contains("pitta") { return .pitta }
        if tokens.contains("kapha") { return .kapha }
        return nil
    }

    private func inferredAgni(from text: String) -> MP5Agni {
        let tokens = Set(AyurvedaRules.modifierTokens(text))
        if !tokens.isDisjoint(with: ["slow", "sluggish", "heavy"]) {
            return .slow
        }
        if !tokens.isDisjoint(with: ["sharp", "acid", "burning"]) {
            return .sharp
        }
        if !tokens.isDisjoint(with: ["irregular", "erratic", "variable"]) {
            return .irregular
        }
        return .balanced
    }

    private func estimatedDailyCalories(for profile: Profile) -> Double {
        let age = Calendar.current.dateComponents(
            [.year],
            from: profile.birthday,
            to: .now
        ).year ?? 30
        let weight = max(20, profile.weight)
        let height = max(120, profile.height)
        let base = profile.gender.lowercased() == "female"
            ? 10 * weight + 6.25 * height - 5 * Double(age) - 161
            : 10 * weight + 6.25 * height - 5 * Double(age) + 5
        let total = base * 1.2
        return max(1_000, min(4_500, total.rounded()))
    }

    private func estimatedDailyProtein(for profile: Profile) -> Double {
        max(45, profile.weight)
    }

    private func currentRitu() -> String {
        switch Calendar.current.component(.month, from: Date()) {
        case 1, 2: return "shishira"
        case 3, 4: return "vasanta"
        case 5, 6: return "grishma"
        case 7, 8: return "varsha"
        case 9, 10: return "sharad"
        default: return "hemanta"
        }
    }

    private func deterministicSeed(
        prompts: [String],
        daysAndMeals: [Int: [String]]
    ) -> UInt64 {
        if let override = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("-mp5Seed=")
        })?.split(separator: "=", maxSplits: 1).last,
           let value = UInt64(override) {
            return value
        }
        let structure = daysAndMeals.keys.sorted().map { day in
            "\(day):\((daysAndMeals[day] ?? []).joined(separator: ","))"
        }.joined(separator: "|")
        return fnv1a64(
            (prompts.joined(separator: "\n") + "|" + structure).lowercased()
        )
    }

    private func deterministicUUID(
        seed: UInt64,
        day: Int,
        meal: String,
        componentIndex: Int,
        foodID: UUID
    ) -> UUID {
        let first = fnv1a64(
            "\(seed)|\(day)|\(meal)|\(componentIndex)|\(foodID)"
        )
        let second = fnv1a64(
            "\(foodID)|\(componentIndex)|\(meal)|\(day)|\(seed)"
        )
        let value = String(
            format: "%016llx%016llx",
            first,
            second
        )
        let uuidString = String(value.prefix(8)) + "-"
            + String(value.dropFirst(8).prefix(4)) + "-"
            + String(value.dropFirst(12).prefix(4)) + "-"
            + String(value.dropFirst(16).prefix(4)) + "-"
            + String(value.dropFirst(20).prefix(12))
        return UUID(uuidString: uuidString) ?? UUID()
    }

    private func fnv1a64(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(0xcbf29ce484222325)) {
            ($0 ^ UInt64($1)) &* 0x100000001b3
        }
    }
}
