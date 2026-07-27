import Foundation

private struct BaselineCandidate: Decodable {
    let candidate: MP5Candidate
}

@main
private enum MP7BaselineSolverHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("candidate JSON path required")
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let candidates = try JSONDecoder().decode(
            [BaselineCandidate].self,
            from: Data(contentsOf: source)
        ).map(\.candidate)
        let profile = MP5SolverProfile(
            dailyKcal: 2_000,
            dailyProteinTarget: 80,
            ageInMonths: 360,
            diet: "vegetarian",
            allergenConcepts: [],
            excludedFoodIDs: [],
            dosha: nil,
            agni: .balanced,
            season: "varsha",
            enableAyurvedicScoring: false
        )
        let slots = (1...7).flatMap { day in
            ["Breakfast", "Lunch", "Dinner"].map {
                MP5MealSlot(day: day, name: $0)
            }
        }
        let plan = try DeterministicMealPlanSolver(
            candidates: candidates
        ).solve(
            MP5SolverRequest(
                profile: profile,
                slots: slots,
                seed: 0x4D50_3662,
                localSearchIterations: 96
            )
        )
        FileHandle.standardOutput.write(try plan.canonicalData())
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
