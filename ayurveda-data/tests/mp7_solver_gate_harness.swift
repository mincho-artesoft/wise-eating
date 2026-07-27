import Foundation
import CryptoKit

private struct CandidateWrapper: Decodable {
    let candidate: MP5Candidate
}

private struct GateProfile: Decodable {
    let id: String
    let kcal: Int
    let diet: String
    let agni: String
    let dosha: String?
    let allergens: [String]
}

private struct GateSuite: Decodable {
    let profiles: [GateProfile]
}

private struct GateRun: Codable {
    let profile: String
    let horizon: Int
    let producedPlan: Bool
    let bindingConstraint: String?
    let solveMilliseconds: Double
    let minimumDailyKcal: Double?
    let maximumDailyKcal: Double?
    let canonicalSHA256: String?
}

private struct Y1Run: Codable {
    let profile: String
    let imbalancedMean: Double
    let clearedMean: Double
    let delta: Double
}

private struct GateOutput: Codable {
    let sourceCandidateCount: Int
    let roleEligibleCount: Int
    let roleIneligibleCount: Int
    let notReadyToEatCount: Int
    let planCount: Int
    let runs: [GateRun]
    let y1Runs: [Y1Run]
    let y1MeanDelta: Double
    let maximumSevenDaySolveMilliseconds: Double
    let profileDiagnostics: ProfileDiagnostics?
}

private struct ProfileDiagnostics: Codable {
    let profile: String
    let eligibilityFilterMilliseconds: Double
    let eligibilityFilterScans: Int
    let allowedCandidateCount: Int
    let mealPoolFilterMilliseconds: Double
    let mealPoolFilterScans: Int
    let greedyConstructionMilliseconds: Double
    let greedySelectionScoreMilliseconds: Double
    let greedySelectionScoreCalls: Int
    let greedySortMilliseconds: Double
    let greedyRankSortMilliseconds: Double
    let greedyDensitySortMilliseconds: Double
    let greedyDescendingKcalSortMilliseconds: Double
    let greedyAscendingKcalSortMilliseconds: Double
    let greedySortInputRows: Int
    let greedyModeMilliseconds: Double
    let greedyModeSequenceScans: Int
    let greedyModeCandidateEvaluations: Int
    let localSearchMilliseconds: Double
    let localSearchIterations: Int
    let localReplacementFilterMilliseconds: Double
    let localReplacementFilterScans: Int
    let localRoleCheckMilliseconds: Double
    let localRoleCheckCalls: Int
    let localHardValidationMilliseconds: Double
    let localHardValidationCalls: Int
    let localObjectiveMilliseconds: Double
    let localObjectiveCalls: Int
    let portionClampMilliseconds: Double
    let portionClampCalls: Int
    let nearDuplicateMilliseconds: Double
    let nearDuplicateCalls: Int
    let finalValidationMilliseconds: Double
}

@main
private enum MP7SolverGateHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 3
            || (
                CommandLine.arguments.count == 5
                    && CommandLine.arguments[3] == "--single"
            )
        else {
            fatalError(
                "usage: mp7_solver_gate_harness real-candidates.json "
                    + "plan-validity-properties.json [--single profile]"
            )
        }
        let wrappers = try JSONDecoder().decode(
            [CandidateWrapper].self,
            from: Data(
                contentsOf: URL(
                    fileURLWithPath: CommandLine.arguments[1]
                )
            )
        )
        let suite = try JSONDecoder().decode(
            GateSuite.self,
            from: Data(
                contentsOf: URL(
                    fileURLWithPath: CommandLine.arguments[2]
                )
            )
        )
        let candidates = wrappers.map(\.candidate)
        let solver = DeterministicMealPlanSolver(candidates: candidates)
        let singleProfile = CommandLine.arguments.count == 5
            ? CommandLine.arguments[4]
            : nil
        let profiles = singleProfile.map { requested in
            suite.profiles.filter { $0.id == requested }
        } ?? suite.profiles
        guard singleProfile == nil || profiles.count == 1 else {
            fatalError("single profile not found")
        }
        let horizons = singleProfile == nil ? [1, 3, 7] : [7]
        let seed: UInt64 = 0x4D50_3700
        var runs: [GateRun] = []
        var capturedDiagnostics: ProfileDiagnostics?

        for source in profiles {
            for horizon in horizons {
                let profile = solverProfile(
                    source,
                    enableAyurvedicScoring: true
                )
                let request = MP5SolverRequest(
                    profile: profile,
                    slots: slots(days: horizon),
                    seed: seed,
                    localSearchIterations: 96
                )
                let diagnostics = singleProfile == nil
                    ? nil
                    : MP7SolverDiagnostics()
                let started = DispatchTime.now().uptimeNanoseconds
                do {
                    let plan = try solver.solve(
                        request,
                        diagnostics: diagnostics
                    )
                    let elapsed = milliseconds(since: started)
                    let dailyKcal = plan.days.map(\.kcal)
                    runs.append(
                        GateRun(
                            profile: source.id,
                            horizon: horizon,
                            producedPlan: true,
                            bindingConstraint: nil,
                            solveMilliseconds: elapsed,
                            minimumDailyKcal: dailyKcal.min(),
                            maximumDailyKcal: dailyKcal.max(),
                            canonicalSHA256: sha256(
                                try plan.canonicalData()
                            )
                        )
                    )
                    if let diagnostics {
                        capturedDiagnostics = profileDiagnostics(
                            source.id,
                            diagnostics
                        )
                    }
                } catch let failure as MP5SolverFailure {
                    runs.append(
                        GateRun(
                            profile: source.id,
                            horizon: horizon,
                            producedPlan: false,
                            bindingConstraint: failure.description,
                            solveMilliseconds: milliseconds(since: started),
                            minimumDailyKcal: nil,
                            maximumDailyKcal: nil,
                            canonicalSHA256: nil
                        )
                    )
                }
            }
        }

        var y1Runs: [Y1Run] = []
        for source in profiles
            where singleProfile == nil && source.dosha != nil {
            let horizon = 7
            let request = MP5SolverRequest(
                profile: solverProfile(
                    source,
                    enableAyurvedicScoring: true
                ),
                slots: slots(days: horizon),
                seed: seed,
                localSearchIterations: 96
            )
            let clearedRequest = MP5SolverRequest(
                profile: solverProfile(
                    source,
                    enableAyurvedicScoring: false
                ),
                slots: slots(days: horizon),
                seed: seed,
                localSearchIterations: 96
            )
            do {
                let imbalanced = try solver.solve(request)
                let cleared = try solver.solve(clearedRequest)
                let imbalancedMean = meanEffect(imbalanced)
                let clearedMean = meanEffect(cleared)
                y1Runs.append(
                    Y1Run(
                        profile: source.id,
                        imbalancedMean: imbalancedMean,
                        clearedMean: clearedMean,
                        delta: clearedMean - imbalancedMean
                    )
                )
            } catch {
                continue
            }
        }

        let sevenDayTimes = runs
            .filter { $0.horizon == 7 }
            .map(\.solveMilliseconds)
        let output = GateOutput(
            sourceCandidateCount: candidates.count,
            roleEligibleCount: candidates.filter {
                $0.roleEligibleAsComponent
            }.count,
            roleIneligibleCount: candidates.filter {
                !$0.roleEligibleAsComponent
            }.count,
            notReadyToEatCount: candidates.filter(\.notReadyToEat).count,
            planCount: runs.filter(\.producedPlan).count,
            runs: runs,
            y1Runs: y1Runs,
            y1MeanDelta: mean(y1Runs.map(\.delta)),
            maximumSevenDaySolveMilliseconds: sevenDayTimes.max() ?? 0,
            profileDiagnostics: capturedDiagnostics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private static func solverProfile(
        _ source: GateProfile,
        enableAyurvedicScoring: Bool
    ) -> MP5SolverProfile {
        let allergens = Set(source.allergens.map {
            $0 == "peanuts" ? "peanut" : $0
        })
        return MP5SolverProfile(
            dailyKcal: Double(source.kcal),
            dailyProteinTarget: Double(source.kcal) * 0.04,
            ageInMonths: 360,
            diet: source.diet,
            allergenConcepts: allergens,
            excludedFoodIDs: [],
            dosha: source.dosha.flatMap(MP5Dosha.init(rawValue:)),
            agni: MP5Agni(rawValue: source.agni) ?? .balanced,
            season: "summer",
            enableAyurvedicScoring: enableAyurvedicScoring
        )
    }

    private static func slots(days: Int) -> [MP5MealSlot] {
        (1...days).flatMap { day in
            ["Breakfast", "Lunch", "Dinner"].map {
                MP5MealSlot(day: day, name: $0)
            }
        }
    }

    private static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }
            .joined()
    }

    private static func profileDiagnostics(
        _ profile: String,
        _ value: MP7SolverDiagnostics
    ) -> ProfileDiagnostics {
        ProfileDiagnostics(
            profile: profile,
            eligibilityFilterMilliseconds: milliseconds(
                value.eligibilityFilterNanoseconds
            ),
            eligibilityFilterScans: value.eligibilityFilterScans,
            allowedCandidateCount: value.allowedCandidateCount,
            mealPoolFilterMilliseconds: milliseconds(
                value.mealPoolFilterNanoseconds
            ),
            mealPoolFilterScans: value.mealPoolFilterScans,
            greedyConstructionMilliseconds: milliseconds(
                value.greedyConstructionNanoseconds
            ),
            greedySelectionScoreMilliseconds: milliseconds(
                value.greedySelectionScoreNanoseconds
            ),
            greedySelectionScoreCalls: value.greedySelectionScoreCalls,
            greedySortMilliseconds: milliseconds(
                value.greedySortNanoseconds
            ),
            greedyRankSortMilliseconds: milliseconds(
                value.greedyRankSortNanoseconds
            ),
            greedyDensitySortMilliseconds: milliseconds(
                value.greedyDensitySortNanoseconds
            ),
            greedyDescendingKcalSortMilliseconds: milliseconds(
                value.greedyDescendingKcalSortNanoseconds
            ),
            greedyAscendingKcalSortMilliseconds: milliseconds(
                value.greedyAscendingKcalSortNanoseconds
            ),
            greedySortInputRows: value.greedySortInputRows,
            greedyModeMilliseconds: milliseconds(
                value.greedyModeNanoseconds
            ),
            greedyModeSequenceScans: value.greedyModeSequenceScans,
            greedyModeCandidateEvaluations:
                value.greedyModeCandidateEvaluations,
            localSearchMilliseconds: milliseconds(
                value.localSearchNanoseconds
            ),
            localSearchIterations: value.localSearchIterations,
            localReplacementFilterMilliseconds: milliseconds(
                value.localReplacementFilterNanoseconds
            ),
            localReplacementFilterScans:
                value.localReplacementFilterScans,
            localRoleCheckMilliseconds: milliseconds(
                value.localRoleCheckNanoseconds
            ),
            localRoleCheckCalls: value.localRoleCheckCalls,
            localHardValidationMilliseconds: milliseconds(
                value.localHardValidationNanoseconds
            ),
            localHardValidationCalls:
                value.localHardValidationCalls,
            localObjectiveMilliseconds: milliseconds(
                value.localObjectiveNanoseconds
            ),
            localObjectiveCalls: value.localObjectiveCalls,
            portionClampMilliseconds: milliseconds(
                value.portionClampNanoseconds
            ),
            portionClampCalls: value.portionClampCalls,
            nearDuplicateMilliseconds: milliseconds(
                value.nearDuplicateNanoseconds
            ),
            nearDuplicateCalls: value.nearDuplicateCalls,
            finalValidationMilliseconds: milliseconds(
                value.finalValidationNanoseconds
            )
        )
    }

    private static func meanEffect(_ plan: MP5SolvedPlan) -> Double {
        mean(plan.components.map { Double($0.doshaEffect) })
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
