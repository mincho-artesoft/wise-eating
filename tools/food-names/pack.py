#!/usr/bin/env python3
"""Checks a language's translated food-name segments and packs them for the app.

  pack.py bg        check tools/food-names/bg.json and write
                    Ayura/FoodSearch/Names/food_names.bg.z
  pack.py           only (re)write food_name_segments.en.z
  pack.py --catalog yoga [languages]
                    the same for the yoga names (tools/yoga-names ->
                    Ayura/Yoga/Names/yoga_names.<language>.z)

segments.en.json is the sorted list of distinct segments of the catalogue's
food names (the parts between ", "). <language>.json maps each of them to its
translation. The app reads both packed files line by line, so line i of a
language is the translation of line i of the segment list; a segment mapped to
itself or missing is written as an empty line and stays English in the app.

A key of the form "Milk|whole" translates a segment only in names whose first
segment is "Milk" ("whole" is "цяло" for a turkey and "пълномаслено" for
milk). These follow the aligned lines as "Milk|whole<TAB>translation".
"""
import json
import pathlib
import re
import sys
import zlib

tools = pathlib.Path(__file__).parent.parent
arguments = sys.argv[1:]
catalog = "food"
if "--catalog" in arguments:
    position = arguments.index("--catalog")
    catalog = arguments[position + 1]
    del arguments[position:position + 2]
# Each catalogue: the folder with segments.en.json and <language>.json, the
# folder the app bundles, and the resource names the app looks for.
CATALOGS = {
    "food": (tools / "food-names", tools.parent / "Ayura" / "FoodSearch" / "Names",
             "food_name_segments.en.z", "food_names"),
    "yoga": (tools / "yoga-names", tools.parent / "Ayura" / "Yoga" / "Names",
             "yoga_name_segments.en.z", "yoga_names"),
}
here, out, segments_file, names_prefix = CATALOGS[catalog]


def pack(lines):
    assert not any("\n" in line for line in lines)
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress("\n".join(lines).encode("utf-8")) + compressor.flush()


def numbers(text):
    return sorted(re.findall(r"\d+(?:[.,/]\d+)*", text))


segments = json.loads((here / "segments.en.json").read_text())
assert segments == sorted(set(segments), key=lambda s: (s.lower(), s)), "segments.en.json is not sorted/unique"
out.mkdir(parents=True, exist_ok=True)
(out / segments_file).write_bytes(pack(segments))
print(f"{catalog} segments: {len(segments)}, {sum(len(s.encode()) for s in segments)} bytes of text, "
      f"{(out / segments_file).stat().st_size} packed")

for language in arguments:
    table = json.loads((here / f"{language}.json").read_text())
    by_food = {key: value for key, value in table.items() if "|" in key}
    table = {key: value for key, value in table.items() if "|" not in key}
    for key in by_food:
        food, _, segment = key.partition("|")
        assert food in segments and segment in segments, f"{language}: unknown segments in {key!r}"
    unknown = sorted(set(table) - set(segments))
    assert not unknown, f"{language}: not catalogue segments: {unknown[:5]}"
    problems = []
    lines = []
    for segment in segments:
        local = table.get(segment, "").strip()
        if local == segment:
            local = ""
        if local and numbers(local) != numbers(segment):
            problems.append(f"numbers differ: {segment!r} -> {local!r}")
        if "\n" in local:
            problems.append(f"line break in: {segment!r}")
        lines.append(local)
    translated = sum(1 for line in lines if line)
    by_food_problems = [key for key, value in by_food.items() if "\t" in value or "\n" in value or not value.strip()]
    assert not by_food_problems, by_food_problems
    for problem in problems[:40]:
        print("  " + problem)
    if problems:
        sys.exit(f"{language}: {len(problems)} problems; nothing written")
    target = out / f"{names_prefix}.{language}.z"
    lines += [f"{key}\t{value.strip()}" for key, value in sorted(by_food.items())]
    target.write_bytes(pack(lines))
    print(f"{language}: {translated} of {len(segments)} segments translated, "
          f"{len(by_food)} food-specific, "
          f"{sum(len(l.encode()) for l in lines)} bytes of text, {target.stat().st_size} packed")
