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

struct MP5DoshaTarget: Codable, Equatable, Sendable {
    let vata: Double
    let pitta: Double
    let kapha: Double

    init(vata: Double, pitta: Double, kapha: Double) {
        let values = [
            max(0, vata.isFinite ? vata : 0),
            max(0, pitta.isFinite ? pitta : 0),
            max(0, kapha.isFinite ? kapha : 0),
        ]
        let total = values.reduce(0, +)
        if total > 0 {
            self.vata = values[0] / total
            self.pitta = values[1] / total
            self.kapha = values[2] / total
        } else {
            self.vata = 1.0 / 3.0
            self.pitta = 1.0 / 3.0
            self.kapha = 1.0 / 3.0
        }
    }
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
    let id: UUID
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

    func doshaFit(_ target: MP5DoshaTarget?) -> Double {
        guard let target, tier != .estimated, tier != .none else {
            return 0
        }
        return target.vata * Double(-doshaVata)
            + target.pitta * Double(-doshaPitta)
            + target.kapha * Double(-doshaKapha)
    }
}

struct MP5SolverProfile: Codable, Equatable, Sendable {
    let dailyKcal: Double
    let dailyProteinTarget: Double
    let ageInMonths: Int
    let allergenConcepts: Set<String>
    let excludedFoodIDs: Set<UUID>
    let dosha: MP5Dosha?
    let agni: MP5Agni
    let season: String?
    let enableAyurvedicScoring: Bool
    var doshaTarget: MP5DoshaTarget? = nil
}

struct MP5MealSlot: Codable, Equatable, Sendable {
    let day: Int
    let name: String
}

struct MP5MustContainRule: Codable, Equatable, Hashable, Sendable {
    let day: Int
    let meal: String?
    let foodID: UUID
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
    let foodID: UUID
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
                                "foodID": component.foodID.uuidString,
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

final class MP7SolverDiagnostics {
    var eligibilityFilterNanoseconds: UInt64 = 0
    var eligibilityFilterScans: Int = 0
    var allowedCandidateCount: Int = 0
    var mealPoolFilterNanoseconds: UInt64 = 0
    var mealPoolFilterScans: Int = 0
    var greedyConstructionNanoseconds: UInt64 = 0
    var greedySelectionScoreNanoseconds: UInt64 = 0
    var greedySelectionScoreCalls: Int = 0
    var greedySortNanoseconds: UInt64 = 0
    var greedyRankSortNanoseconds: UInt64 = 0
    var greedyDensitySortNanoseconds: UInt64 = 0
    var greedyDescendingKcalSortNanoseconds: UInt64 = 0
    var greedyAscendingKcalSortNanoseconds: UInt64 = 0
    var greedySortInputRows: Int = 0
    var greedyModeNanoseconds: UInt64 = 0
    var greedyModeSequenceScans: Int = 0
    var greedyModeCandidateEvaluations: Int = 0
    var localSearchNanoseconds: UInt64 = 0
    var localSearchIterations: Int = 0
    var localReplacementFilterNanoseconds: UInt64 = 0
    var localReplacementFilterScans: Int = 0
    var localRoleCheckNanoseconds: UInt64 = 0
    var localRoleCheckCalls: Int = 0
    var localHardValidationNanoseconds: UInt64 = 0
    var localHardValidationCalls: Int = 0
    var localObjectiveNanoseconds: UInt64 = 0
    var localObjectiveCalls: Int = 0
    var portionClampNanoseconds: UInt64 = 0
    var portionClampCalls: Int = 0
    var nearDuplicateNanoseconds: UInt64 = 0
    var nearDuplicateCalls: Int = 0
    var finalValidationNanoseconds: UInt64 = 0
}

// MARK: - Deterministic solver

struct DeterministicMealPlanSolver {
    private let candidates: [MP5Candidate]
    private let candidatesByID: [UUID: MP5Candidate]
    private let nearDuplicateKeysByID: [UUID: String]
    private let maximumPerMealByRole: [FoodRole: Int]
    private let weights: MP5AyurvedicWeights

    init(
        candidates: [MP5Candidate],
        weights: MP5AyurvedicWeights = MP5AyurvedicWeights()
    ) {
        self.candidates = candidates
            .filter { $0.kcalPer100g > 0 }
            .sorted { lhs, rhs in
                lhs.id == rhs.id
                    ? lhs.name < rhs.name
                    : lhs.id.uuidString < rhs.id.uuidString
            }
        self.candidatesByID = Dictionary(
            uniqueKeysWithValues: self.candidates.map { ($0.id, $0) }
        )
        self.nearDuplicateKeysByID = Dictionary(
            uniqueKeysWithValues: self.candidates.compactMap { candidate in
                guard candidate.roleHeadword != "unknown",
                      !candidate.roleHeadword.isEmpty
                else {
                    return nil
                }
                return (
                    candidate.id,
                    "\(candidate.role.rawValue)|\(candidate.roleHeadword)"
                )
            }
        )
        self.maximumPerMealByRole = Dictionary(
            grouping: self.candidates,
            by: \.role
        ).mapValues { $0.first?.roleMaxPerMeal ?? 0 }
        self.weights = weights
    }

    func solve(
        _ request: MP5SolverRequest,
        diagnostics: MP7SolverDiagnostics? = nil
    ) throws -> MP5SolvedPlan {
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

        let eligibilityStarted = diagnostics == nil
            ? 0
            : DispatchTime.now().uptimeNanoseconds
        let allowed = candidates.filter { hardAllowed($0, for: request.profile) }
        if let diagnostics {
            diagnostics.eligibilityFilterNanoseconds +=
                DispatchTime.now().uptimeNanoseconds - eligibilityStarted
            diagnostics.eligibilityFilterScans += candidates.count
            diagnostics.allowedCandidateCount = allowed.count
        }
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
        var selectedByDay: [Int: Set<UUID>] = [:]
        var selectedHeadwordsByDay: [Int: Set<String>] = [:]
        var recentTastesByDay: [Int: Set<String>] = [:]
        var solvedMeals: [MP5SolvedMeal] = []
        var consumedRules = Set<MP5MustContainRule>()

        let greedyStarted = diagnostics == nil
            ? 0
            : DispatchTime.now().uptimeNanoseconds
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
                rng: &rng,
                diagnostics: diagnostics
            )
            solvedMeals.append(meal)
            consumedRules.formUnion(matchingRules)
            selectedByDay[slot.day, default: []].formUnion(
                meal.components.map(\.foodID)
            )
            selectedHeadwordsByDay[slot.day, default: []].formUnion(
                meal.components.compactMap {
                    nearDuplicateKeysByID[$0.foodID]
                }
            )
            recentTastesByDay[slot.day, default: []].formUnion(
                meal.components.flatMap(\.rasa)
            )
        }
        if let diagnostics {
            diagnostics.greedyConstructionNanoseconds +=
                DispatchTime.now().uptimeNanoseconds - greedyStarted
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
        let localSearchStarted = diagnostics == nil
            ? 0
            : DispatchTime.now().uptimeNanoseconds
        plan = improve(
            plan,
            request: request,
            allowed: allowed,
            rng: &rng,
            diagnostics: diagnostics
        )
        if let diagnostics {
            diagnostics.localSearchNanoseconds +=
                DispatchTime.now().uptimeNanoseconds - localSearchStarted
        }
        let validationStarted = diagnostics == nil
            ? 0
            : DispatchTime.now().uptimeNanoseconds
        try validateHardProperties(plan, request: request)
        if let diagnostics {
            diagnostics.finalValidationNanoseconds +=
                DispatchTime.now().uptimeNanoseconds - validationStarted
        }
        return plan
    }

    private func constructMeal(
        slot: MP5MealSlot,
        targetKcal: Double,
        required: [MP5Candidate],
        recentIDs: Set<UUID>,
        recentHeadwords: Set<String>,
        recentTastes: Set<String>,
        allowed: [MP5Candidate],
        profile: MP5SolverProfile,
        rng: inout MP5SplitMix64,
        diagnostics: MP7SolverDiagnostics?
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
        let poolFilterStarted = diagnostics == nil
            ? 0
            : DispatchTime.now().uptimeNanoseconds
        let pool = allowed.filter { candidate in
            !recentIDs.contains(candidate.id)
                && !requiredIDs.contains(candidate.id)
        }
        if let diagnostics {
            diagnostics.mealPoolFilterNanoseconds +=
                DispatchTime.now().uptimeNanoseconds - poolFilterStarted
            diagnostics.mealPoolFilterScans += allowed.count
        }
        var best: (candidates: [MP5Candidate], score: Double)?
        let minimumCount = max(2, required.count)
        let mealContext = mealScoringContext(slot.name)

        for count in minimumCount...6 {
            let needed = count - required.count
            guard needed >= 0 else { continue }
            let componentTarget = targetKcal / Double(count)
            var ranked: [MP5RankedCandidate] = []
            ranked.reserveCapacity(pool.count)
            let scoreStarted = diagnostics == nil
                ? 0
                : DispatchTime.now().uptimeNanoseconds
            for (candidateIndex, candidate) in pool.enumerated() {
                let distance = densityDistance(
                    candidate,
                    target: componentTarget
                )
                let baseScore = selectionScore(
                    candidate,
                    densityDistance: distance,
                    mealContext: mealContext,
                    recentHeadwords: recentHeadwords,
                    recentTastes: recentTastes,
                    profile: profile
                )
                ranked.append(
                    MP5RankedCandidate(
                        candidateIndex: candidateIndex,
                        candidateID: candidate.id,
                        role: candidate.role,
                        kcalPerGram: candidate.kcalPerGram,
                        randomizedScore:
                            baseScore + rng.nextUnit() * 0.08,
                        baseScore: baseScore,
                        densityDistance: distance
                    )
                )
            }
            if let diagnostics {
                diagnostics.greedySelectionScoreNanoseconds +=
                    DispatchTime.now().uptimeNanoseconds - scoreStarted
                diagnostics.greedySelectionScoreCalls += pool.count
            }
            let baseScoreByID = Dictionary(
                uniqueKeysWithValues: ranked.map {
                    ($0.candidateID, $0.baseScore)
                }
            )
            let rankedByRole = Dictionary(
                grouping: ranked,
                by: \.role
            )
            let modeStarted = diagnostics == nil
                ? 0
                : DispatchTime.now().uptimeNanoseconds
            for ordering in MP5CandidateOrdering.allCases {
                let sortStarted = diagnostics == nil
                    ? 0
                    : DispatchTime.now().uptimeNanoseconds
                let sortedByRole = rankedByRole.mapValues { bucket in
                    orderedRoleBucket(bucket, ordering: ordering)
                }
                if let diagnostics {
                    let elapsed =
                        DispatchTime.now().uptimeNanoseconds - sortStarted
                    diagnostics.greedySortNanoseconds += elapsed
                    diagnostics.greedySortInputRows += ranked.count
                    switch ordering {
                    case .score:
                        diagnostics.greedyRankSortNanoseconds += elapsed
                    case .density:
                        diagnostics.greedyDensitySortNanoseconds += elapsed
                    case .descendingKcal:
                        diagnostics
                            .greedyDescendingKcalSortNanoseconds += elapsed
                    case .ascendingKcal:
                        diagnostics
                            .greedyAscendingKcalSortNanoseconds += elapsed
                    }
                }
                var chosen = required
                var anchorCursors: [FoodRole: Int] = [:]
                if !containsAnchor(chosen, profile: profile),
                   let result = nextEligibleCandidate(
                       in: sortedByRole,
                       pool: pool,
                       ordering: ordering,
                       selected: chosen,
                       profile: profile,
                       requireAnchor: true,
                       cursors: &anchorCursors
                   ) {
                    diagnostics?.greedyModeSequenceScans += result.scans
                    diagnostics?.greedyModeCandidateEvaluations +=
                        result.evaluations
                    chosen.append(result.candidate)
                }
                var cursors: [FoodRole: Int] = [:]
                while chosen.count < count {
                    guard let result = nextEligibleCandidate(
                        in: sortedByRole,
                        pool: pool,
                        ordering: ordering,
                        selected: chosen,
                        profile: profile,
                        requireAnchor: false,
                        cursors: &cursors
                    ) else {
                        break
                    }
                    diagnostics?.greedyModeSequenceScans += result.scans
                    diagnostics?.greedyModeCandidateEvaluations +=
                        result.evaluations
                    chosen.append(result.candidate)
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
                let score = chosen.reduce(0) { partial, candidate in
                    partial + (
                        baseScoreByID[candidate.id]
                            ?? selectionScore(
                                candidate,
                                densityDistance: densityDistance(
                                    candidate,
                                    target: targetKcal / Double(count)
                                ),
                                mealContext: mealContext,
                                recentHeadwords: recentHeadwords,
                                recentTastes: recentTastes,
                                profile: profile
                            )
                    )
                }
                diagnostics?.greedySelectionScoreCalls += chosen.count
                let nearDuplicateStarted = diagnostics == nil
                    ? 0
                    : DispatchTime.now().uptimeNanoseconds
                let duplicatePenalty = nearDuplicatePenalty(chosen)
                if let diagnostics {
                    diagnostics.nearDuplicateNanoseconds +=
                        DispatchTime.now().uptimeNanoseconds
                        - nearDuplicateStarted
                    diagnostics.nearDuplicateCalls += 1
                }
                let shapedScore = score
                    + mealShapeScore(chosen, profile: profile)
                    - duplicatePenalty
                if best == nil || shapedScore > best!.score {
                    best = (chosen, shapedScore)
                }
            }
            if let diagnostics {
                diagnostics.greedyModeNanoseconds +=
                    DispatchTime.now().uptimeNanoseconds - modeStarted
            }
        }

        guard let best else {
            throw MP5SolverFailure.infeasible(
                constraint: "adaptive dish count cannot span \(Int(targetKcal.rounded())) kcal for Day \(slot.day) \(slot.name)"
            )
        }
        let portionStarted = diagnostics == nil
            ? 0
            : DispatchTime.now().uptimeNanoseconds
        let components = try fitPortions(
            best.candidates,
            targetKcal: targetKcal,
            profile: profile
        )
        if let diagnostics {
            diagnostics.portionClampNanoseconds +=
                DispatchTime.now().uptimeNanoseconds - portionStarted
            diagnostics.portionClampCalls += 1
        }
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
        rng: inout MP5SplitMix64,
        diagnostics: MP7SolverDiagnostics?
    ) -> MP5SolvedPlan {
        guard request.localSearchIterations > 0 else { return input }
        var bestPlan = input
        var bestScore = objective(bestPlan, profile: request.profile)
        let requiredIDs = Set(request.mustContain.map(\.foodID))

        for _ in 0..<request.localSearchIterations {
            diagnostics?.localSearchIterations += 1
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
            let candidatesOtherThanReplaced = currentCandidates.filter {
                $0.id != old.foodID
            }
            let replacementViruddhaContext = viruddhaContext(
                candidatesOtherThanReplaced
            )
            let replacementFilterStarted = diagnostics == nil
                ? 0
                : DispatchTime.now().uptimeNanoseconds
            let replacements = allowed.filter { candidate in
                !blocked.contains(candidate.id)
                    && !currentIDs.contains(candidate.id)
                    && !wouldCreateHardViruddha(
                        candidate,
                        in: replacementViruddhaContext
                    )
            }
            if let diagnostics {
                diagnostics.localReplacementFilterNanoseconds +=
                    DispatchTime.now().uptimeNanoseconds
                    - replacementFilterStarted
                diagnostics.localReplacementFilterScans += allowed.count
            }
            guard !replacements.isEmpty else { continue }
            let replacement = replacements[
                rng.nextInt(upperBound: min(replacements.count, 128))
            ]
            var trial = bestPlan
            var mealCandidates = currentCandidates
            mealCandidates[componentIndex] = replacement
            let roleCheckStarted = diagnostics == nil
                ? 0
                : DispatchTime.now().uptimeNanoseconds
            let roleValid = roleConstraintsSatisfied(
                mealCandidates,
                profile: request.profile,
                requireAnchor: true
            )
            if let diagnostics {
                diagnostics.localRoleCheckNanoseconds +=
                    DispatchTime.now().uptimeNanoseconds - roleCheckStarted
                diagnostics.localRoleCheckCalls += 1
            }
            guard roleValid else {
                continue
            }
            let target = trial.days[dayIndex].meals[mealIndex].kcal
            let portionStarted = diagnostics == nil
                ? 0
                : DispatchTime.now().uptimeNanoseconds
            guard let fitted = try? fitPortions(
                mealCandidates,
                targetKcal: target,
                profile: request.profile
            ) else {
                if let diagnostics {
                    diagnostics.portionClampNanoseconds +=
                        DispatchTime.now().uptimeNanoseconds - portionStarted
                    diagnostics.portionClampCalls += 1
                }
                continue
            }
            if let diagnostics {
                diagnostics.portionClampNanoseconds +=
                    DispatchTime.now().uptimeNanoseconds - portionStarted
                diagnostics.portionClampCalls += 1
            }
            trial.days[dayIndex].meals[mealIndex].components = fitted
            let validationStarted = diagnostics == nil
                ? 0
                : DispatchTime.now().uptimeNanoseconds
            let hardValid =
                (try? validateHardProperties(trial, request: request)) != nil
            if let diagnostics {
                diagnostics.localHardValidationNanoseconds +=
                    DispatchTime.now().uptimeNanoseconds - validationStarted
                diagnostics.localHardValidationCalls += 1
            }
            guard hardValid else {
                continue
            }
            let objectiveStarted = diagnostics == nil
                ? 0
                : DispatchTime.now().uptimeNanoseconds
            let score = objective(trial, profile: request.profile)
            if let diagnostics {
                diagnostics.localObjectiveNanoseconds +=
                    DispatchTime.now().uptimeNanoseconds - objectiveStarted
                diagnostics.localObjectiveCalls += 1
            }
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
        return true
    }

    private func failingSafetyConstraint(
        for profile: MP5SolverProfile
    ) -> String {
        if !profile.allergenConcepts.isEmpty {
            return "allergen exclusions leave no safe candidate (\(profile.allergenConcepts.sorted().joined(separator: ", ")))"
        }
        return "safety constraints leave no candidate"
    }

    private func selectionScore(
        _ candidate: MP5Candidate,
        densityDistance: Double,
        mealContext: MP5MealScoringContext,
        recentHeadwords: Set<String>,
        recentTastes: Set<String>,
        profile: MP5SolverProfile
    ) -> Double {
        var score = -densityDistance
        score += min(candidate.proteinPer100g / 20, 1.5)
        score += min(candidate.fiberPer100g / 10, 1.0)
        if let key = nearDuplicateKeysByID[candidate.id],
           recentHeadwords.contains(key) {
            score -= 1.25
        }

        let missingTasteCount = candidate.rasa.reduce(into: 0) {
            if !recentTastes.contains($1) {
                $0 += 1
            }
        }
        score += Double(missingTasteCount) * weights.rasa * 0.12

        if let season = profile.season,
           candidate.seasons.contains(season) {
            score += 0.75
        }

        if mealContext == .midday {
            score += candidate.heaviness * 0.55
        } else if mealContext == .evening {
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

        if profile.enableAyurvedicScoring,
           profile.doshaTarget != nil || profile.dosha != nil {
            let authority = weights.authority(
                hasRasa: !candidate.rasa.isEmpty,
                hasVipaka: candidate.hasVipaka,
                hasVirya: candidate.hasVirya,
                hasPrabhava: candidate.hasPrabhava
            )
            if let target = profile.doshaTarget {
                score += candidate.doshaFit(target) * authority * 0.9
            } else if let dosha = profile.dosha {
                score += Double(-candidate.doshaEffect(dosha))
                    * authority
                    * 0.9
            }
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
        if profile.enableAyurvedicScoring {
            if let target = profile.doshaTarget {
                let fits = plan.components.compactMap {
                    candidatesByID[$0.foodID]
                }.map { $0.doshaFit(target) }
                if !fits.isEmpty {
                    score += fits.reduce(0, +) / Double(fits.count) * 8
                }
            } else if profile.dosha != nil {
                let effects = plan.components.map(\.doshaEffect)
                if !effects.isEmpty {
                    score -= Double(effects.reduce(0, +))
                        / Double(effects.count)
                        * 8
                }
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
            grouping: selected.compactMap {
                nearDuplicateKeysByID[$0.id]
            },
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
        wouldCreateHardViruddha(
            candidate,
            in: viruddhaContext(selected)
        )
    }

    private func wouldCreateHardViruddha(
        _ candidate: MP5Candidate,
        in context: MP5ViruddhaContext
    ) -> Bool {
        if candidate.isHeatedHoney { return true }
        if candidate.concepts.contains("fish")
            && context.hasDairy {
            return true
        }
        if candidate.concepts.contains("dairy")
            && context.hasFish {
            return true
        }
        // Equal-parts honey + ghee is the cited hard rule. The assembler
        // conservatively keeps the pair out of one meal, so later portion
        // fitting cannot accidentally make the parts equal.
        if candidate.isHoney && context.hasGhee {
            return true
        }
        if candidate.isGhee && context.hasHoney {
            return true
        }
        return false
    }

    private func viruddhaContext(
        _ selected: [MP5Candidate]
    ) -> MP5ViruddhaContext {
        MP5ViruddhaContext(
            hasFish: selected.contains {
                $0.concepts.contains("fish")
            },
            hasDairy: selected.contains {
                $0.concepts.contains("dairy")
            },
            hasHoney: selected.contains(where: \.isHoney),
            hasGhee: selected.contains(where: \.isGhee)
        )
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

    private func mealScoringContext(
        _ meal: String
    ) -> MP5MealScoringContext {
        let lower = meal.lowercased()
        if lower.contains("lunch") || lower.contains("midday") {
            return .midday
        }
        if lower.contains("dinner") || lower.contains("evening") {
            return .evening
        }
        return .other
    }

    private func densityDistance(
        _ candidate: MP5Candidate,
        target: Double
    ) -> Double {
        let expected = max(candidate.kcalPerGram * 140, 1)
        return abs(log(expected / max(target, 1)))
    }

    private func orderedRoleBucket(
        _ bucket: [MP5RankedCandidate],
        ordering: MP5CandidateOrdering,
    ) -> [MP5RankedCandidate] {
        bucket.sorted(by: ordering.precedes)
    }

    private func nextEligibleCandidate(
        in buckets: [FoodRole: [MP5RankedCandidate]],
        pool: [MP5Candidate],
        ordering: MP5CandidateOrdering,
        selected: [MP5Candidate],
        profile: MP5SolverProfile,
        requireAnchor: Bool,
        cursors: inout [FoodRole: Int]
    ) -> (
        candidate: MP5Candidate,
        scans: Int,
        evaluations: Int
    )? {
        let selectedIDs = Set(selected.map(\.id))
        var best: MP5RankedCandidate?
        var scans = 0
        var evaluations = 0

        for role in FoodRole.allCases {
            guard roleCanAccept(
                role,
                selected: selected,
                profile: profile
            ) else {
                continue
            }
            guard let bucket = buckets[role],
                  let first = bucket.first,
                  pool.indices.contains(first.candidateIndex),
                  !requireAnchor
                    || isAnchor(
                        pool[first.candidateIndex],
                        profile: profile
                    )
            else {
                continue
            }
            var index = cursors[role] ?? 0
            while index < bucket.count {
                scans += 1
                let ranked = bucket[index]
                let candidate = pool[ranked.candidateIndex]
                guard !selectedIDs.contains(candidate.id) else {
                    index += 1
                    continue
                }
                evaluations += 1
                guard !wouldCreateHardViruddha(candidate, in: selected) else {
                    index += 1
                    continue
                }
                if best == nil
                    || ordering.precedes(ranked, best!) {
                    best = ranked
                }
                break
            }
            cursors[role] = index
        }
        if let best {
            cursors[best.role, default: 0] += 1
            return (
                pool[best.candidateIndex],
                scans,
                evaluations
            )
        }
        return nil
    }

    private func roleCanAccept(
        _ role: FoodRole,
        selected: [MP5Candidate],
        profile: MP5SolverProfile
    ) -> Bool {
        let candidatesForRole = selected.filter { $0.role == role }
        let maximum = role == .infantProduct
            && profile.ageInMonths < 36
            ? 1
            : maximumPerMealByRole[role] ?? 0
        guard candidatesForRole.count < maximum
        else {
            return false
        }
        if [.spice, .herb, .condiment, .medicinalHerb].contains(role) {
            let seasoningCount = selected.filter {
                [.spice, .herb, .condiment, .medicinalHerb]
                    .contains($0.role)
            }.count
            return seasoningCount < 2
        }
        if role == .beverage {
            return selected.filter { $0.role == .beverage }.count < 2
        }
        return true
    }

    private func idsWithinWindow(
        before day: Int,
        window: Int,
        selectedByDay: [Int: Set<UUID>]
    ) -> Set<UUID> {
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
    ) -> Set<UUID> {
        Set(
            plan.days
                .filter { days.contains($0.day) }
                .flatMap(\.meals)
                .flatMap(\.components)
                .map(\.foodID)
        )
    }
}

private enum MP5MealScoringContext {
    case midday
    case evening
    case other
}

private struct MP5RankedCandidate {
    let candidateIndex: Int
    let candidateID: UUID
    let role: FoodRole
    let kcalPerGram: Double
    let randomizedScore: Double
    let baseScore: Double
    let densityDistance: Double
}

private struct MP5ViruddhaContext {
    let hasFish: Bool
    let hasDairy: Bool
    let hasHoney: Bool
    let hasGhee: Bool
}

private enum MP5CandidateOrdering: CaseIterable {
    case score
    case density
    case descendingKcal
    case ascendingKcal

    func precedes(
        _ lhs: MP5RankedCandidate,
        _ rhs: MP5RankedCandidate
    ) -> Bool {
        switch self {
        case .score:
            return scorePrecedes(lhs, rhs)
        case .density:
            if lhs.densityDistance != rhs.densityDistance {
                return lhs.densityDistance < rhs.densityDistance
            }
            return scorePrecedes(lhs, rhs)
        case .descendingKcal:
            if lhs.kcalPerGram != rhs.kcalPerGram {
                return lhs.kcalPerGram > rhs.kcalPerGram
            }
            return scorePrecedes(lhs, rhs)
        case .ascendingKcal:
            if lhs.kcalPerGram != rhs.kcalPerGram {
                return lhs.kcalPerGram < rhs.kcalPerGram
            }
            return scorePrecedes(lhs, rhs)
        }
    }

    private func scorePrecedes(
        _ lhs: MP5RankedCandidate,
        _ rhs: MP5RankedCandidate
    ) -> Bool {
        lhs.randomizedScore == rhs.randomizedScore
            ? lhs.candidateID.uuidString < rhs.candidateID.uuidString
            : lhs.randomizedScore > rhs.randomizedScore
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
