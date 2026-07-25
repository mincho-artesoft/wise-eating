import gzip
import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PRESEED_SCRIPT = REPO_ROOT / "ayurveda-data" / "build_preseeded_store.py"
SPEC = importlib.util.spec_from_file_location("build_preseeded_store", PRESEED_SCRIPT)
assert SPEC and SPEC.loader
build_preseeded_store = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_preseeded_store)


class PreseedArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parts = [
            REPO_ROOT / "WiseEating" / "preseeded_db.store.gz.part-aa",
            REPO_ROOT / "WiseEating" / "preseeded_db.store.gz.part-ab",
        ]
        cls.temporary = tempfile.TemporaryDirectory(prefix="we2-preseed-test-")
        cls.store = Path(cls.temporary.name) / "default.store"
        compressed = b"".join(part.read_bytes() for part in parts)
        cls.store.write_bytes(gzip.decompress(compressed))
        cls.audit = build_preseeded_store.audit_store(cls.store)
        cls.connection = sqlite3.connect(cls.store)
        with gzip.open(
            REPO_ROOT / "WiseEating" / "ayurveda_seed.json.gz",
            "rt",
            encoding="utf-8",
        ) as source:
            cls.seed = json.load(source)

    @classmethod
    def tearDownClass(cls):
        cls.connection.close()
        cls.temporary.cleanup()

    def test_artifact_has_final_canonical_counts_without_duplicates(self):
        self.assertEqual(
            self.audit,
            {
                "foods": 14_484,
                "profiles": 2_214,
                "links": 2_305,
                "ingredientLinks": 10_571,
                "ingredientOwners": 1_500,
                "cacheFoods": 14_484,
                "cacheVersion": 4,
                "facetFoods": 2_214,
                "facetKeys": self.audit["facetKeys"],
                "facetAssignments": self.audit["facetAssignments"],
                "allergenTaggedDravyas": 156,
                "allergenTaggedRecipes": 1_182,
                "payloadBytes": self.audit["payloadBytes"],
            },
        )
        self.assertGreater(self.audit["payloadBytes"], 0)
        self.assertGreater(self.audit["facetKeys"], 0)
        self.assertGreater(self.audit["facetAssignments"], 2_214)

    def test_fresh_store_seed_run_has_zero_inserts(self):
        profile_rows = self.connection.execute(
            "SELECT ZID, ZSEEDVERSION FROM ZAYURVEDAPROFILE"
        ).fetchall()
        existing_profiles = {profile_id: version for profile_id, version in profile_rows}
        existing_food_ids = {
            row[0] for row in self.connection.execute("SELECT ZID FROM ZFOODITEM")
        }
        existing_links = {
            fdc_id: (profile_id, tier)
            for fdc_id, profile_id, tier in self.connection.execute(
                "SELECT ZFDCID, ZDRAVYAPROFILEID, ZTIER FROM ZAYURVEDALINK"
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
            link["fdcId"]
            for link in self.seed["links"]
            if existing_links.get(link["fdcId"])
            != (link["dravyaId"], link["tier"])
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
            {"foods": 14_484, "profiles": 2_214, "links": 2_305},
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
        self.assertEqual(version, 4)
        decoded = json.loads(payload)
        self.assertEqual(len(decoded["compactFoods"]), food_count)
        self.assertEqual(
            sum(bool(food["ayurvedaFacets"]) for food in decoded["compactFoods"]),
            2_214,
        )
        self.assertIn("virya:cooling", decoded["ayurvedaFacetIndex"])


if __name__ == "__main__":
    unittest.main()
