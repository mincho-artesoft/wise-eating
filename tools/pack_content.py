#!/usr/bin/env python3
"""Packs the translated practice and yoga text into the app, in the format of
tools/recipe-content/pack.py: <prefix>.en.z holds the English strings one per
line, <prefix>.<language>.z the translations in the same order (an empty line
where there is none), both raw DEFLATE.

  pack_content.py practice            every tools/practice-content/<language>.json
  pack_content.py yoga de fr          only these languages

  practice -> Ayura/Practices/Names/practice_content.<language>.z
  yoga     -> Ayura/Yoga/Names/yoga_content.<language>.z
"""
import json
import pathlib
import sys
import zlib

tools = pathlib.Path(__file__).resolve().parent
CATALOGS = {
    "practice": (tools / "practice-content", tools.parent / "Ayura" / "Practices" / "Names", "practice_content"),
    "yoga": (tools / "yoga-content", tools.parent / "Ayura" / "Yoga" / "Names", "yoga_content"),
}


def pack(lines):
    assert not any("\n" in line for line in lines)
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress("\n".join(lines).encode("utf-8")) + compressor.flush()


source, out, prefix = CATALOGS[sys.argv[1]]
strings = json.loads((source / "strings.en.json").read_text())
languages = sys.argv[2:] or sorted(p.stem for p in source.glob("*.json") if p.stem != "strings.en")
out.mkdir(parents=True, exist_ok=True)
(out / f"{prefix}.en.z").write_bytes(pack(strings))
total = (out / f"{prefix}.en.z").stat().st_size
for language in languages:
    table = json.loads((source / f"{language}.json").read_text())
    unknown = sorted(set(table) - set(strings))
    assert not unknown, f"{language}: unknown keys: {unknown[:3]}"
    lines = []
    for english in strings:
        local = " ".join(table.get(english, "").split())
        lines.append("" if local == english else local)
    missing = sum(1 for english in strings if english not in table)
    assert not missing, f"{language}: {missing} strings missing"
    target = out / f"{prefix}.{language}.z"
    target.write_bytes(pack(lines))
    total += target.stat().st_size
print(f"{prefix}: {len(strings)} strings, {len(languages)} languages, {total / 1e6:.1f} MB in {out}")
