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
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "USDAWeeklyMealPlanner.swift"
)
CORPUS = ROOT / "ayurveda-data" / "tests" / "resolution-goldens.json"
HOLDOUT = ROOT / "ayurveda-data" / "tests" / "resolution-holdout.json"
CONCEPT_ARTIFACT = ROOT / "Ayura" / "food_concepts.json.gz"
INCIDENTAL_TOKENS = [
    "raw",
    "cooked",
    "mix",
    "salad",
    "prepared",
    "canned",
    "instant",
    "baby",
    "nfs",
    "dry",
    "fresh",
    "juice",
    "home",
    "restaurant",
    "food",
]
ARTIFACT_PARTS = [
    ROOT / "Ayura" / "preseeded_db.store.gz.part-aa",
    ROOT / "Ayura" / "preseeded_db.store.gz.part-ab",
]

TARGET_FOODS = 14_488


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
                WHERE ZKEY = 'main' AND ZVERSION = 10
                """
            ).fetchone()[0]
            profile_rows = connection.execute(
                """
                SELECT ZID, ZFOODID, ZENGINEEXCLUDED, ZKIND
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
        direct_ids = {
            food_id for _, food_id, _, kind in profile_rows if kind != "catalog"
        }
        catalog_ids = {
            food_id for _, food_id, _, kind in profile_rows if kind == "catalog"
        }
        excluded_profile_ids = {
            profile_id
            for profile_id, _, excluded, _ in profile_rows
            if excluded
        }
        excluded_food_ids = {
            food_id
            for _, food_id, excluded, _ in profile_rows
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
            elif food_id in catalog_ids:
                tier = "derived"
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
        with gzip.open(CONCEPT_ARTIFACT, "rt", encoding="utf-8") as source:
            concept_artifact = json.load(source)
        cls.aliases = temporary_root / "aliases.json"
        cls.aliases.write_text(
            json.dumps(
                concept_artifact["aliases"],
                ensure_ascii=False,
                sort_keys=True,
            ),
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
    candidates: [PlannerPreparedResolutionCandidate],
    ontologyAliases: [String: String]
) -> [CorpusRecord] {
    corpus.cases.map { golden in
        let decision = PlannerDeterministicFoodResolver.resolve(
            concept: golden.concept,
            ontologyAliases: ontologyAliases,
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
            candidate(2, "Chicken breast, cooked, grilled"),
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

    let expectedForms: Set<String> = [
        "baby", "bake", "boil", "breast", "can", "cook", "dal", "dry",
        "flour", "fresh", "freeze", "fry", "grill", "ground", "instant",
        "leaf", "milk", "oil", "powder", "prepare", "raw", "roast", "seed",
        "split", "steam", "tadka", "tea", "whip", "whole"
    ]
    require(
        PlannerDeterministicFoodResolver.formVocabulary == expectedForms,
        "catalogue form vocabulary changed unexpectedly"
    )

    let freshGinger = PlannerDeterministicFoodResolver.resolve(
        concept: "fresh ginger",
        candidates: [
            candidate(13, "Spices, ginger, ground", tier: .classical),
            candidate(14, "Ginger root, raw", tier: .classical),
            candidate(15, "Fresh Ginger Achar", recipe: true, tier: .classical),
        ]
    )
    require(freshGinger?.candidate.id == 14, "fresh/ground form conflict failed")

    let roastedAlmond = PlannerDeterministicFoodResolver.resolve(
        concept: "roasted almonds",
        candidates: [
            candidate(16, "Nuts, almonds, raw"),
            candidate(17, "Nuts, almonds, dry roasted, without salt added"),
        ]
    )
    require(roastedAlmond?.candidate.id == 17, "dry-roasted form match failed")

    let steamedBroccoli = PlannerDeterministicFoodResolver.resolve(
        concept: "steamed broccoli",
        candidates: [
            candidate(18, "Broccoli, raw"),
            candidate(19, "Broccoli, cooked, boiled"),
        ]
    )
    require(
        steamedBroccoli == nil,
        "conflicting cooking methods should remain unresolved"
    )

    let plantPart = PlannerDeterministicFoodResolver.resolve(
        concept: "fenugreek seed",
        candidates: [
            candidate(20, "Fenugreek leaves"),
            candidate(21, "Spices, fenugreek seed"),
        ]
    )
    require(plantPart?.candidate.id == 21, "seed/leaf conflict failed")
}

@main
struct MP3ResolutionHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5 else {
            fatalError("usage: harness catalog corpus aliases mode")
        }
        if arguments[4] == "properties" {
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
        let aliases = try decoder.decode(
            [String: String].self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[3]))
        )
        let first = runCorpus(
            corpus,
            candidates: preparedCandidates,
            ontologyAliases: aliases
        )
        let second = runCorpus(
            corpus,
            candidates: preparedCandidates,
            ontologyAliases: aliases
        )
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

        cls.first_output = cls._run_harness(CORPUS)
        cls.clean_relaunch_output = cls._run_harness(CORPUS)
        cls.holdout_output = cls._run_harness(HOLDOUT)
        cls.holdout_clean_relaunch_output = cls._run_harness(HOLDOUT)
        cls.incidental_corpus = temporary_root / "incidental-tokens.json"
        cls.incidental_corpus.write_text(
            json.dumps(
                {
                    "cases": [
                        {
                            "concept": token,
                            "mustMatchAny": [],
                            "mustNotMatch": [],
                            "expectUnresolved": True,
                        }
                        for token in INCIDENTAL_TOKENS
                    ]
                },
                sort_keys=True,
            ),
            encoding="utf-8",
        )
        cls.incidental_output = cls._run_harness(cls.incidental_corpus)
        cls.incidental_clean_relaunch_output = cls._run_harness(
            cls.incidental_corpus
        )
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
        Path("/tmp/mp3c-resolution-holdout.json").write_text(
            json.dumps(
                cls.holdout_output,
                ensure_ascii=False,
                sort_keys=True,
            ),
            encoding="utf-8",
        )
        Path("/tmp/mp3c-incidental-tokens.json").write_text(
            json.dumps(
                cls.incidental_output,
                ensure_ascii=False,
                sort_keys=True,
            ),
            encoding="utf-8",
        )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    @classmethod
    def _run_harness(cls, corpus):
        result = subprocess.run(
            [
                str(cls.binary),
                str(cls.catalog),
                str(corpus),
                str(cls.aliases),
                "corpus",
            ],
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
        self.assertEqual(self.catalog_count, TARGET_FOODS)
        self.assertEqual(self.excluded_count, 2)
        self.assertEqual(self.candidate_count, TARGET_FOODS - 2)

    def test_required_scorer_properties(self):
        result = subprocess.run(
            [
                str(self.binary),
                str(self.catalog),
                str(CORPUS),
                str(self.aliases),
                "properties",
            ],
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
        self.assertEqual(
            self.holdout_output,
            self.holdout_clean_relaunch_output,
        )
        self.assertEqual(
            self.incidental_output,
            self.incidental_clean_relaunch_output,
        )

    def test_fc2_ontology_aliases_improve_held_out_score_without_wrong_matches(self):
        corpus = json.loads(HOLDOUT.read_text(encoding="utf-8"))
        self.assertEqual(len(corpus["cases"]), 53)
        self.assertEqual(
            [
                case["concept"]
                for case in corpus["cases"]
                if "expectRecipe" in case
            ],
            [],
        )
        records = self.holdout_output["records"]
        controls = {
            case["concept"]
            for case in corpus["cases"]
            if case.get("expectUnresolved")
        }
        positive_records = [
            record for record in records if record["concept"] not in controls
        ]
        self.assertEqual(
            sum(record["status"] == "PASS" for record in positive_records),
            44,
        )
        self.assertEqual(
            sum(
                record["status"] == "UNRESOLVED"
                for record in positive_records
            ),
            4,
        )
        self.assertEqual(
            [record for record in positive_records if record["status"] == "FAIL"],
            [],
        )

    def test_mp3c_all_five_held_out_controls_are_unresolved(self):
        records = {
            record["concept"]: record
            for record in self.holdout_output["records"]
        }
        for concept in ("glorbnax", "asdfgh", "the", "a", "food"):
            with self.subTest(concept=concept):
                self.assertEqual(records[concept]["status"], "UNRESOLVED")
                self.assertTrue(records[concept]["expectationMet"])

    def test_mp3c_form_cases_use_compatible_atomic_rows(self):
        records = {
            record["concept"]: record
            for record in self.holdout_output["records"]
        }
        self.assertEqual(records["fresh ginger"]["resolvedID"], 6687)
        self.assertEqual(records["fresh ginger"]["resolvedName"], "Ginger root, raw")
        self.assertFalse(records["fresh ginger"]["isRecipe"])
        self.assertEqual(
            records["ground ginger"]["resolvedName"],
            "Spices, ginger, ground",
        )
        self.assertIn("roasted", records["roasted almonds"]["resolvedName"])
        self.assertEqual(records["steamed broccoli"]["status"], "UNRESOLVED")

    def test_mp3c_incidental_tokens_are_all_unresolved(self):
        records = self.incidental_output["records"]
        self.assertEqual(
            [record["concept"] for record in records],
            INCIDENTAL_TOKENS,
        )
        self.assertEqual(
            [
                record
                for record in records
                if record["status"] != "UNRESOLVED"
                or not record["expectationMet"]
            ],
            [],
        )

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
        resolution_start = planner.index(
            "private func resolveCompactCandidate("
        )
        resolution_end = planner.index(
            "private func buildMustContainRules(",
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

    def test_mp1_static_site_counts_reflect_removed_resolution_calls(self):
        planner = PLANNER.read_text(encoding="utf-8")
        # MP-6 deletes the per-meal title-polish session. Its one batched
        # narrator lives in a separate Foundation Models adapter.
        self.assertEqual(planner.count("LanguageModelSession("), 8)
        self.assertEqual(planner.count(".respond("), 8)
        self.assertEqual(planner.count('site: "mealPlanIntentParse"'), 2)
        assembly = planner.split(
            "// --- Checkpoint 2: deterministic assembly ---",
            1,
        )[1].split("return preview", 1)[0]
        self.assertNotIn("LanguageModelSession", assembly)
        self.assertNotIn(".respond(", assembly)

    def test_mp2_truth_and_structural_constraints_feed_solver(self):
        planner = PLANNER.read_text(encoding="utf-8")
        solver = (
            ROOT
            / "Ayura"
            / "AI"
            / "MealPlanning"
            / "DeterministicMealPlanSolver.swift"
        ).read_text(encoding="utf-8")
        adapter = (
            ROOT
            / "Ayura"
            / "AI"
            / "MealPlanning"
            / "DeterministicMealPlanSolver+Ayura.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "guard referenceWeight > 0",
            adapter,
        )
        self.assertIn(
            "rawEnergy > 0",
            adapter,
        )
        self.assertIn(
            "placements: solverPlacements",
            planner,
        )
        self.assertIn("mustContain: placements", adapter)
        self.assertIn("mustContain: [MP5MustContainRule]", solver)


if __name__ == "__main__":
    unittest.main()
