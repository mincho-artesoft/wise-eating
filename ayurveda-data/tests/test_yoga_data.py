import json
import sys
import unittest
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "ayurveda-data"
YOGA = DATA / "yoga"
sys.path.insert(0, str(DATA))

from stable_ids import yoga_asana_uuid, yoga_sequence_uuid


EXPECTED_FAMILIES = {
    "Backbend": 156,
    "Forward Bend": 119,
    "Hip Opener": 114,
    "Standing": 95,
    "Standing Balance": 72,
    "Inversion": 57,
    "Seated": 57,
    "Twist": 55,
    "Arm Balance": 43,
    "Core": 42,
    "Restorative": 36,
    "Pranayama": 14,
    "Meditation": 13,
    "Supine": 10,
    "Bandha & Mudra": 9,
    "Surya Namaskar": 9,
    "Kriya": 6,
    "Prone": 1,
}


class YogaDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.asanas = json.loads((YOGA / "asanas.json").read_text(encoding="utf-8"))
        cls.sequences = json.loads(
            (YOGA / "sequences.json").read_text(encoding="utf-8")
        )

    def test_asana_catalogue_gate(self):
        self.assertEqual(len(self.asanas), 908)
        self.assertEqual(Counter(row["family"] for row in self.asanas), EXPECTED_FAMILIES)
        self.assertEqual(Counter(row["level"] for row in self.asanas), {1: 370, 2: 259, 3: 279})

        for key in (
            "id",
            "catalogNumber",
            "title",
            "sanskrit",
            "slug",
            "assetImageName",
        ):
            values = [row[key] for row in self.asanas]
            self.assertEqual(len(values), len(set(values)), key)

        for row in self.asanas:
            self.assertNotIn("levelScale", row)
            self.assertEqual(row["doshaProvenance"], "modern-synthesis")
            self.assertTrue(row["desc"].strip())
            self.assertTrue(
                all(-2 <= value <= 2 for value in row["dosha"].values())
            )

        self.assertEqual(len({row["breath"] for row in self.asanas}), 41)
        self.assertEqual(len({row["drishti"] for row in self.asanas}), 24)

    def test_sequence_catalogue_gate(self):
        self.assertEqual(len(self.sequences), 4_419)
        asana_ids = {row["id"] for row in self.asanas}
        dangling = []
        for sequence in self.sequences:
            calculated = sum(
                pose["seconds"] * (2 if pose["side"] == "both" else 1)
                for pose in sequence["poses"]
            )
            self.assertEqual(calculated, sequence["estimatedSeconds"], sequence["id"])
            dangling.extend(
                pose["id"] for pose in sequence["poses"] if pose["id"] not in asana_ids
            )
        self.assertEqual(dangling, [])

        samples = {
            duration: next(
                row for row in self.sequences if row["durationMinutes"] == duration
            )
            for duration in (15, 90)
        }
        self.assertEqual(samples[15]["estimatedSeconds"], 986)
        self.assertEqual(samples[90]["estimatedSeconds"], 5_791)

    def test_runtime_json_uses_complete_canonical_uuids(self):
        asana_ids = {
            row["catalogNumber"]: row["id"] for row in self.asanas
        }
        self.assertEqual(set(asana_ids), set(range(800_000, 800_908)))
        for catalog_number, stable_id in asana_ids.items():
            self.assertEqual(stable_id, yoga_asana_uuid(catalog_number))

        sequence_catalog_numbers = set()
        for sequence in self.sequences:
            catalog_number = sequence["catalogNumber"]
            self.assertNotIn(catalog_number, sequence_catalog_numbers)
            sequence_catalog_numbers.add(catalog_number)
            self.assertEqual(sequence["id"], yoga_sequence_uuid(catalog_number))
            for pose in sequence["poses"]:
                self.assertEqual(
                    pose["id"],
                    asana_ids[pose["catalogNumber"]],
                )

    def test_only_yoga_runtime_data_is_present(self):
        self.assertTrue(all("sports" not in row for row in self.asanas))
        self.assertFalse((ROOT / "Ayura" / "Legacy" / "sports.json").exists())
        self.assertFalse((ROOT / "Ayura" / "Legacy" / "workouts.json").exists())
        self.assertFalse((ROOT / "Ayura" / "AyuraTemplates.store").exists())
        self.assertLess((YOGA / "asanas.json").stat().st_size, 90_000_000)
        self.assertLess((YOGA / "sequences.json").stat().st_size, 90_000_000)

    def test_search_terms_have_results(self):
        for query in ("adho mukha", "backbend", "pranayama", "warrior"):
            matches = [
                row
                for row in self.asanas
                if query.casefold()
                in " ".join((row["title"], row["sanskrit"], row["family"])).casefold()
            ]
            self.assertGreaterEqual(len(matches), 1, query)


if __name__ == "__main__":
    unittest.main()
