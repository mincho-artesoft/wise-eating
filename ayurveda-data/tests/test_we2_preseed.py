import gzip
import importlib.util
import json
import sqlite3
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PRESEED_SCRIPT = REPO_ROOT / "ayurveda-data" / "build_preseeded_store.py"
sys.path.insert(0, str(PRESEED_SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("build_preseeded_store", PRESEED_SCRIPT)
assert SPEC and SPEC.loader
build_preseeded_store = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_preseeded_store)
from stable_ids import yoga_asana_uuid, yoga_sequence_uuid

TARGET = build_preseeded_store.TARGET_EXPECTED


class PreseedArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parts = sorted(
            (REPO_ROOT / "Ayura").glob("preseeded_db.store.gz.part-*")
        )
        cls.temporary = tempfile.TemporaryDirectory(prefix="we2-preseed-test-")
        cls.store = Path(cls.temporary.name) / "default.store"
        compressed = b"".join(part.read_bytes() for part in parts)
        cls.store.write_bytes(gzip.decompress(compressed))
        cls.audit = build_preseeded_store.audit_store(cls.store, TARGET)
        cls.connection = sqlite3.connect(cls.store)
        with gzip.open(
            REPO_ROOT / "Ayura" / "ayurveda_seed.json.gz",
            "rt",
            encoding="utf-8",
        ) as source:
            cls.seed = json.load(source)
        cls.yoga_asanas = json.loads(
            (REPO_ROOT / "ayurveda-data" / "yoga" / "asanas.json").read_text(
                encoding="utf-8"
            )
        )
        cls.yoga_sequences = json.loads(
            (REPO_ROOT / "ayurveda-data" / "yoga" / "sequences.json").read_text(
                encoding="utf-8"
            )
        )

    @classmethod
    def tearDownClass(cls):
        cls.connection.close()
        cls.temporary.cleanup()

    def test_artifact_has_final_canonical_counts_without_duplicates(self):
        self.assertEqual(
            self.audit,
            {
                "foods": TARGET["foods"],
                "profiles": TARGET["profiles"],
                "links": TARGET["links"],
                "ingredientLinks": TARGET["ingredientLinks"],
                "ingredientOwners": TARGET["ingredientOwners"],
                "nutritionFull": TARGET["nutritionFull"],
                "nutritionEstimated": TARGET["nutritionEstimated"],
                "cacheFoods": TARGET["cacheFoods"],
                "cacheVersion": 13,
                "facetFoods": TARGET["foods"],
                "metadataFoods": TARGET["foods"],
                "linkedFacetFoods": 2_007,
                "facetKeys": 45,
                "facetAssignments": 99_439,
                "allergenTaggedDravyas": 155,
                "allergenTaggedRecipes": 1_190,
                "positiveEnforcedAgeDravyas": 389,
                "positiveEnforcedAgeRecipes": 5,
                "yogaAsanas": 908,
                "yogaSequences": 4_419,
                "payloadBytes": self.audit["payloadBytes"],
            },
        )
        self.assertGreater(self.audit["payloadBytes"], 0)
        self.assertGreater(self.audit["facetKeys"], 0)
        self.assertGreater(self.audit["facetAssignments"], TARGET["foods"])

    def test_store_has_no_category_columns(self):
        category_columns = [
            (table_name, column[1])
            for (table_name,) in self.connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            for column in self.connection.execute(f'PRAGMA table_info("{table_name}")')
            if "CATEGORY" in column[1].upper()
        ]
        self.assertEqual(category_columns, [])

    def test_store_has_no_head_circumference_columns(self):
        head_circumference_columns = [
            (table_name, column[1])
            for (table_name,) in self.connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            for column in self.connection.execute(f'PRAGMA table_info("{table_name}")')
            if "HEADCIRCUMFERENCE" in column[1].upper()
        ]
        self.assertEqual(head_circumference_columns, [])

    def test_store_has_no_badge_columns(self):
        badge_columns = [
            (table_name, column[1])
            for (table_name,) in self.connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            for column in self.connection.execute(f'PRAGMA table_info("{table_name}")')
            if "BADGE" in column[1].upper()
        ]
        self.assertEqual(badge_columns, [])

    def test_store_has_no_diet_schema(self):
        schema_objects = self.connection.execute(
            "SELECT name FROM sqlite_master WHERE UPPER(name) LIKE '%DIET%'"
        ).fetchall()
        self.assertEqual(schema_objects, [])

    def test_training_plan_template_artifacts_are_removed(self):
        template_schema_objects = self.connection.execute(
            "SELECT name FROM sqlite_master WHERE UPPER(name) LIKE '%TEMPLATE%'"
        ).fetchall()
        self.assertEqual(template_schema_objects, [])
        self.assertFalse((REPO_ROOT / "Ayura" / "AyuraTemplates.store").exists())
        self.assertFalse((REPO_ROOT / "Ayura" / "Legacy" / "workouts.json").exists())

    def test_bundled_exercise_catalog_is_replaced_by_yoga(self):
        self.assertEqual(
            self.connection.execute("SELECT COUNT(*) FROM ZEXERCISEITEM").fetchone()[0],
            908,
        )
        self.assertFalse((REPO_ROOT / "Ayura" / "Legacy" / "exercises.json").exists())
        self.assertFalse((REPO_ROOT / "Ayura" / "Legacy" / "sports.json").exists())

        asanas = self.connection.execute(
            """
            SELECT ZCATALOGNUMBER, ZID, ZNAME, ZSANSKRIT, ZFAMILY,
                   ZDURATIONSECONDS, ZNAMENORMALIZED, ZSEARCHTOKENS, ZSEARCHTOKENS2
            FROM ZEXERCISEITEM ORDER BY ZCATALOGNUMBER
            """
        ).fetchall()
        self.assertEqual(
            [row[0] for row in asanas],
            list(range(800_000, 800_908)),
        )
        expected_durations = {
            800_000 + index: item["durationSeconds"]
            for index, item in enumerate(self.yoga_asanas)
        }
        for (
            catalog_number,
            stable_id,
            name,
            sanskrit,
            family,
            duration_seconds,
            normalized,
            tokens,
            tokens2,
        ) in asanas:
            self.assertEqual(str(uuid.UUID(bytes=stable_id)), yoga_asana_uuid(catalog_number))
            expected_suffix = f" ({sanskrit})"
            self.assertTrue(name == sanskrit or name.endswith(expected_suffix))
            self.assertTrue(family)
            self.assertEqual(duration_seconds, expected_durations[catalog_number])
            self.assertTrue(normalized)
            self.assertTrue(tokens)
            self.assertTrue(tokens2)

    def test_yoga_sequences_are_preseeded_with_canonical_uuids(self):
        sequences = self.connection.execute(
            """
            SELECT ZCATALOGNUMBER, ZID, ZPOSESDATA, ZDURATIONSECONDS
            FROM ZYOGASEQUENCE ORDER BY ZCATALOGNUMBER
            """
        ).fetchall()
        self.assertEqual(len(sequences), 4_419)
        self.assertEqual(sequences[0][0], 700_001)
        self.assertEqual(sequences[-1][0], 704_419)
        expected_durations = {
            700_001 + index: item["durationMinutes"] * 60
            for index, item in enumerate(self.yoga_sequences)
        }
        for catalog_number, stable_id, poses_data, duration_seconds in sequences:
            self.assertEqual(
                str(uuid.UUID(bytes=stable_id)),
                yoga_sequence_uuid(catalog_number),
            )
            self.assertTrue(poses_data)
            self.assertEqual(duration_seconds, expected_durations[catalog_number])

    def test_removed_profile_and_exercise_fields_are_absent(self):
        profile_columns = {
            row[1]
            for row in self.connection.execute("PRAGMA table_info(ZPROFILE)")
        }
        exercise_columns = {
            row[1]
            for row in self.connection.execute("PRAGMA table_info(ZEXERCISEITEM)")
        }
        self.assertTrue(
            profile_columns.isdisjoint(
                {"ZGOAL", "ZACTIVITYLEVEL", "ZSPORT", "ZSPORTS", "ZDIET", "ZDIETS"}
            )
        )
        self.assertTrue(
            exercise_columns.isdisjoint(
                {"ZSPORT", "ZSPORTS", "ZDURATIONMINUTES"}
            )
        )
        sequence_columns = {
            row[1]
            for row in self.connection.execute("PRAGMA table_info(ZYOGASEQUENCE)")
        }
        self.assertNotIn("ZDURATIONMINUTES", sequence_columns)

    def test_fresh_store_seed_run_has_zero_inserts(self):
        profile_rows = self.connection.execute(
            "SELECT ZID, ZSEEDVERSION FROM ZAYURVEDAPROFILE"
        ).fetchall()
        existing_profiles = {
            str(uuid.UUID(bytes=profile_id)): version
            for profile_id, version in profile_rows
        }
        existing_food_ids = {
            str(uuid.UUID(bytes=row[0]))
            for row in self.connection.execute("SELECT ZID FROM ZFOODITEM")
        }
        existing_links = {
            str(uuid.UUID(bytes=food_id)): (
                str(uuid.UUID(bytes=profile_id)),
                tier,
            )
            for food_id, profile_id, tier in self.connection.execute(
                "SELECT ZFOODID, ZDRAVYAPROFILEID, ZTIER FROM ZAYURVEDALINK"
            )
        }

        canonical_profiles = self.seed["dravyas"] + self.seed["recipes"]
        missing_profiles = [
            item["id"] for item in canonical_profiles if item["id"] not in existing_profiles
        ]
        stale_profiles = [
            item["id"]
            for item in canonical_profiles
            if existing_profiles.get(item["id"], 0) < self.seed["seedVersion"]
        ]
        canonical_food_ids = {
            item["foodId"]
            for item in self.seed["dravyas"]
            if item["foodIsPlaceholder"]
        } | {item["foodId"] for item in self.seed["recipes"]}
        missing_foods = canonical_food_ids - existing_food_ids
        missing_or_stale_links = [
            link["foodId"]
            for link in self.seed["links"]
            if existing_links.get(link["foodId"])
            != (link["dravyaProfileId"], link["tier"])
        ]

        self.assertEqual(missing_profiles, [])
        self.assertEqual(stale_profiles, [])
        self.assertEqual(missing_foods, set())
        self.assertEqual(missing_or_stale_links, [])

    def test_second_seed_run_is_idempotent(self):
        before = {
            "foods": self.connection.execute(
                "SELECT COUNT(*) FROM ZFOODITEM"
            ).fetchone()[0],
            "profiles": self.connection.execute(
                "SELECT COUNT(*) FROM ZAYURVEDAPROFILE"
            ).fetchone()[0],
            "links": self.connection.execute(
                "SELECT COUNT(*) FROM ZAYURVEDALINK"
            ).fetchone()[0],
        }
        self.assertEqual(
            before,
            {
                "foods": TARGET["foods"],
                "profiles": TARGET["profiles"],
                "links": TARGET["links"],
            },
        )
        self.assertEqual(
            self.connection.execute(
                """
                SELECT COUNT(*) FROM (
                  SELECT ZID FROM ZFOODITEM GROUP BY ZID HAVING COUNT(*) > 1
                )
                """
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            self.connection.execute(
                """
                SELECT COUNT(*) FROM (
                  SELECT ZID FROM ZAYURVEDAPROFILE
                  GROUP BY ZID HAVING COUNT(*) > 1
                )
                """
            ).fetchone()[0],
            0,
        )

    def test_fresh_store_search_cache_requires_no_rebuild(self):
        food_count = self.connection.execute(
            "SELECT COUNT(*) FROM ZFOODITEM"
        ).fetchone()[0]
        cache_count, version, payload = self.connection.execute(
            """
            SELECT ZFOODSCOUNT, ZVERSION, ZPAYLOADDATA
            FROM ZSEARCHINDEXCACHE WHERE ZKEY = 'main'
            """
        ).fetchone()
        self.assertEqual(cache_count, food_count)
        self.assertEqual(version, 13)
        decoded = json.loads(payload)
        self.assertEqual(len(decoded["compactFoods"]), food_count)
        self.assertTrue(
            all("diets" not in food for food in decoded["compactFoods"])
        )
        self.assertTrue(
            all(
                "category" not in food.get("ayurvedaMetadata", {})
                for food in decoded["compactFoods"]
            )
        )
        self.assertTrue(
            all(
                not key.startswith("category:")
                for key in decoded["ayurvedaFacetIndex"]
            )
        )
        self.assertEqual(
            sum(bool(food["ayurvedaFacets"]) for food in decoded["compactFoods"]),
            food_count,
        )
        self.assertEqual(
            sum(food.get("ayurvedaMetadata") is not None for food in decoded["compactFoods"]),
            food_count,
        )
        self.assertIn("virya:cooling", decoded["ayurvedaFacetIndex"])


if __name__ == "__main__":
    unittest.main()
