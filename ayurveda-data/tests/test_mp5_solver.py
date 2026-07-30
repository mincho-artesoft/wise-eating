import gzip
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOLVER = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "DeterministicMealPlanSolver.swift"
)
ADAPTER = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "DeterministicMealPlanSolver+Ayura.swift"
)
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
HARNESS = ROOT / "ayurveda-data" / "tests" / "mp5_solver_harness.swift"
CORPUS = (
    ROOT
    / "ayurveda-data"
    / "tests"
    / "plan-validity-properties.json"
)
FOOD_ROLES = ROOT / "Ayura" / "food_roles.json.gz"


class MP5DeterministicSolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mp5-solver-tests-")
        cls.binary = Path(cls.temporary.name) / "mp5_solver_harness"
        compile_result = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-O",
                str(SOLVER),
                str(HARNESS),
                "-o",
                str(cls.binary),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if compile_result.returncode != 0:
            raise AssertionError(
                "MP-5 harness compilation failed:\n"
                + compile_result.stdout
                + compile_result.stderr
            )
        run_result = subprocess.run(
            [str(cls.binary), str(CORPUS)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if run_result.returncode != 0:
            raise AssertionError(
                f"MP-5 harness exited {run_result.returncode}:\n"
                + run_result.stdout
                + run_result.stderr
            )
        cls.result = json.loads(run_result.stdout)
        cls.properties = {
            item["id"]: item for item in cls.result["properties"]
        }

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_all_30_hard_properties_pass(self):
        self.assertEqual(self.result["hardTotal"], 30)
        self.assertEqual(self.result["hardPassed"], 30)
        failed = [
            item["id"]
            for item in self.result["properties"]
            if item["severity"] == "hard" and not item["passed"]
        ]
        self.assertEqual(failed, [])

    def test_all_16_soft_properties_are_measured(self):
        self.assertEqual(self.result["softTotal"], 16)
        self.assertEqual(self.result["softMeasured"], 16)

    def test_harness_role_table_matches_shipped_role_definitions(self):
        with gzip.open(FOOD_ROLES, "rt", encoding="utf-8") as source:
            shipped = json.load(source)["definitions"]

        actual = {
            item["id"]: {
                "anchor": item["anchor"],
                "maxPerMeal": item["maxPerMeal"],
                "eligibleAsComponent": item["eligibleAsComponent"],
                "minimumGrams": item["minimumGrams"],
                "maximumGrams": item["maximumGrams"],
            }
            for item in self.result["roleDefinitions"]
        }
        expected = {
            item["id"]: {
                "anchor": item["anchor"],
                "maxPerMeal": item["maxPerMeal"],
                "eligibleAsComponent": item["eligibleAsComponent"],
                "minimumGrams": item["portionGrams"]["min"],
                "maximumGrams": item["portionGrams"]["max"],
            }
            for item in shipped
        }

        self.assertEqual(set(actual), set(expected))
        self.assertEqual(actual, expected)

    def test_c1_through_c10_are_measured_and_hard_checks_pass(self):
        for index in range(1, 11):
            finding = self.properties[f"C{index}"]
            self.assertGreater(finding["applicableRuns"], 0)
            if finding["severity"] == "hard":
                self.assertTrue(finding["passed"], finding["detail"])

    def test_y1_dosha_signal_changes_selection(self):
        self.assertLess(self.result["y1ImbalancedMean"], 0)
        self.assertGreater(self.result["y1Delta"], 0)
        self.assertTrue(self.properties["Y1"]["passed"])

    def test_p10_is_honestly_infeasible(self):
        self.assertEqual(self.result["infeasibleCount"], 3)
        self.assertTrue(self.properties["F1"]["passed"])
        self.assertTrue(self.properties["F2"]["passed"])
        self.assertIn("allergen", self.properties["F2"]["detail"].lower())

    def test_extreme_calorie_profiles_are_reachable(self):
        p7_min, p7_max = self.result["p7KcalRange"]
        p8_min, p8_max = self.result["p8KcalRange"]
        self.assertAlmostEqual(p7_min, 1200, places=6)
        self.assertAlmostEqual(p7_max, 1200, places=6)
        self.assertAlmostEqual(p8_min, 3600, places=6)
        self.assertAlmostEqual(p8_max, 3600, places=6)

    def test_determinism_properties_pass(self):
        self.assertTrue(self.properties["D1"]["passed"])
        self.assertTrue(self.properties["D2"]["passed"])

    def test_ayurvedic_precedence_is_asserted(self):
        source = SOLVER.read_text(encoding="utf-8")
        self.assertIn(
            "rasa < vipaka && vipaka < virya && virya < prabhava",
            source,
        )

    def test_solver_path_has_no_foundation_models_or_model_calls(self):
        solver_source = SOLVER.read_text(encoding="utf-8")
        adapter_source = ADAPTER.read_text(encoding="utf-8")
        planner_source = PLANNER.read_text(encoding="utf-8")
        self.assertNotIn("FoundationModels", solver_source)
        self.assertNotIn("FoundationModels", adapter_source)
        self.assertNotIn("LanguageModelSession", solver_source)
        self.assertNotIn("LanguageModelSession", adapter_source)
        assembly = planner_source.split(
            "// --- Checkpoint 2: deterministic assembly ---",
            1,
        )[1].split("return preview", 1)[0]
        self.assertNotIn("LanguageModelSession", assembly)
        self.assertNotIn(".respond(", assembly)

    def test_feature_flag_is_named_and_off_by_default(self):
        source = SOLVER.read_text(encoding="utf-8")
        self.assertIn('"MP5AyurvedicSolverEnabled"', source)
        self.assertIn('"-mp5AyurvedicSolver"', source)
        self.assertNotIn(
            'register(defaults: ["MP5AyurvedicSolverEnabled": true])',
            source,
        )

    def test_legacy_repair_pipeline_is_deleted(self):
        combined = (
            PLANNER.read_text(encoding="utf-8")
            + "\n"
            + MODELS.read_text(encoding="utf-8")
        )
        for symbol in (
            "generateFullPlanWithAI",
            "AIConceptualPlanResponse1D",
            "AIConceptualPlanResponse2D",
            "AIConceptualPlanResponse3D",
            "AIConceptualPlanResponse4D",
            "AIConceptualPlanResponse5D",
            "AIConceptualPlanResponse6D",
            "AIConceptualPlanResponse7D",
            "aiGenerateFoodPaletteForCuisine",
            "aiGenerateFoodPaletteForHeadword",
            "aiGenerateFoodPalette(",
            "aiGenerateVariantsOnly",
            "aiInferContextTags",
            "isPlanStructureValid",
            "remapDuplicateDays",
            "ensureIncludedFoodsPlaced",
            "removeBannedCuisineKeywords",
            "trimToRequestedDaysAndMeals",
            "normalizeMealsToRequestedOrder",
            "specializeStructuralRequestsWithHeadwords",
        ):
            self.assertNotIn(symbol, combined)


if __name__ == "__main__":
    unittest.main()
