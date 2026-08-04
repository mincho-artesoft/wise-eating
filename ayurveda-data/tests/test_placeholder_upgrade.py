import gzip
import hashlib
import importlib.util
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "ayurveda-data"
FIXTURES = DATA / "tests" / "fixtures" / "placeholder_upgrade_fixtures.json"
SEEDER = ROOT / "Ayura" / "Main" / "DBSeed" / "AyurvedaSeeder.swift"

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
        dravyas, {food["catalogNumber"] for food in foods}
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

    def test_uuid_seed_supersedes_numeric_placeholder_moves(self):
        self.assertEqual(self.seed["identitySchema"], "stable-uuid-v1")
        placeholders = [
            item for item in self.seed["dravyas"]
            if item["foodIsPlaceholder"]
        ]
        self.assertEqual(len(placeholders), self.seed["counts"]["placeholders"])
        self.assertEqual(len(self.incoming), len(placeholders))
        for profile_id, food_id in self.incoming.items():
            self.assertEqual(str(uuid.UUID(profile_id)), profile_id)
            self.assertEqual(str(uuid.UUID(food_id)), food_id)

    def test_numeric_placeholder_migrations_are_fully_removed(self):
        seeder = SEEDER.read_text(encoding="utf-8")
        self.assertNotIn("migratePlaceholderIdsIfNeeded", seeder)
        self.assertNotIn("migrateV5CanonicalDataIfNeeded", seeder)


if __name__ == "__main__":
    unittest.main()
