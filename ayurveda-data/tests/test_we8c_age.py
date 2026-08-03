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
    / "Ayura"
    / "FoodSearch"
    / "VM"
    / "SmartFoodSearchEngine.swift"
)
FOOD_SEARCH_VIEW = ROOT / "Ayura" / "FoodSearch" / "FoodSearchView.swift"
FOOD_ITEM_MODEL = ROOT / "Ayura" / "Food" / "Models" / "FoodItem.swift"
FOOD_DETAIL_VIEW = ROOT / "Ayura" / "Food" / "Views" / "FoodItemDetailView.swift"
AYURVEDA_SEEDER = ROOT / "Ayura" / "Main" / "DBSeed" / "AyurvedaSeeder.swift"
SPEC = importlib.util.spec_from_file_location("build_seed_we8c", BUILD_SEED_PATH)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)


class WE8CAgeDerivationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data_root = ROOT / "ayurveda-data"
        foods_path = ROOT / "Ayura" / "Legacy" / "foods.json"
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
        cls.age_rules = build_seed.authored_age_rules(cls.dravyas)
        build_seed.validate_safety_rule_ids(cls.dravyas, cls.age_rules)
        assignments, _, _, _ = build_seed.resolve_primary_foods(
            cls.dravyas,
            cls.store_ids,
        )
        cls.dravya_safety = {
            dravya["id"]: build_seed.derive_dravya_safety(
                dravya,
                assignments[dravya["id"]][0],
                cls.source_safety,
                cls.age_rules,
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
        new_dravyas = json.loads(
            (data_root / "dravyas" / "batch-31.json").read_text(encoding="utf-8")
        )
        new_recipes = json.loads(
            (data_root / "recipes" / "batch-r31.json").read_text(encoding="utf-8")
        )
        cls.new_dravya_ids = {item["id"] for item in new_dravyas["items"]}
        cls.new_recipe_ids = {item["id"] for item in new_recipes["items"]}
        cls.historical_recipe_safety = {
            recipe_id: safety
            for recipe_id, safety in cls.recipe_safety.items()
            if recipe_id not in cls.new_recipe_ids
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
            if safety["enforcedMinAgeMonths"] > 0
        ]
        self.assertEqual(len(honey_recipes), 5)
        self.assertTrue(
            all(
                safety["enforcedMinAgeMonths"] == 12
                and build_seed.HONEY_AGE_SOURCE in safety["ageSource"]
                for safety in honey_recipes
            )
        )

    def test_recipe_visibility_matches_founder_simulation(self):
        historical = [
            safety["enforcedMinAgeMonths"]
            for safety in self.historical_recipe_safety.values()
        ]
        self.assertEqual(
            {age: sum(floor <= age for floor in historical) for age in (9, 24, 60)},
            {9: 1_496, 24: 1_500, 60: 1_500},
        )

        current = [
            safety["enforcedMinAgeMonths"]
            for safety in self.recipe_safety.values()
        ]
        self.assertEqual(
            {age: sum(floor <= age for floor in current) for age in (9, 24, 60)},
            {9: 1_506, 24: 1_511, 60: 1_511},
        )

    def test_display_floor_histogram_reports_propagated_preparation_rules(self):
        display = collections.Counter(
            safety["minAgeMonths"] for safety in self.recipe_safety.values()
        )
        self.assertEqual(
            display,
            {6: 1, 12: 1, 24: 1_203, 48: 109, 60: 195, 192: 2},
        )

        r2_recipes = [
            recipe
            for recipe in self.recipes
            if any(
                ingredient.get("dravyaId") in build_seed.WHOLE_NUT_SEED_AGE_IDS
                for ingredient in recipe["ingredients"]
            )
        ]
        self.assertEqual(len(r2_recipes), 155)
        self.assertEqual(
            sum(
                self.recipe_safety[recipe["id"]]["minAgeMonths"] == 60
                for recipe in r2_recipes
            ),
            155,
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
        self.assertEqual(total, 10_644)
        self.assertEqual(authored, 4_957)

    def test_legacy_import_age_is_not_rendered(self):
        historical = {
            dravya_id: safety
            for dravya_id, safety in self.dravya_safety.items()
            if dravya_id not in self.new_dravya_ids
        }
        self.assertEqual(
            collections.Counter(
                safety["ageProvenance"] for safety in historical.values()
            ),
            {"legacyImport": 314, "authored": 389},
        )
        self.assertEqual(
            collections.Counter(
                safety["ageProvenance"] for safety in self.dravya_safety.values()
            ),
            {"legacyImport": 314, "authored": 390},
        )

        model = FOOD_ITEM_MODEL.read_text(encoding="utf-8")
        detail = FOOD_DETAIL_VIEW.read_text(encoding="utf-8")
        seeder = AYURVEDA_SEEDER.read_text(encoding="utf-8")
        self.assertIn("public var ageProvenance: String?", model)
        self.assertIn("public var ageSource: String?", model)
        self.assertIn(
            'food.isEdible\n            && food.minAgeMonths > 0\n'
            '            && food.ageProvenance != "legacyImport"',
            detail,
        )
        self.assertEqual(detail.count("if shouldDisplayMinimumAge"), 2)
        self.assertIn("food.ageProvenance = safety.ageProvenance", seeder)
        self.assertIn("food.ageSource = safety.ageSource", seeder)

    def test_authored_age_sources_and_propagation_modes_are_complete(self):
        self.assertEqual(len(self.dravyas), 704)
        weaning_rule = next(
            rule
            for rule in self.age_rules
            if rule["propagation"] == build_seed.AGE_PROPAGATION_WEANING_FLOOR
        )
        # The CLOSE1 makhana merge removed one member of this source rule.
        self.assertEqual(len(weaning_rule["ids"]), 366)

        category_ids = {
            dravya["id"]
            for dravya in self.dravyas
            if dravya["category"] in {"dry-fruit-nut", "seed"}
        }
        self.assertEqual(len(category_ids), 41)
        self.assertEqual(len(build_seed.WHOLE_NUT_SEED_AGE_IDS), 17)
        self.assertEqual(len(build_seed.NO_FLOOR_NUT_SEED_IDS), 24)
        self.assertFalse(
            build_seed.WHOLE_NUT_SEED_AGE_IDS
            & build_seed.NO_FLOOR_NUT_SEED_IDS
        )
        self.assertEqual(
            category_ids,
            build_seed.WHOLE_NUT_SEED_AGE_IDS
            | build_seed.NO_FLOOR_NUT_SEED_IDS,
        )

        contaminants = {
            rule["name"]
            for rule in self.age_rules
            if rule["propagation"] == build_seed.AGE_PROPAGATION_CONTAMINANT
        }
        self.assertEqual(contaminants, {"honey-min-age:12"})
        self.assertTrue(
            all(
                self.dravya_safety[fish_id]["ageSource"] is None
                for fish_id in ("dravya.seer-fish", "dravya.tuna")
            )
        )

        rows = list(self.dravya_safety.values()) + list(
            self.recipe_safety.values()
        )
        self.assertTrue(
            all(
                row["ageProvenance"] != "authored"
                or bool(row["ageSource"])
                for row in rows
            )
        )
        allowed_sources = {
            build_seed.HONEY_AGE_SOURCE,
            build_seed.SALT_AGE_SOURCE,
            build_seed.WEANING_AGE_SOURCE,
            build_seed.WHOLE_NUT_SEED_AGE_SOURCE,
        }
        observed_sources = {
            source
            for row in rows
            for source in (row["ageSource"] or "").split(" | ")
            if source
        }
        self.assertTrue(observed_sources)
        self.assertFalse(observed_sources - allowed_sources)

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
            {9: 232, 24: 18, 60: 8},
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
            ROOT / "Ayura" / "preseeded_db.store.gz.part-aa",
            ROOT / "Ayura" / "preseeded_db.store.gz.part-ab",
        ]
        cls.store.write_bytes(
            gzip.decompress(b"".join(part.read_bytes() for part in parts))
        )
        cls.connection = sqlite3.connect(cls.store)
        with gzip.open(
            ROOT / "Ayura" / "ayurveda_seed.json.gz",
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
                compact.get("enforcedMinAgeMonths"),
                safety["enforcedMinAgeMonths"] if profile["edible"] else None,
                profile["id"],
            )

    def test_persisted_honey_and_recipe_visibility_gates(self):
        honey = [
            profile
            for profile in self.seed["dravyas"] + self.seed["recipes"]
            if "honey-min-age:12" in profile["safety"]["rules"]
        ]
        self.assertEqual(len(honey), 9)
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
            {9: 1_506, 24: 1_511, 60: 1_511},
        )

    def test_linked_rows_inherit_source_floor_and_unlinked_rows_preserve_legacy(self):
        profiles = self.seed["dravyas"] + self.seed["recipes"]
        profiles_by_id = {profile["id"]: profile for profile in profiles}
        canonical_ids = {profile["foodId"] for profile in profiles}
        links_by_food = {link["fdcId"]: link for link in self.seed["links"]}
        linked_only_ids = set(links_by_food) - canonical_ids
        self.assertEqual(len(linked_only_ids), 2_007)

        for food_id in linked_only_ids:
            link = links_by_food[food_id]
            compact = self.compact_by_id[food_id]
            metadata = compact["ayurvedaMetadata"]
            source_safety = profiles_by_id[link["dravyaId"]]["safety"]
            self.assertEqual(
                compact["enforcedMinAgeMonths"],
                source_safety["enforcedMinAgeMonths"],
                food_id,
            )
            self.assertEqual(
                metadata["enforcedMinAgeMonths"],
                source_safety["enforcedMinAgeMonths"],
                food_id,
            )
            self.assertEqual(metadata["sourceTier"], link["tier"], food_id)

        ayurveda_ids = canonical_ids | set(links_by_food)
        self.assertTrue(
            all(
                compact["enforcedMinAgeMonths"] == compact["minAgeMonths"]
                for food_id, compact in self.compact_by_id.items()
                if food_id not in ayurveda_ids
            )
        )


if __name__ == "__main__":
    unittest.main()
