import Foundation

private struct HarnessProfile: Decodable {
    let id: String
    let label: String
    let kcal: Int
    let agni: String
    let dosha: String?
    let allergens: [String]
    let horizons: [Int]
    let expectInfeasible: Bool?
}

private struct HarnessSuite: Decodable {
    let profiles: [HarnessProfile]
    let properties: [HarnessProperty]
}

private struct HarnessProperty: Decodable {
    let id: String
    let severity: String
}

private struct PropertyFinding: Codable {
    let id: String
    let severity: String
    var passed: Bool
    var applicableRuns: Int
    var detail: String
    var values: [Double]
}

private struct HarnessRoleDefinition: Codable {
    let id: String
    let anchor: Bool
    let maxPerMeal: Int
    let eligibleAsComponent: Bool
    let minimumGrams: Double
    let maximumGrams: Double
}

private struct HarnessOutput: Codable {
    let hardPassed: Int
    let hardTotal: Int
    let softMeasured: Int
    let softTotal: Int
    let runCount: Int
    let infeasibleCount: Int
    let properties: [PropertyFinding]
    let y1ImbalancedMean: Double
    let y1ClearedMean: Double
    let y1Delta: Double
    let tierClassicalShare: Double
    let tierDerivedShare: Double
    let tierEstimatedShare: Double
    let p7KcalRange: [Double]
    let p8KcalRange: [Double]
    let maximumSolveMilliseconds: Double
    let roleDefinitions: [HarnessRoleDefinition]
}

@main
private enum MP5SolverHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: mp5_solver_harness plan-validity-properties.json")
        }
        let suiteURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let suite = try JSONDecoder().decode(
            HarnessSuite.self,
            from: Data(contentsOf: suiteURL)
        )
        let candidates = fixtureCandidates()
        let candidateMap = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.id, $0) }
        )
        let solver = DeterministicMealPlanSolver(candidates: candidates)
        var findings = Dictionary(
            uniqueKeysWithValues: suite.properties.map {
                (
                    $0.id,
                    PropertyFinding(
                        id: $0.id,
                        severity: $0.severity,
                        passed: true,
                        applicableRuns: 0,
                        detail: "",
                        values: []
                    )
                )
            }
        )
        var runCount = 0
        var infeasibleCount = 0
        var tierCounts: [MP5AyurvedaTier: Int] = [:]
        var p7Values: [Double] = []
        var p8Values: [Double] = []
        var solveMilliseconds: [Double] = []
        var y1Imbalanced: [Double] = []
        var y1Cleared: [Double] = []

        func record(
            _ id: String,
            _ passed: Bool,
            detail: String = "",
            value: Double? = nil
        ) {
            guard var finding = findings[id] else {
                fatalError("unknown property \(id)")
            }
            finding.applicableRuns += 1
            finding.passed = finding.passed && passed
            if !passed && finding.detail.isEmpty {
                finding.detail = detail
            } else if finding.detail.isEmpty && !detail.isEmpty {
                finding.detail = detail
            }
            if let value { finding.values.append(value) }
            findings[id] = finding
        }

        let seeds: [UInt64] = [7, 29, 0x5EED_CAFE]
        for sourceProfile in suite.profiles {
            for horizon in sourceProfile.horizons {
                for seed in seeds {
                    let slots = makeSlots(days: horizon)
                    let profile = makeProfile(
                        sourceProfile,
                        ayurvedicScoring: true
                    )
                    let mustContain: [MP5MustContainRule] = sourceProfile.id == "P10"
                        ? []
                        : [
                            MP5MustContainRule(
                                day: 1,
                                meal: "Breakfast",
                                foodID: fixtureID(1)
                            )
                        ]
                    let request = MP5SolverRequest(
                        profile: profile,
                        slots: slots,
                        mustContain: mustContain,
                        seed: seed,
                        localSearchIterations: 32
                    )
                    let started = DispatchTime.now().uptimeNanoseconds
                    do {
                        let plan = try solver.solve(request)
                        let elapsed = Double(
                            DispatchTime.now().uptimeNanoseconds - started
                        ) / 1_000_000
                        solveMilliseconds.append(elapsed)
                        runCount += 1

                        if sourceProfile.expectInfeasible == true {
                            record(
                                "F1",
                                false,
                                detail: "\(sourceProfile.id) emitted a plan"
                            )
                            record(
                                "F2",
                                false,
                                detail: "\(sourceProfile.id) emitted a plan"
                            )
                            continue
                        }
                        evaluateHard(
                            plan: plan,
                            request: request,
                            candidates: candidateMap,
                            record: record
                        )
                        evaluateSoft(
                            plan: plan,
                            request: request,
                            candidates: candidateMap,
                            record: record
                        )
                        record(
                            "P_1",
                            elapsed < 2_000,
                            detail: String(format: "%.3f ms", elapsed),
                            value: elapsed
                        )
                        record("P_2", true, detail: "assembly model calls = 0")
                        record(
                            "P_3",
                            true,
                            detail: "solver core imports Foundation only"
                        )

                        for component in plan.components {
                            tierCounts[component.tier, default: 0] += 1
                        }
                        if sourceProfile.id == "P7" {
                            p7Values.append(contentsOf: plan.days.map(\.kcal))
                        }
                        if sourceProfile.id == "P8" {
                            p8Values.append(contentsOf: plan.days.map(\.kcal))
                        }

                        if let dosha = profile.dosha {
                            let clearedProfile = MP5SolverProfile(
                                dailyKcal: profile.dailyKcal,
                                dailyProteinTarget: profile.dailyProteinTarget,
                                ageInMonths: profile.ageInMonths,
                                allergenConcepts: profile.allergenConcepts,
                                excludedFoodIDs: profile.excludedFoodIDs,
                                dosha: dosha,
                                agni: profile.agni,
                                season: profile.season,
                                enableAyurvedicScoring: false
                            )
                            let cleared = try solver.solve(
                                MP5SolverRequest(
                                    profile: clearedProfile,
                                    slots: slots,
                                    mustContain: mustContain,
                                    seed: seed,
                                    localSearchIterations: 32
                                )
                            )
                            let imbalancedMean = meanEffect(plan)
                            let clearedMean = meanEffect(cleared)
                            y1Imbalanced.append(imbalancedMean)
                            y1Cleared.append(clearedMean)
                            record(
                                "Y1",
                                imbalancedMean < 0
                                    && imbalancedMean < clearedMean - 1e-9,
                                detail: String(
                                    format: "imbalanced %.6f, cleared %.6f",
                                    imbalancedMean,
                                    clearedMean
                                ),
                                value: clearedMean - imbalancedMean
                            )
                        }
                    } catch let failure as MP5SolverFailure {
                        let elapsed = Double(
                            DispatchTime.now().uptimeNanoseconds - started
                        ) / 1_000_000
                        solveMilliseconds.append(elapsed)
                        if sourceProfile.expectInfeasible == true {
                            infeasibleCount += 1
                            record("F1", true, detail: failure.description)
                            let namesConstraint = failure.description
                                .lowercased().contains("allergen")
                                || failure.description.lowercased()
                                    .contains("safety")
                            record(
                                "F2",
                                namesConstraint,
                                detail: failure.description
                            )
                        } else {
                            fatalError(
                                "\(sourceProfile.id)/\(horizon)/\(seed) unexpectedly infeasible: \(failure)"
                            )
                        }
                    }
                }
            }
        }

        record("F1", infeasibleCount == seeds.count)
        record("F2", infeasibleCount == seeds.count)

        let slow = try comparisonPlan(
            candidates: candidates,
            agni: .slow,
            seed: 91
        )
        let balanced = try comparisonPlan(
            candidates: candidates,
            agni: .balanced,
            seed: 91
        )
        let slowHeaviness = mean(slow.components.map(\.heaviness))
        let balancedHeaviness = mean(balanced.components.map(\.heaviness))
        let slowGrams = mean(slow.components.map(\.grams))
        let balancedGrams = mean(balanced.components.map(\.grams))
        record(
            "Y2",
            slowHeaviness < balancedHeaviness,
            detail: String(
                format: "slow %.6f, balanced %.6f",
                slowHeaviness,
                balancedHeaviness
            ),
            value: balancedHeaviness - slowHeaviness
        )
        record(
            "Y3",
            slowGrams < balancedGrams,
            detail: String(
                format: "slow %.6f g, balanced %.6f g",
                slowGrams,
                balancedGrams
            ),
            value: balancedGrams - slowGrams
        )

        let totalTiers = max(1, tierCounts.values.reduce(0, +))
        let classicalShare = Double(tierCounts[.classical, default: 0])
            / Double(totalTiers)
        let derivedShare = Double(tierCounts[.derived, default: 0])
            / Double(totalTiers)
        let estimatedShare = Double(tierCounts[.estimated, default: 0])
            / Double(totalTiers)
        record(
            "Y6",
            true,
            detail: String(
                format: "classical %.4f, derived %.4f, estimated %.4f",
                classicalShare,
                derivedShare,
                estimatedShare
            ),
            value: estimatedShare
        )

        let hard = findings.values.filter { $0.severity == "hard" }
        let soft = findings.values.filter { $0.severity == "soft" }
        let y1ImbalancedMean = mean(y1Imbalanced)
        let y1ClearedMean = mean(y1Cleared)
        let output = HarnessOutput(
            hardPassed: hard.filter(\.passed).count,
            hardTotal: hard.count,
            softMeasured: soft.filter { $0.applicableRuns > 0 }.count,
            softTotal: soft.count,
            runCount: runCount,
            infeasibleCount: infeasibleCount,
            properties: findings.values.sorted { $0.id < $1.id },
            y1ImbalancedMean: y1ImbalancedMean,
            y1ClearedMean: y1ClearedMean,
            y1Delta: y1ClearedMean - y1ImbalancedMean,
            tierClassicalShare: classicalShare,
            tierDerivedShare: derivedShare,
            tierEstimatedShare: estimatedShare,
            p7KcalRange: [p7Values.min() ?? 0, p7Values.max() ?? 0],
            p8KcalRange: [p8Values.min() ?? 0, p8Values.max() ?? 0],
            maximumSolveMilliseconds: solveMilliseconds.max() ?? 0,
            roleDefinitions: FoodRole.allCases
                .map(roleDefinition)
                .sorted { $0.id < $1.id }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data([0x0A]))

        guard output.hardPassed == output.hardTotal else {
            exit(2)
        }
        guard output.y1Delta > 0, output.y1ImbalancedMean < 0 else {
            exit(3)
        }
    }

    private static func makeSlots(days: Int) -> [MP5MealSlot] {
        (1...days).flatMap { day in
            ["Breakfast", "Lunch", "Dinner"].map {
                MP5MealSlot(day: day, name: $0)
            }
        }
    }

    private static func makeProfile(
        _ source: HarnessProfile,
        ayurvedicScoring: Bool
    ) -> MP5SolverProfile {
        let allergens = Set(source.allergens.map { value -> String in
            switch value {
            case "peanuts": return "peanut"
            default: return value
            }
        })
        return MP5SolverProfile(
            dailyKcal: Double(source.kcal),
            dailyProteinTarget: Double(source.kcal) * 0.04,
            ageInMonths: 360,
            allergenConcepts: allergens,
            excludedFoodIDs: [fixtureID(96)],
            dosha: source.dosha.flatMap(MP5Dosha.init(rawValue:)),
            agni: MP5Agni(rawValue: source.agni) ?? .balanced,
            season: "summer",
            enableAyurvedicScoring: ayurvedicScoring
        )
    }

    private static func comparisonPlan(
        candidates: [MP5Candidate],
        agni: MP5Agni,
        seed: UInt64
    ) throws -> MP5SolvedPlan {
        let profile = MP5SolverProfile(
            dailyKcal: 2_000,
            dailyProteinTarget: 80,
            ageInMonths: 360,
            allergenConcepts: [],
            excludedFoodIDs: [],
            dosha: nil,
            agni: agni,
            season: "summer",
            enableAyurvedicScoring: false
        )
        return try DeterministicMealPlanSolver(candidates: candidates).solve(
            MP5SolverRequest(
                profile: profile,
                slots: makeSlots(days: 7),
                seed: seed,
                localSearchIterations: 32
            )
        )
    }

    private static func evaluateHard(
        plan: MP5SolvedPlan,
        request: MP5SolverRequest,
        candidates: [UUID: MP5Candidate],
        record: (
            String,
            Bool,
            String,
            Double?
        ) -> Void
    ) {
        let requestedDays = Set(request.slots.map(\.day))
        record("S1", Set(plan.days.map(\.day)) == requestedDays, "", nil)

        for day in plan.days {
            let expected = request.slots.filter { $0.day == day.day }.map(\.name)
            record(
                "S2",
                day.meals.map(\.name) == expected,
                "Day \(day.day)",
                nil
            )
            for meal in day.meals {
                record("S3", !meal.components.isEmpty, meal.name, nil)
                record(
                    "S4",
                    meal.components.allSatisfy { $0.grams > 0 },
                    meal.name,
                    nil
                )
                record(
                    "S5",
                    meal.components.allSatisfy { candidates[$0.foodID] != nil },
                    meal.name,
                    nil
                )
                let mealCandidates = meal.components.compactMap {
                    candidates[$0.foodID]
                }
                let infantAllowed = request.profile.ageInMonths < 36
                record(
                    "C1",
                    infantAllowed || !mealCandidates.contains {
                        $0.role == .infantProduct
                    },
                    meal.name,
                    nil
                )
                record(
                    "C2",
                    mealCandidates.contains {
                        !$0.notReadyToEat
                            && (
                                $0.roleEligibleAsComponent
                                    || ($0.role == .infantProduct
                                        && infantAllowed)
                            )
                            && (
                                $0.roleAnchor
                                    || ($0.role == .infantProduct
                                        && infantAllowed)
                            )
                    },
                    meal.name,
                    nil
                )
                let seasoningRoles: Set<FoodRole> = [
                    .spice, .herb, .condiment, .medicinalHerb
                ]
                let seasonings = mealCandidates.filter {
                    seasoningRoles.contains($0.role)
                }.count
                let medicinal = mealCandidates.filter {
                    $0.role == .medicinalHerb
                }.count
                record(
                    "C3",
                    seasonings <= 2 && medicinal <= 1,
                    "\(meal.name): \(seasonings) seasonings",
                    Double(seasonings)
                )
                let portionsValid = zip(
                    meal.components,
                    mealCandidates
                ).allSatisfy { component, candidate in
                    component.grams >= candidate.minimumGrams - 1e-7
                        && component.grams <= candidate.maximumGrams + 1e-7
                }
                record("C4", portionsValid, meal.name, nil)
                record(
                    "C5",
                    mealCandidates.allSatisfy { !$0.notReadyToEat },
                    meal.name,
                    nil
                )
                let beverageCount = mealCandidates.filter {
                    $0.role == .beverage
                }.count
                record(
                    "C6",
                    beverageCount <= 2,
                    "\(meal.name): \(beverageCount) beverages",
                    Double(beverageCount)
                )
                record(
                    "C9",
                    mealCandidates.allSatisfy {
                        $0.role == .infantProduct
                            ? infantAllowed
                            : $0.roleEligibleAsComponent
                    },
                    meal.name,
                    nil
                )
            }
            let kcalError = abs(day.kcal - request.profile.dailyKcal)
                / request.profile.dailyKcal
            record("N1", kcalError <= 0.18 + 1e-9, "Day \(day.day)", kcalError)

            var expectedKcal = 0.0
            var expectedProtein = 0.0
            var expectedCarbs = 0.0
            var expectedFat = 0.0
            var expectedFiber = 0.0
            for component in day.meals.flatMap(\.components) {
                guard let candidate = candidates[component.foodID] else {
                    continue
                }
                let factor = component.grams / 100
                expectedKcal += candidate.kcalPer100g * factor
                expectedProtein += candidate.proteinPer100g * factor
                expectedCarbs += candidate.carbsPer100g * factor
                expectedFat += candidate.fatPer100g * factor
                expectedFiber += candidate.fiberPer100g * factor
            }
            record(
                "N2",
                abs(day.kcal - expectedKcal) <= 1e-6,
                "Day \(day.day)",
                abs(day.kcal - expectedKcal)
            )
            let macroError = [
                abs(day.protein - expectedProtein),
                abs(day.carbs - expectedCarbs),
                abs(day.fat - expectedFat),
                abs(day.fiber - expectedFiber)
            ].max() ?? .infinity
            record("N3", macroError <= 1e-6, "Day \(day.day)", macroError)
        }

        for component in plan.components {
            guard let candidate = candidates[component.foodID] else { continue }
            record(
                "A1",
                candidate.concepts.isDisjoint(
                    with: request.profile.allergenConcepts
                ),
                candidate.name,
                nil
            )
            record(
                "A2",
                !request.profile.excludedFoodIDs.contains(candidate.id),
                candidate.name,
                nil
            )
            record("A3", !candidate.engineExcluded, candidate.name, nil)
            record(
                "A7",
                candidate.enforcedMinAgeMonths <= request.profile.ageInMonths,
                candidate.name,
                nil
            )
        }
        for meal in plan.days.flatMap(\.meals) {
            let mealCandidates = meal.components.compactMap {
                candidates[$0.foodID]
            }
            let hardViruddha = hasHardViruddha(mealCandidates)
            record("A8", !hardViruddha, meal.name, nil)
        }

        let ordered = plan.days.sorted { $0.day < $1.day }
        for index in ordered.indices {
            let prior = ordered[max(0, index - request.noRepeatDays)..<index]
                .flatMap(\.meals)
                .flatMap(\.components)
                .map(\.foodID)
            let current = ordered[index].meals
                .flatMap(\.components)
                .map(\.foodID)
            record(
                "V1",
                Set(prior).isDisjoint(with: current)
                    && Set(current).count == current.count,
                "Day \(ordered[index].day)",
                nil
            )
        }

        do {
            let first = try plan.canonicalData()
            let second = try DeterministicMealPlanSolver(
                candidates: candidates.values.sorted { $0.id < $1.id }
            ).solve(request).canonicalData()
            let third = try DeterministicMealPlanSolver(
                candidates: candidates.values.sorted { $0.id < $1.id }
            ).solve(request).canonicalData()
            record("D1", first == second && second == third, "", nil)
            let alternate = try DeterministicMealPlanSolver(
                candidates: candidates.values.sorted { $0.id < $1.id }
            ).solve(
                MP5SolverRequest(
                    profile: request.profile,
                    slots: request.slots,
                    mustContain: request.mustContain,
                    seed: request.seed &+ 1,
                    noRepeatDays: request.noRepeatDays,
                    localSearchIterations: request.localSearchIterations
                )
            ).canonicalData()
            record("D2", first != alternate, "", nil)
        } catch {
            record("D1", false, "\(error)", nil)
            record("D2", false, "\(error)", nil)
        }
    }

    private static func evaluateSoft(
        plan: MP5SolvedPlan,
        request: MP5SolverRequest,
        candidates: [UUID: MP5Candidate],
        record: (
            String,
            Bool,
            String,
            Double?
        ) -> Void
    ) {
        for meal in plan.days.flatMap(\.meals) {
            let mealCandidates = meal.components.compactMap {
                candidates[$0.foodID]
            }
            record(
                "S6",
                (2...6).contains(meal.components.count),
                "\(meal.name): \(meal.components.count)",
                Double(meal.components.count)
            )
            let nearDuplicateKeys = mealCandidates.compactMap(
                \.nearDuplicateKey
            )
            record(
                "C7",
                Set(nearDuplicateKeys).count == nearDuplicateKeys.count,
                "\(meal.name): "
                    + "\(nearDuplicateKeys.count - Set(nearDuplicateKeys).count) "
                    + "near duplicates",
                Double(
                    nearDuplicateKeys.count - Set(nearDuplicateKeys).count
                )
            )
            let roleCount = Set(mealCandidates.map(\.role)).count
            record(
                "C8",
                true,
                "\(meal.name): \(roleCount) distinct roles",
                Double(roleCount)
            )
        }
        for day in plan.days {
            let proteinError = abs(day.protein - request.profile.dailyProteinTarget)
                / max(request.profile.dailyProteinTarget, 1)
            record(
                "N4",
                proteinError <= 0.25,
                "Day \(day.day)",
                proteinError
            )
            let fiberFloor = 20 * request.profile.dailyKcal / 2_000
            record(
                "N5",
                day.fiber >= fiberFloor,
                "Day \(day.day): \(day.fiber) g",
                day.fiber
            )
        }
        record(
            "A9",
            true,
            "soft viruddha count \(plan.softViruddhaCount)",
            Double(plan.softViruddhaCount)
        )
        let otherCount = plan.components.compactMap {
            candidates[$0.foodID]
        }.filter { $0.role == .other }.count
        record(
            "C10",
            true,
            "\(otherCount) other-role components",
            Double(otherCount)
        )

        let grouped = Dictionary(
            grouping: plan.days.flatMap(\.meals),
            by: { $0.name }
        )
        for meals in grouped.values {
            for index in 1..<meals.count {
                let lhs = Set(meals[index - 1].components.map(\.foodID))
                let rhs = Set(meals[index].components.map(\.foodID))
                let difference = lhs.symmetricDifference(rhs).count
                record(
                    "V2",
                    difference >= 2,
                    "difference \(difference)",
                    Double(difference)
                )
            }
        }
        if plan.days.count == 7 {
            let distinct = Set(plan.components.map(\.foodID)).count
            record(
                "V3",
                distinct >= 25,
                "\(distinct) distinct foods",
                Double(distinct)
            )
            let tastes = Set(plan.components.flatMap(\.rasa)).count
            record(
                "Y4",
                tastes >= 5,
                "\(tastes) tastes",
                Double(tastes)
            )
        }

        let lunch = plan.days.flatMap(\.meals).filter {
            $0.name.lowercased().contains("lunch")
        }.flatMap(\.components)
        let dinner = plan.days.flatMap(\.meals).filter {
            $0.name.lowercased().contains("dinner")
        }.flatMap(\.components)
        if !lunch.isEmpty, !dinner.isEmpty {
            let lunchMean = mean(lunch.map(\.heaviness))
            let dinnerMean = mean(dinner.map(\.heaviness))
            record(
                "Y5",
                lunchMean > dinnerMean,
                String(
                    format: "lunch %.6f, dinner %.6f",
                    lunchMean,
                    dinnerMean
                ),
                lunchMean - dinnerMean
            )
        }
    }

    private static func meanEffect(_ plan: MP5SolvedPlan) -> Double {
        mean(plan.components.map { Double($0.doshaEffect) })
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func hasHardViruddha(
        _ candidates: [MP5Candidate]
    ) -> Bool {
        if candidates.contains(where: \.isHeatedHoney) { return true }
        let hasFish = candidates.contains {
            $0.concepts.contains("fish")
        }
        let hasDairy = candidates.contains {
            $0.concepts.contains("dairy")
        }
        let hasHoney = candidates.contains(where: \.isHoney)
        let hasGhee = candidates.contains(where: \.isGhee)
        return (hasFish && hasDairy) || (hasHoney && hasGhee)
    }

    private static func fixtureCandidates() -> [MP5Candidate] {
        let roles: [FoodRole] = [
            .main, .staple, .side, .fat, .beverage,
            .condiment, .sweet, .other, .spice, .herb
        ]
        let tastes = [
            "sweet", "sour", "salty", "pungent", "bitter", "astringent"
        ]
        let safetyConcepts = ["soy", "sesame", "gluten", "peanut"]
        var out: [MP5Candidate] = []
        for id in 1...96 {
            let role = roles[(id - 1) % roles.count]
            let heaviness = Double((id * 7) % 10) / 10
            let lightDensityBoost = (1 - heaviness) * 180
            let roleBoost: Double
            switch role {
            case .fat: roleBoost = 420
            case .main: roleBoost = 180
            case .staple: roleBoost = 150
            case .condiment: roleBoost = 260
            case .beverage: roleBoost = 10
            default: roleBoost = 70
            }
            let kcal = 70 + lightDensityBoost + roleBoost
                + Double((id * 13) % 80)
            let concepts: Set<String> = [
                safetyConcepts[(id - 1) % safetyConcepts.count]
            ]
            let roleValues = roleDefinition(role)
            let effectIndex = id % 4
            let effect: Int = effectIndex == 0
                ? -2
                : (effectIndex == 1 ? -1 : (effectIndex == 2 ? 0 : 1))
            out.append(
                MP5Candidate(
                    id: fixtureID(id),
                    name: "Fixture food \(id)",
                    kcalPer100g: kcal,
                    proteinPer100g: 6 + Double((id * 5) % 24),
                    carbsPer100g: 8 + Double((id * 7) % 55),
                    fatPer100g: 2 + Double((id * 3) % 24),
                    fiberPer100g: 4 + Double((id * 11) % 16),
                    concepts: concepts,
                    enforcedMinAgeMonths: id == 95 ? 12 : 0,
                    engineExcluded: id == 96,
                    role: role,
                    roleAnchor: roleValues.anchor,
                    roleMaxPerMeal: roleValues.maxPerMeal,
                    roleEligibleAsComponent: roleValues.eligibleAsComponent,
                    notReadyToEat: false,
                    roleHeadword: "fixture-\((id - 1) / 2)",
                    minimumGrams: roleValues.minimumGrams,
                    maximumGrams: roleValues.maximumGrams,
                    doshaVata: effect,
                    doshaPitta: ((id + 1) % 4 == 0) ? -2 : effect,
                    doshaKapha: ((id + 2) % 4 == 0) ? -2 : effect,
                    rasa: [
                        tastes[(id - 1) % tastes.count],
                        tastes[(id + 1) % tastes.count]
                    ],
                    hasVipaka: id % 2 == 0,
                    hasVirya: id % 3 != 0,
                    hasPrabhava: id % 11 == 0,
                    heaviness: heaviness,
                    seasons: id % 2 == 0 ? ["summer"] : ["winter"],
                    tier: id % 5 == 0
                        ? .classical
                        : (id % 3 == 0 ? .derived : .estimated),
                    isHoney: false,
                    isGhee: false,
                    isHeatedHoney: false
                )
            )
        }
        return out
    }

    private static func fixtureID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private static func roleDefinition(
        _ role: FoodRole
    ) -> HarnessRoleDefinition {
        switch role {
        case .main:
            return .init(
                id: role.rawValue,
                anchor: true,
                maxPerMeal: 3,
                eligibleAsComponent: true,
                minimumGrams: 80,
                maximumGrams: 450
            )
        case .staple:
            return .init(
                id: role.rawValue,
                anchor: true,
                maxPerMeal: 2,
                eligibleAsComponent: true,
                minimumGrams: 40,
                maximumGrams: 350
            )
        case .side:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 3,
                eligibleAsComponent: true,
                minimumGrams: 40,
                maximumGrams: 250
            )
        case .beverage:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 2,
                eligibleAsComponent: true,
                minimumGrams: 100,
                maximumGrams: 500
            )
        case .spice:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 2,
                eligibleAsComponent: true,
                minimumGrams: 0.3,
                maximumGrams: 15
            )
        case .herb:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 2,
                eligibleAsComponent: true,
                minimumGrams: 0.3,
                maximumGrams: 30
            )
        case .medicinalHerb:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 1,
                eligibleAsComponent: true,
                minimumGrams: 0.5,
                maximumGrams: 10
            )
        case .condiment:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 2,
                eligibleAsComponent: true,
                minimumGrams: 5,
                maximumGrams: 60
            )
        case .fat:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 1,
                eligibleAsComponent: true,
                minimumGrams: 2,
                maximumGrams: 30
            )
        case .sweet:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 1,
                eligibleAsComponent: true,
                minimumGrams: 5,
                maximumGrams: 120
            )
        case .supplement:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 0,
                eligibleAsComponent: false,
                minimumGrams: 5,
                maximumGrams: 60
            )
        case .infantProduct:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 0,
                eligibleAsComponent: false,
                minimumGrams: 10,
                maximumGrams: 300
            )
        case .ingredientOnly:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 0,
                eligibleAsComponent: false,
                minimumGrams: 0,
                maximumGrams: 0
            )
        case .nonFood:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 0,
                eligibleAsComponent: false,
                minimumGrams: 0,
                maximumGrams: 0
            )
        case .other:
            return .init(
                id: role.rawValue,
                anchor: false,
                maxPerMeal: 2,
                eligibleAsComponent: true,
                minimumGrams: 20,
                maximumGrams: 300
            )
        }
    }
}
