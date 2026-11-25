#!/usr/bin/env python3
"""Packs tools/recipe-content/<language>.json into Ayura/FoodSearch/Names/recipe_content.<language>.z."""
import json
import pathlib
import sys
import zlib

here = pathlib.Path(__file__).parent
out = here.parent.parent / "Ayura" / "FoodSearch" / "Names"


def pack(lines):
    assert not any("\n" in line for line in lines)
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress("\n".join(lines).encode("utf-8")) + compressor.flush()


strings = json.loads((here / "strings.en.json").read_text())
assert strings == sorted(set(strings), key=lambda s: (s.lower(), s))
out.mkdir(parents=True, exist_ok=True)
(out / "recipe_content.en.z").write_bytes(pack(strings))
print(f"strings: {len(strings)}, {sum(len(s.encode()) for s in strings)} bytes, "
      f"{(out / 'recipe_content.en.z').stat().st_size} packed")

for language in sys.argv[1:]:
    table = json.loads((here / f"{language}.json").read_text())
    unknown = sorted(set(table) - set(strings))
    assert not unknown, f"{language}: unknown keys: {unknown[:3]}"
    lines = []
    for s in strings:
        local = table.get(s, "").strip().replace("\n", " ").replace("\r", " ")
        if local == s:
            local = ""
        lines.append(local)
    translated = sum(1 for l in lines if l)
    target = out / f"recipe_content.{language}.z"
    target.write_bytes(pack(lines))
    print(f"{language}: {translated}/{len(strings)} translated, {target.stat().st_size} bytes packed")
