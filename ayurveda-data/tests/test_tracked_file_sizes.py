import importlib.util
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
        ignored_video = "WiseEating/Food/food_archive_1024.mp4"

        self.assertNotIn(ignored_video, sizes)
        self.assertTrue(sizes)
        self.assertLessEqual(
            max(sizes.values()),
            validator.TRACKED_FILE_SPLIT_LIMIT_BYTES,
        )
        self.assertEqual(
            sizes["WiseEating/Food/food_archive_480.mp4"],
            82_726_160,
        )


if __name__ == "__main__":
    unittest.main()
