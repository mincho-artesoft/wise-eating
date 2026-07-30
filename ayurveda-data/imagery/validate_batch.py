#!/usr/bin/env python3
"""IMG-3 — validate one generated batch before spending credits on the next.

    python3 validate_batch.py --batch 1 --images /abs/path/to/images [--repo ...]

Checks, in order of how badly each one bites:
  1. every planned filename exists                      missing image
  2. decodes, is square, >= 1024x1024                   wrong geometry
  3. not near-blank and not near-uniform                Flow returned a grey card
  4. perceptual hash is unique within the batch AND     the same picture served
     against every accepted image so far                for two different foods
  5. background corners are light and low-variance      style drift from the
     existing 12,601 frames

Writes accepted/<batch>.json listing what may go into the archive. Nothing
reaches build_archive2.py unless it is listed there.
"""
import argparse, json, os, sys, collections

try:
    from PIL import Image, ImageStat
except ImportError:
    sys.exit("pip install pillow --break-system-packages")

DIR = os.path.dirname(os.path.abspath(__file__))


def dhash(img, size=8):
    g = img.convert("L").resize((size + 1, size), Image.LANCZOS)
    px = list(g.getdata())
    bits = 0
    for r in range(size):
        for c in range(size):
            bits = (bits << 1) | int(px[r * (size + 1) + c] < px[r * (size + 1) + c + 1])
    return bits


def ham(a, b):
    return bin(a ^ b).count("1")


def corner_stats(img, k=48):
    w, h = img.size
    boxes = [(0, 0, k, k), (w - k, 0, w, k), (0, h - k, k, h), (w - k, h - k, w, h)]
    means, sds = [], []
    for b in boxes:
        st = ImageStat.Stat(img.crop(b).convert("L"))
        means.append(st.mean[0]); sds.append(st.stddev[0])
    return sum(means) / 4, sum(sds) / 4


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int, required=True)
    ap.add_argument("--images", required=True)
    ap.add_argument("--min-size", type=int, default=1024)
    ap.add_argument("--hash-distance", type=int, default=6)
    a = ap.parse_args()

    # SUPERSEDED for the flat-jobs architecture. This script needs
    # queue/batch-NNN.json, which build_batches.py now emits only behind
    # --batches, and results/batch-NNN-results.json, which runner.js stopped
    # writing when it moved to a single results/ledger.json. Without a queue/ it
    # exits before checking anything, and the failure reads as "batch not found"
    # rather than "this script no longer applies" — which cost IMG-2b a cycle.
    qdir = os.path.join(DIR, "queue")
    if not os.path.isdir(qdir) or not [f for f in os.listdir(qdir) if f.startswith("batch-")]:
        sys.exit("no queue/batch-*.json — this repo is on the flat-jobs model.\n"
                 "Use:  python3 validate_all.py --images ~/wise-eating-images\n"
                 "which grades every image on disk against jobs.json in one pass and writes\n"
                 "the same accepted/ file build_archive2.py reads.")

    man = json.load(open(os.path.join(DIR, "MANIFEST.json")))
    qfile, where = None, None
    for sub in ("done", "failed", "queue"):
        p = os.path.join(DIR, sub, f"batch-{a.batch:03d}.json")
        if os.path.exists(p): qfile, where = p, sub; break
    if not qfile:
        sys.exit(f"batch-{a.batch:03d}.json not found in queue/ done/ failed/")

    # Refuse to grade a batch that never ran. Writing an accepted file full of
    # "missing" is worse than useless: it looks like a measured result.
    rpath = os.path.join(DIR, "results", f"batch-{a.batch:03d}-results.json")
    if where == "queue" and not os.path.exists(rpath):
        sys.exit(f"batch {a.batch} is still in queue/ and has no results file — it has not run yet. "
                 "Nothing to validate.")
    if os.path.exists(rpath):
        rs = json.load(open(rpath)).get("results", [])
        skipped = [r for r in rs if r.get("status") == "skipped"]
        if skipped:
            sys.exit(f"batch {a.batch} ABORTED mid-run: {len(skipped)} of {len(rs)} jobs were skipped. "
                     "Fix the environment and re-run the batch; do not validate a partial run.")
    batch = json.load(open(qfile))
    planned = [j["output"]["filename"] for j in batch["jobs"]]
    bykey = {j["output"]["filename"]: j["_row"] for j in batch["jobs"]}

    seen = {}
    accepted_path = os.path.join(DIR, "accepted")
    os.makedirs(accepted_path, exist_ok=True)
    for f in sorted(os.listdir(accepted_path)):
        if f.endswith(".json"):
            for r in json.load(open(os.path.join(accepted_path, f))).get("accepted", []):
                seen[r["filename"]] = int(r["dhash"], 16)

    ok, bad = [], collections.defaultdict(list)
    for fn in planned:
        cand = [os.path.join(a.images, fn + e) for e in (".png", ".jpg", ".jpeg", ".webp")]
        p = next((c for c in cand if os.path.exists(c)), None)
        if not p:
            bad["missing"].append(fn); continue
        try:
            img = Image.open(p); img.load()
        except Exception as e:
            bad["undecodable"].append(f"{fn}: {e}"); continue
        w, h = img.size
        if w != h or w < a.min_size:
            bad["geometry"].append(f"{fn}: {w}x{h}"); continue
        st = ImageStat.Stat(img.convert("L"))
        if st.stddev[0] < 8:
            bad["blank"].append(f"{fn}: stddev {st.stddev[0]:.1f}"); continue
        cmean, csd = corner_stats(img)
        if cmean < 150 or csd > 18:
            bad["background"].append(f"{fn}: corner mean {cmean:.0f}, sd {csd:.1f}"); continue
        d = dhash(img)
        dup = next((k for k, v in seen.items() if ham(v, d) <= a.hash_distance), None)
        if dup:
            bad["duplicate"].append(f"{fn}: matches {dup}"); continue
        seen[fn] = d
        row = bykey[fn]
        ok.append({"filename": fn, "path": p, "name": row["name"], "kind": row["kind"],
                   "frameKey": row["frameKey"], "dhash": format(d, "016x")})

    json.dump({"batch": a.batch, "accepted": ok},
              open(os.path.join(accepted_path, f"batch-{a.batch:03d}.json"), "w"),
              indent=2, ensure_ascii=False)

    n = len(planned)
    print(f"batch {a.batch}: {len(ok)}/{n} accepted")
    for k, v in bad.items():
        print(f"  {k}: {len(v)}")
        for x in v[:6]:
            print(f"     {x}")
    print(f"\nwrote accepted/batch-{a.batch:03d}.json")
    if bad:
        print("\nRejected rows stay unbuilt. Re-queue them by hand after fixing the prompt,")
        print("or accept the gap — do NOT lower a threshold to make this pass.")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
