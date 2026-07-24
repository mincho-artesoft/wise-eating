import gzip
import json
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PARSER = (
    ROOT
    / "WiseEating"
    / "FoodSearch"
    / "Constraints"
    / "CanonicalFacetParser.swift"
)
SEARCH_ENGINE = ROOT / "WiseEating" / "FoodSearch" / "VM" / "SmartFoodSearchEngine.swift"
INDEX_STORE = ROOT / "WiseEating" / "FoodSearch" / "SearchIndexStore.swift"
SYNONYMS = ROOT / "WiseEating" / "FoodSearch" / "food_synonyms.json"
SEED = ROOT / "WiseEating" / "ayurveda_seed.json.gz"
ARTIFACT_PARTS = [
    ROOT / "WiseEating" / "preseeded_db.store.gz.part-aa",
    ROOT / "WiseEating" / "preseeded_db.store.gz.part-ab",
]
GOLDEN = ROOT / "ayurveda-data" / "tests" / "fixtures" / "we4_golden_queries.json"


def expected_facets(profile):
    facets = set()
    virya = profile.get("virya")
    if virya:
        facets.add(f"virya:{virya}")

    for dosha, effect in profile["dosha"].items():
        if effect < 0:
            facets.add(f"pacifies:{dosha}")
        elif effect > 0:
            facets.add(f"aggravates:{dosha}")

    agni = profile.get("agniEffect")
    if agni is not None:
        if agni > 0:
            facets.add("agni:kindles")
        elif agni < 0:
            facets.add("agni:dampens")

    digestibility = profile.get("digestibility")
    if digestibility is not None:
        if digestibility >= 4:
            facets.add("digestibility:light")
        elif digestibility <= 2:
            facets.add("digestibility:heavy")

    facets.update(f"season:{season}" for season in profile["seasons"])
    category = profile["category"].lower().replace("_", "-").replace(" ", "-")
    facets.add(f"category:{category}")
    facets.add(f"concept:{category}")
    if (agni or 0) > 0 or (digestibility or 0) >= 4:
        facets.add("concept:digestion")
    return facets


class WE4SearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="we4-search-tests-")
        cls.temporary_root = Path(cls.temporary.name)
        cls.parser_binary = cls.temporary_root / "facet-parser"
        harness = cls.temporary_root / "ParserHarness.swift"
        harness.write_text(
            """
import Foundation

@main
struct ParserHarness {
  static func main() throws {
    let arguments = CommandLine.arguments
    let synonymData = try Data(
      contentsOf: URL(fileURLWithPath: arguments[1])
    )
    let synonyms = try JSONDecoder().decode(
      [String: String].self,
      from: synonymData
    )
    let query = arguments.dropFirst(2).joined(separator: " ")
    let parsed = CanonicalFacetParser.parse(query, synonyms: synonyms)
    let payload: [String: Any] = [
      "remaining": parsed.remainingQuery,
      "constraints": parsed.constraints.map { $0.acceptedKeys.sorted() },
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    FileHandle.standardOutput.write(data)
  }
}
""",
            encoding="utf-8",
        )
        subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(PARSER),
                str(harness),
                "-o",
                str(cls.parser_binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def parse(self, query):
        result = subprocess.run(
            [str(self.parser_binary), str(SYNONYMS), query],
            check=True,
            capture_output=True,
            text=True,
        )
        payload = json.loads(result.stdout)
        payload["constraints"] = {
            frozenset(constraint) for constraint in payload["constraints"]
        }
        return payload

    def assert_parse(self, query, remaining, constraints):
        parsed = self.parse(query)
        self.assertEqual(parsed["remaining"], remaining)
        self.assertEqual(
            parsed["constraints"],
            {frozenset(constraint) for constraint in constraints},
        )

    def test_grammar_vocabulary_families(self):
        cases = [
            ("cooling foods", "", [{"virya:cooling"}]),
            ("warming foods", "", [{"virya:heating"}]),
            ("heating foods", "", [{"virya:heating"}]),
            ("neutral virya", "", [{"virya:neutral"}]),
            ("balances vata", "", [{"pacifies:vata"}]),
            ("calms pitta", "", [{"pacifies:pitta"}]),
            ("good for kapha", "", [{"pacifies:kapha"}]),
            ("vata pacifying", "", [{"pacifies:vata"}]),
            ("aggravates vata", "", [{"aggravates:vata"}]),
            ("avoid for pitta", "", [{"aggravates:pitta"}]),
            ("kapha aggravating", "", [{"aggravates:kapha"}]),
            ("kindles agni", "", [{"agni:kindles"}]),
            ("dampens agni", "", [{"agni:dampens"}]),
            ("for digestion", "", [{"concept:digestion"}]),
            ("light to digest", "", [{"digestibility:light"}]),
            ("hard to digest", "", [{"digestibility:heavy"}]),
            ("summer", "", [{"season:grishma"}]),
            ("winter foods", "", [{"season:hemanta", "season:shishira"}]),
            ("spring foods", "", [{"season:vasanta"}]),
            ("autumn foods", "", [{"season:sharad"}]),
            ("monsoon foods", "", [{"season:varsha"}]),
            ("grishma ritu", "", [{"season:grishma"}]),
            ("category:grain", "", [{"category:grain"}]),
            ("concept:digestion", "", [{"concept:digestion"}]),
        ]
        for query, remaining, constraints in cases:
            with self.subTest(query=query):
                self.assert_parse(query, remaining, constraints)

    def test_mixed_queries_compose_and_preserve_existing_residue(self):
        cases = [
            (
                "cooling tomatoes low fat",
                "tomatoes low fat",
                [{"virya:cooling"}],
            ),
            (
                "high iron pacifies pitta",
                "high iron",
                [{"pacifies:pitta"}],
            ),
            (
                "warming winter grains",
                "",
                [
                    {"virya:heating"},
                    {"season:hemanta", "season:shishira"},
                    {"category:grain"},
                ],
            ),
            (
                "warming dairy free yogurt",
                "dairy free yogurt",
                [{"virya:heating"}],
            ),
        ]
        for query, remaining, constraints in cases:
            with self.subTest(query=query):
                self.assert_parse(query, remaining, constraints)

    def test_sanskrit_synonyms_are_conservative_and_data_backed(self):
        synonyms = json.loads(SYNONYMS.read_text(encoding="utf-8"))
        self.assertEqual(
            {key: synonyms[key] for key in ("ushna", "sheeta", "deepana")},
            {
                "ushna": "heating",
                "sheeta": "cooling",
                "deepana": "kindles agni",
            },
        )
        self.assert_parse("ushna foods", "", [{"virya:heating"}])
        self.assert_parse("sheeta foods", "", [{"virya:cooling"}])
        self.assert_parse("deepana foods", "", [{"agni:kindles"}])

    def test_unknown_vocabulary_degrades_to_the_existing_text_path(self):
        self.assert_parse("tomato sattvic", "tomato sattvic", [])
        self.assert_parse("virya:frothy tomato", "virya:frothy tomato", [])
        self.assert_parse("grains", "grains", [])

    def test_prebuilt_index_exactly_matches_canonical_seed_projection(self):
        combined = self.temporary_root / "preseeded_db.store.gz"
        store = self.temporary_root / "preseeded_db.store"
        with combined.open("wb") as destination:
            for part in ARTIFACT_PARTS:
                with part.open("rb") as source:
                    shutil.copyfileobj(source, destination)
        with gzip.open(combined, "rb") as source, store.open("wb") as destination:
            shutil.copyfileobj(source, destination)

        with sqlite3.connect(f"file:{store}?mode=ro", uri=True) as connection:
            row = connection.execute(
                """
                SELECT ZVERSION, ZFOODSCOUNT, ZPAYLOADDATA
                FROM ZSEARCHINDEXCACHE WHERE ZKEY = 'main'
                """
            ).fetchone()
        version, food_count, payload_data = row
        self.assertEqual((version, food_count), (4, 14_484))
        payload = json.loads(payload_data)
        compact_by_id = {food["id"]: food for food in payload["compactFoods"]}

        with gzip.open(SEED, "rt", encoding="utf-8") as source:
            seed = json.load(source)
        canonical = seed["dravyas"] + seed["recipes"]
        expected_by_id = {
            profile["foodId"]: expected_facets(profile) for profile in canonical
        }
        self.assertEqual(len(expected_by_id), 2_214)

        for food_id, expected in expected_by_id.items():
            self.assertEqual(
                set(compact_by_id[food_id]["ayurvedaFacets"]),
                expected,
                food_id,
            )
        self.assertTrue(
            all(
                not food["ayurvedaFacets"]
                for food_id, food in compact_by_id.items()
                if food_id not in expected_by_id
            )
        )

        expected_index = {}
        for food_id, facets in expected_by_id.items():
            for facet in facets:
                expected_index.setdefault(facet, set()).add(food_id)
        actual_index = {
            facet: set(food_ids)
            for facet, food_ids in payload["ayurvedaFacetIndex"].items()
        }
        self.assertEqual(actual_index, expected_index)
        self.assertEqual(len(actual_index), 64)
        self.assertEqual(sum(map(len, expected_by_id.values())), 20_114)
        self.assertFalse(set(actual_index) & set(payload["invertedIndex"]))

    def test_engine_uses_index_intersection_and_exact_title_escape_hatch(self):
        engine = SEARCH_ENGINE.read_text(encoding="utf-8")
        index_store = INDEX_STORE.read_text(encoding="utf-8")
        self.assertIn("currentIndexVersion: Int = 4", index_store)
        self.assertIn("ayurvedaFacetIndex", index_store)
        self.assertIn("current.intersection(facetCandidateIDs)", engine)
        self.assertIn("AyurvedaFacetParseResult.passthrough(query)", engine)
        self.assertIn("parsed.nutrientGoals", engine)

    def test_production_golden_capture_preserves_legacy_results(self):
        golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
        queries = golden["queries"]
        legacy = [entry for entry in queries if entry["kind"] == "legacy"]
        facet = [entry for entry in queries if entry["kind"] == "facet"]
        self.assertEqual(len(legacy), 25)
        self.assertGreaterEqual(len(facet), 7)
        self.assertTrue(all(entry["baseline"] == entry["after"] for entry in legacy))
        self.assertIn("tomatoes low fat", {entry["query"] for entry in legacy})
        self.assertIn("more iron than spinach", {entry["query"] for entry in legacy})
        self.assertTrue(
            next(
                entry["after"]
                for entry in facet
                if entry["query"] == "high iron pacifies pitta"
            )
        )
        self.assertEqual(
            next(
                entry["after"]
                for entry in facet
                if entry["query"] == "Warming Brown Lentil Soup"
            ),
            ["Warming Brown Lentil Soup"],
        )


if __name__ == "__main__":
    unittest.main()
