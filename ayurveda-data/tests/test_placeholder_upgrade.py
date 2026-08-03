import gzip
import hashlib
import importlib.util
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "ayurveda-data"
FIXTURES = DATA / "tests" / "fixtures" / "placeholder_upgrade_fixtures.json"
SEEDER = ROOT / "Ayura" / "Main" / "DBSeed" / "AyurvedaSeeder.swift"
SEED_MANAGER = ROOT / "Ayura" / "Main" / "DBSeed" / "SeedManager.swift"
SEARCH_INDEX = ROOT / "Ayura" / "FoodSearch" / "SearchIndexStore.swift"

sys.path.insert(0, str(DATA))
SPEC = importlib.util.spec_from_file_location("build_seed_upgrade", DATA / "build_seed.py")
assert SPEC and SPEC.loader
build_seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_seed)


def git_blob(commit: str, path: str) -> bytes:
    return subprocess.run(
        ["git", "show", f"{commit}:{path}"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout


def scalar(connection: sqlite3.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    return row[0] if row else None


def placeholder_mapping():
    dravyas = build_seed.load_batches(DATA / "dravyas", "batch-*.json", "items")
    foods = json.loads((ROOT / "Ayura" / "Legacy" / "foods.json").read_text())
    assignments, _links, _contested, placeholder_ids = build_seed.resolve_primary_foods(
        dravyas, {food["id"] for food in foods}
    )
    return [(dravya_id, assignments[dravya_id][0]) for dravya_id in placeholder_ids]


class PlaceholderUpgradeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = json.loads(FIXTURES.read_text(encoding="utf-8"))
        cls.temporary = tempfile.TemporaryDirectory(prefix="placeholder-upgrade-")
        cls.temp_path = Path(cls.temporary.name)
        with gzip.open(ROOT / "Ayura" / "ayurveda_seed.json.gz", "rt") as handle:
            cls.seed = json.load(handle)
        cls.incoming = {
            item["id"]: item["foodId"]
            for item in cls.seed["dravyas"]
            if item["foodIsPlaceholder"]
        }

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def baseline_store(self, fixture):
        commit = fixture["baselineCommit"]
        compressed = b"".join(
            git_blob(commit, f"Ayura/preseeded_db.store.gz.part-{suffix}")
            for suffix in ("aa", "ab")
        )
        path = self.temp_path / f"{fixture['name']}.store"
        path.write_bytes(gzip.decompress(compressed))
        return path

    def test_upgrade_fixtures_detect_and_model_placeholder_moves(self):
        current_mapping = placeholder_mapping()
        current_sha = hashlib.sha256(
            json.dumps(current_mapping, separators=(",", ":")).encode()
        ).hexdigest()

        for fixture in self.fixtures:
            with self.subTest(fixture=fixture["name"]):
                path = self.baseline_store(fixture)
                connection = sqlite3.connect(path)
                try:
                    before = fixture["before"]
                    after = fixture["after"]
                    self.assertEqual(scalar(connection, "SELECT COUNT(*) FROM ZFOODITEM"), before["foods"])
                    self.assertEqual(scalar(connection, "SELECT COUNT(*) FROM ZAYURVEDAPROFILE"), before["profiles"])
                    self.assertEqual(
                        scalar(connection, "SELECT COUNT(*) FROM ZAYURVEDAPROFILE WHERE ZFOODISPLACEHOLDER = 1"),
                        before["placeholders"],
                    )
                    self.assertEqual(
                        scalar(connection, "SELECT COUNT(DISTINCT ZSEEDVERSION) FROM ZAYURVEDAPROFILE"), 1
                    )
                    self.assertEqual(scalar(connection, "SELECT MAX(ZSEEDVERSION) FROM ZAYURVEDAPROFILE"), before["seedVersion"])
                    self.assertEqual(
                        scalar(connection, "SELECT ZFOODSCOUNT FROM ZSEARCHINDEXCACHE WHERE ZKEY = 'main'"),
                        before["cacheFoods"],
                    )

                    old_profiles = dict(
                        connection.execute(
                            "SELECT ZID, ZFOODID FROM ZAYURVEDAPROFILE WHERE ZFOODISPLACEHOLDER = 1"
                        )
                    )
                    moves = {
                        profile_id: (old_profiles[profile_id], new_food_id)
                        for profile_id, new_food_id in self.incoming.items()
                        if profile_id in old_profiles and old_profiles[profile_id] != new_food_id
                    }
                    deleted = {
                        profile_id: old_food_id
                        for profile_id, old_food_id in old_profiles.items()
                        if profile_id not in self.incoming
                    }
                    self.assertEqual(len(moves), after["remappedFoodIDs"])
                    self.assertEqual(deleted, fixture["deletedProfiles"])
                    self.assertEqual(len(deleted), after["deletedFoods"])

                    identity_before = {
                        profile_id: connection.execute(
                            """
                            SELECT f.Z_PK, f.ZID
                            FROM ZAYURVEDAPROFILE p
                            JOIN ZFOODITEM f ON f.ZID = p.ZFOODID
                            WHERE p.ZID = ?
                            """,
                            (profile_id,),
                        ).fetchone()
                        for profile_id in fixture["identitySamples"]
                    }
                    self.assertTrue(all(identity_before.values()))

                    # Model the migration's collision-safe two-pass ID update.
                    for profile_id, food_id in deleted.items():
                        connection.execute("DELETE FROM ZAYURVEDAPROFILE WHERE ZID = ?", (profile_id,))
                        connection.execute("DELETE FROM ZFOODITEM WHERE ZID = ?", (food_id,))
                    for index, (profile_id, (old_id, _new_id)) in enumerate(sorted(moves.items())):
                        temporary_id = -4_000_000 - index
                        connection.execute("UPDATE ZFOODITEM SET ZID = ? WHERE ZID = ?", (temporary_id, old_id))
                        connection.execute("UPDATE ZAYURVEDAPROFILE SET ZFOODID = ? WHERE ZID = ?", (temporary_id, profile_id))
                    for index, (profile_id, (_old_id, new_id)) in enumerate(sorted(moves.items())):
                        temporary_id = -4_000_000 - index
                        connection.execute("UPDATE ZFOODITEM SET ZID = ? WHERE ZID = ?", (new_id, temporary_id))
                        connection.execute("UPDATE ZAYURVEDAPROFILE SET ZFOODID = ?, ZSEEDVERSION = ? WHERE ZID = ?", (new_id, after["seedVersion"], profile_id))
                    connection.execute("UPDATE ZAYURVEDAPROFILE SET ZSEEDVERSION = ?", (after["seedVersion"],))
                    connection.commit()

                    self.assertEqual(scalar(connection, "SELECT COUNT(*) FROM ZFOODITEM"), after["foods"])
                    self.assertEqual(scalar(connection, "SELECT COUNT(*) FROM ZAYURVEDAPROFILE"), after["profiles"])
                    self.assertEqual(
                        scalar(connection, "SELECT COUNT(*) FROM ZAYURVEDAPROFILE WHERE ZFOODISPLACEHOLDER = 1"),
                        after["placeholders"],
                    )
                    for profile_id, (persistent_id, _old_id) in identity_before.items():
                        identity_after = connection.execute(
                            """
                            SELECT f.Z_PK, f.ZID
                            FROM ZAYURVEDAPROFILE p
                            JOIN ZFOODITEM f ON f.ZID = p.ZFOODID
                            WHERE p.ZID = ?
                            """,
                            (profile_id,),
                        ).fetchone()
                        self.assertEqual(identity_after[0], persistent_id, profile_id)
                        self.assertEqual(identity_after[1], self.incoming[profile_id], profile_id)

                    self.assertEqual(self.seed["seedVersion"], after["seedVersion"])
                    self.assertEqual(self.seed["counts"]["placeholders"], after["placeholders"])
                    self.assertEqual(current_sha, after["mappingSHA256"])
                finally:
                    connection.close()

    def test_migration_is_data_gated_pre_ownership_and_rebuilds_cache(self):
        seeder = SEEDER.read_text(encoding="utf-8")
        manager = SEED_MANAGER.read_text(encoding="utf-8")
        search = SEARCH_INDEX.read_text(encoding="utf-8")

        call = seeder.index("try migratePlaceholderIdsIfNeeded(")
        ownership = seeder.index("try validateCanonicalOwnership(")
        self.assertLess(call, ownership)

        function = seeder[seeder.index("private static func migratePlaceholderIdsIfNeeded"):]
        function = function[:function.index("private static func transferFoodReferences")]
        self.assertIn("profile.foodId != incoming.foodId", function)
        self.assertNotIn("seedVersion <", function)
        self.assertIn("move.food.persistentModelID == move.persistentID", function)
        self.assertIn("rebuildForCatalogueMigration", function)
        self.assertIn("result.rebuiltSearchIndex = true", function)
        self.assertIn("result.requiresSearchIndexRebuild", manager)
        self.assertIn("func rebuildForCatalogueMigration", search)

        v5_start = seeder.index("private static func migrateV5CanonicalDataIfNeeded")
        v5_end = seeder.index("private static func migratePlaceholderIdsIfNeeded")
        v5 = seeder[v5_start:v5_end]
        self.assertIn("$0.seedVersion < 6", v5)


if __name__ == "__main__":
    unittest.main()
