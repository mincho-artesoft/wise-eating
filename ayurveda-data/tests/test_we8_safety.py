import gzip
import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_SEED_PATH = ROOT / "ayurveda-data" / "build_seed.py"
GOLDEN = ROOT / "ayurveda-data" / "tests" / "fixtures" / "we4_golden_queries.json"
SPEC = importlib.util.spec_from_file_location("build_seed_we8", BUILD_SEED_PATH)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)

TARGET_SAFETY_PROFILES = build_seed.TARGET_SAFETY_PROFILES
TARGET_INGREDIENT_LINKS = build_seed.TARGET_INGREDIENT_LINKS
TARGET_INGREDIENT_OWNERS = build_seed.TARGET_INGREDIENT_OWNERS


class WE8SafetyDerivationTests(unittest.TestCase):
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

    def test_every_derivation_is_scaffold_default_and_review_required(self):
        rows = list(self.dravya_safety.values()) + list(
            self.recipe_safety.values()
        )
        self.assertEqual(len(rows), TARGET_SAFETY_PROFILES)
        self.assertTrue(
            all(
                row["provenance"] == "scaffold-default"
                and row["reviewRequired"] is True
                and row["rules"]
                for row in rows
            )
        )

    def test_reviewed_allergen_map_uses_existing_raw_vocabulary(self):
        configured = set(build_seed.CATEGORY_ALLERGEN_RULES.get("dairy", set()))
        configured.update(build_seed.ALLERGEN_DRAVYA_RULES)
        self.assertFalse(configured - build_seed.ALLERGEN_VOCABULARY)
        self.assertEqual(
            self.dravya_safety["dravya.ghee"]["allergens"],
            ["Milk"],
        )
        self.assertIn(
            "Nuts (almonds)",
            self.dravya_safety["dravya.almond-milk"]["allergens"],
        )
        self.assertNotIn(
            "Milk",
            self.dravya_safety["dravya.almond-milk"]["allergens"],
        )
        self.assertIn(
            "Milk",
            self.dravya_safety["dravya.yak-milk"]["allergens"],
        )
        self.assertEqual(
            self.dravya_safety["dravya.celery-seed"]["allergens"],
            ["Celery"],
        )

    def test_exact_slug_rules_avoid_substring_false_positives(self):
        cases = [
            ("dravya.buckwheat", "Cereals containing gluten"),
            ("dravya.water-chestnut-flour", "Nuts"),
            ("dravya.fresh-water-chestnut", "Nuts"),
            ("dravya.eggplant", "Eggs"),
            ("dravya.butternut-squash", "Nuts"),
        ]
        for dravya_id, forbidden in cases:
            with self.subTest(dravya_id=dravya_id):
                allergens = self.dravya_safety[dravya_id]["allergens"]
                self.assertFalse(
                    any(
                        allergen == forbidden
                        or allergen.startswith(forbidden + " (")
                        for allergen in allergens
                    )
                )

    def test_recipe_allergens_are_the_exact_ingredient_union(self):
        for recipe in self.recipes:
            expected = set()
            for ingredient in recipe["ingredients"]:
                if "dravyaId" in ingredient:
                    expected.update(
                        self.dravya_safety[ingredient["dravyaId"]]["allergens"]
                    )
                else:
                    expected.update(
                        self.source_safety[ingredient["fdcId"]]["allergens"]
                    )
            self.assertEqual(
                set(self.recipe_safety[recipe["id"]]["allergens"]),
                expected,
                recipe["id"],
            )

    def test_honey_dravyas_and_recipes_have_minimum_age_twelve(self):
        for dravya_id in build_seed.HONEY_DRAVYA_IDS:
            self.assertGreaterEqual(
                self.dravya_safety[dravya_id]["minAgeMonths"],
                12,
            )
            self.assertEqual(
                self.dravya_safety[dravya_id]["enforcedMinAgeMonths"],
                12,
            )
        honey_recipes = [
            safety
            for safety in self.recipe_safety.values()
            if "honey-min-age:12" in safety["rules"]
        ]
        self.assertEqual(len(honey_recipes), 5)
        self.assertTrue(
            all(
                safety["minAgeMonths"] >= 12
                and safety["enforcedMinAgeMonths"] == 12
                for safety in honey_recipes
            )
        )


class WE8PreseedSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="we8-preseed-")
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
            food["id"]: food for food in payload["compactFoods"]
        }
        cls.recipe_by_slug = {
            recipe["id"]: recipe for recipe in cls.seed["recipes"]
        }
        cls.dravya_by_slug = {
            dravya["id"]: dravya for dravya in cls.seed["dravyas"]
        }

    @classmethod
    def tearDownClass(cls):
        cls.connection.close()
        cls.temporary.cleanup()

    def test_artifact_metadata_exactly_matches_all_seeded_safety_rows(self):
        canonical = self.seed["dravyas"] + self.seed["recipes"]
        self.assertEqual(len(canonical), TARGET_SAFETY_PROFILES)
        for item in canonical:
            compact = self.compact_by_id[item["foodId"]]
            safety = item["safety"]
            self.assertEqual(
                set(compact["allergens"]),
                set(safety["allergens"]),
                item["id"],
            )
            self.assertEqual(
                compact["minAgeMonths"],
                safety["minAgeMonths"],
                item["id"],
            )
            self.assertEqual(
                compact.get("enforcedMinAgeMonths"),
                safety["enforcedMinAgeMonths"] if item["edible"] else None,
                item["id"],
            )

    def test_exclude_all_allergens_rejects_allergen_carrying_seeded_recipes(self):
        allergen_free_ids = {
            food_id
            for food_id, compact in self.compact_by_id.items()
            if not compact["allergens"]
        }
        for recipe_id in (
            "recipe.amaranth-kheer",
            "recipe.classic-mung-kitchari",
        ):
            self.assertNotIn(
                self.recipe_by_slug[recipe_id]["foodId"],
                allergen_free_ids,
            )

    def test_safety_goldens_lock_dairy_and_exclude_all_properties(self):
        golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
        safety = {
            entry["query"]: entry
            for entry in golden["queries"]
            if entry["kind"] == "safety"
        }
        self.assertEqual(set(safety), {"without dairy", "no allergens"})

        for slug in safety["without dairy"]["mustExcludeSlugs"]:
            recipe = self.recipe_by_slug[slug]
            compact = self.compact_by_id[recipe["foodId"]]
            self.assertIn("Milk", compact["allergens"], slug)

        allergen_recipe_ids = {
            recipe["foodId"]
            for recipe in self.seed["recipes"]
            if recipe["safety"]["allergens"]
        }
        self.assertEqual(
            len(allergen_recipe_ids),
            safety["no allergens"]["expectedExcludedCount"],
        )
        self.assertTrue(
            all(
                self.compact_by_id[food_id]["allergens"]
                for food_id in allergen_recipe_ids
            )
        )

    def test_honey_recipe_minimum_age_is_persisted_in_the_fresh_artifact(self):
        honey_recipes = [
            recipe
            for recipe in self.seed["recipes"]
            if "honey-min-age:12" in recipe["safety"]["rules"]
        ]
        self.assertEqual(len(honey_recipes), 5)
        for recipe in honey_recipes:
            self.assertGreaterEqual(
                self.compact_by_id[recipe["foodId"]]["minAgeMonths"],
                12,
                recipe["id"],
            )
            self.assertEqual(
                self.compact_by_id[recipe["foodId"]]["enforcedMinAgeMonths"],
                12,
                recipe["id"],
            )

    def test_fresh_artifact_contains_exact_recipe_ingredient_links(self):
        food_id_by_pk = {
            pk: food_id
            for pk, food_id in self.connection.execute(
                "SELECT Z_PK, ZID FROM ZFOODITEM"
            )
        }
        actual = {}
        for owner, ingredient, grams in self.connection.execute(
            "SELECT ZOWNER, ZFOOD, ZGRAMS FROM ZINGREDIENTLINK"
        ):
            actual.setdefault(food_id_by_pk[owner], []).append(
                (food_id_by_pk[ingredient], float(grams))
            )

        self.assertEqual(sum(map(len, actual.values())), TARGET_INGREDIENT_LINKS)
        self.assertEqual(len(actual), TARGET_INGREDIENT_OWNERS)
        for recipe in self.seed["recipes"]:
            expected = sorted(
                (ingredient["foodId"], float(ingredient["grams"]))
                for ingredient in recipe["ingredients"]
            )
            self.assertEqual(
                sorted(actual.get(recipe["foodId"], [])),
                expected,
                recipe["id"],
            )

    def test_kitchari_links_support_fresh_shopping_list_expansion(self):
        recipe = self.recipe_by_slug["recipe.classic-mung-kitchari"]
        food_id_by_pk = {
            pk: food_id
            for pk, food_id in self.connection.execute(
                "SELECT Z_PK, ZID FROM ZFOODITEM"
            )
        }
        owner_pk = self.connection.execute(
            "SELECT Z_PK FROM ZFOODITEM WHERE ZID = ?",
            (recipe["foodId"],),
        ).fetchone()[0]
        expanded = {
            food_id_by_pk[ingredient_pk]
            for (ingredient_pk,) in self.connection.execute(
                "SELECT ZFOOD FROM ZINGREDIENTLINK WHERE ZOWNER = ?",
                (owner_pk,),
            )
        }
        self.assertEqual(
            expanded,
            {4_558, 6_372, 6_687, 8_148, 9_277, 10_444, 10_962, 11_888},
        )
        shopping_source = (
            ROOT
            / "Ayura"
            / "ShoppingList"
            / "ViewModels"
            / "ShoppingListVM.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("for link in item.ingredients ?? []", shopping_source)
        self.assertIn("unpackIngredients(from: food)", shopping_source)


if __name__ == "__main__":
    unittest.main()
