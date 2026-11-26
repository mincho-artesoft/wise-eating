#!/usr/bin/env python3
"""Two checks on the finished tables that assemble.py cannot make.

  check.py            every language
  check.py bg hi      only these

1. Two different poses with the same translated title. A person then sees two
   rows with one name and cannot tell them apart.
2. One Sanskrit word spelled more than one way inside a language ("Баддха" and
   "Бадха"). Search then finds only the poses with the spelling that was typed.
   A different ending for a grammatical case is not an error; a different
   spelling of the same form is.

Prints what it finds and exits 1 if there is anything, so a language can be
held back until it is clean or the remaining lines have been looked at.
"""
import collections
import json
import pathlib
import re
import sys

here = pathlib.Path(__file__).parent
kind = {}
for path in sorted((here / "work").glob("batch-*.json")):
    for item in json.loads(path.read_text()):
        kind[item["s"]] = item["k"]

found = 0
languages = sys.argv[1:] or sorted(p.stem for p in here.glob("*.json") if p.stem != "segments.en")
for language in languages:
    table = json.loads((here / f"{language}.json").read_text())
    titles = collections.defaultdict(list)
    spellings = collections.defaultdict(collections.Counter)
    for english, local in table.items():
        if kind.get(english) == "pose":
            titles[local].append(english)
        if kind.get(english) == "sanskrit":
            source = re.sub(r"\s*\(.*", "", english).split()
            target = re.sub(r"\s*[（(].*", "", local).split()
            if len(source) == len(target):
                for word, spelled in zip(source, target):
                    spellings[word][spelled.lower()] += 1
    same = {local: names for local, names in titles.items() if len(names) > 1}
    mixed = {word: dict(counts) for word, counts in spellings.items() if len(counts) > 1}
    found += len(same) + len(mixed)
    print(f"{language}: {len(same)} titles shared by two poses, {len(mixed)} Sanskrit words spelled more than one way")
    for local, names in same.items():
        print(f"    same title  {local!r}: {names}")
    for word, counts in mixed.items():
        print(f"    spellings   {word}: {counts}")
sys.exit(1 if found else 0)
