import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MEAL_PLANNING = ROOT / "WiseEating" / "AI" / "MealPlanning"
NARRATION = MEAL_PLANNING / "MealPlanNarration.swift"
FOUNDATION_MODELS_NARRATOR = (
    MEAL_PLANNING / "MealPlanNarrator+FoundationModels.swift"
)
REQUEST = MEAL_PLANNING / "MealPlanRequest.swift"
TELEMETRY = MEAL_PLANNING / "PlannerTelemetry.swift"
PLANNER = MEAL_PLANNING / "USDAWeeklyMealPlanner.swift"
MODELS = MEAL_PLANNING / "AIMealPlanModels.swift"


PURE_HARNESS = r'''
import Foundation

actor CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

func facts(days: Int) -> [MP6NarrationFact] {
    let meals = [
        (
            "Breakfast",
            ["Oat porridge", "Stewed apple"],
            412.0,
            15.4,
            ["sweet", "astringent"],
            "warming"
        ),
        (
            "Lunch",
            ["Mung dal kitchari", "Cucumber raita"],
            638.0,
            25.8,
            ["sweet", "salty", "astringent"],
            "mixed"
        ),
        (
            "Dinner",
            ["Pumpkin soup", "Whole-wheat flatbread"],
            521.0,
            19.6,
            ["sweet", "pungent"],
            "cooling"
        ),
    ]
    return (1...days).flatMap { day in
        meals.enumerated().map { index, meal in
            MP6NarrationFact(
                day: day,
                slotIndex: index,
                slotName: meal.0,
                dishNames: meal.1,
                kcal: meal.2 + Double(day - 1) * 7,
                proteinGrams: meal.3,
                tastes: meal.4,
                thermalCharacter: meal.5,
                agni: day == 2 ? "slow" : "balanced"
            )
        }
    }
}

@main
struct MP6PureHarness {
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            fatalError("scenario required")
        }

        switch CommandLine.arguments[1] {
        case "template3":
            let titles = MP6TemplateNarrator.narrate(facts(days: 3))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(
                String(
                    data: try encoder.encode(titles),
                    encoding: .utf8
                )!
            )

        case "mismatch":
            let supplied = facts(days: 3)
            let counter = CallCounter()
            let outcome = await MP6NarrationCoordinator.narrate(
                facts: supplied,
                modelAvailable: true,
                modelResponse: { modelFacts in
                    await counter.increment()
                    return MP6TemplateNarrator.narrate(
                        Array(modelFacts.dropLast())
                    )
                }
            )
            print(
                "MP6-MISMATCH calls=\(await counter.value()) "
                    + "fallback=\(outcome.usedTemplate) "
                    + "count=\(outcome.titles.count) "
                    + "reason=\(outcome.fallbackReason ?? "none")"
            )

        case "determinism":
            let supplied = facts(days: 7)
            let first = MP6TemplateNarrator.narrate(supplied)
            let identical = (0..<100).allSatisfy { _ in
                MP6TemplateNarrator.narrate(supplied) == first
            }
            print(identical ? "PASS determinism" : "FAIL determinism")

        case "timeout":
            let supplied = facts(days: 1)
            let outcome = await MP6NarrationCoordinator.narrate(
                facts: supplied,
                modelAvailable: true,
                wallClockBudgetNanoseconds: 1_000_000,
                modelResponse: { modelFacts in
                    try await Task.sleep(nanoseconds: 250_000_000)
                    return MP6TemplateNarrator.narrate(modelFacts)
                }
            )
            print(
                "MP6-TIMEOUT fallback=\(outcome.usedTemplate) "
                    + "count=\(outcome.titles.count) "
                    + "reason=\(outcome.fallbackReason ?? "none")"
            )

        default:
            fatalError("unknown scenario")
        }
    }
}
'''


TELEMETRY_HARNESS = r'''
import Foundation

actor MP6CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

func telemetryFacts(days: Int) -> [MP6NarrationFact] {
    (1...days).flatMap { day in
        (0..<3).map { slot in
            MP6NarrationFact(
                day: day,
                slotIndex: slot,
                slotName: ["Breakfast", "Lunch", "Dinner"][slot],
                dishNames: ["Resolved dish \(day)-\(slot)"],
                kcal: 500,
                proteinGrams: 20,
                tastes: ["sweet"],
                thermalCharacter: "neutral",
                agni: "balanced"
            )
        }
    }
}

@main
struct MP6TelemetryHarness {
    @MainActor
    static func main() async {
        guard CommandLine.arguments.count >= 3,
              let dayCount = Int(CommandLine.arguments[2]) else {
            fatalError("scenario and day count required")
        }
        let counter = MP6CallCounter()
        await PlannerTelemetry.shared.reset(
            label: "mp6-\(CommandLine.arguments[1])-\(dayCount)"
        )

        if CommandLine.arguments[1] == "endtoend" {
            await PlannerTelemetry.shared.beginStage("interpretation")
            _ = await MealPlanIntentCoordinator.parse(
                prompts: (1...dayCount).map { "day \($0)" },
                modelAvailable: true,
                modelResponse: { _ in
                    await counter.increment()
                    await PlannerTelemetry.shared.noteSession(
                        site: "mealPlanIntentParse"
                    )
                    var request = ParsedRequest()
                    request.days = dayCount
                    return request
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
        }

        await PlannerTelemetry.shared.beginStage("narration")
        let facts = telemetryFacts(days: dayCount)
        let outcome = await MP6NarrationCoordinator.narrate(
            facts: facts,
            modelAvailable: true,
            modelResponse: { modelFacts in
                await counter.increment()
                await PlannerTelemetry.shared.noteSession(
                    site: "mealPlanNarration"
                )
                await PlannerTelemetry.shared.noteRespond(
                    site: "mealPlanNarration",
                    ok: true,
                    ms: 1
                )
                return MP6TemplateNarrator.narrate(modelFacts)
            }
        )
        await PlannerTelemetry.shared.endStage("narration")
        print(await PlannerTelemetry.shared.summary())
        print(
            "MP6-CALL-GATE scenario=\(CommandLine.arguments[1]) "
                + "days=\(dayCount) closureCalls=\(await counter.value()) "
                + "titles=\(outcome.titles.count)"
        )
    }
}
'''


class MP6NarrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mp6-narration-tests-"
        )
        temporary_root = Path(cls.temporary.name)
        pure_harness = temporary_root / "MP6PureHarness.swift"
        telemetry_harness = temporary_root / "MP6TelemetryHarness.swift"
        cls.pure_binary = temporary_root / "mp6-pure-harness"
        cls.telemetry_binary = temporary_root / "mp6-telemetry-harness"
        pure_harness.write_text(PURE_HARNESS, encoding="utf-8")
        telemetry_harness.write_text(TELEMETRY_HARNESS, encoding="utf-8")

        pure_compile = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(NARRATION),
                str(pure_harness),
                "-o",
                str(cls.pure_binary),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if pure_compile.returncode != 0:
            raise AssertionError(
                "MP-6 pure template harness did not compile:\n"
                + pure_compile.stdout
                + pure_compile.stderr
            )

        telemetry_compile = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(NARRATION),
                str(REQUEST),
                str(TELEMETRY),
                str(telemetry_harness),
                "-o",
                str(cls.telemetry_binary),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if telemetry_compile.returncode != 0:
            raise AssertionError(
                "MP-6 telemetry harness did not compile:\n"
                + telemetry_compile.stdout
                + telemetry_compile.stderr
            )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_pure(self, scenario):
        result = subprocess.run(
            [str(self.pure_binary), scenario],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def run_telemetry(self, scenario, days):
        result = subprocess.run(
            [
                str(self.telemetry_binary),
                scenario,
                str(days),
                "-wePlannerTelemetry",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_one_narration_call_for_1_3_and_7_days(self):
        for days in (1, 3, 7):
            output = self.run_telemetry("narration", days)
            self.assertIn(
                "MP1-TELEMETRY-SITE: mealPlanNarration | 1 | 1 | 0",
                output,
            )
            self.assertIn(
                f"MP6-CALL-GATE scenario=narration days={days} "
                f"closureCalls=1 titles={days * 3}",
                output,
            )

    def test_three_day_template_is_complete_and_readable(self):
        records = json.loads(self.run_pure("template3"))
        self.assertEqual(len(records), 9)
        for record in records:
            copy = record["title"]
            self.assertGreater(len(copy), 80)
            self.assertRegex(copy, r"\d+ kcal")
            self.assertRegex(copy, r"\d+\.\d g protein")
            self.assertIn("Tastes present:", copy)
            self.assertIn("Traditionally considered", copy)

    def test_title_count_mismatch_falls_back_without_misassignment(self):
        output = self.run_pure("mismatch")
        self.assertEqual(
            output,
            "MP6-MISMATCH calls=1 fallback=true count=9 "
            "reason=title count or index mismatch",
        )

    def test_wall_clock_budget_falls_back(self):
        output = self.run_pure("timeout")
        self.assertEqual(
            output,
            "MP6-TIMEOUT fallback=true count=3 "
            "reason=narration exceeded wall-clock budget",
        )

    def test_template_is_deterministic_and_has_no_foundation_models_link(self):
        self.assertEqual(
            self.run_pure("determinism"),
            "PASS determinism",
        )
        linkage = subprocess.run(
            ["otool", "-L", str(self.pure_binary)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertNotIn("FoundationModels", linkage)
        self.assertNotIn(
            "FoundationModels",
            NARRATION.read_text(encoding="utf-8"),
        )

    def test_end_to_end_seven_day_model_call_total_is_two(self):
        output = self.run_telemetry("endtoend", 7)
        self.assertIn(
            "MP1-TELEMETRY: label=mp6-endtoend-7 "
            "total sessions=2 total responds=2 total failed responds=0",
            output,
        )
        self.assertIn(
            "MP1-TELEMETRY-SITE: mealPlanIntentParse | 1 | 1 | 0",
            output,
        )
        self.assertIn(
            "MP1-TELEMETRY-SITE: mealPlanNarration | 1 | 1 | 0",
            output,
        )
        self.assertIn(
            "MP6-CALL-GATE scenario=endtoend days=7 "
            "closureCalls=2 titles=21",
            output,
        )

    def test_schema_safety_rules_wiring_and_deletions(self):
        narrator = FOUNDATION_MODELS_NARRATOR.read_text(encoding="utf-8")
        planner = PLANNER.read_text(encoding="utf-8")
        models = MODELS.read_text(encoding="utf-8")
        self.assertIn("@Generable", narrator)
        self.assertIn("let titles: [MP6GeneratedNarrationTitle]", narrator)
        self.assertEqual(narrator.count("session.respond("), 1)
        for rule in (
            "Never invent, replace, recommend, or omit a food.",
            "Never invent a weight, calorie, protein, taste, thermal, agni",
            "treats, cures, prevents, or",
            'use the register "Traditionally considered"',
            "qualityState aiDraft pending expert review",
        ):
            self.assertIn(rule, narrator)
        self.assertIn("MP6MealPlanNarrator.narrate(", planner)
        self.assertIn("assembly.narrationFacts", planner)
        self.assertIn(
            ".descriptiveTitle = narratedTitle.title",
            planner,
        )
        for deleted in (
            "aiPolishTitle",
            "diversifyDescriptiveTitlesIfNeeded",
        ):
            self.assertNotIn(deleted, planner)
            self.assertNotIn(deleted, models)


if __name__ == "__main__":
    unittest.main()
