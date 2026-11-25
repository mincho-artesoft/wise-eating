#!/usr/bin/env python3
"""Extracts all unique recipe steps, recipe guidance, and dravya notes
(prabhava, preparation, contraindications, viruddha) from Ayura/ayurveda_seed.json.gz
into tools/recipe-content/strings.en.json and splits them into 8 translation batches.
"""
import gzip
import json
import math
import pathlib

here = pathlib.Path(__file__).parent
repo = here.parent.parent
work = here / "work"
work.mkdir(parents=True, exist_ok=True)

with gzip.open(repo / "Ayura" / "ayurveda_seed.json.gz", "rt", encoding="utf-8") as f:
    seed = json.load(f)

kinds = {}  # text -> kind label (for translator context)


def add(text, kind):
    if not isinstance(text, str):
        return
    clean = " ".join(text.replace("\r", " ").replace("\n", " ").split()).strip()
    if clean and clean not in kinds:
        kinds[clean] = kind


for r in seed.get("recipes", []):
    for step in r.get("steps", []):
        add(step, "recipe_step")
    add(r.get("guidance"), "recipe_guidance")

for d in seed.get("dravyas", []):
    add(d.get("prabhava"), "dravya_prabhava")
    add(d.get("preparation"), "dravya_preparation")
    for c in d.get("contraindications", []):
        add(c, "contraindication")
    for v in d.get("viruddha", []):
        add(v, "viruddha")

strings = sorted(kinds.keys(), key=lambda s: (s.lower(), s))
(here / "strings.en.json").write_text(json.dumps(strings, ensure_ascii=False, indent=0))

n_batches = 8
batch_size = math.ceil(len(strings) / n_batches)
sizes = []
for b in range(n_batches):
    chunk = strings[b * batch_size : (b + 1) * batch_size]
    items = [{"i": b * batch_size + idx, "k": kinds[s], "s": s} for idx, s in enumerate(chunk)]
    (work / f"batch-{b}.json").write_text(json.dumps(items, ensure_ascii=False, indent=0))
    sizes.append(len(items))

print(f"Extracted {len(strings)} unique strings into {n_batches} batches: {sizes}")
