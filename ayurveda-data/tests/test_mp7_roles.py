import gzip
import hashlib
import importlib.util
import json
import unittest
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
    "e6c52660bb8549a7136ac5799d02a9accd6861bfe3af7f2c242b38de1ebb7847"
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

    def test_director_source_is_unchanged_and_rev4_complete(self):
        self.assertEqual(
            hashlib.sha256(ROLE_SOURCE_PATH.read_bytes()).hexdigest(),
            DIRECTOR_ROLE_SOURCE_SHA256,
        )
        self.assertEqual(self.role_source["rolesVersion"], 4)
        self.assertEqual(len(self.role_source["roles"]), 15)
        self.assertEqual(len(self.role_source["rules"]), 32)
        self.assertEqual(
            sum(len(rule.get("phrases", [])) for rule in self.role_source["rules"]),
            656,
        )
        self.assertEqual(
            sum(
                len(rule.get("tokenGroups", []))
                for rule in self.role_source["rules"]
            ),
            34,
        )
        self.assertEqual(
            sum(
                len(rule.get("vetoTokens", []))
                for rule in self.role_source["rules"]
            ),
            94,
        )

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

    def test_requires_cooking_training_cases_are_rule_self_consistent(self):
        failures = []
        for case in self.goldens["requiresCookingCases"]:
            actual = self.resolve(case["name"])["requiresCooking"]
            if actual != case["requiresCooking"]:
                failures.append(
                    {
                        "name": case["name"],
                        "expected": case["requiresCooking"],
                        "actual": actual,
                    }
                )
        self.assertEqual(failures, [])

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
        self.assertEqual(self.artifact["ruleCount"], 32)
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
