import csv
import importlib.util
import json
import re
import unittest
import unicodedata
from collections import Counter
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_SEED_PATH = REPO_ROOT / "ayurveda-data" / "build_seed.py"
SPEC = importlib.util.spec_from_file_location("build_seed", BUILD_SEED_PATH)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)

PHASE2_PATH = REPO_ROOT / "ayurveda-data" / "nutrition" / "phase2_rulings.py"
PHASE2_SPEC = importlib.util.spec_from_file_location("phase2_rulings", PHASE2_PATH)
assert PHASE2_SPEC and PHASE2_SPEC.loader
phase2 = importlib.util.module_from_spec(PHASE2_SPEC)
PHASE2_SPEC.loader.exec_module(phase2)


def populated_values(record):
    return {
        (section, nutrient): entry["value"]
        for section, fields in record.items()
        if isinstance(fields, dict)
        for nutrient, entry in fields.items()
        if isinstance(entry, dict) and entry.get("value") is not None
    }


def normalized_tokens(value):
    value = (
        unicodedata.normalize("NFKD", value or "")
        .encode("ascii", "ignore")
        .decode()
        .lower()
    )
    value = re.sub(r"\([^)]*\)", " ", value)
    value = re.sub(r"[^a-z0-9 ]", " ", value)
    stop = {"raw", "the", "and", "of", "a", "an"}
    return frozenset(
        word[:-1]
        if len(word) > 3 and word.endswith("s") and not word.endswith("ss")
        else word
        for word in value.split()
        if word and word not in stop
    )


class NutritionUnitSchemaTests(unittest.TestCase):
    def test_dravya_food_units_match_the_canonical_catalogue(self):
        path = REPO_ROOT / "ayurveda-data" / "nutrition" / "dravya_foods.json"
        rows = json.loads(path.read_text(encoding="utf-8"))

        for row in rows:
            for nutrient, (group, expected_unit) in (
                build_seed.NUTRIENT_CATALOG.items()
            ):
                with self.subTest(
                    dravya_id=row["dravyaId"],
                    group=group,
                    nutrient=nutrient,
                ):
                    entry = row.get(group, {}).get(nutrient)
                    self.assertIsInstance(entry, dict)
                    actual_unit = entry.get("unit")
                    equivalent_micrograms = {
                        actual_unit,
                        expected_unit,
                    } == {"ug", "µg"}
                    self.assertTrue(
                        actual_unit == expected_unit or equivalent_micrograms,
                        f"{row['dravyaId']} {group}.{nutrient} uses "
                        f"{actual_unit!r}, expected {expected_unit!r}",
                    )


class RecipeNutritionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data_root = REPO_ROOT / "ayurveda-data"
        foods_path = REPO_ROOT / "Ayura" / "Legacy" / "foods.json"
        dravya_foods_path = data_root / "nutrition" / "dravya_foods.json"
        foods = json.loads(foods_path.read_text(encoding="utf-8"))
        cls.store_ids = {food["id"] for food in foods}
        cls.usda_nutrition_by_id = build_seed.load_food_nutrition(
            foods_path, cls.store_ids
        )
        cls.dravya_nutrition_by_id = build_seed.load_dravya_food_nutrition(
            dravya_foods_path
        )
        cls.dravya_nutrition_status_by_id = (
            build_seed.load_dravya_food_nutrition_statuses(dravya_foods_path)
        )
        cls.withdrawn_dravya_ids = (
            build_seed.load_withdrawn_dravya_nutrition_ids(dravya_foods_path)
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
        assignments, _, _, placeholder_ids = build_seed.resolve_primary_foods(
            cls.dravyas, cls.store_ids
        )
        cls.nutrition_by_id, cls.preferred_bindings = (
            build_seed.merge_placeholder_nutrition(
                assignments,
                placeholder_ids,
                cls.dravya_nutrition_by_id,
                cls.withdrawn_dravya_ids,
                cls.usda_nutrition_by_id,
                cls.preferred_bindings,
            )
        )
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
            cls.usda_nutrition_by_id,
            cls.dravya_nutrition_by_id,
            cls.withdrawn_dravya_ids,
            cls.source_safety_by_id,
            cls.preferred_bindings,
            cls.dravya_nutrition_status_by_id,
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

        # TRANSITIONAL, POST-INGEST. dravya_foods.json is wired by dravyaId;
        # 4 recipes closed when the dravya ingest landed; 3 more closed when
        # Phase 2 added direct measurements. The remaining 3 use acacia gum,
        # kokum, and neem flower, none of which has a defensible measurement.
        self.assertEqual(counts, {"full": 1508, "estimated": 3, "none": 0})
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

        seeder = (
            REPO_ROOT / "Ayura/Main/DBSeed/AyurvedaSeeder.swift"
        ).read_text(encoding="utf-8")
        helper = seeder.split("private static func applyDravyaNutrition(", 1)[1]
        helper = helper.split("return true", 1)[0]
        swift_keys = set(re.findall(r'nutrient\("([A-Za-z0-9_]+)"\)', helper))
        self.assertEqual(swift_keys, set(build_seed.NUTRIENT_CATALOG))

    def test_nut5_dravya_panels_emit_without_null_to_zero_conversion(self):
        source = {
            row["dravyaId"]: row
            for row in json.loads(
                (
                    REPO_ROOT / "ayurveda-data/nutrition/dravya_foods.json"
                ).read_text(encoding="utf-8")
            )
        }
        emitted = {
            dravya["id"]: dravya["nutrition"]
            for dravya in self.envelope["dravyas"]
            if dravya.get("nutrition") is not None
        }
        self.assertEqual(len(emitted), 124)
        self.assertEqual(
            Counter(payload["status"] for payload in emitted.values()),
            Counter({"measured": 84, "derived": 40}),
        )
        for dravya_id, payload in emitted.items():
            self.assertTrue(payload["per100g"])
            self.assertEqual(
                set(payload["per100g"]), set(payload["units"]), dravya_id
            )
            for nutrient, value in payload["per100g"].items():
                section, _unit = build_seed.NUTRIENT_CATALOG[nutrient]
                source_value = source[dravya_id][section][nutrient]["value"]
                self.assertIsNotNone(source_value, f"{dravya_id}:{nutrient}")
                if value == 0:
                    self.assertEqual(source_value, 0, f"{dravya_id}:{nutrient}")

    def test_nut5_composition_engine_yield_and_missing_panel_policy(self):
        composition = {
            "dravyaId": "dravya.test-composition",
            "yieldG": 400,
            "waterG": 250,
            "ingredients": [
                {"dravyaId": "dravya.a", "grams": 100},
                {"dravyaId": "dravya.b", "grams": 50},
            ],
        }
        payload, source_ids = build_seed.derive_dravya_composition(
            composition,
            {
                1: {"protein": 10.0, "vitaminC": 0.0},
                2: {"protein": 20.0, "vitaminC": 0.0},
            },
            {"dravya.a": 1, "dravya.b": 2},
        )
        self.assertEqual(source_ids, [1, 2])
        self.assertEqual(payload["status"], "derived")
        self.assertEqual(payload["per100g"]["protein"], 5.0)
        self.assertEqual(payload["per100g"]["vitaminC"], 0.0)

        missing, missing_ids = build_seed.derive_dravya_composition(
            composition,
            {1: {"protein": 10.0}},
            {"dravya.a": 1, "dravya.b": 2},
        )
        self.assertIsNone(missing)
        self.assertEqual(missing_ids, [1, None])

    def test_nut5_composition_review_annotations_are_complete(self):
        nutrition_root = REPO_ROOT / "ayurveda-data/nutrition"
        source = json.loads(
            (nutrition_root / "nut5-batch1/compositions.json").read_text(
                encoding="utf-8"
            )
        )
        records = {
            row["dravyaId"]: row
            for row in json.loads(
                (nutrition_root / "dravya_foods.json").read_text(encoding="utf-8")
            )
        }
        traces = []
        affected = set()
        for composition in source["compositions"]:
            review = records[composition["dravyaId"]]["_review"]
            self.assertTrue(review["status"].startswith("derived — computed from "))
            self.assertEqual(review["source"], composition["basis"])
            self.assertIn("established recipe per-nutrient aggregation", review["limitation"])
            if "note" in composition:
                self.assertEqual(review["note"], composition["note"])
            row_traces = review.get("inheritedPartialObservationZeroes", [])
            if row_traces:
                affected.add(composition["dravyaId"])
            for trace in row_traces:
                self.assertTrue(trace["measuredZeroIngredients"])
                self.assertTrue(trace["absentIngredients"])
                nutrient = trace["nutrient"]
                section, _unit = build_seed.NUTRIENT_CATALOG[nutrient]
                self.assertEqual(
                    records[composition["dravyaId"]][section][nutrient]["value"],
                    0,
                )
                traces.append((composition["dravyaId"], nutrient))
        self.assertEqual(len(traces), 28)
        self.assertEqual(
            affected,
            {
                "dravya.kitchari-mung-rice",
                "dravya.kitchari-tridoshic",
                "dravya.khichadi-vegetable",
                "dravya.coconut-rice",
                "dravya.lemon-rice",
                "dravya.dal-tadka-mung",
                "dravya.ambali",
                "dravya.ragi-malt",
                "dravya.payasam-mung",
                "dravya.pongal-sweet",
            },
        )

    def test_recipe_list_projection_reads_the_profile_payload(self):
        projection = (
            REPO_ROOT / "Ayura/Ayurveda/RecipeNutritionProjection.swift"
        ).read_text(encoding="utf-8")
        food_item = (
            REPO_ROOT / "Ayura/Food/Models/FoodItem.swift"
        ).read_text(encoding="utf-8")
        seed_manager = (
            REPO_ROOT / "Ayura/Main/DBSeed/SeedManager.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("profile.nutritionPer100gJSON", projection)
        self.assertIn("profile.nutritionUnitsJSON", projection)
        self.assertIn("RecipeNutritionProjection.shared.load(context: ctx)", seed_manager)
        self.assertIn("RecipeNutritionProjection.shared.snapshot(foodID: item.id)", food_item)
        for nutrient in build_seed.NUTRIENT_CATALOG:
            self.assertIn(f'nutrient("{nutrient}")', food_item)

    def test_phase1b_fields_are_validated_but_not_propagated(self):
        self.assertEqual(len(build_seed.SOURCE_ONLY_NUTRIENT_CATALOG), 66)
        self.assertEqual(len(build_seed.NUTRIENT_CATALOG), 39)

        source = json.loads(
            (REPO_ROOT / "ayurveda-data/nutrition/dravya_foods.json").read_text(
                encoding="utf-8"
            )
        )
        structural_fields = {
            (section, nutrient)
            for food in source
            for section, fields in food.items()
            if isinstance(fields, dict)
            for nutrient, entry in fields.items()
            if isinstance(entry, dict) and {"value", "unit"} <= set(entry)
        }
        self.assertEqual(len(structural_fields), 187)
        self.assertEqual(
            len(set(build_seed.SOURCE_ONLY_NUTRIENT_CATALOG) - {
                ("vitamins", "vitaminD")
            }),
            65,
        )

        source_only_names = {
            nutrient for _, nutrient in build_seed.SOURCE_ONLY_NUTRIENT_CATALOG
        }
        for panel in self.dravya_nutrition_by_id.values():
            self.assertTrue(set(panel) <= set(build_seed.NUTRIENT_CATALOG))
            self.assertFalse(set(panel) & (source_only_names - {"vitaminD"}))

        # Dravya and recipe panels are two emitters of one shipped catalogue.
        # Derive the expected dravya keys directly from that catalogue and the
        # source nulls so an overlapping validation-only entry cannot silently
        # suppress a nutrient on just one path (as vitaminD once did).
        source_by_id = {row["dravyaId"]: row for row in source}
        for dravya_id, panel in self.dravya_nutrition_by_id.items():
            expected = {
                nutrient
                for nutrient, (section, _unit) in (
                    build_seed.NUTRIENT_CATALOG.items()
                )
                if source_by_id[dravya_id][section][nutrient]["value"] is not None
            }
            self.assertEqual(set(panel), expected, dravya_id)
        for recipe in self.envelope["recipes"]:
            self.assertTrue(
                set(recipe["nutrition"]["per100g"])
                <= set(build_seed.NUTRIENT_CATALOG)
            )

        self.assertEqual(
            {
                pair
                for pair, (_, not_for_display) in (
                    build_seed.SOURCE_ONLY_NUTRIENT_CATALOG.items()
                )
                if not_for_display
            },
            {
                ("minerals", "aluminium"),
                ("minerals", "arsenic"),
                ("minerals", "cadmium"),
                ("minerals", "lead"),
                ("minerals", "mercury"),
                ("mineralTotals", "toxic"),
            },
        )

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


class Phase2NutritionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data_root = REPO_ROOT / "ayurveda-data"
        nutrition_root = data_root / "nutrition"
        records = json.loads(
            (nutrition_root / "dravya_foods.json").read_text(encoding="utf-8")
        )
        cls.records = {record["dravyaId"]: record for record in records}
        cls.unresolved = json.loads(
            (nutrition_root / "ifct-unresolved.json").read_text(encoding="utf-8")
        )
        cls.dravyas = {
            item["id"]: item
            for path in (data_root / "dravyas").glob("batch-*.json")
            for item in json.loads(path.read_text(encoding="utf-8"))["items"]
        }

    def test_phase2_population_provenance_and_withdrawals(self):
        populated = {
            dravya_id
            for dravya_id, record in self.records.items()
            if populated_values(record)
        }
        self.assertEqual(len(self.records), 375)
        self.assertEqual(len(populated), 124)

        withdrawn = self.unresolved["withdrawn"]
        self.assertEqual(len(withdrawn), 7)
        self.assertEqual(
            [entry for entry in withdrawn if entry[2] == "F016"],
            [[
                "dravya.fresh-water-chestnut",
                "Fresh water chestnut (singhara)",
                "F016",
                "Water Chestnut",
            ]],
        )
        for dravya_id, _, _, _ in withdrawn:
            self.assertFalse(populated_values(self.records[dravya_id]))
        self.assertEqual(
            sum(
                record.get("_review", {}).get("provenance") == "derived"
                for record in self.records.values()
            ),
            40,
        )

        added_ids = (
            set(phase2.DIRECT_BINDINGS)
            | set(phase2.PUBLISHED_LITERATURE)
            | set(phase2.AMBIGUOUS_BINDINGS)
        )
        self.assertEqual(len(added_ids), 14)
        for dravya_id in added_ids:
            review = self.records[dravya_id]["_review"]
            self.assertTrue(review.get("provenance"), dravya_id)
            self.assertTrue(review.get("source"), dravya_id)
            self.assertTrue(review.get("spread"), dravya_id)
            self.assertTrue(populated_values(self.records[dravya_id]), dravya_id)

    def test_direct_and_literature_rulings_are_exact(self):
        for dravya_id, (code, name) in phase2.DIRECT_BINDINGS.items():
            review = self.records[dravya_id]["_review"]
            self.assertEqual(review["status"], phase2.DIRECT_MATCH_STATUS)
            self.assertEqual(review["ifctCode"], code)
            self.assertEqual(review["ifctName"], name)
            self.assertEqual(review["provenance"], "IFCT 2017")

        for dravya_id, ruling in phase2.PUBLISHED_LITERATURE.items():
            record = self.records[dravya_id]
            review = record["_review"]
            expected = {
                (section, nutrient): value
                for section, fields in ruling["values"].items()
                for nutrient, value in fields.items()
            }
            self.assertEqual(populated_values(record), expected)
            self.assertEqual(review["provenance"], "published-literature")
            self.assertEqual(review["source"], ruling["source"])
            self.assertEqual(review["spread"], ruling["spread"])

        flour_note = self.records["dravya.water-chestnut-flour"]["_review"]["note"]
        self.assertIn("Trapa natans", flour_note)
        self.assertIn("F016", flour_note)
        self.assertIn("Eleocharis dulcis", flour_note)

        for dravya_id, ruling in phase2.DIRECT_DECLINES.items():
            record = self.records[dravya_id]
            self.assertFalse(populated_values(record))
            self.assertEqual(
                record["_review"]["declinedIfctCode"], ruling["ifctCode"]
            )
            self.assertTrue(record["_review"].get("reason"))

    def test_all_ambiguous_candidates_have_a_recorded_disposition(self):
        self.assertEqual(len(self.unresolved["resolvedAmbiguous"]), 6)
        self.assertEqual(len(self.unresolved["ambiguous"]), 16)
        self.assertEqual(
            {entry[0] for entry in self.unresolved["resolvedAmbiguous"]},
            set(phase2.AMBIGUOUS_BINDINGS),
        )
        self.assertEqual(
            {entry[0] for entry in self.unresolved["ambiguous"]},
            set(phase2.AMBIGUOUS_DEFERRALS),
        )

        original_by_id = {
            entry[0]: entry for entry in self.unresolved["resolvedAmbiguous"]
        }
        for dravya_id, ruling in phase2.AMBIGUOUS_BINDINGS.items():
            review = self.records[dravya_id]["_review"]
            resolution = review["manualResolution"]
            selected_code, selected_name = ruling["binding"]
            self.assertEqual(resolution["selectedIfctCode"], selected_code)
            self.assertEqual(resolution["selectedIfctName"], selected_name)
            self.assertEqual(resolution["reason"], ruling["reason"])
            self.assertEqual(
                {
                    (candidate["ifctCode"], candidate["ifctName"])
                    for candidate in resolution["losingCandidates"]
                },
                {
                    tuple(candidate)
                    for candidate in original_by_id[dravya_id][2]
                    if candidate[0] != selected_code
                },
            )

        deferred_by_id = {entry[0]: entry for entry in self.unresolved["ambiguous"]}
        for dravya_id, reason in phase2.AMBIGUOUS_DEFERRALS.items():
            review = self.records[dravya_id]["_review"]
            self.assertEqual(review["reason"], reason)
            self.assertEqual(review["source"], None)
            self.assertEqual(review["spread"], None)
            self.assertEqual(
                {
                    (candidate["ifctCode"], candidate["ifctName"])
                    for candidate in review["ambiguousCandidates"]
                },
                {tuple(candidate) for candidate in deferred_by_id[dravya_id][2]},
            )

    def test_current_no_relation_records_are_unmatched_not_all_null(self):
        nutrition_root = REPO_ROOT / "ayurveda-data" / "nutrition"
        with (nutrition_root / "ifct2017-compositions.csv").open(
            encoding="utf-8", errors="replace"
        ) as source:
            rows = list(csv.DictReader(source))
        columns = {column.split("; ")[-1]: column for column in rows[0]}
        ifct_keys = set()
        for row in rows:
            names = [row[columns["name"]]]
            for part in (row[columns["lang"]] or "").split(";"):
                part = re.sub(r"^\s*[A-Za-z.]{1,5}\.\s*", "", part.strip())
                if part:
                    names.append(part)
            ifct_keys.update(filter(None, map(normalized_tokens, names)))

        no_relation = set()
        for dravya_id, _ in self.unresolved["unmatched"]:
            dravya = self.dravyas[dravya_id]
            names = [
                dravya.get("name"),
                dravya.get("sanskrit"),
                *(dravya.get("aliases") or []),
            ]
            keys = set(filter(None, map(normalized_tokens, names)))
            if not any(
                dravya_key <= ifct_key or ifct_key <= dravya_key
                for dravya_key in keys
                for ifct_key in ifct_keys
            ):
                no_relation.add(dravya_id)

        populated = {
            dravya_id
            for dravya_id in no_relation
            if populated_values(self.records[dravya_id])
        }
        self.assertEqual(len(ifct_keys), 3_435)
        self.assertEqual(len(no_relation), 177)
        self.assertEqual(len(no_relation - populated), 148)
        self.assertEqual(
            populated,
            {
                "dravya.basundi",
                "dravya.black-rice",
                "dravya.coconut-rice",
                "dravya.curd-rice",
                "dravya.camel-milk",
                "dravya.besan-ladoo",
                "dravya.khichadi-vegetable",
                "dravya.kitchari-tridoshic",
                "dravya.lassi-digestive",
                "dravya.lassi-sweet",
                "dravya.lemon-rice",
                "dravya.masala-chai",
                "dravya.pakhala",
                "dravya.panchamrita",
                "dravya.peanut-chikki",
                "dravya.pomegranate-sweet",
                "dravya.pongal-sweet",
                "dravya.pongal-ven",
                "dravya.ponnanganni",
                "dravya.rabri",
                "dravya.rose-milk",
                "dravya.sattu-drink",
                "dravya.shrikhand",
                "dravya.steamed-modak",
                "dravya.tamarind-rice",
                "dravya.tender-tamarind-leaf",
                "dravya.thandai",
                "dravya.veg-pulao",
                "dravya.white-peas",
            },
        )
        self.assertEqual(
            Counter(self.dravyas[dravya_id]["category"] for dravya_id in no_relation),
            Counter(
                {
                    "preparation": 29,
                    "medicinal": 24,
                    "spice": 22,
                    "regional": 21,
                    "beverage": 16,
                    "vegetable": 12,
                    "fruit": 11,
                    "fermented": 8,
                    "grain": 7,
                    "animal": 6,
                    "salt-mineral": 4,
                    "sweetener": 4,
                    "oil-fat": 3,
                    "leafy-green": 3,
                    "seed": 2,
                    "dairy": 2,
                    "dry-fruit-nut": 1,
                    "legume": 2,
                }
            ),
        )


if __name__ == "__main__":
    unittest.main()
