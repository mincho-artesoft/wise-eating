#!/usr/bin/env python3
"""IMG-3b — validate every image on disk against jobs.json, in one pass.

    python3 validate_all.py --repo /path/to/wise-eating [--images ~/wise-eating-images]

Replaces validate_batch.py for the flat-jobs architecture.

WHY THIS EXISTS
---------------
validate_batch.py was written for the batch model: queue/batch-NNN.json in,
results/batch-NNN-results.json to prove the batch ran, accepted/batch-NNN.json
out. That model is gone. build_batches.py emits queue/ only behind --batches,
runner.js writes one results/ledger.json, and the unit of work is now "--limit N
rows from jobs.json" rather than a partition baked into files. So
validate_batch.py cannot find its inputs and exits before checking anything,
which left build_archive2.py permanently staring at an empty accepted/.

It also carried an assumption that is now actively wrong. It treats a planned
filename with no image as a FAILURE and exits non-zero. In the flat model the
normal state is 1,500-odd rows not generated yet. Missing is not a defect here;
it is the work queue. Only "generated but not good enough" is a defect.

WHAT IT DOES
------------
Reads jobs.json — the same file verify.py checks for determinism — scans the
output directory once, and grades every image it finds:

  1. decodes                                     truncated or corrupt download
  2. square and >= --min-size                    wrong geometry
  3. not near-uniform                            Flow returned a grey card
  4. corners light and low-variance              style drift from archive 1
  5. perceptual hash unique across the whole set the same picture serving two
                                                 different foods

Writes accepted/batch-000.json in exactly the shape build_archive2.py reads, and
rejected/rejects.json listing every rejection with the number that caused it.

FULL RESCAN, EVERY TIME
-----------------------
This does not accumulate. Each run regrades everything and rewrites the accepted
file from scratch. That matters for three reasons:

  - the generation loop is usually still running, so an image caught mid-download
    fails to decode; a rescan next time picks it up rather than condemning it;
  - dedup is then genuinely global instead of order-dependent;
  - archive 2 is rebuilt from the whole accepted set anyway, so a partial
    accepted file would silently drop frames.

It refuses to run if accepted/ holds files it did not write, because
build_archive2.py globs accepted/batch-*.json and would concatenate a stale
legacy batch into the archive.

THRESHOLDS — measured on the real 448-image set, do not "tidy" them back
------------------------------------------------------------------------
The values inherited from validate_batch.py rejected 132 of 448 good images.
Both were wrong for this catalogue, and the perceptual one was dangerously so.

**Hash size 16x16, not 8x8.** Every image is a plated subject, centred, on a
light grey background. At 8x8 (64 bits) that style *is* the whole signal:
measured over 100,128 pairs, two completely different foods —
dravya-dwarf-copperleaf-ponnanganni and dravya-kodo-millet — collided at
distance **0**, and 555 pairs fell within distance 6. Any 8x8 threshold able to
catch a true duplicate also condemns hundreds of good images.

At 16x16 (256 bits) the separation is clean: the closest genuine pair over the
same 100,128 comparisons sits at **11**, and only 5 pairs are below 25. A true
duplicate is 0 when byte-identical and a few bits when re-encoded, so the
default of 6 has headroom on both sides.

**Corner brightness is a warning, uniformity is the test.** The first version
of this used a flat corner-mean floor: 150, then 130 once 150 was measured to
reject 7 good images out of 448. On the full 1,866 set, 130 rejected 6 more —
and all six were inspected by eye and are correct. Pale foods and clear drinks
(cumin water, gond katira cooler, gujarati kadhi) need a darker sweep or they
disappear into the background, so they legitimately sit at 106-129 while the
population median is 196. Their corner sd was 1.7-3.4 against a median of 1.3,
i.e. among the cleanest backgrounds in the whole set.

So brightness alone was never the signal. What the check is really asking is
"did this render succeed, or is the background a busy photo or a blank frame",
and UNIFORMITY answers that. Corner sd is now the reject condition; corner mean
only rejects below a floor of 60, which catches a near-black frame, and anything
between 60 and 130 is reported as a warning so a real style drift would still be
visible in the output.

Byte-identical detection is verify.py's check F, which uses sha256 and needs no
threshold at all. That is the primitive to trust; this perceptual pass is a
weaker net for re-encoded copies and is calibrated to err toward accepting.
"""
import argparse, collections, json, os, sys

try:
    from PIL import Image, ImageStat
except ImportError:
    sys.exit("pip install pillow --break-system-packages")

DIR = os.path.dirname(os.path.abspath(__file__))
OURS = "batch-000.json"
IMG_EXT = (".png", ".jpg", ".jpeg", ".webp")


def dhash(img, size=16):
    g = img.convert("L").resize((size + 1, size), Image.LANCZOS)
    # tobytes() on an "L" image is row-major pixel order — identical values to the
    # deprecated getdata(), so hashes stay comparable with anything already graded.
    px = g.tobytes()
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


def pct(vals, p):
    if not vals:
        return float("nan")
    s = sorted(vals)
    return s[min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", help="only used to echo context; validation reads jobs.json")
    ap.add_argument("--images", default=os.path.expanduser("~/wise-eating-images"))
    ap.add_argument("--jobs", default=os.path.join(DIR, "jobs.json"))
    ap.add_argument("--min-size", type=int, default=1024)
    # MEASURED on the real 448-image set, not inherited. See THRESHOLDS below.
    ap.add_argument("--hash-distance", type=int, default=6)
    ap.add_argument("--corner-mean", type=float, default=130.0)
    ap.add_argument("--corner-sd", type=float, default=18.0)
    ap.add_argument("--corner-floor", type=float, default=60.0,
                    help="reject below this however uniform — catches a near-black frame")
    ap.add_argument("--report-only", action="store_true",
                    help="grade and print, write nothing — use this to sanity-check "
                         "thresholds before letting them gate an archive build")
    a = ap.parse_args()

    if not os.path.exists(a.jobs):
        sys.exit(f"{a.jobs} does not exist — run build_batches.py")
    doc = json.load(open(a.jobs))
    jobs = doc["jobs"]
    print(f"jobs.json      {len(jobs)} planned, styleHash {doc.get('styleHash')}")
    print(f"images         {a.images}")

    acc_dir = os.path.join(DIR, "accepted")
    os.makedirs(acc_dir, exist_ok=True)
    foreign = [f for f in sorted(os.listdir(acc_dir))
               if f.endswith(".json") and f != OURS]
    # Only a WRITE is unsafe with foreign batches present. --report-only writes
    # nothing, so refusing there blocks a read-only diagnostic for a hazard it
    # cannot possibly create. That mattered: this check fired while the only
    # thing being asked was "did killing the loop leave a truncated download",
    # which is exactly when you least want a safety guard in the way.
    if foreign and not a.report_only:
        sys.exit(f"accepted/ holds {len(foreign)} file(s) this script did not write: {foreign[:5]}\n"
                 f"build_archive2.py globs accepted/batch-*.json and would concatenate them into\n"
                 f"the archive alongside this run's output, double-counting or resurrecting rows\n"
                 f"graded under different thresholds. Move them out of accepted/ and re-run.\n"
                 f"To inspect without writing anything, add --report-only.")
    if foreign:
        print(f"note           accepted/ holds {len(foreign)} foreign file(s): {foreign[:5]}\n"
              f"               harmless for this read-only run; would block a write.")

    # ---- locate what actually exists ---------------------------------------
    present, absent = [], 0
    for j in jobs:
        fn = j["output"]["filename"]
        p = next((os.path.join(a.images, fn + e) for e in IMG_EXT
                  if os.path.exists(os.path.join(a.images, fn + e))), None)
        if p:
            present.append((fn, p, j["_row"]))
        else:
            absent += 1
    print(f"on disk        {len(present)} of {len(jobs)}   ({absent} not generated yet — "
          f"that is the queue, not a fault)\n")

    if not present:
        sys.exit("no generated images found. Let the loop run, then re-run this.")

    # ---- grade --------------------------------------------------------------
    ok, bad = [], collections.defaultdict(list)
    warn_dark = []
    cmeans, csds, sds = [], [], []
    for fn, p, row in present:
        try:
            img = Image.open(p); img.load()
        except Exception as e:
            # Very often a download still in flight. Harmless: the next rescan
            # picks it up. Only worth acting on if it persists.
            bad["undecodable"].append(f"{fn}: {e}"); continue
        w, h = img.size
        if w != h or w < a.min_size:
            bad["geometry"].append(f"{fn}: {w}x{h}"); continue
        st = ImageStat.Stat(img.convert("L"))
        sds.append(st.stddev[0])
        if st.stddev[0] < 8:
            bad["blank"].append(f"{fn}: stddev {st.stddev[0]:.1f}"); continue
        cm, cs = corner_stats(img)
        cmeans.append(cm); csds.append(cs)
        # Two conditions, not one. The check exists to catch a failed render — a
        # blank frame, or a photo with a busy background instead of the studio
        # sweep. Uniformity answers that; absolute brightness does not.
        #
        # Measured 2026-07-30 on the full 1,866: six images fell below a flat
        # corner-mean floor of 130 (106 to 129) and ALL SIX were inspected by eye
        # and are correct — cumin water, gond katira cooler, sapota, gujarati
        # kadhi, spinach potato bake, vata yam mung stew. Every one is the right
        # food, in the right style, on a clean backdrop that simply sits at the
        # darker end of the grey the style prompt allows: pale foods and clear
        # drinks need a darker sweep or they disappear into it. Their corner sd
        # was 1.7 to 3.4, against a population median of 1.3 — i.e. among the
        # cleanest backgrounds in the set.
        #
        # So a dark background is accepted when it is uniform. The floor stays
        # only to catch a near-black frame, which is a real failure.
        if cs > a.corner_sd or cm < a.corner_floor:
            bad["background"].append(f"{fn}: corner mean {cm:.0f}, sd {cs:.1f}"); continue
        if cm < a.corner_mean:
            warn_dark.append(f"{fn}: corner mean {cm:.0f}, sd {cs:.1f}")
        ok.append({"filename": fn, "path": p, "name": row["name"], "kind": row["kind"],
                   "frameKey": row["frameKey"], "_d": dhash(img)})

    # ---- global dedup, deterministic winner ---------------------------------
    # Sorted by frameKey so which member of a near-identical pair survives does
    # not depend on directory order. Same inputs, same accepted set, same archive.
    ok.sort(key=lambda r: r["frameKey"])
    kept, seen = [], []
    for r in ok:
        dup = next((k for k in seen if ham(k["_d"], r["_d"]) <= a.hash_distance), None)
        if dup:
            bad["duplicate"].append(f"{r['filename']}: within {a.hash_distance} of {dup['filename']}")
            continue
        seen.append(r); kept.append(r)
    accepted = [{k: v for k, v in r.items() if k != "_d"} | {"dhash": format(r["_d"], "016x")}
                for r in kept]

    # ---- report -------------------------------------------------------------
    nbad = sum(len(v) for v in bad.values())
    print(f"accepted       {len(accepted)} of {len(present)} on disk")
    if nbad:
        print(f"rejected       {nbad}")
        for k, v in sorted(bad.items()):
            print(f"   {k:<12} {len(v)}")
            for x in v[:6]:
                print(f"      {x}")
            if len(v) > 6:
                print(f"      ... and {len(v) - 6} more, full list in rejected/rejects.json")

    # Thresholds you can see are thresholds you can argue with. A silent 90%
    # rejection rate and a silent 0% look identical without these.
    if cmeans:
        if warn_dark:
            print(f"\ndark but clean {len(warn_dark)} accepted below corner mean "
                  f"{a.corner_mean:.0f} — uniform background, so not a failed render")
            for w in warn_dark:
                print(f"   {w}")
        print(f"\nbackground     corner mean p05 {pct(cmeans,5):.0f} / med {pct(cmeans,50):.0f} "
              f"(warn below {a.corner_mean:.0f}, reject below {a.corner_floor:.0f})")
        print(f"               corner sd   med {pct(csds,50):.1f} / p95 {pct(csds,95):.1f} "
              f"(reject above {a.corner_sd:.1f})")
    if present and nbad / len(present) > 0.25:
        print(f"\n  !!  {nbad}/{len(present)} rejected. Above about a quarter this is more likely a "
              f"mis-set\n      threshold than {nbad} bad images. Re-run with --report-only and look at "
              f"a few\n      rejects by eye before changing a number — and if the images really are "
              f"fine,\n      the prompt or the style drifted, which is a generation fix, not a "
              f"threshold fix.")

    if a.report_only:
        print("\n--report-only: nothing written.")
        return

    json.dump({"batch": 0, "source": "validate_all.py", "styleHash": doc.get("styleHash"),
               "planned": len(jobs), "onDisk": len(present), "accepted": accepted},
              open(os.path.join(acc_dir, OURS), "w"), indent=2, ensure_ascii=False)
    rej_dir = os.path.join(DIR, "rejected")
    os.makedirs(rej_dir, exist_ok=True)
    json.dump({k: v for k, v in bad.items()},
              open(os.path.join(rej_dir, "rejects.json"), "w"), indent=2, ensure_ascii=False)

    print(f"\nwrote accepted/{OURS}         {len(accepted)} frames for build_archive2.py")
    print(f"wrote rejected/rejects.json    {nbad} rejections with the number that caused each")
    print("\nRejected rows stay unbuilt and stay in jobs.json, so a later run regenerates them.")
    print("Do NOT lower a threshold to make this pass.")
    # Exit 0 whenever there is anything to build. A partial set is the expected
    # state for the entire life of this pipeline; making that non-zero would mean
    # the archive could never be built until all 1,844 exist, which is precisely
    # the coupling IMG-2 was written to avoid.
    sys.exit(0 if accepted else 1)


if __name__ == "__main__":
    main()
