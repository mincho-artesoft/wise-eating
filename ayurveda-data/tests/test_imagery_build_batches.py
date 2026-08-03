import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "ayurveda-data/imagery/build_batches.py"
DENIALS = ROOT / "ayurveda-data/imagery/reuse-deny.json"


def load_builder():
    spec = importlib.util.spec_from_file_location("imagery_build_batches", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ImageryBuildBatchesTests(unittest.TestCase):
    def test_external_output_directory_still_applies_all_reuse_denials(self):
        denied = json.loads(DENIALS.read_text())["dravyas"]

        with tempfile.TemporaryDirectory(prefix="imagery-build-") as output:
            result = subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "--repo",
                    str(ROOT),
                    "--out",
                    output,
                    "--full",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            jobs = json.loads((Path(output) / "jobs.json").read_text())
            reuse = json.loads((Path(output) / "reuse-map.json").read_text())

        self.assertIn("reuse denials loaded    : 26", result.stdout)
        # Restoring Vida as its own dravya adds exactly one generated job.
        self.assertEqual(jobs["count"], 1_878)
        self.assertEqual(jobs["styleHash"], "c8d83786a68f")
        self.assertEqual(len(reuse), 293)
        self.assertTrue(
            {entry["name"] for entry in denied.values()}.isdisjoint(reuse)
        )

    def test_missing_reuse_denial_list_fails_closed_with_resolved_path(self):
        builder = load_builder()
        missing = Path(tempfile.gettempdir()) / "missing-reuse-deny.json"

        with mock.patch.object(builder, "REUSE_DENY_PATH", str(missing)):
            with self.assertRaisesRegex(RuntimeError, str(missing)):
                builder.load_deny()


if __name__ == "__main__":
    unittest.main()
