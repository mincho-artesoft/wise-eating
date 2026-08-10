import json
import sys
import unittest
import uuid
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "ayurveda-data"
YOGA = DATA / "yoga"
SHIPPED_YOGA = ROOT / "Ayura" / "Yoga"
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

    def test_yoga_frame_index_matches_the_ids_materialized_by_the_seeder(self):
        """The shipped archive and YogaSeeder input are one UUID-keyed set.

        A mismatch here does not crash the app; it silently blanks every yoga
        image.  Keep the derivation, materialized JSON ids, frame index and
        runtime lookup in one cross-layer gate.
        """
        frame_index = json.loads(
            (SHIPPED_YOGA / "frame_index.json").read_text(encoding="utf-8")
        )
        seed_ids = {row["id"] for row in self.asanas}

        self.assertEqual(len(frame_index), 908)
        self.assertEqual(len(seed_ids), 908)
        self.assertEqual(set(frame_index), seed_ids)
        self.assertEqual(set(frame_index.values()), set(range(908)))
        self.assertEqual(len(set(frame_index.values())), 908)
        for row in self.asanas:
            self.assertEqual(str(uuid.UUID(row["id"])), row["id"])
            self.assertEqual(row["id"], yoga_asana_uuid(row["catalogNumber"]))

        seeder = (ROOT / "Ayura/Yoga/DBSeed/YogaSeeder.swift").read_text()
        video_source = (SHIPPED_YOGA / "YogaVideoSource.swift").read_text()
        exercise_item = (
            ROOT / "Ayura/Exercise/Models/ExerciseItem.swift"
        ).read_text()
        image_path = exercise_item.split("func exerciseImage", 1)[1].split(
            "// Hashable", 1
        )[0]
        self.assertIn("id: dto.id", seeder)
        self.assertIn("private var frameIndex: [UUID: Int]", video_source)
        self.assertIn("func getFrame(id asanaID: UUID", video_source)
        self.assertNotIn("catalogNumber", video_source)
        self.assertIn("getFrame(id: self.id, variant: variant)", image_path)
        self.assertNotIn("catalogNumber", image_path)

    def test_only_yoga_runtime_data_is_present(self):
        self.assertTrue(all("sports" not in row for row in self.asanas))
        self.assertFalse((ROOT / "Ayura" / "Legacy" / "sports.json").exists())
        self.assertFalse((ROOT / "Ayura" / "Legacy" / "workouts.json").exists())
        self.assertFalse((ROOT / "Ayura" / "AyuraTemplates.store").exists())
        self.assertLess((YOGA / "asanas.json").stat().st_size, 90_000_000)
        self.assertLess((YOGA / "sequences.json").stat().st_size, 90_000_000)

    def test_yoga_image_variants_match_food_detail_behavior(self):
        detail = (
            ROOT / "Ayura/Exercise/Views/ExerciseItemDetailView.swift"
        ).read_text()
        rows = (ROOT / "Ayura/Exercise/Views/ExerciseRowView.swift").read_text()
        video_source = (SHIPPED_YOGA / "YogaVideoSource.swift").read_text()

        self.assertIn('preferredVariants: ["1024", "480"]', detail)
        self.assertIn('exerciseImage(variant: "144")', rows)
        self.assertIn('"1024": 47_000_394', video_source)

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
