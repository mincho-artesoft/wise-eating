import base64
import csv
import gzip
import json
import random
import re
import sqlite3
import subprocess
import tempfile
import unittest
import unicodedata
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FOOD = ROOT / "Ayura/Food"
ORPHANS = {
    "Black mustard seed",
    "Curry leaf powder",
    "Dosa",
    "Grapes",
    "Lamb",
    "Lotus seeds (makhana)",
    "Rice kheer",
    "Rice, brown",
    "Sardine",
    "Spiced buttermilk (takra)",
    "Sweet potato",
    "Wheat, whole grain",
}
SANITIZE = re.compile(r'[/\\:*?"<>|]')


def nfc(value):
    return unicodedata.normalize("NFC", value)


def frame_key(value):
    return SANITIZE.sub("_", nfc(value))


class IDKeyVideoLookupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="idkey-video-")
        root = Path(cls.temporary.name)
        cls.store = root / "default.store"
        with cls.store.open("wb") as output:
            with gzip.GzipFile(
                fileobj=_PartReader(sorted(ROOT.glob("Ayura/preseeded_db.store.gz.part-*")))
            ) as source:
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)
        cls.large_video = root / "food_archive_1024.mp4"
        with cls.large_video.open("wb") as output:
            with gzip.GzipFile(
                fileobj=_PartReader(sorted(FOOD.glob("food_archive_1024.mp4.gz.part-*")))
            ) as source:
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_every_db_food_id_matches_the_previous_name_resolution(self):
        frame_map = json.loads((FOOD / "frame_map.json").read_text())
        reuse = json.loads(
            (ROOT / "ayurveda-data/imagery/reuse-map.json").read_text()
        )
        id_map = {int(key): value for key, value in json.loads(
            (FOOD / "frame_index.json").read_text()
        ).items()}
        with sqlite3.connect(self.store) as connection:
            foods = connection.execute(
                "SELECT ZID, ZNAME FROM ZFOODITEM ORDER BY ZID"
            ).fetchall()

        def old_resolution(name):
            for candidate in (nfc(name), frame_key(name)):
                if candidate in frame_map:
                    return frame_map[candidate]
            reference = None
            for candidate in (nfc(name), frame_key(name)):
                if candidate in reuse:
                    reference = reuse[candidate]["frameKey"]
                    break
            if reference is not None:
                return frame_map.get(reference, frame_map.get(frame_key(reference)))
            return None

        self.assertEqual(len(foods), 14_489)
        self.assertEqual(set(id_map), {food_id for food_id, _ in foods})
        previous = {food_id: old_resolution(name) for food_id, name in foods}
        self.assertNotIn(None, previous.values())
        self.assertEqual(id_map, previous)

        # The packet calls for 200 random round trips. The exhaustive equality
        # above is stronger; keep the deterministic sample explicit as a
        # readable regression set as well.
        sample = random.Random(20260803).sample([row[0] for row in foods], 200)
        self.assertTrue(all(id_map[food_id] == previous[food_id] for food_id in sample))

        addressed = set(id_map.values())
        inverse = {index: key for key, index in frame_map.items()}
        self.assertEqual(len(addressed), 14_466)
        self.assertEqual(
            {inverse[index] for index in set(inverse) - addressed},
            ORPHANS,
        )

    def test_food_index_and_shipped_id_map_are_a_matched_pair(self):
        with (ROOT / "ayurveda-data/archive/foods_index.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        id_map = json.loads((FOOD / "frame_index.json").read_text())
        self.assertEqual(len(rows), 14_489)
        self.assertEqual(len(id_map), 14_489)
        self.assertEqual(
            {row["db_id"]: int(row["frame_index"]) for row in rows},
            id_map,
        )

    def test_all_variants_embed_the_exact_id_map_and_keep_seek_invariants(self):
        payload = (FOOD / "frame_index.json").read_bytes()
        variants = {
            "144": FOOD / "food_archive_144.mp4",
            "480": FOOD / "food_archive_480.mp4",
            "1024": self.large_video,
        }
        for variant, video in variants.items():
            probe = json.loads(subprocess.check_output(
                [
                    "ffprobe", "-v", "error", "-count_packets",
                    "-select_streams", "v:0", "-show_entries",
                    "stream=nb_read_packets,has_b_frames,time_base,codec_tag_string:format_tags=frame_index_b64",
                    "-of", "json", str(video),
                ]
            ))
            stream = probe["streams"][0]
            self.assertEqual(stream["nb_read_packets"], "14478", variant)
            self.assertEqual(stream["has_b_frames"], 0, variant)
            self.assertEqual(stream["time_base"], "1/600", variant)
            self.assertEqual(stream["codec_tag_string"], "hvc1", variant)
            embedded = base64.b64decode(
                probe["format"]["tags"]["frame_index_b64"]
            )
            self.assertEqual(embedded, payload, variant)

    def test_swift_runtime_has_no_name_or_secondary_lookup_path(self):
        source = (FOOD / "FoodVideoSource.swift").read_text()
        food_item = (ROOT / "Ayura/Food/Models/FoodItem.swift").read_text()
        self.assertIn("func getFrame(id foodID: Int, variant: String)", source)
        self.assertIn("func hasVideo(for foodID: Int)", source)
        self.assertIn('forResource: "frame_index"', source)
        self.assertNotIn("getFrame(named", source)
        self.assertNotIn("frameMap2", source)
        self.assertNotIn("secondaryGenerators", source)
        self.assertNotIn("reuseMap", source)
        self.assertIn("getFrame(id: self.id, variant: variant)", food_item)
        self.assertNotIn("sanitizedName", food_item)


class _PartReader:
    """Minimal readable stream joining split gzip parts without copying them."""

    def __init__(self, paths):
        self.paths = iter(paths)
        self.current = None

    def read(self, size=-1):
        if size < 0:
            chunks = []
            while chunk := self.read(1024 * 1024):
                chunks.append(chunk)
            return b"".join(chunks)
        chunks = []
        remaining = size
        while remaining:
            if self.current is None:
                try:
                    self.current = next(self.paths).open("rb")
                except StopIteration:
                    break
            chunk = self.current.read(remaining)
            if chunk:
                chunks.append(chunk)
                remaining -= len(chunk)
            else:
                self.current.close()
                self.current = None
        return b"".join(chunks)


if __name__ == "__main__":
    unittest.main()
