import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REQUEST = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "MealPlanRequest.swift"
)
PLANNER = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "USDAWeeklyMealPlanner.swift"
)
TELEMETRY = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "PlannerTelemetry.swift"
)


class MP4IntentParseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mp4-intent-tests-")
        temporary_root = Path(cls.temporary.name)
        harness = temporary_root / "MP4IntentHarness.swift"
        cls.binary = temporary_root / "mp4-intent-harness"
        harness.write_text(
            r'''
import Foundation

struct FallbackRecord: Codable {
    let id: String
    let days: Int
    let mealsPerDay: Int
    let statedKcal: Int
    let avoid: [String]
    let allergens: [String]
    let dosha: String?
    let agni: String?
}

struct SanitizerRecord: Codable {
    let id: String
    let days: Int
    let statedKcal: Int
    let messages: [String]
}

func fallbackRecord(_ id: String, _ prompt: String) -> FallbackRecord {
    let request = FallbackParser.parse(prompt)
    return FallbackRecord(
        id: id,
        days: request.days,
        mealsPerDay: request.mealsPerDay,
        statedKcal: request.statedKcal,
        avoid: request.avoid,
        allergens: request.allergens.map(\.rawValue),
        dosha: request.doshaFocus?.rawValue,
        agni: request.agni?.rawValue
    )
}

@main
struct MP4IntentHarness {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            fatalError("scenario required")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        switch CommandLine.arguments[1] {
        case "fallback":
            let records = [
                fallbackRecord(
                    "light-week",
                    "light vegetarian week, no dairy, trying to lose a bit, digestion is sluggish"
                ),
                fallbackRecord(
                    "three-day",
                    "3 day plan around 1800 calories, no mushrooms please"
                ),
                fallbackRecord(
                    "vegan-peanut",
                    "I'm vegan and allergic to peanuts, make me a week of meals"
                ),
                fallbackRecord(
                    "tomorrow",
                    "just tomorrow, two meals, I have acid reflux"
                ),
                fallbackRecord(
                    "pitta",
                    "my pitta is high, cooling food for 5 days, skip chillies"
                ),
                fallbackRecord(
                    "gluten-muscle",
                    "gluten free week for muscle gain, 2800 kcal"
                ),
                fallbackRecord(
                    "positive-dairy",
                    "I love cheese and paneer, vegetarian week please"
                ),
                fallbackRecord(
                    "weekend",
                    "weekend plan, nothing too heavy, I get bloated easily"
                ),
                fallbackRecord(
                    "shellfish",
                    "pescatarian, no shellfish, 4 days"
                ),
                fallbackRecord(
                    "kapha",
                    "kapha imbalance, want lighter meals for a week"
                ),
            ]
            print(String(data: try encoder.encode(records), encoding: .utf8)!)

        case "sanitizer":
            let low = RequestSanitizer.sanitize(
                FallbackParser.parse("500 calories a day for a week"),
                computedMaintenanceKcal: 2_000
            )
            let high = RequestSanitizer.sanitize(
                FallbackParser.parse("9000 calories, 7 days, vegan"),
                computedMaintenanceKcal: 2_000
            )
            let records = [
                SanitizerRecord(
                    id: "low",
                    days: low.request.days,
                    statedKcal: low.request.statedKcal,
                    messages: low.adjustments.map(\.message)
                ),
                SanitizerRecord(
                    id: "high",
                    days: high.request.days,
                    statedKcal: high.request.statedKcal,
                    messages: high.adjustments.map(\.message)
                ),
            ]
            print(String(data: try encoder.encode(records), encoding: .utf8)!)

        case "determinism":
            let prompt = "3 day vegan plan, no peanuts, prefer mung dal"
            let first = FallbackParser.parse(prompt)
            let identical = (0..<100).allSatisfy { _ in
                FallbackParser.parse(prompt) == first
            }
            print(identical ? "PASS determinism" : "FAIL determinism")

        case "telemetry":
            guard CommandLine.arguments.count >= 3,
                  let promptCount = Int(CommandLine.arguments[2]) else {
                fatalError("telemetry prompt count required")
            }
            let prompts = (1...promptCount).map { "prompt \($0)" }
            var closureCalls = 0
            await PlannerTelemetry.shared.reset(label: "mp4-\(promptCount)")
            await PlannerTelemetry.shared.beginStage("interpretation")
            let outcome = await MealPlanIntentCoordinator.parse(
                prompts: prompts,
                modelAvailable: true,
                modelResponse: { _ in
                    closureCalls += 1
                    await PlannerTelemetry.shared.noteSession(
                        site: "mealPlanIntentParse"
                    )
                    return ParsedRequest()
                },
                onModelCall: { ok, elapsed in
                    await PlannerTelemetry.shared.noteRespond(
                        site: "mealPlanIntentParse",
                        ok: ok,
                        ms: elapsed
                    )
                }
            )
            await PlannerTelemetry.shared.endStage("interpretation")
            let summary = await PlannerTelemetry.shared.summary()
            print(summary)
            print(
                "MP4-CALL-GATE prompts=\(promptCount) "
                    + "closureCalls=\(closureCalls) "
                    + "fallback=\(outcome.usedFallback)"
            )

        default:
            fatalError("unknown scenario")
        }
    }
}
''',
            encoding="utf-8",
        )
        compile_result = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(REQUEST),
                str(TELEMETRY),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if compile_result.returncode != 0:
            raise AssertionError(
                "MP-4 production parser harness did not compile:\n"
                + compile_result.stdout
                + compile_result.stderr
            )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_harness(self, scenario, *arguments, telemetry=False):
        command = [str(self.binary), scenario, *map(str, arguments)]
        if telemetry:
            command.append("-ayurvedaasanayogaPlannerTelemetry")
        result = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_fallback_reference_cases(self):
        records = {
            row["id"]: row
            for row in json.loads(self.run_harness("fallback"))
        }
        self.assertEqual(len(records), 10)

        self.assertEqual(records["light-week"]["days"], 7)
        self.assertEqual(records["light-week"]["agni"], "slow")
        self.assertIn("dairy", records["light-week"]["allergens"])

        self.assertEqual(records["three-day"]["days"], 3)
        self.assertEqual(records["three-day"]["statedKcal"], 1800)
        self.assertIn("mushrooms", records["three-day"]["avoid"])

        self.assertEqual(records["vegan-peanut"]["days"], 7)
        self.assertEqual(records["vegan-peanut"]["allergens"], ["peanuts"])

        self.assertEqual(records["tomorrow"]["days"], 1)
        self.assertEqual(records["tomorrow"]["mealsPerDay"], 2)
        self.assertEqual(records["tomorrow"]["agni"], "sharp")

        self.assertEqual(records["pitta"]["days"], 5)
        self.assertEqual(records["pitta"]["dosha"], "pitta")

        self.assertEqual(records["gluten-muscle"]["days"], 7)
        self.assertEqual(records["gluten-muscle"]["statedKcal"], 2800)
        self.assertIn("gluten", records["gluten-muscle"]["allergens"])

        self.assertEqual(records["positive-dairy"]["allergens"], [])

        self.assertEqual(records["weekend"]["days"], 2)

        self.assertEqual(records["shellfish"]["days"], 4)
        self.assertEqual(records["shellfish"]["allergens"], ["shellfish"])

        self.assertEqual(records["kapha"]["days"], 7)
        self.assertEqual(records["kapha"]["dosha"], "kapha")

    def test_sanitizer_adversarial_cases(self):
        records = {
            row["id"]: row
            for row in json.loads(self.run_harness("sanitizer"))
        }
        self.assertEqual(records["low"]["days"], 7)
        self.assertEqual(records["low"]["statedKcal"], 1200)
        self.assertTrue(records["low"]["messages"])
        self.assertIn("Raised", records["low"]["messages"][0])
        self.assertEqual(records["high"]["days"], 7)
        self.assertEqual(records["high"]["statedKcal"], 3200)
        self.assertTrue(records["high"]["messages"])
        self.assertIn("Capped", records["high"]["messages"][0])

    def test_fallback_is_deterministic(self):
        self.assertEqual(
            self.run_harness("determinism"),
            "PASS determinism",
        )

    def test_one_telemetry_call_for_1_3_and_6_prompts(self):
        for prompt_count in (1, 3, 6):
            output = self.run_harness(
                "telemetry",
                prompt_count,
                telemetry=True,
            )
            self.assertIn(
                "MP1-TELEMETRY-SITE: mealPlanIntentParse | 1 | 1 | 0",
                output,
            )
            self.assertRegex(
                output,
                r"MP1-TELEMETRY-STAGE: interpretation \| [0-9.]+ \| 1",
            )
            self.assertIn(
                f"MP4-CALL-GATE prompts={prompt_count} "
                "closureCalls=1 fallback=false",
                output,
            )

    def test_checkpoint_uses_only_the_single_intent_path(self):
        source = PLANNER.read_text(encoding="utf-8")
        start = source.index("// --- Checkpoint 1: Interpretation ---")
        end = source.index(
            "// --- Checkpoint 2: deterministic assembly ---",
            start,
        )
        checkpoint = source[start:end]
        self.assertEqual(checkpoint.count("interpretIntent("), 1)
        for old_call in (
            "aiSplitIntoAtomicPrompts(",
            "aiExtractRequestedFoods(",
            "aiFixAtomsAndFoods(",
            "aiInterpretUserPrompts(",
        ):
            self.assertNotIn(old_call, checkpoint)
        self.assertIn("generating: PlanRequest.self", source)
        self.assertIn("MealPlanIntentCoordinator.parse(", source)

    def test_existing_vocab_and_resolution_are_wired(self):
        source = PLANNER.read_text(encoding="utf-8")
        self.assertIn("private func mappedAllergens(for tags: [AllergenTag])", source)
        self.assertIn("FoodConcepts.shared.canonical(alias: term)", source)
        self.assertIn("resolveFoodConcept(", source)
        self.assertIn("termIsEnforcedByAllergen(term, allergens: allergens)", source)

    def test_availability_fallback_and_prewarm_are_wired(self):
        source = PLANNER.read_text(encoding="utf-8")
        self.assertIn("SystemLanguageModel.default.availability", source)
        self.assertIn("session.prewarm()", source)
        self.assertIn("prewarmedIntentSession", source)
        for relative in (
            "Ayura/AI/Views/AIPlanGenerationView.swift",
            "Ayura/Nutrient/Views/AIDailyMealGeneratorView.swift",
            "Ayura/Meal/Views/MealPlanEditorView.swift",
        ):
            view = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("USDAWeeklyMealPlanner.prewarmIntentModel()", view)

    def test_caveat_survives_resume_and_result_merging(self):
        progress = (
            ROOT
            / "Ayura"
            / "AI"
            / "MealPlanning"
            / "MealPlanGenerationProgress.swift"
        ).read_text(encoding="utf-8")
        models = (
            ROOT
            / "Ayura"
            / "AI"
            / "MealPlanning"
            / "AIMealPlanModels.swift"
        ).read_text(encoding="utf-8")
        manager = (ROOT / "Ayura" / "AI" / "AIManager.swift").read_text(
            encoding="utf-8"
        )
        host = (
            ROOT
            / "Ayura"
            / "AI"
            / "Views"
            / "AIGenerationHostView.swift"
        ).read_text(encoding="utf-8")
        self.assertGreaterEqual(progress.count("interpretationCaveat"), 5)
        self.assertIn("public let interpretationCaveat: String?", models)
        self.assertIn(
            "interpretationCaveat: generatedPreview.interpretationCaveat",
            manager,
        )
        self.assertIn("job.result?.interpretationCaveat", host)


if __name__ == "__main__":
    unittest.main()
