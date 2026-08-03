#!/usr/bin/env python3
"""Order the staged frames and encode the unified archive.

    # settle the two open encoder questions on measurements, ~20 min:
    python3 order_and_encode.py --pool /Volumes/scratch/frame-pool --matrix 2000

    # then the real build:
    python3 order_and_encode.py --pool /Volumes/scratch/frame-pool \
        --repo ~/work/wise-eating --variants 144 480 1024

THREE THINGS THIS CHANGES FROM generate_multires_assets.py

1.  -video_track_timescale 600.
    The tolerance the old pipeline needed came from the timescale, not the frame
    rate. MP4 defaults to 1000, where 30 fps is 33.333 ticks per frame and never
    lands exactly. 20 fps at timescale 1000 is exactly 50 ticks, which is why
    dropping the rate appeared to fix it. 600 is divisible by 20, 24, 25, 30 and
    60, so every rate is exact and frame i sits at exactly i/fps seconds.
    Keep 30 fps and fix the timescale instead of slowing the video down.

    Consequence worth taking: frame_timestamps.json becomes derivable
    arithmetic. It is written anyway for compatibility, and verified against the
    encoder rather than trusted.

2.  The GOP rule follows USAGE, not resolution.
    The old rule was `res <= 240 -> GOP 1`. In this app 480 is requested by four
    separate list-row views — it is the scrolling path — and it was on GOP 30, so
    a seek could decode thirty frames mid-scroll. GOP_BY_VARIANT below is
    explicit per size. Run --matrix before choosing 480's value; GOP 1 there may
    exceed the 90 MB tracked-file gate.

3.  Similarity ordering, which is worth less than you would hope.
    Measured 2.5% on the encoded size — food photographs differ in every texture
    pixel even within a family, and high-frequency detail does not predict from a
    neighbour. At GOP 1 it buys 0.2%, i.e. nothing, because all-intra frames have
    no neighbour to predict from. It is applied because it is cheap and
    deterministic, not because it is the lever that matters.

    B-frames are forbidden for shipped archives. Packet count and sorted PTS
    alone looked healthy in an earlier measurement, but AVAssetImageGenerator
    cannot reliably random-access the reordered HEVC stream. The visible
    failure is a missing or wrong food image. Keep -bf 0.

    The shipped 480 variant uses CRF 26 to stay below the 90 MB tracked-file
    gate; 1024 remains CRF 24.
"""
import argparse, base64, csv, json, os, subprocess, sys, tempfile

FPS = 30
TIMESCALE = 600
GOP_BY_VARIANT = {"144": 1, "240": 1, "360": 12, "480": 12, "720": 30, "1024": 30}
CRF_BY_VARIANT = {"144": 28, "240": 28, "360": 26, "480": 26, "720": 24, "1024": 24}
PRESET_BY_VARIANT = {"144": "fast", "240": "fast"}      # default "medium"
GATE_MB = 90


def encode(frames_dir, out_mp4, variant, bframes, gop=None, crf=None):
    res = int(variant)
    g = str(gop if gop is not None else GOP_BY_VARIANT.get(variant, 30))
    c = str(crf if crf is not None else CRF_BY_VARIANT.get(variant, 24))
    preset = PRESET_BY_VARIANT.get(variant, "medium")
    scale = "scale=1024:-2" if res == 1024 else f"scale=-2:{res}"
    cmd = ["ffmpeg", "-y", "-f", "image2", "-framerate", str(FPS),
           "-i", os.path.join(frames_dir, "img_%05d.jpg"),
           "-c:v", "libx265", "-preset", preset, "-crf", c, "-tag:v", "hvc1",
           "-g", g, "-vsync", "0", "-bf", "8" if bframes else "0",
           "-pix_fmt", "yuv420p", "-video_track_timescale", str(TIMESCALE),
           "-vf", scale, out_mp4]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"variant": variant, "gop": g, "crf": c, "bframes": bool(bframes),
            "mb": os.path.getsize(out_mp4) / 1e6}


def packet_times(mp4):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "packet=pts_time", "-of", "csv=p=0", mp4],
                         capture_output=True, text=True).stdout
    return sorted(float(x) for x in out.split() if x.strip())


def check_exact(ts):
    """Every frame must sit on an exact tick. This is the whole point of the
    timescale change, so it is asserted rather than assumed."""
    worst = max(abs(t - i / FPS) for i, t in enumerate(ts)) if ts else 0.0
    return worst


def build_id_index(food_index_csv, frame_map):
    with open(food_index_csv, newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    mapping = {}
    for row in rows:
        db_id = str(int(row["db_id"]))
        frame_key = row["frame_key"]
        if frame_key not in frame_map:
            sys.exit(
                f"foods_index.csv points DB id {db_id} at missing frame key "
                f"{frame_key!r}"
            )
        if db_id in mapping:
            sys.exit(f"foods_index.csv repeats DB id {db_id}")
        mapping[db_id] = frame_map[frame_key]
    return mapping


def embed_id_index(dist, variants, food_index_csv, frame_map):
    """Embed the canonical DB-id map without re-encoding the video stream."""
    mapping = build_id_index(food_index_csv, frame_map)
    payload = (
        json.dumps(mapping, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode("utf-8")
    index_path = os.path.join(dist, "frame_index.json")
    with open(index_path, "wb") as output:
        output.write(payload)

    # Base64 makes ffmetadata escaping lossless. The file side input avoids
    # ARG_MAX, and each remux is read back immediately as an integrity gate.
    encoded = base64.b64encode(payload).decode("ascii")
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", suffix=".ffmeta", delete=False
    ) as metadata:
        metadata.write(";FFMETADATA1\n")
        metadata.write(f"frame_index_b64={encoded}\n")
        metadata_path = metadata.name
    try:
        for variant in variants:
            source = os.path.join(dist, f"food_archive_{variant}.mp4")
            if not os.path.isfile(source):
                sys.exit(f"cannot embed DB-id map; missing encoded variant: {source}")
            temporary = source + ".idkey.tmp.mp4"
            subprocess.run(
                [
                    "ffmpeg", "-y", "-i", source,
                    "-f", "ffmetadata", "-i", metadata_path,
                    "-map", "0", "-c", "copy", "-map_metadata", "1",
                    "-movflags", "use_metadata_tags",
                    "-video_track_timescale", str(TIMESCALE), temporary,
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            os.replace(temporary, source)
            probe = subprocess.run(
                [
                    "ffprobe", "-v", "error", "-show_entries",
                    "format_tags=frame_index_b64", "-of", "json", source,
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            tag = json.loads(probe.stdout)["format"]["tags"]["frame_index_b64"]
            if base64.b64decode(tag) != payload:
                sys.exit(
                    f"{variant}: embedded DB-id table differs from frame_index.json"
                )
            print(
                f"  {variant:>4}: embedded {len(mapping)} DB-id pairs; "
                "round-trip byte-identical"
            )
    finally:
        os.unlink(metadata_path)
    return mapping, payload


def build_order(pool, dims=8):
    import numpy as np
    F = np.load(os.path.join(pool, "features.npy"))
    man = json.load(open(os.path.join(pool, "manifest.json")))["frames"]
    n = len(man)
    X = F - F.mean(axis=0)
    # PCA to `dims` via the covariance of the (small) feature space.
    cov = (X.T @ X) / max(1, n - 1)
    w, V = np.linalg.eigh(cov)
    P = X @ V[:, -dims:]
    P = np.ascontiguousarray(P, dtype=np.float32)
    used = np.zeros(n, dtype=bool)
    order = [0]
    used[0] = True
    cur = P[0]
    for _ in range(n - 1):
        d = ((P - cur) ** 2).sum(axis=1)
        d[used] = np.inf
        j = int(d.argmin())
        order.append(j)
        used[j] = True
        cur = P[j]
    adj = float(np.mean([np.linalg.norm(P[order[i]] - P[order[i + 1]]) for i in range(n - 1)]))
    base = float(np.mean([np.linalg.norm(P[i] - P[i + 1]) for i in range(n - 1)]))
    print(f"ordering: mean adjacent distance {base:.3f} -> {adj:.3f}  ({base/max(adj,1e-9):.1f}x closer)")
    return order, man


def link_frames(pool, order, dest):
    os.makedirs(dest, exist_ok=True)
    for slot, idx in enumerate(order):
        src = os.path.join(pool, f"{idx:05d}.jpg")
        dst = os.path.join(dest, f"img_{slot:05d}.jpg")
        if os.path.exists(dst):
            os.remove(dst)
        os.link(src, dst)          # hardlink: no extra disk, same filesystem


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pool", required=True)
    ap.add_argument("--repo")
    ap.add_argument("--out", help="where the mp4s land (default <pool>/dist)")
    ap.add_argument("--variants", nargs="+", default=["144", "480", "1024"])
    ap.add_argument("--bframes", action="store_true",
                    help="diagnostic only; NEVER use for a shipped archive")
    ap.add_argument("--no-order", action="store_true", help="skip similarity ordering")
    ap.add_argument("--crf", type=int,
                    help="override CRF for every variant in this run (default: per-variant table)")
    ap.add_argument("--matrix", type=int, metavar="N",
                    help="encode the first N frames every way and print the table, "
                         "then stop. Settles the B-frame and 480-GOP questions.")
    ap.add_argument(
        "--food-index",
        help="foods_index.csv with db_id; writes and embeds frame_index.json",
    )
    ap.add_argument(
        "--embed-only",
        action="store_true",
        help="metadata-remux existing variants in --out; do not re-encode video",
    )
    a = ap.parse_args()

    pool = os.path.expanduser(a.pool)
    dist = os.path.expanduser(a.out) if a.out else os.path.join(pool, "dist")
    os.makedirs(dist, exist_ok=True)
    man_all = json.load(open(os.path.join(pool, "manifest.json")))["frames"]

    if a.embed_only:
        if not a.food_index:
            sys.exit("--embed-only requires --food-index")
        frame_map_path = os.path.join(dist, "frame_map.json")
        if not os.path.isfile(frame_map_path):
            sys.exit(f"--embed-only requires {frame_map_path}")
        frame_map = json.load(open(frame_map_path))
        embed_id_index(dist, a.variants, a.food_index, frame_map)
        return

    # ---------------- measurement mode ---------------------------------------
    if a.matrix:
        n = min(a.matrix, len(man_all))
        stage = os.path.join(dist, "matrix_frames")
        link_frames(pool, list(range(n)), stage)
        print(f"\nsample: FIRST {n} frames of the pool\n")
        print("  NOTE: this is a contiguous slice, and the pool begins with archive 1 in")
        print("  its own similarity order — so the sample's neighbours are unusually")
        print("  close and it compresses better than the whole set. Measured 2026-07-30:")
        print("  the 480 extrapolation came out 60% low (60.5 MB predicted, 96.9 actual).")
        print("  Treat the full-MB column as a floor, not an estimate.\n")
        rows = []
        for variant in ("480", "1024"):
            for bf in (False, True):
                for gop in (1, 12, 30):
                    out = os.path.join(dist, f"m_{variant}_g{gop}_b{int(bf)}.mp4")
                    r = encode(stage, out, variant, bf, gop=gop)
                    ts = packet_times(out)
                    r["frames"] = len(ts)
                    r["worstTickError"] = check_exact(ts)
                    r["fullMB"] = r["mb"] * len(man_all) / n
                    rows.append(r)
                    print(f"  {variant:>4}  gop {gop:>2}  bframes {str(bf):<5} "
                          f"{r['mb']:7.2f} MB sample -> {r['fullMB']:7.1f} MB full   "
                          f"packets {len(ts)}/{n}  worst tick error {r['worstTickError']:.2e}")
                    os.remove(out)
        json.dump(rows, open(os.path.join(dist, "matrix.json"), "w"), indent=1)
        print("\nRead it this way: 'packets' must equal the frame count in every row — if")
        print("B-frames broke frame addressing it would not. 'worst tick error' must be ~0,")
        print("which is what -video_track_timescale 600 buys. Then pick 480's GOP on the")
        print("size column against how the scroll feels with GOP 30 today.")
        return

    # ---------------- real build ---------------------------------------------
    if not a.repo:
        sys.exit("--repo is required for a real build")
    order = list(range(len(man_all))) if a.no_order else build_order(pool)[0]
    if a.no_order:
        print("ordering skipped (--no-order)")
    stage = os.path.join(dist, "sorted_frames")
    print(f"linking {len(order)} frames -> {stage}")
    link_frames(pool, order, stage)

    fmap = {man_all[idx]["frameKey"]: slot for slot, idx in enumerate(order)}
    results, ts_ref = [], None
    for v in a.variants:
        r = encode(stage, os.path.join(dist, f"food_archive_{v}.mp4"), v, a.bframes, crf=a.crf)
        ts = packet_times(os.path.join(dist, f"food_archive_{v}.mp4"))
        if len(ts) != len(order):
            sys.exit(f"FRAME COUNT MISMATCH at {v}: {len(ts)} packets vs {len(order)} frames. "
                     "Do not ship this — the seek would return the wrong food.")
        err = check_exact(ts)
        if err > 1e-6:
            sys.exit(f"{v}: frames are not on exact ticks (worst {err:.2e}). "
                     "The timescale did not take; do not ship this.")
        ts_ref = ts_ref or ts
        flag = "   <-- OVER the 90 MB tracked-file gate, needs gzip+split" if r["mb"] > GATE_MB else ""
        print(f"  {v:>4}: gop {r['gop']:>2} crf {r['crf']} bf {r['bframes']}  "
              f"{r['mb']:7.1f} MB  {len(ts)} frames  tick error {err:.2e}{flag}")
        results.append(r)

    json.dump(fmap, open(os.path.join(dist, "frame_map.json"), "w"), indent=0, ensure_ascii=False)
    json.dump(ts_ref, open(os.path.join(dist, "frame_timestamps.json"), "w"))
    json.dump({"fps": FPS, "timescale": TIMESCALE, "frames": len(order),
               "ordered": not a.no_order, "bframes": a.bframes, "variants": results},
              open(os.path.join(dist, "build-info.json"), "w"), indent=1)

    if a.food_index:
        embed_id_index(dist, a.variants, a.food_index, fmap)

    print(f"\n{len(order)} frames -> {dist}")
    print("frame_map.json now covers BOTH archives, so frame_map2.json is dead.")
    print("runtime reuse-map.json is dead. build_food_index.py resolves reviewed reuse")
    print("once at build time and writes those DB ids directly into frame_index.json.")


if __name__ == "__main__":
    main()
