import gzip
import json
import unittest
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROLE_SOURCE = ROOT / "ayurveda-data" / "rules" / "food-roles.json"
ROLE_ARTIFACT = ROOT / "Ayura" / "food_roles.json.gz"
KNOWN_BAD_PLAN = (
    ROOT / "ayurveda-data" / "tests" / "mp6b-known-bad-plan.json"
)

TARGET_FOODS = 14_487


class CulinaryValidityChecker:
    """C1-C10 checker backed only by the shipped food-role sources."""

    HARD_IDS = {"C1", "C2", "C3", "C4", "C5", "C6", "C9"}
    SEASONING_ROLES = {"spice", "herb", "condiment", "medicinalHerb"}

    def __init__(self, role_source, role_artifact):
        self.definitions = {
            role["id"]: role for role in role_source["roles"]
        }
        self.items = {
            item["foodId"]: item for item in role_artifact["items"]
        }
        self.catalog_other_count = sum(
            item["role"] == "other" for item in role_artifact["items"]
        )

    def check_meal(self, meal, profile_age_months):
        resolved = []
        for component in meal["components"]:
            item = self.items.get(component["foodId"])
            if item is None:
                raise AssertionError(
                    f"role artifact missing foodId {component['foodId']}"
                )
            resolved.append((component, item, self.definitions[item["role"]]))

        failures = set()
        infant_allowed = profile_age_months < 36
        infant_count = sum(
            item["role"] == "infantProduct"
            for _component, item, _definition in resolved
        )
        if infant_count and not infant_allowed:
            failures.add("C1")

        has_anchor = any(
            not item["notReadyToEat"]
            and (
                definition.get("eligibleAsComponent", True)
                or (item["role"] == "infantProduct" and infant_allowed)
            )
            and (
                definition["anchor"]
                or (item["role"] == "infantProduct" and infant_allowed)
            )
            for _component, item, definition in resolved
        )
        if not has_anchor:
            failures.add("C2")

        role_counts = Counter(
            item["role"] for _component, item, _definition in resolved
        )
        if (
            sum(role_counts[role] for role in self.SEASONING_ROLES) > 2
            or role_counts["medicinalHerb"] > 1
        ):
            failures.add("C3")

        for component, item, definition in resolved:
            limits = definition["portionGrams"]
            if not limits["min"] <= component["grams"] <= limits["max"]:
                failures.add("C4")
            if item["notReadyToEat"]:
                failures.add("C5")

        if role_counts["beverage"] > 2:
            failures.add("C6")

        duplicate_keys = [
            (item["role"], item["headword"])
            for _component, item, _definition in resolved
            if item["headword"] != "unknown"
        ]
        near_duplicate_count = sum(
            count - 1
            for count in Counter(duplicate_keys).values()
            if count > 1
        )

        for _component, item, definition in resolved:
            eligible = definition.get("eligibleAsComponent", True)
            if item["role"] == "infantProduct":
                eligible = infant_allowed
            if not eligible:
                failures.add("C9")

        return {
            "day": meal["day"],
            "name": meal["name"],
            "hardFailures": sorted(failures),
            "nearDuplicateCount": near_duplicate_count,
            "roleDistribution": dict(sorted(role_counts.items())),
            "otherCount": role_counts["other"],
        }

    def check_plan(self, plan):
        meals = []
        for day in plan["days"]:
            for meal in day["meals"]:
                meals.append(
                    self.check_meal(
                        {**meal, "day": day["day"]},
                        plan["profileAgeMonths"],
                    )
                )
        role_distribution = Counter()
        for meal in meals:
            role_distribution.update(meal["roleDistribution"])
        return {
            "meals": meals,
            "failedHardMealCount": sum(
                bool(meal["hardFailures"]) for meal in meals
            ),
            "roleDistribution": dict(sorted(role_distribution.items())),
            "catalogOtherCount": self.catalog_other_count,
            "planOtherCount": sum(meal["otherCount"] for meal in meals),
            "nearDuplicateCount": sum(
                meal["nearDuplicateCount"] for meal in meals
            ),
        }


class MP7ValidityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.role_source = json.loads(
            ROLE_SOURCE.read_text(encoding="utf-8")
        )
        with gzip.open(ROLE_ARTIFACT, "rt", encoding="utf-8") as source:
            cls.role_artifact = json.load(source)
        cls.known_bad = json.loads(
            KNOWN_BAD_PLAN.read_text(encoding="utf-8")
        )
        cls.checker = CulinaryValidityChecker(
            cls.role_source,
            cls.role_artifact,
        )
        cls.result = cls.checker.check_plan(cls.known_bad)
        cls.by_slot = {
            (meal["day"], meal["name"]): meal
            for meal in cls.result["meals"]
        }

    def test_g0_known_bad_meal_failure_rate(self):
        self.assertEqual(len(self.result["meals"]), 21)
        self.assertEqual(self.result["failedHardMealCount"], 21)

    def test_g0_all_three_infant_formula_meals_fail_c1(self):
        for slot in ((2, "Breakfast"), (3, "Dinner"), (4, "Dinner")):
            with self.subTest(slot=slot):
                self.assertIn("C1", self.by_slot[slot]["hardFailures"])

    def test_g0_four_chocolate_drink_breakfast_fails_c6(self):
        self.assertIn(
            "C6",
            self.by_slot[(1, "Breakfast")]["hardFailures"],
        )

    def test_g0_six_herb_dinner_fails_c2_and_c3(self):
        failures = self.by_slot[(5, "Dinner")]["hardFailures"]
        self.assertIn("C2", failures)
        self.assertIn("C3", failures)

    def test_g0_raw_mung_and_lentil_meals_fail_c5(self):
        for slot in (
            (2, "Breakfast"),
            (5, "Breakfast"),
            (5, "Dinner"),
        ):
            with self.subTest(slot=slot):
                self.assertIn("C5", self.by_slot[slot]["hardFailures"])

    def test_checker_uses_role_source_for_every_culinary_rule(self):
        source = Path(__file__).read_text(encoding="utf-8")
        self.assertIn('definition["portionGrams"]', source)
        self.assertIn('item["notReadyToEat"]', source)
        self.assertIn('(item["role"], item["headword"])', source)
        self.assertEqual(set(self.checker.definitions), {
            role["id"] for role in self.role_source["roles"]
        })
        self.assertEqual(len(self.checker.items), TARGET_FOODS)


if __name__ == "__main__":
    unittest.main()
