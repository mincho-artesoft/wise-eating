#!/usr/bin/env python3
"""IMG-4 — encode every accepted image into a SECOND archive.

    python3 build_archive2.py --repo /path/to/wise-eating [--variants 1024 480 144]

Produces, in ayurveda-data/imagery/dist/:
    food_archive2_<variant>.mp4
    frame_map2.json          name -> frame index   (same shape as frame_map.json)
    frame_timestamps2.json   index -> pts seconds

The original food_archive_*.mp4 files are NEVER read, rewritten or re-encoded.
food_archive_1024.mp4 is 285 MB, gitignored and has exactly one copy; and
food_archive_480.mp4 is git-tracked at 82.7 MB, only 7 MB under the 90 MB
limit, so appending to it would breach that gate. A second archive avoids both.

FoodVideoSource then reads map 1, falls back to map 2, then to reuse-map.json.

Encoder settings follow the project's own
gemini-food-stylist/generated images/generate_multires_assets.py, including its
per-resolution GOP split: GOP 1 for thumbnail sizes so a seek decodes one frame,
GOP 30 above. Variants default to the three archive 1 actually ships.
"""
import argparse, glob, json, os, shutil, subprocess, sys

DIR = os.path.dirname(os.path.abspath(__file__))


def encode(frames_dir, out_mp4, variant):
    """Per-resolution encoder settings, taken from the project's own
    generate_multires_assets.py rather than reinvented.

    The part worth keeping is the GOP split. Thumbnail variants use GOP 1, so
    every frame is a keyframe and a seek decodes exactly one frame — which is
    what makes a scrolling grid of food thumbnails feel instant. Larger variants
    use GOP 30 for file size, because they are opened one at a time.

    An earlier version of this file used keyint=30 for everything, which would
    have made the 144 thumbnail archive decode up to 30 frames per seek.

    `-vsync 0` and `-bf 0` are load-bearing at every size: B-frames break the
    strictly linear frame order the iOS seek depends on.
    """
    res = int(variant)
    if res <= 240:
        gop, crf, preset, mode = "1", "28", "fast", "instant seek"
    else:
        gop, crf, preset, mode = "30", "24", "medium", "efficient storage"
    scale = "scale=1024:-2" if res == 1024 else f"scale=-2:{res}"
    print(f"   {res}: {mode} (GOP {gop}, crf {crf}, {preset})")
    subprocess.run(["ffmpeg", "-y", "-f", "image2", "-framerate", "30",
                    "-i", os.path.join(frames_dir, "img_%05d.jpg"),
                    "-c:v", "libx265", "-preset", preset, "-crf", crf, "-tag:v", "hvc1",
                    "-g", gop, "-vsync", "0", "-bf", "0", "-pix_fmt", "yuv420p",
                    "-vf", scale, out_mp4], check=True)


def timestamps(mp4):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "packet=pts_time", "-of", "csv=p=0", mp4],
                         capture_output=True, text=True).stdout
    ts = sorted(float(x) for x in out.split() if x.strip())
    return ts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--variants", nargs="+", default=["1024", "480", "144"],
                    help="must match the variants archive 1 ships, or FoodVideoSource "
                         "will ask for a generator that does not exist")
    a = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        sys.exit("pip install pillow --break-system-packages")

    accepted = []
    for f in sorted(glob.glob(os.path.join(DIR, "accepted", "batch-*.json"))):
        accepted += json.load(open(f)).get("accepted", [])
    if not accepted:
        sys.exit("nothing in accepted/ — run validate_batch.py first")

    # Stable order: sorting by frameKey makes the archive reproducible.
    accepted.sort(key=lambda r: r["frameKey"])

    existing = set(json.load(open(f"{a.repo}/Ayura/Food/frame_map.json")))
    clash = [r["frameKey"] for r in accepted if r["frameKey"] in existing]
    if clash:
        sys.exit(f"{len(clash)} frameKeys already exist in frame_map.json, e.g. {clash[:3]}. "
                 "Resolve before building — a duplicate key would silently shadow map 1.")

    dist = os.path.join(DIR, "dist")
    stage = os.path.join(dist, "sorted_frames")
    shutil.rmtree(stage, ignore_errors=True)
    os.makedirs(stage, exist_ok=True)

    fmap = {}
    for i, r in enumerate(accepted):
        img = Image.open(r["path"]).convert("RGB")
        img.save(os.path.join(stage, f"img_{i:05d}.jpg"), quality=95)
        fmap[r["frameKey"]] = i

    for v in a.variants:
        mp4 = os.path.join(dist, f"food_archive2_{v}.mp4")
        encode(stage, mp4, v)
        ts = timestamps(mp4)
        if len(ts) != len(accepted):
            sys.exit(f"FRAME COUNT MISMATCH for {v}: {len(ts)} timestamps vs {len(accepted)} images. "
                     "Do not ship this — the iOS seek would return the wrong food.")
        if v == a.variants[0]:
            json.dump(ts, open(os.path.join(dist, "frame_timestamps2.json"), "w"))
        print(f"  {v}: {os.path.getsize(mp4)/1e6:.1f} MB, {len(ts)} frames")

    json.dump(fmap, open(os.path.join(dist, "frame_map2.json"), "w"), indent=0, ensure_ascii=False)
    print(f"\n{len(accepted)} frames -> {dist}")
    for v in a.variants:
        sz = os.path.getsize(os.path.join(dist, f"food_archive2_{v}.mp4")) / 1e6
        flag = "  <-- OVER the 90 MB tracked-file gate" if sz > 90 else ""
        print(f"   food_archive2_{v}.mp4  {sz:.1f} MB{flag}")


if __name__ == "__main__":
    main()
