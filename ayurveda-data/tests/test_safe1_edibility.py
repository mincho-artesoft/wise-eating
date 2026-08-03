import glob
import gzip
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "ayurveda-data"
SPEC = importlib.util.spec_from_file_location(
    "build_seed_safe1", DATA / "build_seed.py"
)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)

EXPECTED = {
    "dravya.camphor-edible": (
        "neurotoxic — paediatric lethal dose is a few times the culinary pinch"
    ),
    "dravya.alkanet-root": (
        "dye, not an ingredient — pyrrolizidine alkaloids, not swallowed"
    ),
    "dravya.edible-lime": "caustic alkali — a reagent, not a food",
    "dravya.castor-oil": (
        "stimulant laxative — a drug dose, not a cooking oil"
    ),
    "dravya.shilajit": (
        "supplement taken by dose — contamination risk, not a food"
    ),
    "dravya.kaunch-beej": (
        "pharmacologically active L-DOPA seed — requires processing and dosing, "
        "not a food"
    ),
}
LEGACY_ENGINE_EXCLUSIONS = {"dravya.betel-nut", "dravya.vanaspati"}
ENGINE_ONLY_EXCLUSIONS = {
    "dravya.acacia-gum",
    "dravya.silver-leaf",
    "dravya.tragacanth-gum",
}
HONEY_AGE_SOURCE = (
    "NHS, Foods to avoid — do not give honey until over 1 year old | "
    "WHO, Infant and young child feeding, 20 Dec 2023 — complementary foods "
    "at 6 months"
)


class SAFE1EdibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dravyas = build_seed.load_batches(
            DATA / "dravyas", "batch-*.json", "items"
        )
        cls.recipes = build_seed.load_batches(
            DATA / "recipes", "batch-r*.json", "items"
        )
        cls.by_id = {dravya["id"]: dravya for dravya in cls.dravyas}

    def test_source_schema_defaults_true_and_has_exact_six_exclusions(self):
        inedible = {
            dravya["id"]: build_seed.dravya_edibility(dravya)[1]
            for dravya in self.dravyas
            if build_seed.dravya_edibility(dravya)[0] is False
        }
        self.assertEqual(inedible, EXPECTED)
        self.assertTrue(
            all(
                build_seed.dravya_edibility(dravya)[0]
                for dravya in self.dravyas
                if dravya["id"] not in EXPECTED
            )
        )
        readme = (DATA / "README.md").read_text(encoding="utf-8")
        validator = (DATA / "validate.py").read_text(encoding="utf-8")
        self.assertIn("defaults to `true` when omitted", readme)
        self.assertIn("edible false requires inedibleReason", validator)

    def test_meal_engine_uses_the_existing_exclusion_set(self):
        self.assertEqual(
            build_seed.ENGINE_EXCLUDED_IDS,
            set(EXPECTED) | LEGACY_ENGINE_EXCLUSIONS | ENGINE_ONLY_EXCLUSIONS,
        )
        source = (DATA / "build_seed.py").read_text(encoding="utf-8")
        self.assertIn(
            'output["engineExcluded"] = dravya["id"] in ENGINE_EXCLUDED_IDS',
            source,
        )
        self.assertIn("expected {len(ENGINE_EXCLUDED_IDS)}", source)

    def test_no_recipe_references_any_inedible_dravya(self):
        references = {dravya_id: [] for dravya_id in EXPECTED}
        for recipe in self.recipes:
            for ingredient in recipe["ingredients"]:
                dravya_id = ingredient.get("dravyaId")
                if dravya_id in references:
                    references[dravya_id].append(recipe["id"])
        self.assertEqual(references, {dravya_id: [] for dravya_id in EXPECTED})

    def test_future_recipe_reference_is_named_and_non_portioned(self):
        metadata = build_seed.ingredient_presentation_metadata(
            {"dravyaId": "dravya.castor-oil", "name": "Castor oil", "grams": 4.5},
            self.by_id,
        )
        self.assertEqual(metadata["portioned"], False)
        self.assertEqual(
            metadata["contraindications"],
            self.by_id["dravya.castor-oil"]["contraindications"],
        )
        detail = (
            ROOT / "Ayura/Food/Views/FoodItemDetailView.swift"
        ).read_text(encoding="utf-8")
        self.assertIn('Text("Non-portioned")', detail)
        self.assertIn("ingredient.inedibleContraindications", detail)
        self.assertIn("if ingredient.isEdible", detail)

    def test_search_browse_and_suggestion_surfaces_exclude_rows(self):
        smart = (
            ROOT / "Ayura/FoodSearch/VM/SmartFoodSearchEngine.swift"
        ).read_text(encoding="utf-8")
        browse = (
            ROOT / "Ayura/Food/ViewModels/FoodListVM.swift"
        ).read_text(encoding="utf-8")
        gate = (
            ROOT / "Ayura/Ayurveda/AyurvedaRecommendationGate.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("if !item.isEdible { continue }", smart)
        self.assertIn(".filter(\\.isEdible)", smart)
        self.assertGreaterEqual(browse.count("$0.isEdible"), 5)
        self.assertIn("profiles.filter(\\.engineExcluded)", gate)

    def test_compact_age_is_nullable_and_cache_shape_is_reversioned(self):
        compact = (
            ROOT / "Ayura/FoodSearch/Structs/CompactFoodItem.swift"
        ).read_text(encoding="utf-8")
        index = (
            ROOT / "Ayura/FoodSearch/SearchIndexStore.swift"
        ).read_text(encoding="utf-8")
        preseed = (DATA / "build_preseeded_store.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("let enforcedMinAgeMonths: Int?", compact)
        self.assertIn("currentIndexVersion: Int = 9", index)
        self.assertIn("food.isEdible", index)
        self.assertIn('"cacheVersion": 9', preseed)
        self.assertIn(
            '"compact nil enforced ages differ from inedible foods"',
            preseed,
        )
        self.assertIn(
            '"metadata nil enforced ages differ from inedible foods"',
            preseed,
        )

    def test_leatherwood_honey_age_is_authored_by_id(self):
        foods = json.loads(
            (ROOT / "Ayura/Legacy/foods.json").read_text(encoding="utf-8")
        )
        row = next(food for food in foods if food["id"] == 12_117)
        self.assertEqual(row["name"], "Honey (especially Leatherwood)")
        self.assertEqual(row["minAgeMonths"], 12)
        self.assertEqual(row["ageProvenance"], "authored")
        self.assertEqual(row["ageSource"], HONEY_AGE_SOURCE)

    def test_serving_age_and_dosha_are_unreachable_in_ui(self):
        detail = (
            ROOT / "Ayura/Food/Views/FoodItemDetailView.swift"
        ).read_text(encoding="utf-8")
        section = (
            ROOT / "Ayura/Ayurveda/Views/AyurvedaSectionView.swift"
        ).read_text(encoding="utf-8")
        seeder = (
            ROOT / "Ayura/Main/DBSeed/AyurvedaSeeder.swift"
        ).read_text(encoding="utf-8")
        facet = (
            ROOT / "Ayura/FoodSearch/Structs/AyurvedaFacet.swift"
        ).read_text(encoding="utf-8")
        search_row = (
            ROOT / "Ayura/Food/Views/SearchResultRow.swift"
        ).read_text(encoding="utf-8")
        food_search = (
            ROOT / "Ayura/FoodSearch/FoodSearchView.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("guard food.isEdible else { return nil }", detail)
        self.assertIn("food.isEdible\n            && food.minAgeMonths", detail)
        self.assertIn("servingsJSON: dravya.edible ? servingsJSON : nil", seeder)
        self.assertIn("if display.edible {", section)
        self.assertIn("DoshaBarsView(", section)
        self.assertIn("profile.edible", facet)
        self.assertIn("food.isEdible && food.minAgeMonths", food_search)
        self.assertIn("item.isEdible && item.minAgeMonths", search_row)

    def test_shipped_seed_carries_edibility_and_honey_age_contract(self):
        with gzip.open(ROOT / "Ayura/ayurveda_seed.json.gz", "rt") as handle:
            seed = json.load(handle)
        self.assertGreaterEqual(seed["seedVersion"], 7)
        dravyas = {dravya["id"]: dravya for dravya in seed["dravyas"]}
        profiles = seed["dravyas"] + seed["recipes"]
        self.assertTrue(all("edible" in profile for profile in profiles))
        self.assertEqual(
            sum(profile["edible"] is False for profile in profiles),
            6,
        )
        self.assertEqual(
            {item["id"] for item in seed["dravyas"] if not item["edible"]},
            set(EXPECTED),
        )
        self.assertEqual(
            sum(item["engineExcluded"] for item in seed["dravyas"]), 11
        )
        for dravya_id, reason in EXPECTED.items():
            self.assertEqual(dravyas[dravya_id]["inedibleReason"], reason)

        self.assertEqual(dravyas["dravya.honey"]["safety"]["minAgeMonths"], 12)
        self.assertEqual(
            dravyas["dravya.honey-aged"]["safety"]["minAgeMonths"], 12
        )
        honey_ids = {"dravya.honey", "dravya.honey-aged"}
        honey_recipes = [
            recipe
            for recipe in seed["recipes"]
            if any(
                contributor["ingredientId"] in honey_ids
                for contributor in recipe["safety"]["ageContributors"]
            )
        ]
        self.assertEqual(len(honey_recipes), 5)
        self.assertTrue(
            all(recipe["safety"]["minAgeMonths"] >= 12 for recipe in honey_recipes)
        )


if __name__ == "__main__":
    unittest.main()
