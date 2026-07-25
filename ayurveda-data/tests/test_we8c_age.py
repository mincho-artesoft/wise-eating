import collections
import gzip
import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_SEED_PATH = ROOT / "ayurveda-data" / "build_seed.py"
SEARCH_ENGINE = (
    ROOT
    / "WiseEating"
    / "FoodSearch"
    / "VM"
    / "SmartFoodSearchEngine.swift"
)
FOOD_SEARCH_VIEW = ROOT / "WiseEating" / "FoodSearch" / "FoodSearchView.swift"
SPEC = importlib.util.spec_from_file_location("build_seed_we8c", BUILD_SEED_PATH)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)


class WE8CAgeDerivationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data_root = ROOT / "ayurveda-data"
        foods_path = ROOT / "WiseEating" / "Legacy" / "foods.json"
        foods = json.loads(foods_path.read_text(encoding="utf-8"))
        cls.store_ids = {food["id"] for food in foods}
        cls.source_safety = build_seed.load_food_safety(
            foods_path,
            cls.store_ids,
        )
        cls.dravyas = build_seed.load_batches(
            data_root / "dravyas",
            "batch-*.json",
            "items",
        )
        cls.recipes = build_seed.load_batches(
            data_root / "recipes",
            "batch-r*.json",
            "items",
        )
        assignments, _, _, _ = build_seed.resolve_primary_foods(
            cls.dravyas,
            cls.store_ids,
        )
        cls.dravya_safety = {
            dravya["id"]: build_seed.derive_dravya_safety(
                dravya,
                assignments[dravya["id"]][0],
                cls.source_safety,
            )
            for dravya in cls.dravyas
        }
        cls.recipe_safety = {
            recipe["id"]: build_seed.derive_recipe_safety(
                recipe,
                cls.dravya_safety,
                cls.source_safety,
            )
            for recipe in cls.recipes
        }

    def test_honey_authored_floor_remains_enforced(self):
        for dravya_id in build_seed.HONEY_DRAVYA_IDS:
            safety = self.dravya_safety[dravya_id]
            self.assertEqual(safety["ageProvenance"], "authored")
            self.assertEqual(safety["enforcedMinAgeMonths"], 12)
            self.assertGreaterEqual(safety["minAgeMonths"], 12)

        honey_recipes = [
            safety
            for safety in self.recipe_safety.values()
            if safety["ageProvenance"] == "authored"
        ]
        self.assertEqual(len(honey_recipes), 4)
        self.assertTrue(
            all(safety["enforcedMinAgeMonths"] == 12 for safety in honey_recipes)
        )

    def test_recipe_visibility_matches_founder_simulation(self):
        enforced = [
            safety["enforcedMinAgeMonths"]
            for safety in self.recipe_safety.values()
        ]
        self.assertEqual(
            {age: sum(floor <= age for floor in enforced) for age in (9, 24, 60)},
            {9: 1_496, 24: 1_500, 60: 1_500},
        )

    def test_display_floor_histogram_is_unchanged(self):
        display = collections.Counter(
            safety["minAgeMonths"] for safety in self.recipe_safety.values()
        )
        self.assertEqual(
            display,
            {6: 1, 24: 1_201, 48: 226, 60: 70, 192: 2},
        )

    def test_provenance_is_carried_per_recipe_ingredient(self):
        total = 0
        authored = 0
        for recipe in self.recipes:
            safety = self.recipe_safety[recipe["id"]]
            contributors = safety["ageContributors"]
            self.assertEqual(len(contributors), len(recipe["ingredients"]))
            for ingredient, contributor in zip(
                recipe["ingredients"],
                contributors,
                strict=True,
            ):
                expected_id = ingredient.get("dravyaId")
                if expected_id is None:
                    expected_id = f"fdc:{ingredient['fdcId']}"
                self.assertEqual(contributor["ingredientId"], expected_id)
                self.assertEqual(contributor["grams"], ingredient["grams"])
                self.assertIn(
                    contributor["ageProvenance"],
                    {"authored", "legacyImport"},
                )
                total += 1
                authored += contributor["ageProvenance"] == "authored"
        self.assertEqual(total, 10_571)
        self.assertEqual(authored, 4)

    def test_dravya_visibility_delta_is_exact(self):
        display = {
            dravya_id: safety["minAgeMonths"]
            for dravya_id, safety in self.dravya_safety.items()
        }
        enforced = {
            dravya_id: safety["enforcedMinAgeMonths"]
            for dravya_id, safety in self.dravya_safety.items()
        }
        self.assertEqual(
            {
                age: sum(
                    display[dravya_id] > age
                    and enforced[dravya_id] <= age
                    for dravya_id in display
                )
                for age in (9, 24, 60)
            },
            {9: 253, 24: 30, 60: 8},
        )

    def test_search_filters_enforced_floor_while_badge_uses_display_floor(self):
        engine = SEARCH_ENGINE.read_text(encoding="utf-8")
        view = FOOD_SEARCH_VIEW.read_text(encoding="utf-8")
        self.assertEqual(engine.count("item.enforcedMinAgeMonths"), 2)
        self.assertNotIn("item.minAgeMonths) > age", engine)
        self.assertIn("food.minAgeMonths >= 0", view)
        self.assertNotIn("enforcedMinAgeMonths", view)


class WE8CPreseedAgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="we8c-preseed-")
        cls.store = Path(cls.temporary.name) / "preseed.store"
        parts = [
            ROOT / "WiseEating" / "preseeded_db.store.gz.part-aa",
            ROOT / "WiseEating" / "preseeded_db.store.gz.part-ab",
        ]
        cls.store.write_bytes(
            gzip.decompress(b"".join(part.read_bytes() for part in parts))
        )
        cls.connection = sqlite3.connect(cls.store)
        with gzip.open(
            ROOT / "WiseEating" / "ayurveda_seed.json.gz",
            "rt",
            encoding="utf-8",
        ) as source:
            cls.seed = json.load(source)
        payload = json.loads(
            cls.connection.execute(
                "SELECT ZPAYLOADDATA FROM ZSEARCHINDEXCACHE WHERE ZKEY = 'main'"
            ).fetchone()[0]
        )
        cls.compact_by_id = {
            compact["id"]: compact for compact in payload["compactFoods"]
        }

    @classmethod
    def tearDownClass(cls):
        cls.connection.close()
        cls.temporary.cleanup()

    def test_persisted_canonical_floors_match_seed(self):
        canonical = self.seed["dravyas"] + self.seed["recipes"]
        for profile in canonical:
            compact = self.compact_by_id[profile["foodId"]]
            safety = profile["safety"]
            self.assertEqual(
                compact["minAgeMonths"],
                safety["minAgeMonths"],
                profile["id"],
            )
            self.assertEqual(
                compact["enforcedMinAgeMonths"],
                safety["enforcedMinAgeMonths"],
                profile["id"],
            )

    def test_persisted_honey_and_recipe_visibility_gates(self):
        honey = [
            profile
            for profile in self.seed["dravyas"] + self.seed["recipes"]
            if profile["safety"]["ageProvenance"] == "authored"
        ]
        self.assertEqual(len(honey), 8)
        self.assertTrue(
            all(
                self.compact_by_id[profile["foodId"]]["enforcedMinAgeMonths"]
                == 12
                for profile in honey
            )
        )
        recipe_floors = [
            self.compact_by_id[recipe["foodId"]]["enforcedMinAgeMonths"]
            for recipe in self.seed["recipes"]
        ]
        self.assertEqual(
            {age: sum(floor <= age for floor in recipe_floors) for age in (9, 24, 60)},
            {9: 1_496, 24: 1_500, 60: 1_500},
        )

    def test_noncanonical_rows_preserve_legacy_age_enforcement(self):
        canonical_ids = {
            profile["foodId"]
            for profile in self.seed["dravyas"] + self.seed["recipes"]
        }
        self.assertTrue(
            all(
                compact["enforcedMinAgeMonths"] == compact["minAgeMonths"]
                for food_id, compact in self.compact_by_id.items()
                if food_id not in canonical_ids
            )
        )


if __name__ == "__main__":
    unittest.main()
