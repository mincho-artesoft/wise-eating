import gzip
import hashlib
import importlib.util
import json
import unittest
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_SEED_PATH = ROOT / "ayurveda-data" / "build_seed.py"
ROLE_SOURCE_PATH = ROOT / "ayurveda-data" / "rules" / "food-roles.json"
ROLE_GOLDENS_PATH = ROOT / "ayurveda-data" / "tests" / "food-role-goldens.json"
MODIFIERS_PATH = ROOT / "ayurveda-data" / "rules" / "modifiers.json"
FOODS_PATH = ROOT / "WiseEating" / "Legacy" / "foods.json"
SEED_PATH = ROOT / "WiseEating" / "ayurveda_seed.json.gz"
ROLE_ARTIFACT_PATH = ROOT / "WiseEating" / "food_roles.json.gz"
KNOWLEDGE_BASE_PATH = (
    ROOT / "WiseEating" / "FoodSearch" / "SearchKnowledgeBase.swift"
)
RUNTIME_PATH = (
    ROOT
    / "WiseEating"
    / "AI"
    / "MealPlanning"
    / "FoodRoleResolver.swift"
)

DIRECTOR_ROLE_SOURCE_SHA256 = (
    "0a9c19b1ed90bcf1a9cdc126b336afc7a6be6c958b1f8e72dab503973f987cac"
)
DIRECTOR_GOLDENS_SHA256 = (
    "5dae3f4ff44ee904b38dbb207c6a2affa3fbfaaa6ea8b02f62b4765915b337f2"
)

SPEC = importlib.util.spec_from_file_location("build_seed_mp7", BUILD_SEED_PATH)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)


class MP7FoodRoleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.role_source = build_seed.load_food_role_source(ROLE_SOURCE_PATH)
        cls.goldens = json.loads(ROLE_GOLDENS_PATH.read_text(encoding="utf-8"))
        cls.modifiers = json.loads(
            MODIFIERS_PATH.read_text(encoding="utf-8")
        )["modifiers"]
        cls.suffix_terms = build_seed.load_suffix_negation_terms(
            KNOWLEDGE_BASE_PATH
        )
        cls.foods = json.loads(FOODS_PATH.read_text(encoding="utf-8"))
        source_ids = {food["id"] for food in cls.foods}
        cls.catalog = build_seed.load_food_catalog(FOODS_PATH, source_ids)
        with gzip.open(SEED_PATH, "rt", encoding="utf-8") as source:
            cls.seed = json.load(source)
        cls.artifact, cls.diagnostics = build_seed.build_food_roles(
            cls.seed,
            cls.catalog,
            cls.role_source,
            cls.modifiers,
            cls.suffix_terms,
        )

    @classmethod
    def resolve(cls, name, **signals):
        return build_seed.resolve_food_role_fixture(
            name,
            cls.role_source,
            cls.modifiers,
            cls.suffix_terms,
            **signals,
        )

    def test_director_sources_are_unchanged_and_rev9_complete(self):
        self.assertEqual(
            hashlib.sha256(ROLE_SOURCE_PATH.read_bytes()).hexdigest(),
            DIRECTOR_ROLE_SOURCE_SHA256,
        )
        self.assertEqual(
            hashlib.sha256(ROLE_GOLDENS_PATH.read_bytes()).hexdigest(),
            DIRECTOR_GOLDENS_SHA256,
        )
        self.assertEqual(self.role_source["rolesVersion"], 9)
        self.assertEqual(self.goldens["goldensVersion"], 3)
        self.assertEqual(len(self.role_source["roles"]), 15)
        self.assertEqual(len(self.role_source["rules"]), 34)
        self.assertEqual(
            sum(len(rule.get("phrases", [])) for rule in self.role_source["rules"]),
            670,
        )
        self.assertEqual(
            sum(
                len(rule.get("tokenGroups", []))
                for rule in self.role_source["rules"]
            ),
            38,
        )
        self.assertEqual(
            sum(
                len(rule.get("vetoTokens", []))
                for rule in self.role_source["rules"]
            ),
            123,
        )

    def test_dry_mix_is_ineligible_only_before_preparation(self):
        cases = (
            ("Puddings, tapioca, dry mix", "ingredientOnly"),
            ("Pudding, tapioca, made from dry mix", "sweet"),
            (
                "Hot chocolate / cocoa, dry mix, made with water",
                "beverage",
            ),
            (
                "Milk, malted, dry mix, not reconstituted",
                "ingredientOnly",
            ),
        )
        for name, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(self.resolve(name)["role"], expected)

    def test_real_signal_vocabularies_are_exact_and_recipe_post_pass_wins(self):
        rules = {rule["id"]: rule for rule in self.role_source["rules"]}
        category_values = set().union(
            *(
                set(rules[rule_id]["categoryMap"])
                for rule_id in (
                    "U-CATEGORY-SENSITIVE",
                    "U-CATEGORY-FINE",
                    "U-CATEGORY-COARSE",
                )
            )
        )
        self.assertEqual(
            self.diagnostics["categoryValues"],
            category_values,
        )
        self.assertEqual(
            self.diagnostics["dravyaCategoryValues"],
            set(rules["D-DRAVYA-CATEGORY"]["dravyaMap"]),
        )
        self.assertEqual(
            self.diagnostics["recipeMealValues"],
            {"breakfast", "lunch", "dinner", "snack", "drink", "dessert"},
        )
        self.assertEqual(rules["A-RECIPE-MEAL"]["priority"], 85)

        self.assertEqual(
            self.resolve(
                "Unsignalled prepared breakfast",
                recipe_meal="breakfast",
                ingredient_count=2,
                step_count=1,
            )["role"],
            "main",
        )
        self.assertEqual(
            self.resolve(
                "Bathua Raita",
                recipe_meal="lunch",
                ingredient_count=2,
                step_count=1,
            )["role"],
            "side",
        )
        self.assertEqual(
            self.resolve(
                "Masala Vegetable Khichdi",
                recipe_meal="lunch",
                ingredient_count=13,
                step_count=4,
            )["role"],
            "main",
        )
        self.assertEqual(
            self.resolve(
                "Fennel Coriander Cooling Masala",
                recipe_meal="lunch",
                ingredient_count=5,
                step_count=2,
            )["role"],
            "spice",
        )
        self.assertEqual(
            self.resolve(
                "Bajra Roti with Gud-Ghee",
                recipe_meal="breakfast",
                ingredient_count=6,
                step_count=3,
            )["role"],
            "staple",
        )
        self.assertEqual(
            self.resolve(
                "Unknown infusion",
                recipe_meal="drink",
                ingredient_count=2,
                step_count=1,
            )["ruleId"],
            "A-RECIPE-MEAL",
        )

    def test_role_training_cases_are_rule_self_consistent(self):
        failures = []
        for case in self.goldens["roleCases"]:
            actual = self.resolve(case["name"])["role"]
            if actual != case["expectRole"]:
                failures.append(
                    {
                        "name": case["name"],
                        "expected": case["expectRole"],
                        "actual": actual,
                    }
                )
        self.assertEqual(failures, [])

    def test_legacy_requires_cooking_fixture_has_only_the_rev6_semantic_delta(self):
        failures = []
        for case in self.goldens["requiresCookingCases"]:
            actual = self.resolve(case["name"])["notReadyToEat"]
            if actual != case["requiresCooking"]:
                failures.append(
                    {
                        "name": case["name"],
                        "expected": case["requiresCooking"],
                        "actual": actual,
                    }
                )
        self.assertEqual(
            failures,
            [
                {
                    "name": "Chickpea flour (besan)",
                    "expected": False,
                    "actual": True,
                }
            ],
        )

    def test_not_ready_evaluation_order_and_structural_triggers(self):
        must_flag = (
            "Sweet Potatoes, french fried, crosscut, frozen, unprepared",
            "Orange juice, frozen concentrate, undiluted",
            "Cookies, chocolate chip, refrigerated dough",
            "Chickpea flour",
            "Bread dough, ready-to-bake",
            "Lentils, pink or red, raw",
        )
        must_not_flag = (
            "Hot chocolate / cocoa, dry mix, made with water",
            "Prunes, dehydrated, uncooked",
            "Bread, sour dough",
            "Lemon juice from concentrate, canned",
            "Bread, whole-wheat, made with wheat flour",
            "Pasta with tomato-based sauce, ready-to-heat",
        )
        for name in must_flag:
            with self.subTest(name=name):
                self.assertTrue(self.resolve(name)["notReadyToEat"])
        for name in must_not_flag:
            with self.subTest(name=name):
                self.assertFalse(self.resolve(name)["notReadyToEat"])

    def test_near_duplicate_training_cases_are_rule_self_consistent(self):
        failures = []
        for case in self.goldens["nearDuplicateCases"]:
            left = self.resolve(case["a"])
            right = self.resolve(case["b"])
            actual = (
                left["role"] == right["role"]
                and left["headword"] == right["headword"]
            )
            if actual != case["expectDuplicate"]:
                failures.append(
                    {
                        "a": case["a"],
                        "b": case["b"],
                        "expected": case["expectDuplicate"],
                        "actual": actual,
                        "left": left,
                        "right": right,
                    }
                )
        self.assertEqual(failures, [])

    def test_artifact_is_complete_sorted_and_deterministic(self):
        self.assertEqual(self.artifact["catalogCount"], 14_484)
        self.assertEqual(self.artifact["roleCount"], 15)
        self.assertEqual(self.artifact["ruleCount"], 34)
        self.assertEqual(
            [item["foodId"] for item in self.artifact["items"]],
            sorted(item["foodId"] for item in self.artifact["items"]),
        )
        rebuilt, _ = build_seed.build_food_roles(
            self.seed,
            self.catalog,
            self.role_source,
            self.modifiers,
            self.suffix_terms,
        )
        self.assertEqual(
            build_seed.encode_deterministic_gzip(self.artifact),
            build_seed.encode_deterministic_gzip(rebuilt),
        )

    def test_rev9_plain_catalogue_reference_populations(self):
        plain_ids = {food["id"] for food in self.foods}
        plain = [
            item for item in self.artifact["items"]
            if item["foodId"] in plain_ids
        ]
        ineligible = {
            role["id"]
            for role in self.role_source["roles"]
            if not role.get("eligibleAsComponent", True)
        }
        self.assertEqual(len(plain), 12_601)
        self.assertEqual(sum(item["role"] == "other" for item in plain), 108)
        self.assertEqual(
            sum(item["role"] in ineligible for item in plain),
            543,
        )
        self.assertEqual(
            sum(item["notReadyToEat"] for item in plain),
            304,
        )
        trigger_counts = Counter(
            trigger
            for food_id, trigger in self.diagnostics[
                "notReadyTriggers"
            ].items()
            if food_id in plain_ids
        )
        self.assertEqual(
            trigger_counts,
            {
                "unprepared": 87,
                "dry-pulse-or-grain": 89,
                "commodity-flour": 58,
                "unreconstituted": 26,
                "uncooked": 12,
                "dough": 11,
                "ready-to-bake": 10,
                "concentrate": 11,
            },
        )

    def test_rev7_concentrate_token_and_vetoes(self):
        cases = (
            ("Raspberry juice concentrate", True),
            ("Lemon juice from concentrate, canned", False),
            (
                "Orange juice, chilled, includes from concentrate",
                False,
            ),
        )
        for name, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(
                    self.resolve(name)["notReadyToEat"],
                    expected,
                )

    def test_rev8_holdout_corrections_remain_projected(self):
        cases = (
            (
                "Corn, sweet, yellow, raw",
                "side",
                {"category": "Vegetables and Vegetable Products"},
            ),
            (
                "Nuts, formulated, wheat-based, all flavors except macadamia",
                "side",
                {},
            ),
            ("Egg roll, meatless", "side", {"category": "Egg rolls"}),
            ("Milk, dry, whole", "ingredientOnly", {}),
        )
        for name, expected, signals in cases:
            with self.subTest(name=name):
                self.assertEqual(
                    self.resolve(name, **signals)["role"],
                    expected,
                )

    def test_rev9_concentrated_milk_is_contiguous_and_prepared_aware(self):
        rules = {rule["id"]: rule for rule in self.role_source["rules"]}
        self.assertNotIn("matchScope", rules["G-STAPLE"])
        self.assertNotIn("tokenGroups", rules["X-CONCENTRATED-MILK"])
        self.assertEqual(
            rules["X-CONCENTRATED-MILK"]["matchScope"],
            "wholeName",
        )
        self.assertTrue(rules["X-CONCENTRATED-MILK"]["phrases"])
        self.assertTrue(rules["X-CONCENTRATED-MILK"]["preparedIndicators"])

        by_name = {food["name"]: food["id"] for food in self.foods}
        artifact_by_id = {
            item["foodId"]: item for item in self.artifact["items"]
        }
        ineligible = {
            "infantProduct",
            "ingredientOnly",
            "nonFood",
            "supplement",
        }
        must_remain_eligible = (
            "Puddings, vanilla, dry mix, instant, prepared with whole milk",
            "Hot chocolate / cocoa, dry mix, made with whole or reduced fat (2%) milk",
            "Bread, white, prepared from recipe, made with nonfat dry milk",
            "Milk, dry, reconstituted, whole",
            "Potatoes, au gratin, dry mix, prepared with water, whole milk and butter",
        )
        for name in must_remain_eligible:
            with self.subTest(name=name):
                self.assertNotIn(
                    artifact_by_id[by_name[name]]["role"],
                    ineligible,
                )

        must_be_ingredient_only = (
            "Milk, evaporated, 2% fat, with added vitamin A and vitamin D",
            "Milk, condensed, sweetened",
            "Milk, dry, whole, with added vitamin D",
            "Milk, dry, not reconstituted",
        )
        for name in must_be_ingredient_only:
            with self.subTest(name=name):
                self.assertEqual(
                    artifact_by_id[by_name[name]]["role"],
                    "ingredientOnly",
                )

        plain_ids = {food["id"] for food in self.foods}
        self.assertEqual(
            sum(
                item["foodId"] in plain_ids
                and item["ruleId"] == "X-CONCENTRATED-MILK"
                for item in self.artifact["items"]
            ),
            17,
        )

    def test_rev9_recipe_reference_populations(self):
        recipe_ids = {recipe["foodId"] for recipe in self.seed["recipes"]}
        recipes = [
            item for item in self.artifact["items"]
            if item["foodId"] in recipe_ids
        ]
        definitions = {
            role["id"]: role for role in self.role_source["roles"]
        }
        prohibited = set(self.role_source["recipePostPass"]["prohibited"])
        self.assertEqual(len(recipes), 1_500)
        self.assertEqual(
            sum(definitions[item["role"]]["anchor"] for item in recipes),
            1_039,
        )
        self.assertEqual(
            sum(item["role"] in prohibited for item in recipes),
            0,
        )

    def test_bundled_artifact_matches_current_build(self):
        with gzip.open(ROLE_ARTIFACT_PATH, "rt", encoding="utf-8") as source:
            bundled = json.load(source)
        self.assertEqual(bundled, self.artifact)

    def test_runtime_is_an_immutable_food_id_cache(self):
        source = RUNTIME_PATH.read_text(encoding="utf-8")
        self.assertIn("struct FoodRoleResolver: Sendable", source)
        self.assertIn("private let resolutionByFoodID", source)
        self.assertIn("func resolution(for foodID: Int)", source)
        self.assertIn('forResource: "food_roles"', source)
        self.assertNotIn("FoodItem", source)

    def test_contested_role_cases_are_visible_but_not_gated(self):
        self.assertEqual(len(self.goldens["contested"]), 6)
        self.assertTrue(
            all(case.get("candidates") for case in self.goldens["contested"])
        )


if __name__ == "__main__":
    unittest.main()
