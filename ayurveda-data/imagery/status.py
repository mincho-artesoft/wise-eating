#!/usr/bin/env python3
"""IMG — reconcile the master job list against everything that might already exist.

    python3 status.py --out ~/wise-eating-images [--downloads ~/Downloads] [--json]

Three places a generated image can be, and this checks all of them:

  1. the output folder            the normal, finished state
  2. Chrome's Downloads folder    downloaded but the move failed or was interrupted
  3. results/ledger.json          what the runner believes it did

A fourth place — the Flow project itself — cannot be reconciled by name. Flow's
media grid does not expose the prompt or filename on the tile (verified against
/inspect: the tiles are anonymous div/a pairs), so a generation that completed
in Flow but was never downloaded is invisible to any name-based check. What you
CAN do is compare the two counts: this script prints how many images it accounts
for, and you compare that with the image count in the Flow project. A gap means
orphans — images you paid for and did not receive.
"""
import argparse, collections, hashlib, json, os, sys

DIR = os.path.dirname(os.path.abspath(__file__))
IMG_EXT = (".jpeg", ".jpg", ".png", ".webp")


def index_folder(folder):
    """basename (no extension) -> full path, for image files only."""
    out = {}
    if not folder or not os.path.isdir(folder):
        return out
    for f in os.listdir(folder):
        if f.startswith("_"):            # _rejected/, _to_delete/ and friends
            continue
        stem, ext = os.path.splitext(f)
        if ext.lower() in IMG_EXT:
            out.setdefault(stem, os.path.join(folder, f))
    return out


def sha(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="the runner's --out folder")
    ap.add_argument("--downloads", default=os.path.expanduser("~/Downloads"))
    ap.add_argument("--jobs", default=os.path.join(DIR, "jobs.json"))
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    a = ap.parse_args()

    if not os.path.exists(a.jobs):
        sys.exit(f"{a.jobs} not found — run build_batches.py first")
    jobs = json.load(open(a.jobs))["jobs"]

    have = index_folder(a.out)
    dl = index_folder(a.downloads)

    done, stranded, missing = [], [], []
    for j in jobs:
        fn = j["output"]["filename"]
        if fn in have:
            done.append(fn)
        elif fn in dl:
            stranded.append(fn)          # generated and downloaded, never moved
        else:
            missing.append(fn)

    # Duplicate detection across everything we have accepted so far. This is the
    # failure that produces a plausible image under the wrong name, so it is worth
    # the full hash pass rather than a sample.
    byhash = collections.defaultdict(list)
    for fn in done:
        byhash[sha(have[fn])].append(fn)
    dupes = {h: v for h, v in byhash.items() if len(v) > 1}

    # Anything in the output folder that no job asked for.
    known = {j["output"]["filename"] for j in jobs}
    orphan_files = sorted(set(have) - known)

    rejected = index_folder(os.path.join(a.out, "_rejected"))

    ledger_path = os.path.join(DIR, "results", "ledger.json")
    ledger = json.load(open(ledger_path)) if os.path.exists(ledger_path) else {}

    if a.json:
        print(json.dumps({"total": len(jobs), "done": len(done), "stranded": stranded,
                          "rejected": sorted(rejected),
                          "missing": len(missing), "duplicateGroups": list(dupes.values()),
                          "unexpectedFiles": orphan_files,
                          "nextFilenames": missing[:10]}, indent=2))
        return

    n = len(jobs)
    print(f"master list        {n} prompts   ({a.jobs})")
    print(f"complete           {len(done)}  ({100*len(done)/n:.1f}%)")
    print(f"still to generate  {len(missing)}")
    if stranded:
        print(f"\nSTRANDED in {a.downloads} — downloaded but never moved: {len(stranded)}")
        print("  these are already paid for; move them into --out rather than regenerating:")
        for f in stranded[:10]:
            print(f"     {f}")
        if len(stranded) > 10:
            print(f"     ... and {len(stranded)-10} more")
    if dupes:
        print(f"\nDUPLICATE IMAGES — {len(dupes)} group(s), same bytes under different names:")
        for v in list(dupes.values())[:6]:
            print(f"     {', '.join(v)}")
        print("  one of each group has the wrong food attached. Delete and re-run those rows.")
    if rejected:
        print(f"\nquarantined in {a.out}/_rejected: {len(rejected)}")
        print("  these were byte-identical to another row — wrong food, correct name.")
        print("  they are excluded from `complete`, so they will be regenerated. Delete the folder when happy.")
    if orphan_files:
        print(f"\nunexpected files in {a.out} (no job asked for these): {len(orphan_files)}")
        for f in orphan_files[:6]:
            print(f"     {f}")
    if ledger:
        print(f"\nledger            {len(ledger)} row(s) recorded by the runner")
        by = collections.Counter(v.get("status") for v in ledger.values())
        print(f"                  {dict(by)}")

    print(f"\nAccounted for here: {len(done) + len(stranded)} image(s).")
    print("Compare that with the image count in the Flow project. Flow's grid does not")
    print("expose the food name, so orphans — generated, never downloaded — can only be")
    print("found by the count difference. A gap is credits spent for nothing.")

    if missing:
        print(f"\nnext up: {', '.join(missing[:5])}{' ...' if len(missing) > 5 else ''}")


if __name__ == "__main__":
    main()
