import csv
import importlib.util
import io
import json
import os
import random
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FOOD = ROOT / "Ayura/Food"
PREPARE_PATH = ROOT / "ayurveda-data/archive/prepare_frames.py"
DEFAULT_ZIP = (
    Path.home()
    / "Downloads/gemini-food-stylist/generated images/extra_images.zip"
)
DEFAULT_GENERATED = Path.home() / "wise-eating-images"
SAMPLE_PER_BAND = 200
MAX_MEAN_ABSOLUTE_DIFFERENCE = 5.0


def load_prepare_frames():
    spec = importlib.util.spec_from_file_location(
        "prepare_frames_for_content_test",
        PREPARE_PATH,
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class IDKeyFrameContentTests(unittest.TestCase):
    def test_seeded_cross_band_sample_matches_its_named_source_image(self):
        source_zip = Path(
            os.environ.get("WISE_EATING_EXTRA_IMAGES_ZIP", DEFAULT_ZIP)
        ).expanduser()
        generated = Path(
            os.environ.get("WISE_EATING_IMAGES", DEFAULT_GENERATED)
        ).expanduser()
        missing = [
            str(path)
            for path in (source_zip, generated)
            if not path.exists()
        ]
        if missing:
            self.skipTest(
                "frame-content source assets are absent: " + ", ".join(missing)
            )
        if not shutil.which("ffmpeg"):
            self.skipTest("ffmpeg is required for the frame-content audit")
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow is required for the frame-content audit")

        with (ROOT / "ayurveda-data/archive/foods_index.csv").open(
            newline="",
            encoding="utf-8",
        ) as stream:
            rows = list(csv.DictReader(stream))
        by_band = {
            "base": [
                row
                for row in rows
                if int(row["db_id"]) < 900_000
            ],
            "ayurveda": [
                row
                for row in rows
                if int(row["db_id"]) >= 900_000
            ],
        }
        rng = random.Random(20260803)
        sampled = []
        for band in ("base", "ayurveda"):
            self.assertGreaterEqual(len(by_band[band]), SAMPLE_PER_BAND)
            sampled.extend(rng.sample(by_band[band], SAMPLE_PER_BAND))
        sampled_ids = {int(row["db_id"]) for row in sampled}
        panchamrita_rows = [
            row
            for row in rows
            if row["frame_key"] in {"Panchamrita", "recipe-panchamrita"}
        ]
        self.assertEqual(len(panchamrita_rows), 2)
        sampled.extend(
            row
            for row in panchamrita_rows
            if int(row["db_id"]) not in sampled_ids
        )

        frame_index = {
            int(key): value
            for key, value in json.loads(
                (FOOD / "frame_index.json").read_text(encoding="utf-8")
            ).items()
        }
        selected_indices = sorted(
            {frame_index[int(row["db_id"])] for row in sampled}
        )

        prepare = load_prepare_frames()
        with zipfile.ZipFile(source_zip) as archive:
            zip_sources = {}
            for info in archive.infolist():
                if info.is_dir():
                    continue
                base = os.path.basename(prepare.zip_name(info))
                if base.startswith("._"):
                    continue
                key = prepare.sanitize(os.path.splitext(base)[0])
                zip_sources.setdefault(key, info)

            manifest_rows = json.loads(
                (ROOT / "ayurveda-data/imagery/MANIFEST.json").read_text(
                    encoding="utf-8"
                )
            )["rows"]
            generated_sources = {}
            for row in manifest_rows:
                physical_key = prepare.generated_frame_key(
                    row["filename"],
                    row["frameKey"],
                )
                generated_sources.setdefault(physical_key, []).append(row)

            with tempfile.TemporaryDirectory(prefix="idkey-content-") as output:
                output_path = Path(output)
                expression = "+".join(
                    f"eq(n\\,{index})" for index in selected_indices
                )
                subprocess.run(
                    [
                        "ffmpeg",
                        "-v",
                        "error",
                        "-i",
                        str(FOOD / "food_archive_480.mp4"),
                        "-vf",
                        f"select='{expression}'",
                        "-fps_mode",
                        "vfr",
                        str(output_path / "frame-%04d.png"),
                    ],
                    check=True,
                )
                decoded_paths = sorted(output_path.glob("frame-*.png"))
                self.assertEqual(len(decoded_paths), len(selected_indices))
                decoded_by_index = dict(zip(selected_indices, decoded_paths, strict=True))

                def thumbnail(data):
                    with Image.open(io.BytesIO(data)) as image:
                        resized = image.convert("L").resize(
                            (16, 16),
                            Image.Resampling.LANCZOS,
                        )
                        pixel_reader = getattr(
                            resized,
                            "get_flattened_data",
                            resized.getdata,
                        )
                        return list(pixel_reader())

                def generated_path(row):
                    candidates = generated_sources.get(row["frame_key"], [])
                    if len(candidates) > 1:
                        candidates = [
                            candidate
                            for candidate in candidates
                            if candidate["kind"] == row["kind"]
                        ]
                    self.assertEqual(
                        len(candidates),
                        1,
                        f"ambiguous generated source for DB id {row['db_id']}",
                    )
                    stem = candidates[0]["filename"]
                    matches = sorted(generated.glob(f"{stem}.*"))
                    self.assertEqual(
                        len(matches),
                        1,
                        f"missing generated source for {stem}",
                    )
                    return matches[0]

                differences = []
                for row in sampled:
                    frame_key = row["frame_key"]
                    if frame_key in generated_sources:
                        source_data = generated_path(row).read_bytes()
                    else:
                        self.assertIn(
                            frame_key,
                            zip_sources,
                            f"missing archive-1 source for {frame_key}",
                        )
                        source_data = archive.read(zip_sources[frame_key])
                    source_pixels = thumbnail(source_data)
                    decoded_pixels = thumbnail(
                        decoded_by_index[
                            frame_index[int(row["db_id"])]
                        ].read_bytes()
                    )
                    difference = sum(
                        abs(actual - expected)
                        for actual, expected in zip(
                            decoded_pixels,
                            source_pixels,
                            strict=True,
                        )
                    ) / len(source_pixels)
                    differences.append((difference, row))

        worst_difference, worst_row = max(differences, key=lambda item: item[0])
        print(
            "IDKEY frame-content audit: "
            f"sample={len(sampled)} "
            f"(base={SAMPLE_PER_BAND}, ayurveda={SAMPLE_PER_BAND}); "
            f"worstMAD={worst_difference:.4f} "
            f"at DB id {worst_row['db_id']} {worst_row['name']!r}"
        )
        self.assertLess(
            worst_difference,
            MAX_MEAN_ABSOLUTE_DIFFERENCE,
        )


if __name__ == "__main__":
    unittest.main()
