#!/usr/bin/env python3
"""IMG-1 — build Flow batch files for every catalogue row that has no image.

Emits queue/batch-NNN.json, 100 rows each. Deterministic: same inputs, same
batches, same order, so a re-run after a partial failure produces identical
files and you can diff them.

    python3 build_batches.py --repo /path/to/wise-eating [--size 100]

Writes:
    imagery/queue/batch-001.json ...      to be consumed by runner.js
    imagery/reuse-map.json                dravya -> existing USDA frame, no generation
    imagery/MANIFEST.json                 what was planned, for validate_batch.py
"""
import argparse, glob, json, os, re, sys, hashlib

STYLE = (
 "A Michelin 5-star food presentation, photorealistic, ultra-high detail, professional studio lighting. "
 "The dish should be centered and fully visible, captured from a slight top-down (45°) angle. "
 "Present the food in a clean, minimal serving vessel appropriate to its texture: "
 "liquids or pourable foods → shown in a clear glass, cup, or bottle; "
 "creamy or semi-solid foods → shown in a bowl, cup, or parfait glass; "
 "solid foods → shown on a clean white ceramic plate. "
 "Use a plain, neutral background (white, gray, or soft gradient). "
 "No wood surfaces, no cutting boards, no textured tables, no additional props. "
 "No text, labels, or logos. Entire vessel visible with natural soft shadows."
)
# Verbatim from gemini-food-stylist/App.tsx. Do not paraphrase it: the 12,601
# images already in food_archive_1024.mp4 were generated from this exact text,
# and the new frames have to sit beside them without looking like a second set.

SETTINGS = {"aspectRatio": "1:1", "model": "Nano Banana 2"}


def sanitize(name):
    """The transform the original pipeline applied when it built frame_map keys.

    Measured against the real data, not guessed: keys were derived from FILENAMES,
    so the filesystem-unsafe set became "_" and nothing else did. Replacing "%" —
    which an earlier version of this file did — corrupted names that were already
    correct and left 1,023 rows unable to find their frame. Full set: 0 unmatched
    of 12,601. See TASK-FIX1.md.
    """
    return re.sub(r'[/\\:*?"<>|]', "_", name)


def slug(name):
    s = re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-").lower()
    return s[:70] or "row"


def load(repo):
    fm = json.load(open(f"{repo}/WiseEating/Food/frame_map.json"))
    foods = json.load(open(f"{repo}/WiseEating/Legacy/foods.json"))
    recs, dr = [], []
    for f in sorted(glob.glob(f"{repo}/ayurveda-data/recipes/batch-r*.json")):
        d = json.load(open(f))
        recs += d if isinstance(d, list) else d.get("recipes", d.get("items", []))
    for f in sorted(glob.glob(f"{repo}/ayurveda-data/dravyas/batch-*.json")):
        d = json.load(open(f))
        dr += d if isinstance(d, list) else d.get("dravyas", d.get("items", []))
    return fm, foods, recs, dr


def subject_prompt(row, kind):
    """The subject clause. The style clause is appended identically to every row."""
    if kind == "recipe":
        ings = [i.get("name", i) if isinstance(i, dict) else i for i in (row.get("ingredients") or [])][:6]
        base = row["name"]
        if ings:
            base += ", made with " + ", ".join(str(i) for i in ings)
        meal = row.get("meal")
        if meal in ("drink", "dessert"):
            base += f", served as a {meal}"
        return base
    return row["name"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--size", type=int, default=100)
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--batches", action="store_true",
                    help="also emit the legacy queue/batch-NNN.json split")
    a = ap.parse_args()

    fm, foods, recs, dr = load(a.repo)
    keys = set(fm)

    # ---- free win: dravyas whose usda[] link already has a frame ----
    reuse, gen_dravya = {}, []
    for d in dr:
        if d["name"] in keys or sanitize(d["name"]) in keys:
            continue
        hit = None
        for u in (d.get("usda") or []):
            n = u.get("name") if isinstance(u, dict) else None
            if n and (n in keys or sanitize(n) in keys):
                hit = {"frameKey": n if n in keys else sanitize(n), "tier": u.get("tier")}
                break
        if hit:
            reuse[d["name"]] = hit
        else:
            gen_dravya.append(d)

    gen = ([("recipe", r) for r in recs if r["name"] not in keys and sanitize(r["name"]) not in keys]
           + [("dravya", d) for d in gen_dravya])
    gen.sort(key=lambda kv: (kv[0], kv[1]["name"]))

    qdir = os.path.join(a.out, "queue")
    os.makedirs(qdir, exist_ok=True)

    rows, manifest, used = [], [], set()
    for kind, r in gen:
        fn = f"{kind}-{slug(r['name'])}"
        if fn in used:
            # Slugging is lossy: "Ghee (Clarified Butter)" and "Ghee, clarified butter"
            # collapse to the same string. A collision would mean one download
            # silently overwriting another, so disambiguate by content hash.
            fn = f"{fn}-{hashlib.sha1(r['name'].encode()).hexdigest()[:6]}"
        used.add(fn)
        rows.append({
            "id": f"img-{hashlib.sha1(r['name'].encode()).hexdigest()[:10]}",
            "type": "image",
            "prompt": subject_prompt(r, kind) + ". " + STYLE,
            "settings": dict(SETTINGS),
            "output": {"filename": fn, "quality": "original"},
            "_row": {"kind": kind, "name": r["name"], "frameKey": sanitize(r["name"])},
        })
        manifest.append({"filename": fn, "kind": kind, "name": r["name"],
                         "frameKey": sanitize(r["name"])})

    style_hash = hashlib.sha1(STYLE.encode()).hexdigest()[:12]

    # ONE master file holding every prompt. The runner walks it, skips whatever is
    # already on disk, and stops after --limit new rows. Batches stopped being a
    # useful unit once resume worked: a "batch" is now just how many you choose to
    # run in one sitting, not a partition baked into the files.
    json.dump({"count": len(rows), "createdBy": "build_batches.py", "styleHash": style_hash,
               "jobs": rows},
              open(os.path.join(a.out, "jobs.json"), "w"), indent=2, ensure_ascii=False)

    batches = [rows[i:i + a.size] for i in range(0, len(rows), a.size)]
    if a.batches:
        for i, b in enumerate(batches, 1):
            path = os.path.join(qdir, f"batch-{i:03d}.json")
            json.dump({"batch": i, "count": len(b), "createdBy": "build_batches.py",
                       "styleHash": style_hash, "jobs": b}, open(path, "w"), indent=2, ensure_ascii=False)

    json.dump(reuse, open(os.path.join(a.out, "reuse-map.json"), "w"), indent=2, ensure_ascii=False)
    json.dump({"totalToGenerate": len(rows), "batchSize": a.size, "batches": len(batches),
               "reuseWithoutGeneration": len(reuse),
               "styleHash": hashlib.sha1(STYLE.encode()).hexdigest()[:12],
               "rows": manifest},
              open(os.path.join(a.out, "MANIFEST.json"), "w"), indent=2, ensure_ascii=False)

    print(f"reuse without generation : {len(reuse)}")
    print(f"rows to generate         : {len(rows)}  ({sum(1 for k,_ in gen if k=='recipe')} recipes, "
          f"{sum(1 for k,_ in gen if k=='dravya')} dravyas)")
    print(f"master file              : {os.path.join(a.out, 'jobs.json')}")
    if a.batches:
        print(f"legacy batches of {a.size:<3}    : {len(batches)}  -> {qdir}")


if __name__ == "__main__":
    main()
