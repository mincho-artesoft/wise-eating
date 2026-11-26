#!/usr/bin/env python3
"""Writes strings.en.json and work/batch-N.json: the yoga text that is not a
name - the pose descriptions, the breath, gaze and caution labels of a pose,
and the parts a sequence's title and note are put together from."""
import json
import pathlib
import sys

here = pathlib.Path(__file__).parent
sys.path.insert(0, str(here.parent))
import translation_batches as tb

yoga = here.parent.parent / "ayurveda-data" / "yoga"
asanas = json.loads((yoga / "asanas.json").read_text())
sequences = json.loads((yoga / "sequences.json").read_text())

items = []
for kind, values in [
    ("breath", {a["breath"] for a in asanas}),
    ("gaze", {a["drishti"] for a in asanas}),
    ("pose_caution", {c for a in asanas for c in a["contraindications"]}),
    ("sequence_school", {s["school"] for s in sequences}),
    ("sequence_intent", {s["intent"] for s in sequences}),
    ("sequence_season", {s["season"] for s in sequences}),
    ("sequence_stage", {p["stage"] for s in sequences for p in s["poses"]}),
    # A sequence's note is two of these sentences joined by a space.
    ("sequence_note_sentence", {part.strip() for s in sequences
                                for part in s["note"].replace(". ", ".|").split("|")}),
]:
    items += [{"k": kind, "s": tb.clean(v)} for v in sorted(values)]
# "Hatha Energising — 15 min — Level 1 — Vasanta": the two fixed words.
items += [{"k": "sequence_title_word", "s": "min"}, {"k": "sequence_title_word", "s": "Level"}]
for a in sorted(asanas, key=lambda a: (a["family"], a["title"])):
    items.append({"k": "pose_description", "s": tb.clean(a["desc"]),
                  "in": f'{a["title"]} ({a["sanskrit"]})' if a.get("sanskrit") else a["title"]})

tb.write_batches(here, items, 4)
