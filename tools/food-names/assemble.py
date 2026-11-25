#!/usr/bin/env python3
"""Builds <language>.json from the translators' and reviewers' files.

  assemble.py                 every language folder under work/
  assemble.py de ja           only these

For each language it reads work/<language>/out-0..7.json (translations,
aligned with work/batch-0..7.json) and fixes-0..7.json (the reviewer's
corrections), applies each correction whose English matches and whose numbers
survive, and writes <language>.json when all eight batches are complete. A
language with a missing or short batch is reported and skipped, and so is one
whose reviewer never ran, unless --unreviewed is given.
"""
import json
import pathlib
import re
import sys

here = pathlib.Path(__file__).parent
work = here / "work"
segments = json.loads((here / "segments.en.json").read_text())
batches = [json.loads((work / f"batch-{i}.json").read_text()) for i in range(8)]
assert [item["s"] for batch in batches for item in batch] == segments


def numbers(text):
    return sorted(re.findall(r"\d+(?:[.,/]\d+)*", text))


arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
allow_unreviewed = "--unreviewed" in sys.argv
languages = arguments or sorted(p.name for p in work.iterdir() if p.is_dir())
for language in languages:
    folder = work / language
    table = {}
    problems = []
    applied = rejected = unreviewed = number_issues = 0
    for index, batch in enumerate(batches):
        out_path = folder / f"out-{index}.json"
        if not out_path.exists():
            problems.append(f"batch {index}: no translation")
            continue
        try:
            out = json.loads(out_path.read_text())
        except json.JSONDecodeError as error:
            problems.append(f"batch {index}: does not parse ({error})")
            continue
        if len(out) != len(batch) or not all(isinstance(x, str) for x in out):
            problems.append(f"batch {index}: {len(out)} translations for {len(batch)} segments")
            continue
        for item, text in zip(batch, out):
            table[item["s"]] = text.strip()
        fixes_path = folder / f"fixes-{index}.json"
        if not fixes_path.exists():
            unreviewed += 1
            continue
        by_number = {item["i"]: item["s"] for item in batch}
        for fix in json.loads(fixes_path.read_text()):
            english = by_number.get(fix.get("i"))
            new = str(fix.get("fix", "")).strip()
            if english is None or english != fix.get("en") or not new or "\n" in new \
                    or numbers(new) != numbers(english):
                rejected += 1
                continue
            if table[english] != new:
                table[english] = new
                applied += 1
    for english, text in list(table.items()):
        if numbers(text) != numbers(english) or "\n" in text or "\t" in text:
            # Not shippable as it stands: fall back to English for this segment.
            table[english] = english
            number_issues += 1
    status = (f"{language}: {len(table)} of {len(segments)} segments, {applied} corrections applied, "
              f"{rejected} rejected, {number_issues} left in English (numbers changed), "
              f"{unreviewed} batches unreviewed")
    if problems or (unreviewed and not allow_unreviewed):
        print(status + " -- NOT WRITTEN" + (": " + "; ".join(problems) if problems else ""))
        continue
    overrides_path = folder / "overrides.json"
    overrides = {}
    if overrides_path.exists():
        try:
            raw_ov = json.loads(overrides_path.read_text())
            if isinstance(raw_ov, dict):
                seg_set = set(segments)
                for key, val in raw_ov.items():
                    if not isinstance(key, str) or "|" not in key or not isinstance(val, str):
                        continue
                    food, _, seg = key.partition("|")
                    val = val.strip()
                    if food in seg_set and seg in seg_set and val and "\n" not in val and "\t" not in val \
                            and numbers(val) == numbers(seg):
                        overrides[key] = val
        except json.JSONDecodeError:
            pass
    ordered = dict(sorted(table.items(), key=lambda kv: (kv[0].lower(), kv[0])))
    for key in sorted(overrides):
        ordered[key] = overrides[key]
    (here / f"{language}.json").write_text(json.dumps(ordered, ensure_ascii=False, indent=0))
    print(status + (f", {len(overrides)} overrides" if overrides else ""))
