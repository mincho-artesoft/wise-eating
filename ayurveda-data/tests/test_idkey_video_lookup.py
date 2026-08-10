import base64
import csv
import gzip
import json
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
import unicodedata
import uuid
from pathlib import Path

import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ayurveda-data"))
from stable_ids import food_uuid
FOOD = ROOT / "Ayura/Food"
FRAME_CLOCK = ROOT / "Ayura/Media/FrameArchiveClock.swift"
FRAME_VERIFIER = ROOT / "ayurveda-data/archive/verify_frame_archive.swift"
SOURCE_FIXTURES = ROOT / "ayurveda-data/tests/fixtures/idkey_video_sources"
ORPHANS = {
    "Black mustard seed",
    "Curry leaf powder",
    "Dosa",
    "Fox nut (makhana)",
    "Grapes",
    "Lamb",
    "Lotus seeds (makhana)",
    "Punjabi tinda (apple gourd)",
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
        cls.frame_verifier = root / "verify-frame-archive"
        if shutil.which("xcrun") and shutil.which("ffmpeg"):
            subprocess.run(
                [
                    "xcrun", "swiftc", str(FRAME_VERIFIER), str(FRAME_CLOCK),
                    "-o", str(cls.frame_verifier),
                ],
                check=True,
            )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_every_db_food_id_matches_the_previous_name_resolution(self):
        frame_map = json.loads((FOOD / "frame_map.json").read_text())
        reuse = json.loads(
            (ROOT / "ayurveda-data/imagery/reuse-map.json").read_text()
        )
        id_map = {str(uuid.UUID(key)): value for key, value in json.loads(
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

        self.assertEqual(len(foods), 14_487)
        foods = [(str(uuid.UUID(bytes=food_id)), name) for food_id, name in foods]
        self.assertEqual(set(id_map), {food_id for food_id, _ in foods})
        expected = {food_id: old_resolution(name) for food_id, name in foods}
        # ID-keying deliberately gives the recipe its reviewed private image;
        # name-keying previously collapsed it onto the dravya frame.
        with gzip.open(ROOT / "Ayura/ayurveda_seed.json.gz", "rt") as source:
            seed = json.load(source)
        panchamrita_id = next(
            recipe["foodId"] for recipe in seed["recipes"]
            if recipe["key"] == "recipe.panchamrit-classic"
        )
        expected[panchamrita_id] = frame_map["recipe-panchamrita"]
        self.assertNotIn(None, expected.values())
        self.assertEqual(id_map, expected)

        # The packet calls for 200 random round trips. The exhaustive equality
        # above is stronger; keep the deterministic sample explicit as a
        # readable regression set as well.
        sample = random.Random(20260803).sample([row[0] for row in foods], 200)
        self.assertTrue(all(id_map[food_id] == expected[food_id] for food_id in sample))

        addressed = set(id_map.values())
        inverse = {index: key for key, index in frame_map.items()}
        self.assertEqual(len(addressed), 14_465)
        self.assertEqual(
            {inverse[index] for index in set(inverse) - addressed},
            ORPHANS,
        )

    def test_food_index_and_shipped_id_map_are_a_matched_pair(self):
        with (ROOT / "ayurveda-data/archive/foods_index.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        id_map = json.loads((FOOD / "frame_index.json").read_text())
        catalog_to_uuid = {
            str(food["catalogNumber"]): food["id"]
            for food in json.loads(
                (ROOT / "Ayura/Legacy/foods.json").read_text()
            )
        }
        self.assertEqual(len(rows), 14_487)
        self.assertEqual(len(id_map), 14_487)
        self.assertEqual(
            {
                catalog_to_uuid.get(row["db_id"], food_uuid(int(row["db_id"]))):
                    int(row["frame_index"])
                for row in rows
            },
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
            self.assertEqual(stream["nb_read_packets"], "14479", variant)
            self.assertEqual(stream["has_b_frames"], 0, variant)
            self.assertEqual(stream["time_base"], "1/600", variant)
            self.assertEqual(stream["codec_tag_string"], "hvc1", variant)
            embedded = json.loads(base64.b64decode(
                probe["format"]["tags"]["frame_index_b64"]
            ))
            migrated_embedded = {
                food_uuid(int(food_id)): frame
                for food_id, frame in embedded.items()
            }
            self.assertEqual(
                migrated_embedded,
                json.loads(payload),
                variant,
            )

    def test_swift_runtime_has_no_name_or_secondary_lookup_path(self):
        source = (FOOD / "FoodVideoSource.swift").read_text()
        food_item = (ROOT / "Ayura/Food/Models/FoodItem.swift").read_text()
        self.assertIn("func getFrame(id foodID: UUID, variant: String)", source)
        self.assertIn("func hasVideo(for foodID: UUID)", source)
        self.assertIn('forResource: "frame_index"', source)
        self.assertNotIn("getFrame(named", source)
        self.assertNotIn("frameMap2", source)
        self.assertNotIn("secondaryGenerators", source)
        self.assertNotIn("reuseMap", source)
        self.assertIn("FrameArchiveClock.time(", source)
        self.assertNotIn("CMTime(seconds:", source)
        self.assertNotIn("timestamps[index]", source)
        self.assertIn("getFrame(id: self.id, variant: variant)", food_item)
        self.assertNotIn("sanitizedName", food_item)

    def test_index_to_cmtime_to_decoded_frame_matches_source_not_neighbor(self):
        """Cross the exact boundary missed by the original ID-key tests.

        Indices congruent to 1 modulo 3 are the reproducing set for the old
        decimal-truncation defect. Those samples are load-bearing: do not
        "simplify" this set to 0, 1, 2. The production FrameArchiveClock is
        compiled into the probe, and each decoded result must resemble its
        requested source much more closely than either adjacent source.
        """
        missing_tools = [
            tool for tool in ("xcrun", "ffmpeg") if not shutil.which(tool)
        ]
        if missing_tools:
            message = (
                "CRITICAL PIXEL GATE NOT EXECUTED — missing "
                + ", ".join(missing_tools)
                + ". ID→CMTime→AVAssetImageGenerator→SSIM is unverified."
            )
            print(f"\n{'!' * 78}\n{message}\n{'!' * 78}", file=sys.stderr)
            self.skipTest(message)
        requested_indices = [0, 1, 2, 4, 436, 472, 11_194, 12_514, 14_478]
        id_map = json.loads((FOOD / "frame_index.json").read_text())
        id_by_frame = {frame: food_id for food_id, frame in id_map.items()}
        requested_ids = [id_by_frame[index] for index in requested_indices]
        output = Path(self.temporary.name) / "decoded-source-gate"
        output.mkdir()
        probe = subprocess.run(
            [
                str(self.frame_verifier),
                "--archive", str(FOOD / "food_archive_144.mp4"),
                "--frame-index", str(FOOD / "frame_index.json"),
                "--timestamps", str(FOOD / "frame_timestamps.json"),
                "--ids", ",".join(requested_ids),
                "--fps", "30",
                "--timescale", "600",
                "--out", str(output),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertIn("delta_seconds", probe.stdout)
        for row in probe.stdout.strip().splitlines()[1:]:
            self.assertEqual(float(row.split("\t")[4]), 0.0)

        for frame, food_id in zip(requested_indices, requested_ids):
            decoded = output / f"{food_id}.png"
            expected = _ssim(SOURCE_FIXTURES / f"{frame}.jpg", decoded)
            neighbors = [
                candidate for candidate in (frame - 1, frame + 1)
                if (SOURCE_FIXTURES / f"{candidate}.jpg").is_file()
            ]
            neighbor_scores = [
                _ssim(SOURCE_FIXTURES / f"{neighbor}.jpg", decoded)
                for neighbor in neighbors
            ]
            with self.subTest(frame=frame, food_id=food_id):
                self.assertGreaterEqual(expected, 0.90)
                if neighbor_scores:
                    self.assertGreaterEqual(expected - max(neighbor_scores), 0.10)

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


def _ssim(reference, decoded):
    result = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-nostats",
            "-i", str(reference), "-i", str(decoded),
            "-filter_complex",
            (
                "[0:v]format=yuv420p[reference];"
                "[1:v]format=yuv420p[decoded];"
                "[reference][decoded]ssim"
            ),
            "-f", "null", "-",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    match = re.search(r"All:([0-9.]+)", result.stderr)
    if not match:
        raise AssertionError(f"ffmpeg did not report SSIM:\n{result.stderr}")
    return float(match.group(1))


if __name__ == "__main__":
    unittest.main()
