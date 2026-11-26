#!/usr/bin/env python3
"""Writes strings.en.json and work/batch-N.json: everything a person reads in
the 60 practices (meditation, pranayama, relaxation, visualisation, kriya) -
titles, descriptions, sources, cautions, the labels the list is filtered and
searched by, and the 601 spoken cues, practice by practice and in order."""
import json
import pathlib
import sys

here = pathlib.Path(__file__).parent
sys.path.insert(0, str(here.parent))
import translation_batches as tb

practices = json.loads((here.parent.parent / "Ayura" / "Practices" / "Data" / "practices.json").read_text())

items = []
for kind, field in [("kind", "kind"), ("posture", "posture"), ("eyes", "eyes"), ("guna", "guna"),
                    ("agni_effect", "agni"), ("time_of_day", "timeOfDay"), ("season", "season"),
                    ("goal", "goals"), ("technique", "technique"), ("theme", "themes")]:
    values = set()
    for p in practices:
        value = p[field]
        values.update(value if isinstance(value, list) else [value])
    items += [{"k": kind, "p": "labels", "s": v} for v in sorted(values)]
for p in practices:
    slug, name = p["slug"], p["title"]
    items.append({"k": "title", "p": slug, "s": p["title"]})
    if p.get("sanskrit"):
        items.append({"k": "sanskrit", "p": slug, "s": p["sanskrit"], "in": name})
    items.append({"k": "description", "p": slug, "s": tb.clean(p["desc"])})
    items.append({"k": "source", "p": slug, "s": tb.clean(p["sourceTradition"])})
    for caution in p["contraindications"]:
        items.append({"k": "caution", "p": slug, "s": tb.clean(caution)})
    for number, cue in enumerate(p["script"]):
        items.append({"k": "cue", "p": slug, "n": number, "hold": cue["hold"], "s": tb.clean(cue["text"])})

tb.write_batches(here, items, 4)
