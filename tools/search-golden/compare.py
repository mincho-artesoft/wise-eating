#!/usr/bin/env python3
"""Compares out/actual.json (written by Tests/FoodSearch) with baseline.json
and checks the expectations in golden_queries.json.

  compare.py            report; exit 1 if a result differs from the baseline or
                        an expectation that passed in the baseline now fails
  compare.py --accept   make the current output the new baseline
"""
import json
import pathlib
import re
import shutil
import sys

here = pathlib.Path(__file__).parent
actual_path = here / "out" / "actual.json"
baseline_path = here / "baseline.json"


def load(path):
    return {(row["q"], row["cat"]): row for row in json.loads(path.read_text())}


DIRECTION = {"low": "low", "max": "low", "strictMax": "low", "lowest": "low",
             "high": "high", "min": "high", "strictMin": "high", "highest": "high"}


def words_of(name):
    return set(re.findall(r"\w+", name.lower()))


def has_word(word, tokens):
    word = word.lower()
    forms = {word, word + "s", word.rstrip("s")}
    if word.endswith("es"):
        forms.add(word[:-2])
    return bool(forms & tokens)


def failures(expect, row):
    """Why this row does not meet its expectation; empty when it does."""
    out = []
    goals = {g.split(":")[0] for g in row["goals"]}
    if "topAll" in expect:
        if not any(all(has_word(w, words_of(n)) for w in expect["topAll"]) for n in row["top"]):
            out.append("no top-10 name has all of: " + " ".join(expect["topAll"]))
    if expect.get("noPh") and row.get("ph"):
        out.append("became a pH filter (" + row.get("ph") + ")")
    if expect.get("noGoals") and goals:
        out.append("became a nutrient filter (" + ", ".join(sorted(goals)) + ")")
    for spec in expect.get("goals", []):
        goal, _, direction = spec.partition(":")
        if goal not in goals:
            out.append("no filter on " + goal)
        elif direction:
            # One nutrient must not be filtered both ways at once.
            got = {DIRECTION.get(re.split(r"[(:]", g.split(":", 1)[1])[0]) for g in row["goals"]
                   if g.split(":")[0] == goal} - {None}
            if got != {direction}:
                out.append(f"{goal} should be {direction}, got {' and '.join(sorted(got)) or 'neither'}")
    if expect.get("ph") and not row.get("ph"):
        out.append("no pH filter")
    if row["total"] < expect.get("minTotal", 0):
        out.append(f"only {row['total']} results")
    return out


if not actual_path.exists():
    sys.exit("no out/actual.json: run remote.sh test and remote.sh pull first")
if "--accept" in sys.argv:
    shutil.copyfile(actual_path, baseline_path)
    print("baseline.json updated")
    sys.exit(0)

queries = json.loads((here / "golden_queries.json").read_text())
actual = load(actual_path)
baseline = load(baseline_path) if baseline_path.exists() else None
missing = [q["q"] for q in queries if (q["q"], q["cat"]) not in actual]
if missing:
    sys.exit("queries with no result row: " + ", ".join(repr(m) for m in missing))

changed, regressed, fixed = [], [], []
per_category = {}
failing = []
for query in queries:
    key = (query["q"], query["cat"])
    row = actual[key]
    expect = query.get("expect")
    why = failures(expect, row) if expect else []
    if expect:
        total, bad = per_category.get(query["cat"], (0, 0))
        per_category[query["cat"]] = (total + 1, bad + bool(why))
        if why:
            failing.append((query, why))
    if baseline is not None and key in baseline:
        before = baseline[key]
        if before != row:
            changed.append((query["q"], before["top"][:3], row["top"][:3]))
        if expect:
            was_failing = bool(failures(expect, before))
            if why and not was_failing:
                regressed.append((query["q"], why))
            if was_failing and not why:
                fixed.append(query["q"])

print("expectations by category (failing / judged):")
for cat, (total, bad) in per_category.items():
    print(f"  {cat:15s} {bad:3d} / {total}")
print(f"  {'all':15s} {len(failing):3d} / {sum(t for t, _ in per_category.values())}")
if "--list" in sys.argv:
    for query, why in failing:
        print(f"  [{query['cat']}] {query['q']!r}: {'; '.join(why)}")

timing_path = here / "out" / "timing.json"
if timing_path.exists():
    t = json.loads(timing_path.read_text())
    print(f"speed: index load {t['indexLoadMs']:.0f} ms, per query p50 {t['p50Ms']:.1f} ms, "
          f"p95 {t['p95Ms']:.1f} ms, max {t['maxMs']:.1f} ms ({t['foods']} foods)")

if baseline is None:
    print("no baseline.json yet: review the output, then run compare.py --accept")
    sys.exit(0)
print(f"against baseline: {len(changed)} changed, {len(fixed)} newly passing, {len(regressed)} newly failing")
for q, before, after in changed[:40]:
    print(f"  changed {q!r}: {before} -> {after}")
for q, why in regressed:
    print(f"  REGRESSED {q!r}: {'; '.join(why)}")
sys.exit(1 if changed or regressed else 0)
