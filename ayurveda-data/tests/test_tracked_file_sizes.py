import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "ayurveda-data" / "validate.py"
sys.path.insert(0, str(VALIDATOR_PATH.parent))
SPEC = importlib.util.spec_from_file_location(
    "validate_tracked_file_sizes",
    VALIDATOR_PATH,
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class TrackedFileSizeTests(unittest.TestCase):
    def test_only_git_tracked_files_are_gated_at_90_mb(self):
        sizes = validator.tracked_file_sizes(ROOT)
        archived_video = "Ayura/Food/food_archive_1024.mp4"
        local_video = "Ayura/Food/food_archive_480.mp4"
        manifest_path = ROOT / "Ayura" / "Food" / "assets-manifest.json"

        self.assertNotIn(archived_video, sizes)
        self.assertIn("Ayura/Food/assets-manifest.json", sizes)
        self.assertTrue(sizes)
        self.assertLessEqual(
            max(sizes.values()),
            validator.TRACKED_FILE_SPLIT_LIMIT_BYTES,
        )

        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        video_entry = next(
            asset
            for asset in manifest["assets"]
            if asset["filename"] == local_video
        )
        self.assertEqual(
            video_entry["byteSize"],
            82_726_160,
        )

        archive_parts = [
            asset
            for asset in manifest["assets"]
            if asset["filename"].startswith(
                "Ayura/Food/food_archive_1024.mp4.gz.part-"
            )
        ]
        self.assertEqual(len(archive_parts), 4)
        for part in archive_parts:
            part_path = ROOT / part["filename"]
            self.assertEqual(part_path.stat().st_size, part["byteSize"])
            self.assertLessEqual(
                part["byteSize"],
                validator.TRACKED_FILE_SPLIT_LIMIT_BYTES,
            )


if __name__ == "__main__":
    unittest.main()
