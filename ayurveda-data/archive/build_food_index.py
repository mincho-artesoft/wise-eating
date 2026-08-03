#!/usr/bin/env python3
"""Build the DB-id to unified-video-frame index.

The app owns `ZFOODITEM.ZID`; Gemini CSV ids are provenance only and must never
be used at runtime.  This command is deliberately run against the final preseed
because the Ayurveda placeholder band can be renumbered by a source rebuild.

    python3 build_food_index.py --repo ~/work/wise-eating \
        --store /tmp/default.store \
        --usda-csv ".../generated images/foods_names_with_id.csv"

It writes a reviewable foods_index.csv and the exact frame_index.json shipped by
the app.  Every catalogue row must resolve.  The twelve retained physical
orphans are a reviewed JOB4 inventory and are asserted by name; any other
unaddressed frame is a build failure.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


SANITIZE = re.compile(r'[/\\:*?"<>|]')
EXPECTED_ORPHAN_FRAME_KEYS = {
    "Black mustard seed",
    "Curry leaf powder",
    "Dosa",
    "Grapes",
    "Lamb",
    "Lotus seeds (makhana)",
    "Rice kheer",
    "Rice, brown",
    "Sardine",
    "Spiced buttermilk (takra)",
    "Sweet potato",
    "Wheat, whole grain",
}


def nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value)


def frame_key(value: str) -> str:
    return SANITIZE.sub("_", nfc(value))


def unique_normalized_map(rows, label):
    result = {}
    for key, value in rows:
        normalized = nfc(key)
        if normalized in result:
            raise RuntimeError(f"{label} has duplicate NFC key {normalized!r}")
        result[normalized] = (key, value)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--store", required=True, type=Path)
    parser.add_argument(
        "--usda-csv",
        type=Path,
        help="optional Gemini source-id provenance; never used as the runtime key",
    )
    parser.add_argument("--reuse", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--frame-index-out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = args.repo.expanduser().resolve()
    store = args.store.expanduser().resolve()
    out = args.out or repo / "ayurveda-data/archive/foods_index.csv"
    frame_index_out = args.frame_index_out or repo / "Ayura/Food/frame_index.json"
    reuse_path = args.reuse or repo / "ayurveda-data/imagery/reuse-map.json"
    frame_map_path = repo / "Ayura/Food/frame_map.json"

    for path, label in (
        (store, "preseed store"),
        (reuse_path, "reviewed reuse map"),
        (frame_map_path, "frame map"),
    ):
        if not path.is_file():
            sys.exit(f"missing {label}: {path}")

    frame_map_raw = json.loads(frame_map_path.read_text(encoding="utf-8"))
    reuse_raw = json.loads(reuse_path.read_text(encoding="utf-8"))
    expected_slots = set(range(len(frame_map_raw)))
    actual_slots = set(frame_map_raw.values())
    if actual_slots != expected_slots or len(actual_slots) != len(frame_map_raw):
        sys.exit(
            "REFUSING TO WRITE — frame_map.json is not a one-to-one physical "
            "inventory covering 0...N-1"
        )
    frame_map = unique_normalized_map(frame_map_raw.items(), "frame_map.json")
    reuse = unique_normalized_map(reuse_raw.items(), "reuse-map.json")

    with sqlite3.connect(f"file:{store}?mode=ro", uri=True) as connection:
        foods = connection.execute(
            "SELECT ZID, ZNAME FROM ZFOODITEM ORDER BY ZID"
        ).fetchall()
        profiles = dict(
            connection.execute("SELECT ZFOODID, ZKIND FROM ZAYURVEDAPROFILE")
        )

    legacy_ids = {}
    if args.usda_csv:
        with args.usda_csv.expanduser().open(newline="") as stream:
            source_rows = list(csv.DictReader(stream))
        for row in source_rows:
            key = nfc(row["name"])
            if key in legacy_ids:
                sys.exit(f"Gemini CSV has duplicate NFC name {key!r}")
            legacy_ids[key] = row["id"]
        if len(source_rows) != 12_601:
            sys.exit(
                f"wrong Gemini CSV: expected 12601 rows, found {len(source_rows)} at "
                f"{args.usda_csv}"
            )

    rows = []
    frame_index = {}
    resolution_counts = Counter()
    unresolved = []
    for db_id, name in foods:
        normalized_name = nfc(name)
        candidates = (normalized_name, frame_key(normalized_name))
        resolved = None

        for candidate in candidates:
            if candidate in frame_map:
                physical_key, index = frame_map[candidate]
                resolved = (physical_key, index, "direct")
                break

        if resolved is None:
            reference = None
            for candidate in candidates:
                if candidate in reuse:
                    _, reference = reuse[candidate]
                    break
            if reference is not None:
                borrowed = nfc(reference["frameKey"])
                target = frame_map.get(borrowed) or frame_map.get(frame_key(borrowed))
                if target is not None:
                    physical_key, index = target
                    resolved = (physical_key, index, "reviewed-reuse")

        if resolved is None:
            unresolved.append((db_id, name))
            continue

        physical_key, index, route = resolved
        kind = profiles.get(db_id, "usda")
        legacy_id = legacy_ids.get(normalized_name, "") if kind == "usda" else ""
        rows.append(
            {
                "id": legacy_id,
                "db_id": db_id,
                "name": name,
                "kind": kind,
                "frame_key": physical_key,
                "archive": 1,
                "frame_index": index,
                "resolution": route,
            }
        )
        frame_index[str(db_id)] = index
        resolution_counts[route] += 1

    if unresolved:
        details = "\n".join(f"  {db_id}: {name}" for db_id, name in unresolved)
        sys.exit(
            f"REFUSING TO WRITE — {len(unresolved)} DB food(s) have no frame:\n{details}"
        )
    if len(rows) != len(foods) or len(frame_index) != len(foods):
        sys.exit("REFUSING TO WRITE — DB-id resolution is not one row per FoodItem")

    by_index = defaultdict(list)
    for row in rows:
        by_index[row["frame_index"]].append((row["db_id"], row["name"]))
    physical_keys_by_index = {value: key for key, value in frame_map_raw.items()}
    orphan_indices = set(physical_keys_by_index) - set(by_index)
    orphan_keys = {physical_keys_by_index[index] for index in orphan_indices}
    if orphan_keys != EXPECTED_ORPHAN_FRAME_KEYS:
        sys.exit(
            "REFUSING TO WRITE — retained orphan inventory changed.\n"
            f"  missing expected: {sorted(EXPECTED_ORPHAN_FRAME_KEYS - orphan_keys)}\n"
            f"  unexpected: {sorted(orphan_keys - EXPECTED_ORPHAN_FRAME_KEYS)}"
        )

    shared = {index: members for index, members in by_index.items() if len(members) > 1}
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(
            output,
            fieldnames=list(rows[0]),
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)
    frame_index_out.parent.mkdir(parents=True, exist_ok=True)
    frame_index_out.write_text(
        json.dumps(frame_index, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )

    print(f"DB catalogue      : {len(foods)}")
    print(f"physical frames   : {len(frame_map_raw)}")
    print(f"resolved DB ids   : {len(frame_index)} (unresolved 0)")
    print(
        "routes            : "
        + ", ".join(f"{key} {value}" for key, value in sorted(resolution_counts.items()))
    )
    print(
        f"addressed slots   : {len(by_index)}; shared slots {len(shared)} "
        f"({sum(len(members) - 1 for members in shared.values())} extra DB ids)"
    )
    print(f"retained orphans  : {len(orphan_keys)} (exact reviewed JOB4 inventory)")
    print(f"wrote             : {out}")
    print(f"wrote             : {frame_index_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
