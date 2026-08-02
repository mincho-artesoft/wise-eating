import importlib.util
import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_SEED_PATH = REPO_ROOT / "ayurveda-data" / "build_seed.py"
SPEC = importlib.util.spec_from_file_location("build_seed", BUILD_SEED_PATH)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)


class RecipeNutritionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data_root = REPO_ROOT / "ayurveda-data"
        foods_path = REPO_ROOT / "Ayura" / "Legacy" / "foods.json"
        foods = json.loads(foods_path.read_text(encoding="utf-8"))
        cls.store_ids = {food["id"] for food in foods}
        cls.nutrition_by_id = build_seed.load_food_nutrition(
            foods_path, cls.store_ids
        )
        cls.source_safety_by_id = build_seed.load_food_safety(
            foods_path, cls.store_ids
        )
        cls.dravyas = build_seed.load_batches(
            data_root / "dravyas", "batch-*.json", "items"
        )
        cls.recipes = build_seed.load_batches(
            data_root / "recipes", "batch-r*.json", "items"
        )
        claims, bindings = build_seed.validate_bindings(
            cls.dravyas, cls.store_ids
        )
        cls.preferred_bindings = build_seed.preferred_nutrition_bindings(bindings)
        v1_fdc_ids = set(claims)
        cls.derived_links = build_seed.load_crosswalk_links(
            data_root / "crosswalk" / "crosswalk.csv",
            cls.store_ids,
            {dravya["id"] for dravya in cls.dravyas},
            v1_fdc_ids,
        )
        cls.envelope, _, _ = build_seed.build_envelope(
            cls.dravyas,
            cls.recipes,
            cls.store_ids,
            cls.derived_links,
            cls.nutrition_by_id,
            cls.source_safety_by_id,
            cls.preferred_bindings,
        )

    def test_kitchari_energy_matches_independent_hand_calculation(self):
        expected_sources = {
            6372: (180, 365.0),
            10962: (180, 347.0),
            4558: (24, 876.0),
            8148: (4, 375.0),
            9277: (2, 312.0),
            6687: (7, 80.0),
        }
        for fdc_id, (_, expected_per_100g) in expected_sources.items():
            self.assertEqual(
                self.nutrition_by_id[fdc_id]["energyKcal"],
                expected_per_100g,
            )
        self.assertNotIn("energyKcal", self.nutrition_by_id[11888])
        self.assertNotIn("energyKcal", self.nutrition_by_id[10444])

        line_items = [
            grams * energy_per_100g / 100
            for grams, energy_per_100g in expected_sources.values()
        ]
        hand_total = sum(line_items)
        hand_per_serving = hand_total / 4
        self.assertAlmostEqual(hand_total, 1518.68, places=9)
        self.assertAlmostEqual(hand_per_serving, 379.67, places=9)

        recipe = next(
            recipe
            for recipe in self.envelope["recipes"]
            if recipe["id"] == "recipe.classic-mung-kitchari"
        )
        pipeline_value = recipe["nutrition"]["perServing"]["energyKcal"]
        self.assertLessEqual(abs(pipeline_value - hand_per_serving), 0.5)

    def test_all_recipes_meet_coverage_floor(self):
        counts = self.envelope["counts"]["nutrition"]
        self.assertEqual(counts["none"], 0)
        self.assertEqual(sum(counts.values()), len(self.recipes))

        source_recipes = {recipe["id"]: recipe for recipe in self.recipes}
        for recipe in self.envelope["recipes"]:
            panel = recipe["nutrition"]
            if panel["status"] != "estimated":
                continue
            active_source_null_dravyas = {
                ingredient["dravyaId"]
                for ingredient in source_recipes[recipe["id"]]["ingredients"]
                if "dravyaId" in ingredient
                and self.nutrition_by_id.get(
                    self.preferred_bindings.get(ingredient["dravyaId"])
                )
                is None
            }
            self.assertTrue(active_source_null_dravyas, recipe["id"])
            self.assertEqual(
                set(panel["missingIngredients"]),
                active_source_null_dravyas,
                recipe["id"],
            )

        # TRANSITIONAL, PRE-INGEST. dravya_foods.json is not wired into the build;
        # the build reads Ayura/Legacy/foods.json. 4 of these 10 close on ingest
        # alone, 3 on NUT-1 review, 3 are permanently unfillable. TASK-NUT1 must
        # update this figure. See issue #3.
        self.assertEqual(counts, {"full": 1501, "estimated": 10, "none": 0})
        self.assertLessEqual(counts["none"], len(self.recipes) * 0.25)

    def test_panels_cover_energy_macros_all_vitamins_and_all_minerals(self):
        self.assertEqual(len(build_seed.NUTRIENT_CATALOG), 39)
        self.assertEqual(
            set(build_seed.NUTRIENT_CATALOG),
            set(
                [
                    "energyKcal",
                    "carbohydrates",
                    "protein",
                    "fat",
                    "fiber",
                    "totalSugars",
                ]
                + [
                    nutrient
                    for nutrient, (section, _) in build_seed.NUTRIENT_CATALOG.items()
                    if section == "vitamins"
                ]
                + [
                    nutrient
                    for nutrient, (section, _) in build_seed.NUTRIENT_CATALOG.items()
                    if section == "minerals"
                ]
            ),
        )
        for recipe in self.envelope["recipes"]:
            panel = recipe["nutrition"]
            self.assertEqual(set(panel["units"]), set(build_seed.NUTRIENT_CATALOG))
            self.assertGreater(panel["totalWeightG"], 0)
            self.assertIn("energyKcal", panel["perServing"])
            self.assertIn("energyKcal", panel["per100g"])

    def test_unresolved_ingredient_is_reported_without_fabricated_values(self):
        recipe = {
            "id": "recipe.coverage-test",
            "servings": 2,
            "ingredients": [
                {"dravyaId": "dravya.white-rice", "name": "Rice", "grams": 100},
                {"dravyaId": "dravya.no-binding", "name": "Unknown", "grams": 25},
            ],
        }
        panel, source_ids = build_seed.derive_recipe_nutrition(
            recipe, self.nutrition_by_id, self.preferred_bindings
        )
        self.assertEqual(panel["status"], "estimated")
        self.assertEqual(panel["missingIngredients"], ["dravya.no-binding"])
        self.assertEqual(source_ids, [6372, None])
        self.assertAlmostEqual(panel["perServing"]["energyKcal"], 182.5)

        missing_only = dict(recipe)
        missing_only["ingredients"] = recipe["ingredients"][1:]
        none_panel, _ = build_seed.derive_recipe_nutrition(
            missing_only, self.nutrition_by_id, self.preferred_bindings
        )
        self.assertEqual(none_panel["status"], "none")
        self.assertNotIn("energyKcal", none_panel["perServing"])


if __name__ == "__main__":
    unittest.main()
