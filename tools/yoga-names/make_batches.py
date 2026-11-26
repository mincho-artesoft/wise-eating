#!/usr/bin/env python3
"""Writes work/batch-N.json from segments.en.json for the translators: every
string once, each pose title beside its Sanskrit name so that both are read
together. Run build_segments.py first when the catalogue has changed."""
import json
import pathlib
import sys

here = pathlib.Path(__file__).parent
sys.path.insert(0, str(here.parent))
import translation_batches as tb

asanas = json.loads((here.parent.parent / "ayurveda-data" / "yoga" / "asanas.json").read_text())
segments = json.loads((here / "segments.en.json").read_text())

items = []
for value in sorted({a["family"] for a in asanas}):
    items.append({"k": "family", "s": value})
for value in sorted({m for a in asanas for m in a["muscleGroups"]}):
    items.append({"k": "muscle_group", "s": value})
for value in ["Beginner", "Intermediate", "Advanced", "Easy", "Level 1", "Level 2", "Level 3", "Workout"]:
    items.append({"k": "level", "s": value})
for a in sorted(asanas, key=lambda a: (a["family"], a["title"])):
    items.append({"k": "pose", "s": a["title"], "in": a.get("sanskrit")})
    for part in (a.get("sanskrit") or "").split(", "):
        if part.strip():
            items.append({"k": "sanskrit", "s": part.strip(), "in": a["title"]})

assert {item["s"] for item in items} == set(segments), "segments.en.json is stale: run build_segments.py"
tb.write_batches(here, items, 2, "segments.en.json")
