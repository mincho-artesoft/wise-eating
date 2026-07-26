import gzip
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_SEED_PATH = ROOT / "ayurveda-data" / "build_seed.py"
ONTOLOGY_PATH = ROOT / "ayurveda-data" / "rules" / "food-concepts.json"
OVERRIDES_PATH = (
    ROOT / "ayurveda-data" / "crosswalk" / "concept-overrides.json"
)
EXCLUSION_PATH = (
    ROOT / "ayurveda-data" / "tests" / "exclusion-goldens.json"
)
HOLDOUT_PATH = ROOT / "ayurveda-data" / "tests" / "resolution-holdout.json"
FOODS_PATH = ROOT / "WiseEating" / "Legacy" / "foods.json"
SEED_PATH = ROOT / "WiseEating" / "ayurveda_seed.json.gz"
CONCEPT_ARTIFACT_PATH = ROOT / "WiseEating" / "food_concepts.json.gz"
KNOWLEDGE_BASE_PATH = (
    ROOT / "WiseEating" / "FoodSearch" / "SearchKnowledgeBase.swift"
)
RUNTIME_PATH = ROOT / "WiseEating" / "Ayurveda" / "FoodConcepts.swift"

DIRECTOR_HASHES = {
    ONTOLOGY_PATH: "2755da46ab2621d6ed4acb9204b4953d79eb03e8893f568c748e5abda9a48d24",
    EXCLUSION_PATH: "8ab92be44d987aab86e14d69c5933b0eed428efdb7fc31bd7f2a516401c2bf27",
    HOLDOUT_PATH: "557fe9cd78e751522310ec520c2a94a8b19366f12c8405814566d38a517a7a9d",
}

SPEC = importlib.util.spec_from_file_location("build_seed_fc1", BUILD_SEED_PATH)
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)


class FoodConceptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with gzip.open(SEED_PATH, "rt", encoding="utf-8") as source:
            cls.seed = json.load(source)
        foods = json.loads(FOODS_PATH.read_text(encoding="utf-8"))
        source_names = {food["id"]: food["name"] for food in foods}
        cls.ontology, cls.overrides = build_seed.load_food_concept_sources(
            ONTOLOGY_PATH,
            OVERRIDES_PATH,
        )
        cls.suffix_terms = build_seed.load_suffix_negation_terms(
            KNOWLEDGE_BASE_PATH
        )
        cls.artifact, cls.diagnostics = build_seed.build_food_concepts(
            cls.seed,
            source_names,
            cls.ontology,
            cls.overrides,
            cls.suffix_terms,
        )

    def test_director_artifacts_are_unchanged_and_complete(self):
        for path, expected in DIRECTOR_HASHES.items():
            with self.subTest(path=path.name):
                self.assertEqual(
                    hashlib.sha256(path.read_bytes()).hexdigest(),
                    expected,
                )
        self.assertEqual(len(self.ontology["concepts"]), 25)
        self.assertEqual(len(self.ontology["aliases"]), 75)

    def test_modifier_normalization_and_suffix_terms_are_reused(self):
        self.assertEqual(
            build_seed.modifier_normalized_tokens(
                "Food (NFS), fat-free/oil's & Spice"
            ),
            ("food", "fat", "free", "oil", "s", "and", "spice"),
        )
        self.assertEqual(self.suffix_terms, {"free", "zero", "less"})
        validator = (
            ROOT / "ayurveda-data" / "validate.py"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "d34_normalized_tokens = build_seed.modifier_normalized_tokens",
            validator,
        )

    def test_hierarchy_is_acyclic_and_transitively_rolled_up(self):
        concepts = {
            concept["id"]: concept for concept in self.ontology["concepts"]
        }
        ancestors = build_seed.food_concept_ancestors(concepts)
        self.assertIn("poultry", ancestors["chicken"])
        self.assertIn("meat", ancestors["chicken"])
        self.assertTrue(
            (
                self.diagnostics["membership"]["chicken"]
                - set(self.diagnostics["negativeVetoes"]["poultry"])
            ).issubset(
                self.diagnostics["membership"]["poultry"]
            )
        )
        self.assertTrue(
            (
                self.diagnostics["membership"]["poultry"]
                - set(self.diagnostics["negativeVetoes"]["meat"])
            ).issubset(
                self.diagnostics["membership"]["meat"]
            )
        )

        cyclic = {
            "a": {"parents": ["b"]},
            "b": {"parents": ["a"]},
        }
        with self.assertRaisesRegex(
            build_seed.BuildError,
            "hierarchy cycle",
        ):
            build_seed.food_concept_ancestors(cyclic)

    def test_negative_veto_token_boundaries_and_suffix_negation(self):
        names = self.diagnostics["catalogNames"]
        direct = self.diagnostics["directMembership"]

        def matching_ids(fragment):
            return {
                food_id
                for food_id, name in names.items()
                if fragment in name.lower()
            }

        self.assertTrue(matching_ids("milk, nfs") & direct["dairy"])
        self.assertFalse(matching_ids("eggplant, raw") & direct["egg"])
        self.assertFalse(matching_ids("coconut milk, raw") & direct["dairy"])
        self.assertFalse(matching_ids("buckwheat, raw") & direct["gluten"])
        self.assertFalse(matching_ids("hamburger") & direct["pork"])
        self.assertFalse(
            matching_ids("chicken, meatless")
            & self.diagnostics["membership"]["meat"]
        )
        self.assertFalse(
            matching_ids("coconut ladoo")
            & self.diagnostics["membership"]["tree_nuts"]
        )

        gluten_tokens = build_seed.modifier_normalized_tokens(
            "Bread, certified gluten-free"
        )
        matches = build_seed._longest_positive_matches(
            gluten_tokens,
            [("gluten", ("gluten",))],
            self.suffix_terms,
        )
        self.assertEqual(matches, [])

    def test_all_recipes_propagate_from_complete_non_nested_links(self):
        propagation = self.artifact["propagation"]
        self.assertEqual(propagation["ingredientLinks"], 10_571)
        self.assertEqual(propagation["recipeOwners"], 1_500)
        self.assertEqual(propagation["nestedRecipeLinks"], 0)
        self.assertEqual(propagation["depthUsed"], 1)
        self.assertEqual(propagation["depthCap"], 16)

        for recipe in self.seed["recipes"]:
            owner_id = recipe["foodId"]
            ingredient_ids = {
                ingredient["foodId"] for ingredient in recipe["ingredients"]
            }
            for concept_id, members in self.diagnostics["membership"].items():
                if ingredient_ids.intersection(members):
                    if owner_id in self.diagnostics["negativeVetoes"][concept_id]:
                        self.assertNotIn(
                            owner_id,
                            members,
                            (recipe["id"], concept_id, "negative veto"),
                        )
                    else:
                        self.assertIn(
                            owner_id,
                            members,
                            (recipe["id"], concept_id),
                        )

    def test_membership_is_sorted_bounded_and_deterministic(self):
        self.assertEqual(self.artifact["catalogCount"], 14_484)
        self.assertEqual(self.artifact["conceptCount"], 25)
        self.assertEqual(self.artifact["aliasCount"], 75)
        for concept, members in self.artifact["membership"].items():
            with self.subTest(concept=concept):
                self.assertEqual(members, sorted(set(members)))
                self.assertLessEqual(len(members) / 14_484, 0.40)

        rebuilt, _ = build_seed.build_food_concepts(
            self.seed,
            {
                food["id"]: food["name"]
                for food in json.loads(FOODS_PATH.read_text(encoding="utf-8"))
            },
            self.ontology,
            self.overrides,
            self.suffix_terms,
        )
        self.assertEqual(
            build_seed.encode_deterministic_gzip(self.artifact),
            build_seed.encode_deterministic_gzip(rebuilt),
        )

    def test_bundled_artifact_matches_the_current_build(self):
        with gzip.open(CONCEPT_ARTIFACT_PATH, "rt", encoding="utf-8") as source:
            bundled = json.load(source)
        self.assertEqual(bundled, self.artifact)

    def test_runtime_service_is_lazy_sendable_and_has_no_consumer(self):
        source = RUNTIME_PATH.read_text(encoding="utf-8")
        self.assertIn("public struct FoodConcepts: Sendable", source)
        self.assertIn("public func members(of concept: String) -> Set<Int32>", source)
        self.assertIn("public func concepts(for foodID: Int32) -> Set<String>", source)
        self.assertIn("public func canonical(alias: String) -> String?", source)
        self.assertIn("public struct Requirement: Codable, Hashable, Sendable", source)
        self.assertIn("public struct Restriction: Codable, Hashable, Sendable", source)

        consumers = []
        for path in (ROOT / "WiseEating").rglob("*.swift"):
            if path == RUNTIME_PATH:
                continue
            if "FoodConcepts.shared" in path.read_text(
                encoding="utf-8",
                errors="ignore",
            ):
                consumers.append(path)
        self.assertEqual(consumers, [])


if __name__ == "__main__":
    unittest.main()
