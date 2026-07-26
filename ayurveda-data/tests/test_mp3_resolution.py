import gzip
import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLANNER = (
    ROOT
    / "WiseEating"
    / "AI"
    / "MealPlanning"
    / "USDAWeeklyMealPlanner.swift"
)
CORPUS = ROOT / "ayurveda-data" / "tests" / "resolution-goldens.json"
ARTIFACT_PARTS = [
    ROOT / "WiseEating" / "preseeded_db.store.gz.part-aa",
    ROOT / "WiseEating" / "preseeded_db.store.gz.part-ab",
]


class MP3DeterministicResolutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        planner_source = PLANNER.read_text(encoding="utf-8")
        start_marker = "// MP3_TESTABLE_BEGIN"
        end_marker = "// MP3_TESTABLE_END"
        if (
            planner_source.count(start_marker) != 1
            or planner_source.count(end_marker) != 1
        ):
            raise AssertionError("MP-3 helper markers must each occur exactly once")
        helper = planner_source.split(start_marker, 1)[1].split(end_marker, 1)[0]

        cls.temporary = tempfile.TemporaryDirectory(prefix="mp3-resolution-tests-")
        temporary_root = Path(cls.temporary.name)
        store = temporary_root / "preseed.store"
        compressed = b"".join(part.read_bytes() for part in ARTIFACT_PARTS)
        store.write_bytes(gzip.decompress(compressed))

        with sqlite3.connect(store) as connection:
            payload_data = connection.execute(
                """
                SELECT ZPAYLOADDATA FROM ZSEARCHINDEXCACHE
                WHERE ZKEY = 'main' AND ZVERSION = 5
                """
            ).fetchone()[0]
            profile_rows = connection.execute(
                """
                SELECT ZID, ZFOODID, ZENGINEEXCLUDED
                FROM ZAYURVEDAPROFILE
                """
            ).fetchall()
            link_rows = connection.execute(
                """
                SELECT ZFDCID, ZDRAVYAPROFILEID, ZTIER
                FROM ZAYURVEDALINK
                """
            ).fetchall()

        payload = json.loads(payload_data)
        direct_ids = {food_id for _, food_id, _ in profile_rows}
        excluded_profile_ids = {
            profile_id
            for profile_id, _, excluded in profile_rows
            if excluded
        }
        excluded_food_ids = {
            food_id
            for _, food_id, excluded in profile_rows
            if excluded
        }
        link_tiers = {}
        for food_id, profile_id, tier in link_rows:
            link_tiers[food_id] = tier
            if profile_id in excluded_profile_ids:
                excluded_food_ids.add(food_id)

        candidates = []
        for food in payload["compactFoods"]:
            food_id = food["id"]
            if food_id in excluded_food_ids:
                continue
            if food_id in direct_ids:
                tier = "classical"
            elif food_id in link_tiers:
                tier = (
                    "derived"
                    if link_tiers[food_id] == "derived"
                    else "classical"
                )
            else:
                tier = "estimated"
            candidates.append(
                {
                    "id": food_id,
                    "name": food["name"],
                    "isRecipe": food["isRecipe"],
                    "tier": tier,
                }
            )

        cls.catalog_count = len(payload["compactFoods"])
        cls.excluded_count = len(excluded_food_ids)
        cls.candidate_count = len(candidates)
        cls.catalog = temporary_root / "catalog.json"
        cls.catalog.write_text(
            json.dumps(candidates, ensure_ascii=False, sort_keys=True),
            encoding="utf-8",
        )

        harness = temporary_root / "MP3ResolutionHarness.swift"
        cls.binary = temporary_root / "mp3-resolution-harness"
        harness.write_text(
            "import Foundation\n"
            + helper
            + r'''

struct GoldenCorpus: Codable {
    let cases: [GoldenCase]
}

struct GoldenCase: Codable {
    let concept: String
    let mustMatchAny: [String]
    let mustNotMatch: [String]
    let expectUnresolved: Bool?
    let expectRecipe: Bool?
}

struct CorpusRecord: Codable, Equatable {
    let concept: String
    let status: String
    let expectationMet: Bool
    let resolvedName: String?
    let resolvedID: Int?
    let isRecipe: Bool?
    let tier: String?
    let score: Double?
    let missingQualifiers: [String]
    let extraTokens: [String]
}

struct HarnessOutput: Codable {
    let sameSessionIdentical: Bool
    let records: [CorpusRecord]
}

func normalizedTokens(_ value: String) -> Set<String> {
    let folded = value.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
    )
    let normalized = folded.unicodeScalars
        .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
        .joined()
    return Set(
        normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    )
}

func matchesPattern(_ name: String, _ pattern: String) -> Bool {
    let patternTokens = normalizedTokens(pattern)
    guard !patternTokens.isEmpty else { return false }
    let nameTokens = normalizedTokens(name)
    return patternTokens.allSatisfy { patternToken in
        nameTokens.contains { $0.contains(patternToken) }
    }
}

func runCorpus(
    _ corpus: GoldenCorpus,
    candidates: [PlannerPreparedResolutionCandidate]
) -> [CorpusRecord] {
    corpus.cases.map { golden in
        let decision = PlannerDeterministicFoodResolver.resolve(
            concept: golden.concept,
            candidates: candidates
        )
        let expectsUnresolved = golden.expectUnresolved == true
        guard let decision else {
            return CorpusRecord(
                concept: golden.concept,
                status: "UNRESOLVED",
                expectationMet: expectsUnresolved,
                resolvedName: nil,
                resolvedID: nil,
                isRecipe: nil,
                tier: nil,
                score: nil,
                missingQualifiers: [],
                extraTokens: []
            )
        }

        let name = decision.candidate.name
        let positiveMatch = golden.mustMatchAny.contains {
            matchesPattern(name, $0)
        }
        let forbiddenMatch = golden.mustNotMatch.contains {
            matchesPattern(name, $0)
        }
        let recipeMatch = golden.expectRecipe != true
            || decision.candidate.isRecipe
        let passed = !expectsUnresolved
            && positiveMatch
            && !forbiddenMatch
            && recipeMatch
        return CorpusRecord(
            concept: golden.concept,
            status: passed ? "PASS" : "FAIL",
            expectationMet: passed,
            resolvedName: name,
            resolvedID: decision.candidate.id,
            isRecipe: decision.candidate.isRecipe,
            tier: decision.candidate.tier.rawValue,
            score: decision.score,
            missingQualifiers: decision.missingQualifiers,
            extraTokens: decision.extraTokens
        )
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

func syntheticProperties() {
    func candidate(
        _ id: Int,
        _ name: String,
        recipe: Bool = false,
        tier: PlannerResolutionTier = .estimated
    ) -> PlannerResolutionCandidate {
        PlannerResolutionCandidate(
            id: id,
            name: name,
            isRecipe: recipe,
            tier: tier
        )
    }

    let chicken = PlannerDeterministicFoodResolver.resolve(
        concept: "grilled chicken breast",
        candidates: [
            candidate(1, "Beef breast, grilled"),
            candidate(2, "Chicken breast, cooked, roasted"),
        ]
    )
    require(chicken?.candidate.id == 2, "headword weighting failed")

    let milk = PlannerDeterministicFoodResolver.resolve(
        concept: "milk",
        candidates: [
            candidate(3, "Coconut milk"),
            candidate(4, "Milk, whole"),
        ]
    )
    require(milk?.candidate.id == 4, "extra-token penalty failed")

    let tier = PlannerDeterministicFoodResolver.resolve(
        concept: "tomato",
        candidates: [
            candidate(5, "Tomato", tier: .estimated),
            candidate(6, "Tomato", tier: .classical),
        ]
    )
    require(tier?.candidate.id == 6, "tier preference failed")

    let cooked = PlannerDeterministicFoodResolver.resolve(
        concept: "cooked lentils",
        candidates: [
            candidate(7, "Lentils, raw"),
            candidate(8, "Lentils, cooked, boiled"),
        ]
    )
    require(cooked?.candidate.id == 8, "cooked-form preference failed")

    let recipe = PlannerDeterministicFoodResolver.resolve(
        concept: "kitchari",
        candidates: [
            candidate(9, "Kitchari", recipe: false, tier: .classical),
            candidate(10, "Kitchari", recipe: true, tier: .classical),
        ]
    )
    require(recipe?.candidate.id == 10, "recipe preference failed")

    let control = PlannerDeterministicFoodResolver.resolve(
        concept: "unicorn steak",
        candidates: [
            candidate(11, "Beef steak, cooked", tier: .classical),
            candidate(12, "Pork steak, grilled", tier: .derived),
        ]
    )
    require(control == nil, "threshold forced a best-of-bad-options match")
}

@main
struct MP3ResolutionHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            fatalError("usage: harness catalog corpus mode")
        }
        if arguments[3] == "properties" {
            syntheticProperties()
            print("PASS properties")
            return
        }

        let decoder = JSONDecoder()
        let candidates = try decoder.decode(
            [PlannerResolutionCandidate].self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        )
        let preparedCandidates = PlannerDeterministicFoodResolver.prepare(
            candidates
        )
        let corpus = try decoder.decode(
            GoldenCorpus.self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        )
        let first = runCorpus(corpus, candidates: preparedCandidates)
        let second = runCorpus(corpus, candidates: preparedCandidates)
        let output = HarnessOutput(
            sameSessionIdentical: first == second,
            records: first
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
    }
}
''',
            encoding="utf-8",
        )
        compile_result = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-O",
                "-parse-as-library",
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
                "isolated MP-3 helper did not compile:\n"
                + compile_result.stdout
                + compile_result.stderr
            )

        cls.first_output = cls._run_harness()
        cls.clean_relaunch_output = cls._run_harness()
        Path("/tmp/mp3-resolution-corpus.json").write_text(
            json.dumps(cls.first_output, ensure_ascii=False, sort_keys=True),
            encoding="utf-8",
        )
        Path("/tmp/mp3-resolution-corpus-clean.json").write_text(
            json.dumps(
                cls.clean_relaunch_output,
                ensure_ascii=False,
                sort_keys=True,
            ),
            encoding="utf-8",
        )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    @classmethod
    def _run_harness(cls):
        result = subprocess.run(
            [str(cls.binary), str(cls.catalog), str(CORPUS), "corpus"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            raise AssertionError(result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_corpus_and_shipped_catalogue_counts(self):
        corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
        self.assertEqual(len(corpus["cases"]), 59)
        self.assertEqual(
            [
                case["concept"]
                for case in corpus["cases"]
                if case.get("expectUnresolved")
            ],
            ["unicorn steak", "xyzzy", ""],
        )
        self.assertEqual(self.catalog_count, 14_484)
        self.assertEqual(self.excluded_count, 2)
        self.assertEqual(self.candidate_count, 14_482)

    def test_required_scorer_properties(self):
        result = subprocess.run(
            [str(self.binary), str(self.catalog), str(CORPUS), "properties"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "PASS properties")

    def test_control_cases_are_unresolved(self):
        records = {
            record["concept"]: record for record in self.first_output["records"]
        }
        for concept in ("unicorn steak", "xyzzy", ""):
            with self.subTest(concept=concept):
                self.assertEqual(records[concept]["status"], "UNRESOLVED")
                self.assertTrue(records[concept]["expectationMet"])
                self.assertIsNone(records[concept].get("resolvedName"))

    def test_all_positive_corpus_cases_pass(self):
        positive_records = [
            record
            for record in self.first_output["records"]
            if record["status"] != "UNRESOLVED"
        ]
        self.assertEqual(len(positive_records), 56)
        self.assertEqual(
            [
                record
                for record in positive_records
                if not record["expectationMet"]
            ],
            [],
        )

    def test_full_corpus_runs_twice_in_one_session_identically(self):
        self.assertTrue(self.first_output["sameSessionIdentical"])
        self.assertEqual(len(self.first_output["records"]), 59)

    def test_clean_relaunch_is_identical(self):
        self.assertEqual(self.first_output, self.clean_relaunch_output)

    def test_recipe_cases_prefer_recipe_rows_when_resolved(self):
        records = {
            record["concept"]: record for record in self.first_output["records"]
        }
        for concept in ("kitchari", "dal tadka"):
            with self.subTest(concept=concept):
                if records[concept]["status"] != "UNRESOLVED":
                    self.assertTrue(records[concept]["isRecipe"])

    def test_production_resolution_has_no_model_call(self):
        planner = PLANNER.read_text(encoding="utf-8")
        resolution_start = planner.index("private func resolveFoodConcept(")
        resolution_end = planner.index(
            "private func trimToRequestedDaysAndMeals(",
            resolution_start,
        )
        resolution_source = planner[resolution_start:resolution_end]
        removed_symbols = (
            "aiBuild" + "SmartQueries",
            "aiChooseBest" + "FoodCandidate",
        )
        for symbol in removed_symbols:
            self.assertNotIn(symbol, planner)
        self.assertNotIn("LanguageModelSession", resolution_source)
        self.assertNotIn(".respond(", resolution_source)
        self.assertIn("smartSearch.searchCompact(", resolution_source)
        self.assertIn(
            "PlannerDeterministicFoodResolver.resolve(",
            resolution_source,
        )
        self.assertIn(
            "AyurvedaRecommendationGate.excludedFoodIds",
            resolution_source,
        )

    def test_mp1_static_site_counts_reflect_removed_resolution_calls(self):
        planner = PLANNER.read_text(encoding="utf-8")
        self.assertEqual(planner.count("LanguageModelSession("), 18)
        self.assertEqual(planner.count(".respond("), 23)

    def test_mp2_unresolved_counting_and_structure_path_remain(self):
        planner = PLANNER.read_text(encoding="utf-8")
        self.assertIn(
            "conceptualMeal.components.count - resolvedItemCount",
            planner,
        )
        self.assertIn(
            "unresolved component(s) from goal math",
            planner,
        )
        self.assertIn(
            "finalItems = rebalanceMealCalories(items: resolvedItems",
            planner,
        )


if __name__ == "__main__":
    unittest.main()
