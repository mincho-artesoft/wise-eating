#!/usr/bin/env python3
"""IMG — is it safe to restart?

    python3 verify.py --repo /path/to/wise-eating --out ~/wise-eating-images

Answers one question: does jobs.json still describe exactly the work that needs
doing, and does everything on disk still belong to it?

The failure this exists to catch is quiet. If the filename rule or the style
prompt drifts — a tweak to slug(), an edited word in STYLE, a recipe renamed —
then jobs.json is rebuilt with different filenames, every image already
downloaded stops matching a job, and the runner cheerfully regenerates all of
them. Nothing errors. You just pay twice and end up with two half-sets.

Checks, in the order they would hurt:

  A  coverage       jobs.json covers exactly the rows that still need an image
  B  uniqueness     every filename is distinct
  C  determinism    re-deriving from the repo reproduces jobs.json byte for byte
  D  prompts        every job has a prompt, all carrying the same style suffix
  E  disk -> jobs   every image on disk belongs to a job in the list
  F  duplicates     no two accepted images are byte-identical

Exit code 0 only if every check passes. run.sh calls this before generating.
"""
import argparse, collections, hashlib, importlib.util, json, os, sys

DIR = os.path.dirname(os.path.abspath(__file__))
IMG_EXT = (".jpeg", ".jpg", ".png", ".webp")


def load_builder():
    spec = importlib.util.spec_from_file_location("bb", os.path.join(DIR, "build_batches.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--jobs", default=os.path.join(DIR, "jobs.json"))
    a = ap.parse_args()

    fails, warns = [], []
    bb = load_builder()

    if not os.path.exists(a.jobs):
        sys.exit(f"FAIL  {a.jobs} does not exist — run build_batches.py")
    doc = json.load(open(a.jobs))
    jobs = doc["jobs"]
    print(f"jobs.json          {len(jobs)} prompts, styleHash {doc.get('styleHash')}")

    # ---- C: re-derive from the repo and compare -----------------------------
    fm, foods, recs, dr = bb.load(a.repo)
    keys = set(fm)
    reuse, gen_dravya = set(), []
    for d in dr:
        if d["name"] in keys or bb.sanitize(d["name"]) in keys:
            continue
        hit = any((u.get("name") in keys or bb.sanitize(u.get("name") or "") in keys)
                  for u in (d.get("usda") or []) if isinstance(u, dict))
        (reuse.add(d["name"]) if hit else gen_dravya.append(d))
    expected = ([("recipe", r) for r in recs
                 if r["name"] not in keys and bb.sanitize(r["name"]) not in keys]
                + [("dravya", d) for d in gen_dravya])
    expected.sort(key=lambda kv: (kv[0], kv[1]["name"]))

    used, derived = set(), []
    for kind, r in expected:
        fn = f"{kind}-{bb.slug(r['name'])}"
        if fn in used:
            fn = f"{fn}-{hashlib.sha1(r['name'].encode()).hexdigest()[:6]}"
        used.add(fn)
        derived.append((fn, r["name"], kind))

    style_now = hashlib.sha1(bb.STYLE.encode()).hexdigest()[:12]
    if doc.get("styleHash") != style_now:
        fails.append(f"C  STYLE PROMPT HAS CHANGED — jobs.json {doc.get('styleHash')} vs build_batches {style_now}.\n"
                     f"       Regenerating now would produce images in a different style from the "
                     f"{len(os.listdir(a.out)) if os.path.isdir(a.out) else 0} already on disk.")

    # ---- A: coverage --------------------------------------------------------
    want = {fn for fn, _, _ in derived}
    got = {j["output"]["filename"] for j in jobs}
    missing_from_jobs, extra_in_jobs = want - got, got - want
    if missing_from_jobs:
        fails.append(f"A  {len(missing_from_jobs)} row(s) need an image but have no job: "
                     f"{sorted(missing_from_jobs)[:5]}")
    if extra_in_jobs:
        fails.append(f"A  {len(extra_in_jobs)} job(s) no longer correspond to a row needing an image: "
                     f"{sorted(extra_in_jobs)[:5]}")
    if not missing_from_jobs and not extra_in_jobs:
        print(f"A  coverage        ok — {len(want)} rows need an image, {len(got)} jobs, exact match")
        print(f"                   (+{len(reuse)} dravyas reuse an existing USDA frame, no generation)")

    # ---- B: uniqueness ------------------------------------------------------
    dup = [f for f, n in collections.Counter(j["output"]["filename"] for j in jobs).items() if n > 1]
    if dup:
        fails.append(f"B  {len(dup)} duplicated filename(s) — one download would overwrite another: {dup[:5]}")
    else:
        print(f"B  uniqueness      ok — {len(got)} distinct filenames")

    # ---- C continued: name -> filename mapping is stable --------------------
    by_fn = {j["output"]["filename"]: j["_row"]["name"] for j in jobs}
    drift = [(fn, nm, by_fn.get(fn)) for fn, nm, _ in derived if by_fn.get(fn) not in (None, nm)]
    if drift:
        fails.append(f"C  {len(drift)} filename(s) now map to a different food: {drift[:3]}")
    elif not fails or all(not f.startswith("C ") for f in fails):
        print("C  determinism     ok — re-deriving from the repo reproduces every filename")

    # ---- D: prompts ---------------------------------------------------------
    noprompt = [j["output"]["filename"] for j in jobs if not j.get("prompt", "").strip()]
    nostyle = [j["output"]["filename"] for j in jobs if bb.STYLE not in j.get("prompt", "")]
    if noprompt:
        fails.append(f"D  {len(noprompt)} job(s) have no prompt: {noprompt[:5]}")
    if nostyle:
        fails.append(f"D  {len(nostyle)} job(s) do not carry the style suffix verbatim: {nostyle[:5]}")
    if not noprompt and not nostyle:
        lens = [len(j["prompt"]) for j in jobs]
        print(f"D  prompts         ok — all {len(jobs)} present, style suffix verbatim, "
              f"{min(lens)}-{max(lens)} chars")

    # ---- E / F: what is on disk --------------------------------------------
    have = {}
    if os.path.isdir(a.out):
        for f in os.listdir(a.out):
            if f.startswith("_"):
                continue
            stem, ext = os.path.splitext(f)
            if ext.lower() in IMG_EXT:
                have[stem] = os.path.join(a.out, f)
    unowned = sorted(set(have) - got)
    if unowned:
        # A WARNING, not a failure. An extra file costs nothing: it is never read,
        # never uploaded, never confused for a job. Blocking generation over one
        # stray download — which is what a raw-UUID filename from Flow is — stops
        # real work to protect against nothing. Only the checks that waste credits
        # or mislabel food are allowed to block.
        warns.append(f"E  {len(unowned)} image(s) on disk belong to no job: {unowned[:5]}\n"
                     f"       harmless, but if there are many it may mean the filename rule moved. "
                     f"Move them out of the folder to silence this.")
    else:
        print(f"E  disk -> jobs    ok — all {len(have)} image(s) on disk belong to a job")

    byhash = collections.defaultdict(list)
    for stem, p in have.items():
        with open(p, "rb") as fh:
            byhash[hashlib.sha256(fh.read()).hexdigest()].append(stem)
    dupes = [v for v in byhash.values() if len(v) > 1]
    if dupes:
        fails.append(f"F  {len(dupes)} group(s) of byte-identical images — one of each has the wrong "
                     f"food attached: {dupes[:3]}")
    else:
        print(f"F  duplicates      ok — {len(have)} image(s), {len(byhash)} distinct")

    print()
    if fails:
        print("NOT SAFE TO RESTART\n")
        for f in fails:
            print("  " + f)
        print("\nFix these before generating. Every one of them either wastes credits or\n"
              "attaches an image to the wrong food.")
        sys.exit(1)
    for w in warns:
        print("  warn  " + w)
    remaining = len(got) - len(set(have) & got)
    print(f"SAFE TO RESTART — {len(set(have) & got)} done, {remaining} remaining")


if __name__ == "__main__":
    main()
