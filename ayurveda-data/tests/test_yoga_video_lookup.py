import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
YOGA = ROOT / "Ayura/Yoga"
FRAME_CLOCK = ROOT / "Ayura/Media/FrameArchiveClock.swift"
FRAME_VERIFIER = ROOT / "ayurveda-data/archive/verify_frame_archive.swift"
YOGA_SOURCE_FIXTURES = (
    ROOT / "ayurveda-data/tests/fixtures/idkey_yoga_video_sources"
)


class YogaVideoLookupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="yoga-video-")
        cls.frame_verifier = Path(cls.temporary.name) / "verify-frame-archive"
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

    def test_uuid_to_cmtime_to_decoded_frame_matches_source_not_neighbors(self):
        """Exercise the Yoga UUID lookup through the real media clock.

        Indices congruent to 1 modulo 3 are the reproducing set for the old
        decimal-truncation defect. Those samples are load-bearing: do not
        "simplify" this set to 0, 1, 2. Each decoded result must beat both
        authored neighbours; duplicate-image pairs are tested separately and
        deliberately are not suitable neighbour discriminators here.
        """
        missing_tools = [
            tool for tool in ("xcrun", "ffmpeg") if not shutil.which(tool)
        ]
        if missing_tools:
            message = (
                "CRITICAL YOGA PIXEL GATE NOT EXECUTED — missing "
                + ", ".join(missing_tools)
                + ". UUID→CMTime→AVAssetImageGenerator→SSIM is unverified."
            )
            print(f"\n{'!' * 78}\n{message}\n{'!' * 78}", file=sys.stderr)
            self.skipTest(message)

        requested_indices = [0, 1, 2, 4, 319, 472, 907]
        id_map = json.loads((YOGA / "frame_index.json").read_text())
        id_by_frame = {frame: asana_id for asana_id, frame in id_map.items()}
        requested_ids = [id_by_frame[index] for index in requested_indices]
        # A 20-asana calibration against authored sources measured 0.860546 at
        # 144 px. Heavy downscaling of Yoga's high-frequency backgrounds makes
        # the food archive's 0.90 floor unreachable, so 0.85 preserves a
        # measured 0.010546 margin. At 480 px the measured minimum was 0.920731,
        # so that variant retains the same 0.90 floor as food. Native-resolution
        # 1024 measured 0.955723; its 0.95 floor preserves a measured 0.005723
        # margin while requiring materially higher fidelity than 480.
        variant_floors = {"144": 0.85, "480": 0.90, "1024": 0.95}
        minimum_neighbor_advantage = 0.10

        for variant, ssim_floor in variant_floors.items():
            fixtures = YOGA_SOURCE_FIXTURES / variant
            output = (
                Path(self.temporary.name) / f"decoded-yoga-source-gate-{variant}"
            )
            output.mkdir()
            probe = subprocess.run(
                [
                    str(self.frame_verifier),
                    "--archive", str(YOGA / f"yoga_archive_{variant}.mp4"),
                    "--frame-index", str(YOGA / "frame_index.json"),
                    "--timestamps", str(YOGA / "frame_timestamps.json"),
                    "--ids", ",".join(requested_ids),
                    "--fps", "30",
                    "--timescale", "600",
                    "--out", str(output),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            rows = probe.stdout.strip().splitlines()[1:]
            self.assertEqual(len(rows), len(requested_indices))
            for row in rows:
                self.assertEqual(float(row.split("\t")[4]), 0.0)

            expected_scores = []
            neighbor_advantages = []
            for frame, asana_id in zip(requested_indices, requested_ids):
                decoded = output / f"{asana_id}.png"
                expected = _ssim(fixtures / f"{frame}.jpg", decoded)
                neighbors = [
                    candidate for candidate in (frame - 1, frame + 1)
                    if (fixtures / f"{candidate}.jpg").is_file()
                ]
                neighbor_scores = [
                    _ssim(fixtures / f"{neighbor}.jpg", decoded)
                    for neighbor in neighbors
                ]
                expected_scores.append(expected)
                if neighbor_scores:
                    neighbor_advantages.append(expected - max(neighbor_scores))
                with self.subTest(
                    variant=variant, frame=frame, asana_id=asana_id
                ):
                    self.assertGreaterEqual(expected, ssim_floor)
                    for score in neighbor_scores:
                        self.assertGreater(expected, score)
                    if neighbor_scores:
                        self.assertGreaterEqual(
                            expected - max(neighbor_scores),
                            minimum_neighbor_advantage,
                        )
            print(
                f"Yoga {variant} pixel gate: floor={ssim_floor:.2f} "
                f"measured_min={min(expected_scores):.6f} "
                f"neighbor_floor={minimum_neighbor_advantage:.2f} "
                f"measured_min_advantage={min(neighbor_advantages):.6f}"
            )


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
