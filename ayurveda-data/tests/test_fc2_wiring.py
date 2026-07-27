import gzip
import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLANNER_PATH = (
    ROOT
    / "WiseEating"
    / "AI"
    / "MealPlanning"
    / "USDAWeeklyMealPlanner.swift"
)
RECIPE_GENERATOR_PATH = (
    ROOT
    / "WiseEating"
    / "AI"
    / "ReceptGeneration"
    / "AIRecipeGenerator.swift"
)
CONCEPT_ARTIFACT_PATH = ROOT / "WiseEating" / "food_concepts.json.gz"
FOODS_PATH = ROOT / "WiseEating" / "Legacy" / "foods.json"


class FC2PlannerWiringTests(unittest.TestCase):
    def test_planner_exclusions_are_canonical_set_operations(self):
        planner = PLANNER_PATH.read_text(encoding="utf-8")
        recipe_generator = RECIPE_GENERATOR_PATH.read_text(encoding="utf-8")

        for retired_symbol in (
            "containsExcluded",
            "violatesExcluded",
            "deriveHardExcludes",
            "removeBannedCuisineKeywords",
            "alcoholKeywords",
        ):
            self.assertNotIn(retired_symbol, planner)

        self.assertIn("candidateIDs.subtracting(blockedIDs)", planner)
        self.assertIn("FoodConcepts.shared.members(of: concept)", planner)
        self.assertIn("ontologyAliases: ontologyAliases", planner)
        self.assertIn("candidateIDs.subtracting(blockedIDs)", recipe_generator)
        self.assertNotRegex(
            planner,
            re.compile(
                r"(?:excluded|banned)\w*\.contains\s*\{[^}]*\.contains\(",
                re.DOTALL,
            ),
        )

    def test_alcohol_concept_spares_ale_and_root_beer(self):
        with gzip.open(CONCEPT_ARTIFACT_PATH, "rt", encoding="utf-8") as source:
            artifact = json.load(source)
        foods = {
            int(food["id"]): food["name"].lower()
            for food in json.loads(FOODS_PATH.read_text(encoding="utf-8"))
        }
        alcohol_ids = set(artifact["membership"]["alcohol"])

        spared = {
            food_id
            for food_id, name in foods.items()
            if "root beer" in name or "ginger ale" in name
        }
        alcoholic = {
            food_id
            for food_id, name in foods.items()
            if (
                "table wine" in name
                or "beer, regular" in name
                or "distilled" in name
            )
        }

        self.assertTrue(spared)
        self.assertTrue(alcoholic)
        self.assertTrue(spared.isdisjoint(alcohol_ids))
        self.assertTrue(alcoholic.intersection(alcohol_ids))


if __name__ == "__main__":
    unittest.main()
