import Foundation

// MARK: - MP-5 feature boundary

/// The vaidya-gated objective is deliberately off by default. The deterministic
/// structural assembler remains active in both modes so the former LLM repair
/// pipeline can stay deleted; this switch controls whether aiDraft Ayurvedic
/// scoring is allowed to influence selection.
enum MP5FeatureFlags {
    static let ayurvedicSolverFlagName = "MP5AyurvedicSolverEnabled"
    static let launchArgument = "-mp5AyurvedicSolver"

    static var ayurvedicSolverEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || UserDefaults.standard.bool(forKey: ayurvedicSolverFlagName)
    }
}

enum MP5Dosha: String, Codable, Sendable {
    case vata, pitta, kapha
}

enum MP5Agni: String, Codable, Sendable {
    case balanced, irregular, sharp, slow
}

enum MP5AyurvedaTier: String, Codable, Sendable {
    case classical, derived, estimated, none
}

enum FoodRole: String, Codable, CaseIterable, Sendable {
    case main
    case staple
    case side
    case beverage
    case spice
    case herb
    case medicinalHerb
    case condiment
    case fat
    case sweet
    case supplement
    case infantProduct
    case ingredientOnly
    case nonFood
    case other
}

/// A.H.Su.9/24–25: rasa < vipaka < virya < prabhava. Construction fails
/// instead of permitting a caller to invert the classical precedence.
struct MP5AyurvedicWeights: Equatable, Sendable {
    let rasa: Double
    let vipaka: Double
    let virya: Double
    let prabhava: Double

    init(
        rasa: Double = 1,
        vipaka: Double = 2,
        virya: Double = 4,
        prabhava: Double = 8
    ) {
        precondition(
            rasa < vipaka && vipaka < virya && virya < prabhava,
            "Ayurvedic precedence must remain rasa < vipaka < virya < prabhava"
        )
        self.rasa = rasa
        self.vipaka = vipaka
        self.virya = virya
        self.prabhava = prabhava
    }

    func authority(
        hasRasa: Bool,
        hasVipaka: Bool,
        hasVirya: Bool,
        hasPrabhava: Bool
    ) -> Double {
        if hasPrabhava { return prabhava }
        if hasVirya { return virya }
        if hasVipaka { return vipaka }
        if hasRasa { return rasa }
        return 0
    }
}

struct MP5Candidate: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let fiberPer100g: Double
    let concepts: Set<String>
    let enforcedMinAgeMonths: Int
    let engineExcluded: Bool
    let role: FoodRole
    let roleAnchor: Bool
    let roleMaxPerMeal: Int
    let roleEligibleAsComponent: Bool
    let notReadyToEat: Bool
    let roleHeadword: String
    let minimumGrams: Double
    let maximumGrams: Double
    let doshaVata: Int
    let doshaPitta: Int
    let doshaKapha: Int
    let rasa: Set<String>
    let hasVipaka: Bool
    let hasVirya: Bool
    let hasPrabhava: Bool
    let heaviness: Double
    let seasons: Set<String>
    let tier: MP5AyurvedaTier
    let isHoney: Bool
    let isGhee: Bool
    let isHeatedHoney: Bool

    var kcalPerGram: Double { kcalPer100g / 100 }

    var nearDuplicateKey: String? {
        guard roleHeadword != "unknown", !roleHeadword.isEmpty else {
            return nil
        }
        return "\(role.rawValue)|\(roleHeadword)"
    }

    func doshaEffect(_ dosha: MP5Dosha?) -> Int {
        switch dosha {
        case .vata: return doshaVata
        case .pitta: return doshaPitta
        case .kapha: return doshaKapha
        case nil: return 0
        }
    }
}

struct MP5SolverProfile: Codable, Equatable, Sendable {
    let dailyKcal: Double
    let dailyProteinTarget: Double
    let ageInMonths: Int
    let diet: String
    let allergenConcepts: Set<String>
    let excludedFoodIDs: Set<Int>
    let dosha: MP5Dosha?
    let agni: MP5Agni
    let season: String?
    let enableAyurvedicScoring: Bool
}

struct MP5MealSlot: Codable, Equatable, Sendable {
    let day: Int
    let name: String
}

struct MP5MustContainRule: Codable, Equatable, Hashable, Sendable {
    let day: Int
    let meal: String?
    let foodID: Int
}

struct MP5SolverRequest: Codable, Equatable, Sendable {
    let profile: MP5SolverProfile
    let slots: [MP5MealSlot]
    let mustContain: [MP5MustContainRule]
    let seed: UInt64
    let noRepeatDays: Int
    let localSearchIterations: Int

    init(
        profile: MP5SolverProfile,
        slots: [MP5MealSlot],
        mustContain: [MP5MustContainRule] = [],
        seed: UInt64,
        noRepeatDays: Int = 2,
        localSearchIterations: Int = 96
    ) {
        self.profile = profile
        self.slots = slots
        self.mustContain = mustContain
        self.seed = seed
        self.noRepeatDays = max(1, noRepeatDays)
        self.localSearchIterations = max(0, min(localSearchIterations, 256))
    }
}

struct MP5SolvedComponent: Codable, Equatable, Sendable {
    let foodID: Int
    let name: String
    let grams: Double
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let doshaEffect: Int
    let heaviness: Double
    let rasa: Set<String>
    let tier: MP5AyurvedaTier
}

struct MP5SolvedMeal: Codable, Equatable, Sendable {
    let day: Int
    let name: String
    var components: [MP5SolvedComponent]

    var kcal: Double { components.reduce(0) { $0 + $1.kcal } }
    var protein: Double { components.reduce(0) { $0 + $1.protein } }
    var carbs: Double { components.reduce(0) { $0 + $1.carbs } }
    var fat: Double { components.reduce(0) { $0 + $1.fat } }
    var fiber: Double { components.reduce(0) { $0 + $1.fiber } }
}

struct MP5SolvedDay: Codable, Equatable, Sendable {
    let day: Int
    var meals: [MP5SolvedMeal]

    var kcal: Double { meals.reduce(0) { $0 + $1.kcal } }
    var protein: Double { meals.reduce(0) { $0 + $1.protein } }
    var carbs: Double { meals.reduce(0) { $0 + $1.carbs } }
    var fat: Double { meals.reduce(0) { $0 + $1.fat } }
    var fiber: Double { meals.reduce(0) { $0 + $1.fiber } }
}

struct MP5SolvedPlan: Codable, Equatable, Sendable {
    let seed: UInt64
    var days: [MP5SolvedDay]
    let softViruddhaCount: Int

    var components: [MP5SolvedComponent] {
        days.flatMap(\.meals).flatMap(\.components)
    }

    func canonicalData() throws -> Data {
        let dayObjects: [[String: Any]] = days.map { day in
            [
                "day": day.day,
                "meals": day.meals.map { meal in
                    [
                        "day": meal.day,
                        "name": meal.name,
                        "components": meal.components.map { component in
                            [
                                "foodID": component.foodID,
                                "name": component.name,
                                "grams": component.grams,
                                "kcal": component.kcal,
                                "protein": component.protein,
                                "carbs": component.carbs,
                                "fat": component.fat,
                                "fiber": component.fiber,
                                "doshaEffect": component.doshaEffect,
                                "heaviness": component.heaviness,
                                "rasa": component.rasa.sorted(),
                                "tier": component.tier.rawValue
                            ] as [String: Any]
                        }
                    ] as [String: Any]
                }
            ]
        }
        return try JSONSerialization.data(
            withJSONObject: [
                "seed": seed,
                "days": dayObjects,
                "softViruddhaCount": softViruddhaCount
            ],
            options: [.sortedKeys]
        )
    }
}

enum MP5SolverFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case infeasible(constraint: String)

    var description: String {
        switch self {
        case .infeasible(let constraint):
            return "Meal plan is infeasible: \(constraint)"
        }
    }
}

// MARK: - Deterministic solver

struct DeterministicMealPlanSolver {
    private let candidates: [MP5Candidate]
    private let candidatesByID: [Int: MP5Candidate]
    private let weights: MP5AyurvedicWeights

    init(
        candidates: [MP5Candidate],
        weights: MP5AyurvedicWeights = MP5AyurvedicWeights()
    ) {
        self.candidates = candidates
            .filter { $0.id > 0 && $0.kcalPer100g > 0 }
            .sorted { lhs, rhs in
                lhs.id == rhs.id ? lhs.name < rhs.name : lhs.id < rhs.id
            }
        self.candidatesByID = Dictionary(
            uniqueKeysWithValues: self.candidates.map { ($0.id, $0) }
        )
        self.weights = weights
    }

    func solve(_ request: MP5SolverRequest) throws -> MP5SolvedPlan {
        let orderedSlots = request.slots.sorted {
            $0.day == $1.day
                ? mealOrder($0.name) < mealOrder($1.name)
                : $0.day < $1.day
        }
        guard !orderedSlots.isEmpty else {
            throw MP5SolverFailure.infeasible(
                constraint: "structural placement requires at least one meal"
            )
        }

        let days = Dictionary(grouping: orderedSlots, by: \.day)
        guard days.values.allSatisfy({ !$0.isEmpty }) else {
            throw MP5SolverFailure.infeasible(
                constraint: "every requested day must contain a meal"
            )
        }

        let allowed = candidates.filter { hardAllowed($0, for: request.profile) }
        guard !allowed.isEmpty else {
            throw MP5SolverFailure.infeasible(
                constraint: failingSafetyConstraint(for: request.profile)
            )
        }

        for rule in request.mustContain {
            guard let candidate = candidatesByID[rule.foodID] else {
                throw MP5SolverFailure.infeasible(
                    constraint: "structural placement references missing food id \(rule.foodID)"
                )
            }
            guard hardAllowed(candidate, for: request.profile) else {
                throw MP5SolverFailure.infeasible(
                    constraint: "structural placement for \(candidate.name) conflicts with a safety constraint"
                )
            }
            guard days[rule.day] != nil else {
                throw MP5SolverFailure.infeasible(
                    constraint: "structural placement references unrequested day \(rule.day)"
                )
            }
            if let meal = rule.meal,
               days[rule.day]?.contains(where: {
                   $0.name.caseInsensitiveCompare(meal) == .orderedSame
               }) != true {
                throw MP5SolverFailure.infeasible(
                    constraint: "structural placement references unrequested meal \(meal)"
                )
            }
        }

        var rng = MP5SplitMix64(seed: request.seed)
        var selectedByDay: [Int: Set<Int>] = [:]
        var selectedHeadwordsByDay: [Int: Set<String>] = [:]
        var recentTastesByDay: [Int: Set<String>] = [:]
        var solvedMeals: [MP5SolvedMeal] = []
        var consumedRules = Set<MP5MustContainRule>()

        for slot in orderedSlots {
            let daySlots = days[slot.day] ?? []
            let target = request.profile.dailyKcal
                * normalizedMealShare(slot.name, in: daySlots.map(\.name))
            let recentIDs = idsWithinWindow(
                before: slot.day,
                window: request.noRepeatDays,
                selectedByDay: selectedByDay
            ).union(selectedByDay[slot.day] ?? [])
            let recentTastes = tastesWithinWindow(
                before: slot.day,
                window: 3,
                tastesByDay: recentTastesByDay
            )
            let recentHeadwords = headwordsWithinWindow(
                before: slot.day,
                window: request.noRepeatDays,
                headwordsByDay: selectedHeadwordsByDay
            ).union(selectedHeadwordsByDay[slot.day] ?? [])

            let matchingRules = request.mustContain.filter { rule in
                guard rule.day == slot.day, !consumedRules.contains(rule) else {
                    return false
                }
                if let meal = rule.meal {
                    return meal.caseInsensitiveCompare(slot.name) == .orderedSame
                }
                return daySlots.first?.name == slot.name
            }
            let required = matchingRules.compactMap { candidatesByID[$0.foodID] }
            let meal = try constructMeal(
                slot: slot,
                targetKcal: target,
                required: required,
                recentIDs: recentIDs,
                recentHeadwords: recentHeadwords,
                recentTastes: recentTastes,
                allowed: allowed,
                profile: request.profile,
                rng: &rng
            )
            solvedMeals.append(meal)
            consumedRules.formUnion(matchingRules)
            selectedByDay[slot.day, default: []].formUnion(
                meal.components.map(\.foodID)
            )
            selectedHeadwordsByDay[slot.day, default: []].formUnion(
                meal.components.compactMap {
                    candidatesByID[$0.foodID]?.nearDuplicateKey
                }
            )
            recentTastesByDay[slot.day, default: []].formUnion(
                meal.components.flatMap(\.rasa)
            )
        }

        guard consumedRules.count == request.mustContain.count else {
            throw MP5SolverFailure.infeasible(
                constraint: "not every structural placement could be assigned"
            )
        }

        var plan = MP5SolvedPlan(
            seed: request.seed,
            days: Dictionary(grouping: solvedMeals, by: \.day)
                .map { MP5SolvedDay(day: $0.key, meals: $0.value) }
                .sorted { $0.day < $1.day },
            softViruddhaCount: 0
        )
        plan = improve(
            plan,
            request: request,
            allowed: allowed,
            rng: &rng
        )
        try validateHardProperties(plan, request: request)
        return plan
    }

    private func constructMeal(
        slot: MP5MealSlot,
        targetKcal: Double,
        required: [MP5Candidate],
        recentIDs: Set<Int>,
        recentHeadwords: Set<String>,
        recentTastes: Set<String>,
        allowed: [MP5Candidate],
        profile: MP5SolverProfile,
        rng: inout MP5SplitMix64
    ) throws -> MP5SolvedMeal {
        if Set(required.map(\.id)).count != required.count {
            throw MP5SolverFailure.infeasible(
                constraint: "duplicate structural placement in Day \(slot.day) \(slot.name)"
            )
        }
        if required.contains(where: { recentIDs.contains($0.id) }) {
            throw MP5SolverFailure.infeasible(
                constraint: "structural placement violates the two-day no-repeat window"
            )
        }
        guard !containsHardViruddha(required) else {
            throw MP5SolverFailure.infeasible(
                constraint: "structural placement creates a hard viruddha pair"
            )
        }
        guard roleConstraintsSatisfied(
            required,
            profile: profile,
            requireAnchor: false
        ) else {
            throw MP5SolverFailure.infeasible(
                constraint: "structural placement violates meal role caps"
            )
        }

        let requiredIDs = Set(required.map(\.id))
        let pool = allowed.filter { candidate in
            !recentIDs.contains(candidate.id)
                && !requiredIDs.contains(candidate.id)
        }
        var best: (candidates: [MP5Candidate], score: Double)?
        let minimumCount = max(2, required.count)

        for count in minimumCount...6 {
            let needed = count - required.count
            guard needed >= 0 else { continue }
            let componentTarget = targetKcal / Double(count)
            var ranked: [(candidate: MP5Candidate, score: Double)] = []
            ranked.reserveCapacity(pool.count)
            for candidate in pool {
                let baseScore = selectionScore(
                    candidate,
                    mealName: slot.name,
                    targetPerComponent: componentTarget,
                    recentHeadwords: recentHeadwords,
                    recentTastes: recentTastes,
                    profile: profile
                )
                ranked.append(
                    (candidate: candidate, score: baseScore + rng.nextUnit() * 0.08)
                )
            }
            ranked.sort { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.candidate.id < rhs.candidate.id
                    : lhs.score > rhs.score
            }
            let rankedCandidates = ranked.map { $0.candidate }

            let modes: [[MP5Candidate]] = [
                rankedCandidates,
                rankedCandidates.sorted {
                    densityDistance($0, target: componentTarget)
                        < densityDistance($1, target: componentTarget)
                },
                rankedCandidates.sorted { $0.kcalPerGram > $1.kcalPerGram },
                rankedCandidates.sorted { $0.kcalPerGram < $1.kcalPerGram }
            ]
            for ordered in modes {
                var chosen = required
                if !containsAnchor(chosen, profile: profile),
                   let anchor = ordered.first(where: { candidate in
                       !chosen.contains(where: { $0.id == candidate.id })
                           && isAnchor(candidate, profile: profile)
                           && canAdd(candidate, to: chosen, profile: profile)
                           && !wouldCreateHardViruddha(candidate, in: chosen)
                   }) {
                    chosen.append(anchor)
                }
                for candidate in ordered where chosen.count < count {
                    guard !chosen.contains(where: { $0.id == candidate.id }),
                          canAdd(candidate, to: chosen, profile: profile),
                          !wouldCreateHardViruddha(candidate, in: chosen)
                    else {
                        continue
                    }
                    chosen.append(candidate)
                }
                guard chosen.count == count,
                      roleConstraintsSatisfied(
                          chosen,
                          profile: profile,
                          requireAnchor: true
                      )
                else {
                    continue
                }
                let span = calorieSpan(chosen, profile: profile)
                guard targetKcal >= span.minimum - 1e-9,
                      targetKcal <= span.maximum + 1e-9
                else {
                    continue
                }
                let score = chosen.reduce(0) {
                    $0 + selectionScore(
                        $1,
                        mealName: slot.name,
                        targetPerComponent: targetKcal / Double(count),
                        recentHeadwords: recentHeadwords,
                        recentTastes: recentTastes,
                        profile: profile
                    )
                }
                let shapedScore = score
                    + mealShapeScore(chosen, profile: profile)
                    - nearDuplicatePenalty(chosen)
                if best == nil || shapedScore > best!.score {
                    best = (chosen, shapedScore)
                }
            }
        }

        guard let best else {
            throw MP5SolverFailure.infeasible(
                constraint: "adaptive dish count cannot span \(Int(targetKcal.rounded())) kcal for Day \(slot.day) \(slot.name)"
            )
        }
        let components = try fitPortions(
            best.candidates,
            targetKcal: targetKcal,
            profile: profile
        )
        return MP5SolvedMeal(
            day: slot.day,
            name: slot.name,
            components: components
        )
    }

    private func improve(
        _ input: MP5SolvedPlan,
        request: MP5SolverRequest,
        allowed: [MP5Candidate],
        rng: inout MP5SplitMix64
    ) -> MP5SolvedPlan {
        guard request.localSearchIterations > 0 else { return input }
        var bestPlan = input
        var bestScore = objective(bestPlan, profile: request.profile)
        let requiredIDs = Set(request.mustContain.map(\.foodID))

        for _ in 0..<request.localSearchIterations {
            guard !bestPlan.days.isEmpty else { break }
            let dayIndex = rng.nextInt(upperBound: bestPlan.days.count)
            guard !bestPlan.days[dayIndex].meals.isEmpty else { continue }
            let mealIndex = rng.nextInt(
                upperBound: bestPlan.days[dayIndex].meals.count
            )
            let componentCount = bestPlan.days[dayIndex]
                .meals[mealIndex].components.count
            guard componentCount > 0 else { continue }
            let componentIndex = rng.nextInt(upperBound: componentCount)
            let old = bestPlan.days[dayIndex]
                .meals[mealIndex].components[componentIndex]
            guard !requiredIDs.contains(old.foodID) else { continue }

            let day = bestPlan.days[dayIndex].day
            let blocked = selectedIDs(
                in: bestPlan,
                days: (day - request.noRepeatDays)...(day + request.noRepeatDays)
            ).subtracting([old.foodID])
            let currentCandidates = bestPlan.days[dayIndex]
                .meals[mealIndex].components
                .compactMap { candidatesByID[$0.foodID] }
            let currentIDs = Set(currentCandidates.map(\.id))
            let replacements = allowed.filter { candidate in
                !blocked.contains(candidate.id)
                    && !currentIDs.contains(candidate.id)
                    && !wouldCreateHardViruddha(
                        candidate,
                        in: currentCandidates.filter { $0.id != old.foodID }
                    )
            }
            guard !replacements.isEmpty else { continue }
            let replacement = replacements[
                rng.nextInt(upperBound: min(replacements.count, 128))
            ]
            var trial = bestPlan
            var mealCandidates = currentCandidates
            mealCandidates[componentIndex] = replacement
            guard roleConstraintsSatisfied(
                mealCandidates,
                profile: request.profile,
                requireAnchor: true
            ) else {
                continue
            }
            let target = trial.days[dayIndex].meals[mealIndex].kcal
            guard let fitted = try? fitPortions(
                mealCandidates,
                targetKcal: target,
                profile: request.profile
            ) else {
                continue
            }
            trial.days[dayIndex].meals[mealIndex].components = fitted
            guard (try? validateHardProperties(trial, request: request)) != nil else {
                continue
            }
            let score = objective(trial, profile: request.profile)
            if score > bestScore + 1e-9 {
                bestPlan = trial
                bestScore = score
            }
        }
        return bestPlan
    }

    private func fitPortions(
        _ selected: [MP5Candidate],
        targetKcal: Double,
        profile: MP5SolverProfile
    ) throws -> [MP5SolvedComponent] {
        let limits = selected.map { portionLimits($0, agni: profile.agni) }
        let minimum = zip(selected, limits).reduce(0.0) {
            $0 + $1.0.kcalPerGram * $1.1.minimum
        }
        let capacities = zip(selected, limits).map {
            max(0, ($0.1.maximum - $0.1.minimum) * $0.0.kcalPerGram)
        }
        let maximum = minimum + capacities.reduce(0, +)
        guard targetKcal >= minimum - 1e-7,
              targetKcal <= maximum + 1e-7
        else {
            throw MP5SolverFailure.infeasible(
                constraint: "portion clamps cannot reach the meal calorie target"
            )
        }

        let remaining = max(0, targetKcal - minimum)
        let totalCapacity = capacities.reduce(0, +)
        var grams: [Double] = []
        grams.reserveCapacity(selected.count)
        for index in selected.indices {
            let candidate = selected[index]
            let limit = limits[index]
            let share = totalCapacity > 0
                ? remaining * capacities[index] / totalCapacity
                : 0
            let addedGrams = candidate.kcalPerGram > 0
                ? share / candidate.kcalPerGram
                : 0
            grams.append(min(limit.maximum, limit.minimum + addedGrams))
        }

        // Remove floating-point residue from the final component only.
        let current = zip(selected, grams).reduce(0.0) {
            $0 + $1.0.kcalPerGram * $1.1
        }
        if let last = selected.indices.last,
           selected[last].kcalPerGram > 0 {
            let adjusted = grams[last]
                + (targetKcal - current) / selected[last].kcalPerGram
            grams[last] = min(
                limits[last].maximum,
                max(limits[last].minimum, adjusted)
            )
        }
        let fittedKcal = zip(selected, grams).reduce(0.0) {
            $0 + $1.0.kcalPerGram * $1.1
        }
        guard abs(fittedKcal - targetKcal) <= 1e-6 else {
            throw MP5SolverFailure.infeasible(
                constraint: "role portion clamps leave calorie residue"
            )
        }

        return selected.indices.map { index in
            makeComponent(
                selected[index],
                grams: grams[index],
                dosha: profile.dosha
            )
        }
    }

    private func makeComponent(
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

    private func hardAllowed(
        _ candidate: MP5Candidate,
        for profile: MP5SolverProfile
    ) -> Bool {
        guard !candidate.engineExcluded,
              candidate.enforcedMinAgeMonths <= profile.ageInMonths,
              !profile.excludedFoodIDs.contains(candidate.id),
              candidate.concepts.isDisjoint(with: profile.allergenConcepts),
              !candidate.isHeatedHoney,
              !candidate.notReadyToEat,
              isRoleEligible(candidate, profile: profile)
        else {
            return false
        }
        return candidate.concepts.isDisjoint(
            with: dietExclusions(profile.diet)
        )
    }

    private func failingSafetyConstraint(
        for profile: MP5SolverProfile
    ) -> String {
        if !profile.allergenConcepts.isEmpty {
            return "allergen exclusions leave no safe candidate (\(profile.allergenConcepts.sorted().joined(separator: ", ")))"
        }
        if !dietExclusions(profile.diet).isEmpty {
            return "diet \(profile.diet) leaves no safe candidate"
        }
        return "safety constraints leave no candidate"
    }

    private func dietExclusions(_ diet: String) -> Set<String> {
        switch diet.lowercased() {
        case "vegan":
            return [
                "dairy", "egg", "meat", "fish", "shellfish",
                "crustacean", "mollusc", "honey"
            ]
        case "vegetarian":
            return ["meat", "fish", "shellfish", "crustacean", "mollusc"]
        case "jain_sattvic", "jain sattvic":
            return [
                "meat", "fish", "shellfish", "crustacean", "mollusc",
                "allium"
            ]
        default:
            return []
        }
    }

    private func selectionScore(
        _ candidate: MP5Candidate,
        mealName: String,
        targetPerComponent: Double,
        recentHeadwords: Set<String>,
        recentTastes: Set<String>,
        profile: MP5SolverProfile
    ) -> Double {
        var score = -densityDistance(candidate, target: targetPerComponent)
        score += min(candidate.proteinPer100g / 20, 1.5)
        score += min(candidate.fiberPer100g / 10, 1.0)
        if let key = candidate.nearDuplicateKey,
           recentHeadwords.contains(key) {
            score -= 1.25
        }

        let missingTastes = candidate.rasa.subtracting(recentTastes)
        score += Double(missingTastes.count) * weights.rasa * 0.12

        if let season = profile.season,
           candidate.seasons.contains(season) {
            score += 0.75
        }

        let lowerMeal = mealName.lowercased()
        if lowerMeal.contains("lunch") || lowerMeal.contains("midday") {
            score += candidate.heaviness * 0.55
        } else if lowerMeal.contains("dinner") || lowerMeal.contains("evening") {
            score -= candidate.heaviness * 0.70
        }

        switch profile.agni {
        case .slow:
            score -= candidate.heaviness * 1.8
        case .irregular:
            score -= abs(candidate.heaviness - 0.42)
        case .sharp:
            score -= candidate.hasVirya ? 0.05 : 0.2
        case .balanced:
            break
        }

        if profile.enableAyurvedicScoring, let dosha = profile.dosha {
            let authority = weights.authority(
                hasRasa: !candidate.rasa.isEmpty,
                hasVipaka: candidate.hasVipaka,
                hasVirya: candidate.hasVirya,
                hasPrabhava: candidate.hasPrabhava
            )
            score += Double(-candidate.doshaEffect(dosha)) * authority * 0.9
        }
        return score
    }

    private func objective(
        _ plan: MP5SolvedPlan,
        profile: MP5SolverProfile
    ) -> Double {
        var score = 0.0
        for day in plan.days {
            let kcalError = abs(day.kcal - profile.dailyKcal)
                / max(profile.dailyKcal, 1)
            score -= kcalError * 50
            let proteinError = abs(day.protein - profile.dailyProteinTarget)
                / max(profile.dailyProteinTarget, 1)
            score -= proteinError * 4
            score += min(day.fiber / max(profile.dailyKcal / 100, 1), 1) * 2
        }
        if profile.enableAyurvedicScoring, profile.dosha != nil {
            let effects = plan.components.map(\.doshaEffect)
            if !effects.isEmpty {
                score -= Double(effects.reduce(0, +)) / Double(effects.count) * 8
            }
        }
        score += Double(Set(plan.components.flatMap(\.rasa)).count) * 0.5
        for meal in plan.days.flatMap(\.meals) {
            let mealCandidates = meal.components.compactMap {
                candidatesByID[$0.foodID]
            }
            score += mealShapeScore(mealCandidates, profile: profile)
            score -= nearDuplicatePenalty(mealCandidates)
        }
        return score
    }

    private func calorieSpan(
        _ selected: [MP5Candidate],
        profile: MP5SolverProfile
    ) -> (minimum: Double, maximum: Double) {
        selected.reduce(into: (minimum: 0.0, maximum: 0.0)) {
            let limits = portionLimits($1, agni: profile.agni)
            $0.minimum += limits.minimum * $1.kcalPerGram
            $0.maximum += limits.maximum * $1.kcalPerGram
        }
    }

    private func portionLimits(
        _ candidate: MP5Candidate,
        agni: MP5Agni
    ) -> (minimum: Double, maximum: Double) {
        let multiplier: Double
        switch agni {
        case .slow: multiplier = 0.84
        case .irregular: multiplier = 0.93
        case .sharp: multiplier = 0.95
        case .balanced: multiplier = 1.0
        }
        let minimum = max(0.1, candidate.minimumGrams)
        let maximum = max(
            minimum,
            candidate.maximumGrams * multiplier
        )
        return (minimum, maximum)
    }

    private func isRoleEligible(
        _ candidate: MP5Candidate,
        profile: MP5SolverProfile
    ) -> Bool {
        if candidate.role == .infantProduct {
            return profile.ageInMonths < 36
        }
        return candidate.roleEligibleAsComponent
    }

    private func isAnchor(
        _ candidate: MP5Candidate,
        profile: MP5SolverProfile
    ) -> Bool {
        candidate.roleAnchor
            || (candidate.role == .infantProduct && profile.ageInMonths < 36)
    }

    private func containsAnchor(
        _ selected: [MP5Candidate],
        profile: MP5SolverProfile
    ) -> Bool {
        selected.contains { isAnchor($0, profile: profile) }
    }

    private func maximumPerMeal(
        _ candidate: MP5Candidate,
        profile: MP5SolverProfile
    ) -> Int {
        if candidate.role == .infantProduct && profile.ageInMonths < 36 {
            return 1
        }
        return candidate.roleMaxPerMeal
    }

    private func canAdd(
        _ candidate: MP5Candidate,
        to selected: [MP5Candidate],
        profile: MP5SolverProfile
    ) -> Bool {
        roleConstraintsSatisfied(
            selected + [candidate],
            profile: profile,
            requireAnchor: false
        )
    }

    private func roleConstraintsSatisfied(
        _ selected: [MP5Candidate],
        profile: MP5SolverProfile,
        requireAnchor: Bool
    ) -> Bool {
        let grouped = Dictionary(grouping: selected, by: \.role)
        for candidatesForRole in grouped.values {
            guard let candidate = candidatesForRole.first,
                  candidatesForRole.count <= maximumPerMeal(
                      candidate,
                      profile: profile
                  )
            else {
                return false
            }
        }
        let seasoningRoles: Set<FoodRole> = [
            .spice, .herb, .condiment, .medicinalHerb
        ]
        guard selected.filter({
            seasoningRoles.contains($0.role)
        }).count <= 2,
        selected.filter({ $0.role == .beverage }).count <= 2
        else {
            return false
        }
        return !requireAnchor || containsAnchor(selected, profile: profile)
    }

    private func mealShapeScore(
        _ selected: [MP5Candidate],
        profile: MP5SolverProfile
    ) -> Double {
        var score = containsAnchor(selected, profile: profile) ? 1.2 : 0
        if selected.contains(where: { $0.role == .side }) {
            score += 0.7
        }
        let seasonings = selected.filter {
            [.spice, .herb, .condiment, .medicinalHerb].contains($0.role)
        }.count
        if seasonings <= 1 {
            score += 0.35
        }
        return score
    }

    private func nearDuplicatePenalty(
        _ selected: [MP5Candidate]
    ) -> Double {
        let counts = Dictionary(
            grouping: selected.compactMap(\.nearDuplicateKey),
            by: { $0 }
        ).values.map(\.count)
        return Double(counts.reduce(0) { $0 + max(0, $1 - 1) }) * 0.8
    }

    private func containsHardViruddha(_ selected: [MP5Candidate]) -> Bool {
        for candidate in selected {
            if candidate.isHeatedHoney
                || wouldCreateHardViruddha(
                    candidate,
                    in: selected.filter { $0.id != candidate.id }
                ) {
                return true
            }
        }
        return false
    }

    private func wouldCreateHardViruddha(
        _ candidate: MP5Candidate,
        in selected: [MP5Candidate]
    ) -> Bool {
        if candidate.isHeatedHoney { return true }
        if candidate.concepts.contains("fish")
            && selected.contains(where: { $0.concepts.contains("dairy") }) {
            return true
        }
        if candidate.concepts.contains("dairy")
            && selected.contains(where: { $0.concepts.contains("fish") }) {
            return true
        }
        // Equal-parts honey + ghee is the cited hard rule. The assembler
        // conservatively keeps the pair out of one meal, so later portion
        // fitting cannot accidentally make the parts equal.
        if candidate.isHoney && selected.contains(where: \.isGhee) {
            return true
        }
        if candidate.isGhee && selected.contains(where: \.isHoney) {
            return true
        }
        return false
    }

    private func validateHardProperties(
        _ plan: MP5SolvedPlan,
        request: MP5SolverRequest
    ) throws {
        let expectedDays = Set(request.slots.map(\.day))
        guard Set(plan.days.map(\.day)) == expectedDays else {
            throw MP5SolverFailure.infeasible(
                constraint: "post-solve day structure validation"
            )
        }
        for day in plan.days {
            let expectedMeals = request.slots
                .filter { $0.day == day.day }
                .map { $0.name.lowercased() }
            guard day.meals.map({ $0.name.lowercased() }) == expectedMeals else {
                throw MP5SolverFailure.infeasible(
                    constraint: "post-solve meal structure validation"
                )
            }
            guard day.meals.allSatisfy({
                !$0.components.isEmpty
                    && $0.components.allSatisfy { $0.grams > 0 }
            }) else {
                throw MP5SolverFailure.infeasible(
                    constraint: "post-solve nonempty component validation"
                )
            }
            let error = abs(day.kcal - request.profile.dailyKcal)
                / max(request.profile.dailyKcal, 1)
            guard error <= 0.18 + 1e-9 else {
                throw MP5SolverFailure.infeasible(
                    constraint: "daily calories are outside the ±18% hard band"
                )
            }
        }

        for day in plan.days {
            for meal in day.meals {
                let mealCandidates = meal.components.compactMap {
                    candidatesByID[$0.foodID]
                }
                guard mealCandidates.count == meal.components.count,
                      !containsHardViruddha(mealCandidates)
                else {
                    throw MP5SolverFailure.infeasible(
                        constraint: "hard viruddha or unresolved component"
                    )
                }
                guard mealCandidates.allSatisfy({
                    hardAllowed($0, for: request.profile)
                }) else {
                    throw MP5SolverFailure.infeasible(
                        constraint: "post-solve safety validation"
                    )
                }
                guard roleConstraintsSatisfied(
                    mealCandidates,
                    profile: request.profile,
                    requireAnchor: true
                ) else {
                    throw MP5SolverFailure.infeasible(
                        constraint: "post-solve meal role validation"
                    )
                }
                for (component, candidate) in zip(
                    meal.components,
                    mealCandidates
                ) {
                    let limits = portionLimits(
                        candidate,
                        agni: request.profile.agni
                    )
                    guard component.grams >= limits.minimum - 1e-7,
                          component.grams <= limits.maximum + 1e-7
                    else {
                        throw MP5SolverFailure.infeasible(
                            constraint: "post-solve role portion validation"
                        )
                    }
                }
            }
        }

        let sortedDays = plan.days.sorted { $0.day < $1.day }
        for index in sortedDays.indices {
            let start = max(0, index - request.noRepeatDays)
            let prior = sortedDays[start..<index]
                .flatMap(\.meals)
                .flatMap(\.components)
                .map(\.foodID)
            let current = sortedDays[index].meals
                .flatMap(\.components)
                .map(\.foodID)
            guard Set(prior).isDisjoint(with: current),
                  Set(current).count == current.count
            else {
                throw MP5SolverFailure.infeasible(
                    constraint: "two-day no-repeat window"
                )
            }
        }

        for rule in request.mustContain {
            guard let day = plan.days.first(where: { $0.day == rule.day }) else {
                throw MP5SolverFailure.infeasible(
                    constraint: "missing structural placement day"
                )
            }
            let meals = rule.meal.map { requestedMeal in
                day.meals.filter {
                    $0.name.caseInsensitiveCompare(requestedMeal) == .orderedSame
                }
            } ?? day.meals
            guard meals.contains(where: {
                $0.components.contains(where: { $0.foodID == rule.foodID })
            }) else {
                throw MP5SolverFailure.infeasible(
                    constraint: "missing structural placement food \(rule.foodID)"
                )
            }
        }
    }

    private func normalizedMealShare(
        _ meal: String,
        in names: [String]
    ) -> Double {
        let raw = names.map { name -> Double in
            let lower = name.lowercased()
            if lower.contains("breakfast") || lower.contains("morning") {
                return 0.25
            }
            if lower.contains("lunch") || lower.contains("midday") {
                return 0.40
            }
            if lower.contains("dinner") || lower.contains("evening") {
                return 0.35
            }
            return 1
        }
        let total = raw.reduce(0, +)
        guard let index = names.firstIndex(where: {
            $0.caseInsensitiveCompare(meal) == .orderedSame
        }), total > 0 else {
            return 1 / Double(max(1, names.count))
        }
        return raw[index] / total
    }

    private func mealOrder(_ meal: String) -> Int {
        let lower = meal.lowercased()
        if lower.contains("breakfast") || lower.contains("morning") { return 0 }
        if lower.contains("lunch") || lower.contains("midday") { return 1 }
        if lower.contains("dinner") || lower.contains("evening") { return 2 }
        return 3
    }

    private func densityDistance(
        _ candidate: MP5Candidate,
        target: Double
    ) -> Double {
        let expected = max(candidate.kcalPerGram * 140, 1)
        return abs(log(expected / max(target, 1)))
    }

    private func idsWithinWindow(
        before day: Int,
        window: Int,
        selectedByDay: [Int: Set<Int>]
    ) -> Set<Int> {
        guard window > 0 else { return [] }
        return ((day - window)..<day).reduce(into: []) {
            $0.formUnion(selectedByDay[$1] ?? [])
        }
    }

    private func tastesWithinWindow(
        before day: Int,
        window: Int,
        tastesByDay: [Int: Set<String>]
    ) -> Set<String> {
        guard window > 0 else { return [] }
        return ((day - window)..<day).reduce(into: []) {
            $0.formUnion(tastesByDay[$1] ?? [])
        }
    }

    private func headwordsWithinWindow(
        before day: Int,
        window: Int,
        headwordsByDay: [Int: Set<String>]
    ) -> Set<String> {
        guard window > 0 else { return [] }
        return ((day - window)..<day).reduce(into: []) {
            $0.formUnion(headwordsByDay[$1] ?? [])
        }
    }

    private func selectedIDs(
        in plan: MP5SolvedPlan,
        days: ClosedRange<Int>
    ) -> Set<Int> {
        Set(
            plan.days
                .filter { days.contains($0.day) }
                .flatMap(\.meals)
                .flatMap(\.components)
                .map(\.foodID)
        )
    }
}

private struct MP5SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}
