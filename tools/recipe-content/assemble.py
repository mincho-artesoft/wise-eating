#!/usr/bin/env python3
"""Assembles tools/recipe-content/<language>.json from work/<language>/out-0..7.json."""
import json
import pathlib
import re
import sys

here = pathlib.Path(__file__).parent
work = here / "work"
strings = json.loads((here / "strings.en.json").read_text())
batches = [json.loads((work / f"batch-{i}.json").read_text()) for i in range(8)]
assert [item["s"] for batch in batches for item in batch] == strings


def numbers(text):
    return sorted(re.findall(r"\d+(?:[.,/–-]\d+)*", text))


arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
languages = arguments or sorted(p.name for p in work.iterdir() if p.is_dir())
for language in languages:
    folder = work / language
    table = {}
    problems = []
    bad_ws = 0
    for index, batch in enumerate(batches):
        out_path = folder / f"out-{index}.json"
        if not out_path.exists():
            problems.append(f"batch {index}: missing")
            continue
        try:
            out = json.loads(out_path.read_text())
        except json.JSONDecodeError as e:
            problems.append(f"batch {index}: invalid JSON ({e})")
            continue
        if len(out) != len(batch) or not all(isinstance(x, str) and x.strip() for x in out):
            problems.append(f"batch {index}: len={len(out)} expected={len(batch)}")
            continue
        for item, text in zip(batch, out):
            clean = " ".join(text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split()).strip()
            if not clean:
                clean = item["s"]
                bad_ws += 1
            table[item["s"]] = clean
    if problems:
        print(f"{language}: NOT WRITTEN: {'; '.join(problems)}")
        continue
    ordered = dict(sorted(table.items(), key=lambda kv: (kv[0].lower(), kv[0])))
    (here / f"{language}.json").write_text(json.dumps(ordered, ensure_ascii=False, indent=0))
    print(f"{language}: {len(ordered)} of {len(strings)} strings assembled (fallbacks={bad_ws})")
