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
            uniqueKeysWithValues: links.map { ($0.fdcId, $0) }
        )

        var flattened: [MP5Candidate] = []
        var thermalByFoodID: [Int: String] = [:]
        flattened.reserveCapacity(foods.count)
        for food in foods.sorted(by: { $0.id < $1.id }) {
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
                engineExcluded: excludedByGate.contains(food.id)
            ) else {
                continue
            }
            flattened.append(resolved.candidate)
            thermalByFoodID[food.id] = resolved.thermalCharacter
        }

        let text = (prompts
            + interpretedPrompts.qualitativeGoals
            + interpretedPrompts.structuralRequests)
            .joined(separator: " ")
            .lowercased()
        let profileRequest = MP5SolverProfile(
            dailyKcal: estimatedDailyCalories(for: profile),
            dailyProteinTarget: estimatedDailyProtein(for: profile),
            ageInMonths: profile.ageInMonths,
            diet: canonicalDiet(for: profile),
            allergenConcepts: allergenConcepts(for: profile),
            excludedFoodIDs: exclusions.explicitFoodIDs.union(excludedByGate),
            dosha: inferredDosha(from: text),
            agni: inferredAgni(from: text),
            season: currentRitu(),
            enableAyurvedicScoring: MP5FeatureFlags.ayurvedicSolverEnabled
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

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let solved = try DeterministicMealPlanSolver(
            candidates: flattened
        ).solve(request)
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
                prompt: profileRequest.enableAyurvedicScoring
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
        engineExcluded: Bool
    ) -> (candidate: MP5Candidate, thermalCharacter: String)? {
        let referenceWeight = compact.referenceWeightG
        guard referenceWeight > 0,
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
        let concepts = FoodConcepts.shared.concepts(for: Int32(food.id))
            .union(safetyConcepts(from: compact))
        let roleResolution = FoodRoleResolver.shared.resolution(
            for: food.id
        )
        let roleDefinition = FoodRoleResolver.shared.definition(
            for: roleResolution.role
        )
        let tokens = Set(AyurvedaRules.modifierTokens(food.name))
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
                enforcedMinAgeMonths: compact.enforcedMinAgeMonths,
                engineExcluded: engineExcluded,
                role: roleResolution.role,
                roleAnchor: roleDefinition.anchor,
                roleMaxPerMeal: roleDefinition.maxPerMeal,
                roleEligibleAsComponent: roleDefinition.eligibleAsComponent,
                notReadyToEat: roleResolution.notReadyToEat,
                roleHeadword: roleResolution.headword,
                minimumGrams: roleDefinition.portionGrams.min,
                maximumGrams: roleDefinition.portionGrams.max,
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
                isHeatedHoney: isHeatedHoney
            ),
            resolution.thermalCharacter
        )
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
                tier: .classical
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
        guard let category = food.category?.first?.rawValue else {
            return (
                (0, 0, 0), [], false, false, false, "unrecorded",
                0.5, [], .none
            )
        }
        let estimate = AyurvedaRules.shared.estimated(
            category: category,
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

    private func canonicalDiet(for profile: Profile) -> String {
        let names = profile.diets.map { $0.name.lowercased() }
        if names.contains(where: { $0.contains("vegan") }) { return "vegan" }
        if names.contains(where: {
            $0.contains("jain") || $0.contains("sattvic")
        }) {
            return "jain_sattvic"
        }
        if names.contains(where: { $0.contains("vegetarian") }) {
            return "vegetarian"
        }
        return "omnivore"
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
        var total = base * profile.activityLevel.rawValue
        if profile.isPregnant { total += 300 }
        if profile.isLactating { total += 500 }
        return max(1_000, min(4_500, total.rounded()))
    }

    private func estimatedDailyProtein(for profile: Profile) -> Double {
        let multiplier = profile.goal?.title.lowercased().contains("muscle")
            == true ? 1.6 : 1.0
        return max(45, profile.weight * multiplier)
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
        foodID: Int
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
