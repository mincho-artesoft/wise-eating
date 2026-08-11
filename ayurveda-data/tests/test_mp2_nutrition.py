import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLANNER = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "USDAWeeklyMealPlanner.swift"
)
MODELS = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "AIMealPlanModels.swift"
)
SOLVER = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "DeterministicMealPlanSolver.swift"
)
SOLVER_ADAPTER = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "DeterministicMealPlanSolver+AyurvedaAsanaYoga.swift"
)


class MP2NutritionTruthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = PLANNER.read_text(encoding="utf-8")
        start_marker = "// MP2_TESTABLE_BEGIN"
        end_marker = "// MP2_TESTABLE_END"
        if source.count(start_marker) != 1 or source.count(end_marker) != 1:
            raise AssertionError("MP-2 testable helper markers must each occur once")
        helper = source.split(start_marker, 1)[1].split(end_marker, 1)[0]

        cls._temp_dir = tempfile.TemporaryDirectory(prefix="mp2-nutrition-tests-")
        temp_root = Path(cls._temp_dir.name)
        swift_source = temp_root / "MP2NutritionTests.swift"
        cls._binary = temp_root / "MP2NutritionTests"
        swift_source.write_text(
            "import Foundation\n"
            + helper
            + r'''

let tolerance = 1e-9

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

func close(_ actual: Double, _ expected: Double, _ message: String) {
    require(abs(actual - expected) <= tolerance,
            "\(message): expected \(expected), got \(actual)")
}

func item(
    meal: Int = 0,
    index: Int = 0,
    name: String = "fixture",
    grams: Double,
    kcalPerGram: Double = 1,
    referenceWeight: Double = 100,
    protein: Double,
    fat: Double = 0,
    carbs: Double = 0
) -> PlannerResolvedMacroItem {
    PlannerResolvedMacroItem(
        mealIndex: meal,
        itemIndex: index,
        name: name,
        grams: grams,
        caloriesPerGram: kcalPerGram,
        referenceWeightGrams: referenceWeight,
        proteinPerReference: protein,
        fatPerReference: fat,
        carbohydratesPerReference: carbs
    )
}

guard CommandLine.arguments.count == 2 else {
    fatalError("one scenario argument required")
}

let scenario = CommandLine.arguments[1]
switch scenario {
case "fidelity":
    let input = [
        item(meal: 0, index: 0, name: "chicken", grams: 150,
             kcalPerGram: 1.65, protein: 31, fat: 3.6),
        item(meal: 0, index: 1, name: "rice", grams: 200,
             kcalPerGram: 1.30, protein: 2.7, fat: 0.3, carbs: 28),
        item(meal: 1, index: 0, name: "oil", grams: 10,
             kcalPerGram: 9, protein: 0, fat: 100)
    ]
    let result = PlannerMacroGoalAdjuster.adjust(
        items: input,
        targets: [],
        unresolvedComponentCount: 0
    )
    close(result.before.protein, 51.9, "protein sum")
    close(result.before.fat, 16.0, "fat sum")
    close(result.before.carbohydrates, 56.0, "carbohydrate sum")
    close(result.after.protein, result.before.protein, "no-goal protein")
    close(result.after.fat, result.before.fat, "no-goal fat")
    close(result.after.carbohydrates, result.before.carbohydrates,
          "no-goal carbohydrates")

case "single":
    let input = [
        item(name: "single", grams: 100, kcalPerGram: 2,
             protein: 10, fat: 5, carbs: 20)
    ]
    let result = PlannerMacroGoalAdjuster.adjust(
        items: input,
        targets: [
            PlannerMacroTarget(
                nutrient: .protein,
                constraint: .exactly,
                value: 20
            )
        ],
        unresolvedComponentCount: 0
    )
    require(result.items.count == 1, "single item count changed")
    close(result.items[0].grams, 200, "single-item adjusted grams")
    close(result.after.protein, 20, "single-item protein")
    close(result.items[0].caloriesPerGram * result.items[0].grams,
          400, "single-item calories")

case "zero":
    let input = [
        item(name: "zero", grams: 0, kcalPerGram: 3, protein: 20)
    ]
    let result = PlannerMacroGoalAdjuster.adjust(
        items: input,
        targets: [
            PlannerMacroTarget(
                nutrient: .protein,
                constraint: .moreThan,
                value: 20
            )
        ],
        unresolvedComponentCount: 0
    )
    close(result.before.protein, 0, "zero-gram pre total")
    close(result.after.protein, 0, "zero-gram post total")
    close(result.items[0].grams, 0, "zero-gram guard")
    require(result.after.protein.isFinite, "zero-gram total is not finite")

case "unresolved":
    let deliberatelyUnresolvable: PlannerResolvedMacroItem? = nil
    let fixture: [PlannerResolvedMacroItem?] = [
        item(name: "resolved", grams: 100, protein: 10),
        deliberatelyUnresolvable
    ]
    let resolvedItems = fixture.compactMap { $0 }
    let unresolvedCount = fixture.count - resolvedItems.count
    let result = PlannerMacroGoalAdjuster.adjust(
        items: resolvedItems,
        targets: [
            PlannerMacroTarget(
                nutrient: .protein,
                constraint: .exactly,
                value: 20
            )
        ],
        unresolvedComponentCount: unresolvedCount
    )
    require(result.unresolvedComponentCount == 1,
            "unresolved component count was not preserved")
    require(result.items.count == 1,
            "unresolved component entered goal math")
    close(result.after.protein, 20,
          "unresolved component changed resolved-only macro math")

case "floor":
    // Production's estimated daily-calorie floor is 1,400 kcal.
    let input = [
        item(name: "floor", grams: 100, kcalPerGram: 14, protein: 10)
    ]
    let result = PlannerMacroGoalAdjuster.adjust(
        items: input,
        targets: [
            PlannerMacroTarget(
                nutrient: .protein,
                constraint: .moreThan,
                value: 10
            )
        ],
        unresolvedComponentCount: 0
    )
    close(result.items[0].grams, 100, "floor boundary grams")
    close(result.after.protein, 10, "floor boundary total")
    close(result.items[0].caloriesPerGram * result.items[0].grams,
          1_400, "daily calorie floor")

case "ceiling":
    // A 2,000 kcal target's unchanged 105% rebalance ceiling is 2,100 kcal.
    let input = [
        item(name: "ceiling", grams: 100, kcalPerGram: 21, protein: 10)
    ]
    let result = PlannerMacroGoalAdjuster.adjust(
        items: input,
        targets: [
            PlannerMacroTarget(
                nutrient: .protein,
                constraint: .lessThan,
                value: 10
            )
        ],
        unresolvedComponentCount: 0
    )
    close(result.items[0].grams, 100, "ceiling boundary grams")
    close(result.after.protein, 10, "ceiling boundary total")
    close(result.items[0].caloriesPerGram * result.items[0].grams,
          2_100, "daily calorie ceiling")

case "structure":
    let input = [
        item(meal: 0, index: 0, name: "a", grams: 100, protein: 10),
        item(meal: 0, index: 1, name: "b", grams: 80, protein: 20),
        item(meal: 1, index: 0, name: "c", grams: 120, protein: 15)
    ]
    let result = PlannerMacroGoalAdjuster.adjust(
        items: input,
        targets: [
            PlannerMacroTarget(
                nutrient: .protein,
                constraint: .exactly,
                value: 55
            )
        ],
        unresolvedComponentCount: 0
    )
    require(result.items.count == input.count, "item count changed")
    for index in input.indices {
        require(result.items[index].mealIndex == input[index].mealIndex,
                "meal order changed")
        require(result.items[index].itemIndex == input[index].itemIndex,
                "item order changed")
        require(result.items[index].name == input[index].name,
                "item name changed")
        require(result.items[index].grams > 0,
                "adjustment produced a non-positive portion")
    }
    require(Set(result.items.map(\.mealIndex)).count == 2,
            "meal count changed")

default:
    fatalError("unknown scenario \(scenario)")
}

print("PASS \(scenario)")
''',
            encoding="utf-8",
        )
        compile_result = subprocess.run(
            ["xcrun", "swiftc", str(swift_source), "-o", str(cls._binary)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if compile_result.returncode != 0:
            raise AssertionError(
                "isolated MP-2 helper did not compile:\n"
                + compile_result.stdout
                + compile_result.stderr
            )

    @classmethod
    def tearDownClass(cls):
        cls._temp_dir.cleanup()

    def run_scenario(self, scenario):
        result = subprocess.run(
            [str(self._binary), scenario],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(
            result.returncode,
            0,
            msg=result.stdout + result.stderr,
        )
        self.assertEqual(result.stdout.strip(), f"PASS {scenario}")

    def test_fixed_resolved_plan_equals_fooditem_derived_sum(self):
        self.run_scenario("fidelity")

    def test_single_item_meal_adjustment(self):
        self.run_scenario("single")

    def test_zero_gram_guard_is_finite_and_not_adjustable(self):
        self.run_scenario("zero")

    def test_unresolved_component_is_excluded_and_counted(self):
        self.run_scenario("unresolved")

    def test_more_than_floor_boundary_is_stable(self):
        self.run_scenario("floor")

    def test_less_than_ceiling_boundary_is_stable(self):
        self.run_scenario("ceiling")

    def test_adjustment_preserves_structure_order_and_positive_portions(self):
        self.run_scenario("structure")

    def test_production_solver_uses_resolved_usda_macro_truth(self):
        planner = PLANNER.read_text(encoding="utf-8")
        models = MODELS.read_text(encoding="utf-8")
        solver = SOLVER.read_text(encoding="utf-8")
        adapter = SOLVER_ADAPTER.read_text(encoding="utf-8")
        self.assertIn("let referenceWeight = compact.referenceWeightG", adapter)
        self.assertIn("let scale = 100 / referenceWeight", adapter)
        self.assertIn("compact.nutrientValues[.energy]", adapter)
        self.assertIn("compact.nutrientValues[.protein]", adapter)
        self.assertIn("compact.nutrientValues[.carbs]", adapter)
        self.assertIn("compact.nutrientValues[.totalFat]", adapter)
        self.assertIn("compact.nutrientValues[.fiber]", adapter)
        self.assertIn("guard referenceWeight > 0", adapter)
        self.assertIn("rawEnergy > 0", adapter)
        self.assertIn("kcal: candidate.kcalPer100g * factor", solver)
        self.assertIn("protein: candidate.proteinPer100g * factor", solver)
        self.assertIn(
            'beginStage("deterministic_assembly")',
            planner,
        )
        for removed_symbol in (
            "aiFetch" + "NutritionData",
            "AINutrition" + "Info",
            "AINutrition" + "Response",
        ):
            self.assertNotIn(removed_symbol, planner)
            self.assertNotIn(removed_symbol, models)

    def test_telemetry_static_nutrition_site_is_removed(self):
        planner = PLANNER.read_text(encoding="utf-8")
        # MP-5 removes complete-plan generation and repair sites; MP-4 adds
        # exactly one shared intent session and one guided response. MP-6
        # removes the per-title polish session from this file; its single
        # batched narrator is isolated in the Foundation Models adapter.
        self.assertEqual(planner.count("LanguageModelSession("), 8)
        self.assertEqual(planner.count(".respond("), 8)
        self.assertIn('site: "mealPlanIntentParse"', planner)
        assembly = planner.split(
            "// --- Checkpoint 2: deterministic assembly ---",
            1,
        )[1].split("return preview", 1)[0]
        self.assertNotIn("LanguageModelSession", assembly)
        self.assertNotIn(".respond(", assembly)
        removed_site = "aiFetch" + "NutritionData"
        self.assertNotIn(f'noteSession(site: "{removed_site}")', planner)
        self.assertNotIn(
            f'noteRespond(\n                    site: "{removed_site}"',
            planner,
        )


if __name__ == "__main__":
    unittest.main()
