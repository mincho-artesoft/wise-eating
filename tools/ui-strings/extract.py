#!/usr/bin/env python3
"""Writes keys.en.json, strings.en.json and work/batch-N.json from the strings
the Swift compiler extracted (work/stringsdata, see fetch.sh) and the
permission texts in the project file.

  extract.py          every string
  extract.py --new    only strings that some <language>.json does not have yet

A string is a key of Ayura/Localizable.xcstrings: the English text exactly as
the compiler sees it, format specifiers included. The 18 keys that are already
in the catalogue and translated are left out.
"""
import collections
import json
import pathlib
import re
import sys

here = pathlib.Path(__file__).resolve().parent
repo = here.parent.parent
sys.path.insert(0, str(here))
import ui_strings as ui

BATCH = 205
LATE = ("Subscriptions/", "ProfileWizardView", "AyurvedaConstitutionViews")
KEEP_SHORT = {"C": "initial of Carbohydrates in the macro ring", "P": "initial of Protein in the macro ring",
              "F": "initial of Fat in the macro ring", "N/A": "not available"}
KINDS = [("navigationTitle(", "title"), ("accessibility", "accessibility"), ("TextField(", "placeholder"),
         ("prompt:", "placeholder"), ("Button(", "button"), ("alert(", "alert"), ("confirmationDialog(", "alert"),
         ("message:", "message"), ("Section(", "heading"), ("Label(", "label"), ("Toggle(", "label"),
         ("Picker(", "label"), ("Text(", "text")]

data = sorted((here / "work" / "stringsdata").rglob("*.stringsdata"))
if not data:
    raise SystemExit("no work/stringsdata: run tools/search-golden/remote.sh test, then tools/ui-strings/fetch.sh")

catalogue = json.loads((repo / "Ayura" / "Localizable.xcstrings").read_text())["strings"]
places = collections.defaultdict(list)
for path in data:
    content = json.loads(path.read_text())
    source = content["source"].split("/src/", 1)[-1]
    if "GeneratedStringSymbols" in source:
        continue
    for entries in content["tables"].values():
        for entry in entries:
            places[entry["key"]].append((source, entry["location"]["startingLine"]))


def code_line(source, line, key):
    path = repo / source
    if not path.exists():
        return None
    lines = path.read_text(errors="ignore").split("\n")
    probe = key[:12].split("%")[0].split("\n")[0]
    for offset in (0, -1, 1, -2, 2):
        if 0 < line + offset <= len(lines) and probe in lines[line + offset - 1]:
            return " ".join(lines[line + offset - 1].split())[:160]
    return None


items = []
for key, where in places.items():
    if key in catalogue and catalogue[key].get("localizations"):
        continue
    if not re.search(r"[^\W\d_]{2}", key) and key not in KEEP_SHORT:
        continue
    where = sorted(set(where), key=lambda place: (any(mark in place[0] for mark in LATE), place))
    source, line = where[0]
    late = any(mark in source for mark in LATE)
    code = code_line(source, line, key)
    kind = next((name for mark, name in KINDS if code and mark in code), "text")
    arguments = ui.specifiers(key)
    item = {"k": kind, "p": "onboarding-paywall" if late else source.split("/")[1 if source.startswith("Ayura/") else 0],
            "s": key, "in": sorted({pathlib.Path(s).stem for s, _ in where})[:4], "code": code}
    if list(arguments.values()) == ["int"]:
        item["plural"] = True
    if re.search(r"%lld [a-z]+%@", key):
        item["note"] = ("the %@ after the noun is the English plural ending ('s' or nothing): leave it out and "
                        "word the translation so that it reads with any number")
    if key in KEEP_SHORT:
        item["note"] = KEEP_SHORT[key]
    items.append((late, source, line, item))

project = (repo / "Ayurveda & Asana Yoga.xcodeproj" / "project.pbxproj").read_text()
permissions = dict(re.findall(r'INFOPLIST_KEY_(NS\w+UsageDescription) = "([^"]+)";', project))
plist = (repo / "Ayura" / "Info.plist").read_text()
for name, text in re.findall(r"<key>(NS\w+UsageDescription)</key>\s*<string>([^<]+)</string>", plist):
    permissions.setdefault(name, text.replace("&amp;", "&"))
for name, text in sorted(permissions.items()):
    items.append((False, "~permissions", 0, {
        "k": "permission", "p": "permissions", "s": text, "key": name,
        "note": "shown by iOS when it asks for this permission; the app name stays in English"}))

items = [item for _, _, _, item in sorted(items, key=lambda entry: entry[:3])]
seen, unique = set(), []
for item in items:
    if item["s"] not in seen:
        seen.add(item["s"])
        unique.append(item)

(here / "keys.en.json").write_text(json.dumps(
    [{k: v for k, v in item.items() if v not in (None, "")} for item in unique], ensure_ascii=False, indent=0))
(here / "strings.en.json").write_text(json.dumps(sorted(seen, key=lambda s: (s.lower(), s)), ensure_ascii=False, indent=0))

if "--new" in sys.argv:
    tables = [json.loads(p.read_text()) for p in here.glob("*.json") if p.stem not in ("keys.en", "strings.en")]
    unique = [item for item in unique if any(item["s"] not in table for table in tables)]

batches, current = [], []
for position, item in enumerate(unique):
    current.append(item)
    following = unique[position + 1]["p"] if position + 1 < len(unique) else None
    if following is None or (following != item["p"] and (len(current) >= BATCH or following == "onboarding-paywall")):
        batches.append(current)
        current = []

work = here / "work"
for old in work.glob("batch-*.json"):
    old.unlink()
number = 0
for index, batch in enumerate(batches):
    numbered = []
    for item in batch:
        numbered.append({"i": number, **{k: v for k, v in item.items() if v not in (None, "")}})
        number += 1
    (work / f"batch-{index}.json").write_text(json.dumps(numbered, ensure_ascii=False, indent=0))
    words = sum(len(item["s"].split()) for item in batch)
    print(f"batch {index}: {len(batch)} strings, {words} words, {sorted({item['p'] for item in batch})}")
print(f"{len(seen)} strings in all, {number} in the batches, "
      f"{sum(1 for item in unique if item.get('plural'))} of them plural")
if any((work / d.name).is_dir() and d.name != "stringsdata" for d in work.iterdir()):
    print("work/<language>/ folders exist: their out files belong to the previous batches")
