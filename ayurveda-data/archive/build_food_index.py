#!/usr/bin/env python3
"""Build foods_index.csv — one stable id per food, across both archives.

    python3 build_food_index.py --repo /path/to/wise-eating \
        --usda-csv "/path/to/generated images/foods_names_with_id.csv" \
        --out foods_index.csv

WHY THIS FILE EXISTS
--------------------
Today a frame is addressed by a sanitised name. That is why FIX-1 existed (a `%`
in a name orphaned its image), why `sanitize()` has to stay byte-identical
forever, and why renaming a food silently detaches its picture. A stable integer
id fixes all three at once.

This builds the id table without changing anything yet: every existing archive-1
row keeps the id it already had in foods_names_with_id.csv, and the sanitised
frame key is carried alongside so both addressing schemes work during migration.

WHICH CSV IS AUTHORITATIVE — this matters
-----------------------------------------
There are two copies of foods_names_with_id.csv and they disagree on 269 ids.
Verified against Ayura/Food/frame_map.json:

  gemini-food-stylist/generated images/foods_names_with_id.csv
      12,601 rows -> sanitises to exactly the 12,601 frame_map keys.
      Perfect bijection: 0 unmatched, 0 uncovered.  <-- USE THIS ONE

  gemini-food-stylist/foods_names_with_id.csv
      12,625 rows, 25 of which have no frame at all (Cheese fontina, Cheese
      provolone, Broccoli chinese, ...), and 269 shared ids naming a different
      food.  Using it to key frames would give 269 foods someone else's picture.

The script re-verifies the bijection every run and refuses to write if it breaks.

COLUMNS
-------
  id           stable, never reused. 1..12622 are the existing USDA ids,
               untouched. New rows start at 13001 so the boundary is obvious.
  name         the food name as written
  kind         usda | recipe | dravya
  frame_key    the sanitised name currently used as the frame_map key
  archive      1 = in food_archive_*.mp4 today (includes reuse-map dravyas that
               borrow an archive-1 frame), 2 = to be encoded into archive 2
  frame_index  archive-1 rows only.

frame_index is deliberately BLANK for archive 2. Archive 2's indices shift on
every rebuild — that is the whole reason map and archive must ship as a matched
pair — so writing a number here would be a lie with a shelf life.
"""
import argparse, csv, json, os, re, sys

SAN = re.compile(r'[/\\:*?"<>|]')


def sanitize(name):
    return SAN.sub("_", name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--usda-csv", required=True)
    ap.add_argument("--jobs", help="imagery/jobs.json (default: <repo>/ayurveda-data/imagery/jobs.json)")
    ap.add_argument("--reuse", help="imagery/reuse-map.json")
    ap.add_argument("--out", default="foods_index.csv")
    ap.add_argument("--new-id-base", type=int, default=13001)
    a = ap.parse_args()

    jobs_p = a.jobs or os.path.join(a.repo, "ayurveda-data/imagery/jobs.json")
    reuse_p = a.reuse or os.path.join(a.repo, "ayurveda-data/imagery/reuse-map.json")
    fmap = json.load(open(os.path.join(a.repo, "Ayura/Food/frame_map.json")))

    usda = list(csv.DictReader(open(a.usda_csv)))
    keys = {sanitize(r["name"]) for r in usda}
    unmatched = [r["name"] for r in usda if sanitize(r["name"]) not in fmap]
    uncovered = sorted(set(fmap) - keys)
    if unmatched or uncovered:
        sys.exit(
            f"REFUSING TO WRITE — {a.usda_csv} is not the CSV archive 1 was built from.\n"
            f"  {len(unmatched)} row(s) sanitise to a key that is not in frame_map.json"
            f"{': ' + str(unmatched[:3]) if unmatched else ''}\n"
            f"  {len(uncovered)} frame_map key(s) have no row"
            f"{': ' + str(uncovered[:3]) if uncovered else ''}\n"
            f"Use 'gemini-food-stylist/generated images/foods_names_with_id.csv'. The copy one\n"
            f"directory up has 25 extra foods and disagrees on 269 ids; keying frames with it\n"
            f"would attach the wrong picture to 269 foods.")

    rows = []
    seen_names = set()
    for r in usda:
        k = sanitize(r["name"])
        rows.append({"id": int(r["id"]), "name": r["name"], "kind": "usda",
                     "frame_key": k, "archive": 1, "frame_index": fmap[k]})
        seen_names.add(r["name"])

    nxt = max(a.new_id_base, max(x["id"] for x in rows) + 1)

    # reuse-map dravyas: real foods that borrow an archive-1 frame, no generation
    reuse = json.load(open(reuse_p)) if os.path.exists(reuse_p) else {}
    for name in sorted(reuse):
        if name in seen_names:
            continue
        k = reuse[name].get("frameKey")
        if k not in fmap:
            sys.exit(f"reuse-map points {name!r} at {k!r}, which is not in frame_map.json")
        rows.append({"id": nxt, "name": name, "kind": "dravya",
                     "frame_key": k, "archive": 1, "frame_index": fmap[k]})
        seen_names.add(name)
        nxt += 1

    # everything still to be generated
    jobs = json.load(open(jobs_p))["jobs"]

    # jobs.json guarantees unique FILENAMES — build_batches.py appends a content
    # hash when slugs collide — but it does not guarantee unique frameKeys, and
    # the frameKey is what addresses the frame. Two jobs sharing one frameKey
    # means two images encoded and one silently shadowing the other in
    # frame_map2, i.e. a food showing the wrong picture. Nothing downstream
    # catches this: build_archive2.py only checks archive 2 against map 1, and
    # its frame-count assertion still passes because the count is right and only
    # the map is short.
    bykey = {}
    for j in jobs:
        bykey.setdefault(j["_row"]["frameKey"], []).append(j)
    clashes = {k: v for k, v in bykey.items() if len(v) > 1}
    if clashes:
        msg = [f"REFUSING TO WRITE — {len(clashes)} frameKey(s) are claimed by more than one job.",
               "Each would encode two frames and keep one at random; the other food shows the",
               "wrong picture. Fix the source data (rename one), rebuild jobs.json, re-run.", ""]
        for k, v in sorted(clashes.items()):
            msg.append(f"  {k!r}")
            for j in v:
                msg.append(f"      {j['_row']['kind']:<7} {j['output']['filename']}")
        sys.exit("\n".join(msg))

    for j in sorted(jobs, key=lambda j: (j["_row"]["kind"], j["_row"]["name"])):
        row = j["_row"]
        if row["name"] in seen_names:
            sys.exit(f"job {row['name']!r} duplicates a name already claimed by an archive-1 row; "
                     f"resolve in the source data rather than here")
        rows.append({"id": nxt, "name": row["name"], "kind": row["kind"],
                     "frame_key": row["frameKey"], "archive": 2, "frame_index": ""})
        seen_names.add(row["name"])
        nxt += 1

    ids = [r["id"] for r in rows]
    assert len(set(ids)) == len(ids), "duplicate id generated"
    fk = [(r["archive"], r["frame_key"]) for r in rows if r["archive"] == 2]
    assert len(set(fk)) == len(fk), "duplicate archive-2 frame_key"

    with open(a.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["id", "name", "kind", "frame_key",
                                           "archive", "frame_index"])
        w.writeheader()
        w.writerows(rows)

    n1 = sum(1 for r in rows if r["archive"] == 1)
    print(f"verified   {len(usda)} USDA rows <-> {len(fmap)} frame_map keys, exact bijection")
    print(f"wrote      {a.out}   {len(rows)} rows")
    print(f"  archive 1  {n1}   ({len(usda)} usda + {n1 - len(usda)} dravyas reusing a frame)")
    for k in ("recipe", "dravya"):
        c = sum(1 for r in rows if r["archive"] == 2 and r["kind"] == k)
        print(f"  archive 2  {c:<6} {k}")
    print(f"  id range   {min(ids)}-{max(ids)}, new ids from {a.new_id_base}")


if __name__ == "__main__":
    main()
