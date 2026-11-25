#!/usr/bin/env python3
"""Checks a language's translated food-name segments and packs them for the app.

  pack.py bg        check tools/food-names/bg.json and write
                    Ayura/FoodSearch/Names/food_names.bg.z
  pack.py           only (re)write food_name_segments.en.z

segments.en.json is the sorted list of distinct segments of the catalogue's
food names (the parts between ", "). <language>.json maps each of them to its
translation. The app reads both packed files line by line, so line i of a
language is the translation of line i of the segment list; a segment mapped to
itself or missing is written as an empty line and stays English in the app.
"""
import json
import pathlib
import re
import sys
import zlib

here = pathlib.Path(__file__).parent
out = here.parent.parent / "Ayura" / "FoodSearch" / "Names"


def pack(lines):
    assert not any("\n" in line for line in lines)
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress("\n".join(lines).encode("utf-8")) + compressor.flush()


def numbers(text):
    return sorted(re.findall(r"\d+(?:[.,/]\d+)*", text))


segments = json.loads((here / "segments.en.json").read_text())
assert segments == sorted(set(segments), key=lambda s: (s.lower(), s)), "segments.en.json is not sorted/unique"
out.mkdir(parents=True, exist_ok=True)
(out / "food_name_segments.en.z").write_bytes(pack(segments))
print(f"segments: {len(segments)}, {sum(len(s.encode()) for s in segments)} bytes of text, "
      f"{(out / 'food_name_segments.en.z').stat().st_size} packed")

for language in sys.argv[1:]:
    table = json.loads((here / f"{language}.json").read_text())
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
    for problem in problems[:40]:
        print("  " + problem)
    if problems:
        sys.exit(f"{language}: {len(problems)} problems; nothing written")
    target = out / f"food_names.{language}.z"
    target.write_bytes(pack(lines))
    print(f"{language}: {translated} of {len(segments)} segments translated, "
          f"{sum(len(l.encode()) for l in lines)} bytes of text, {target.stat().st_size} packed")
