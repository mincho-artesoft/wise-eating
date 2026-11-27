#!/usr/bin/env python3
"""Writes keys.en.json, strings.en.json and work/batch-N.json from the strings
the Swift compiler extracted (work/stringsdata, see fetch.sh) and the
permission texts in the project file.

  extract.py            every string, in new batches numbered from 0
  extract.py --append   keep the batches that exist and add batches with the
                        strings that are in none of them; item numbers go on
                        from the last one, so translations in progress stay valid

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
    """The source line of the literal and, when that line is little more than
    the literal itself, the nearest declaration or text above it."""
    path = repo / source
    if not path.exists():
        return None, None
    lines = path.read_text(errors="ignore").split("\n")
    probe = key[:12].split("%")[0].split("\n")[0]
    for offset in (0, -1, 1, -2, 2):
        at = line + offset - 1
        if 0 <= at < len(lines) and probe in lines[at]:
            code = " ".join(lines[at].split())
            above = None
            if len(code) - len(key) < 40:
                for earlier in range(at - 1, max(at - 12, -1), -1):
                    text = " ".join(lines[earlier].split())
                    if re.search(r"\b(case|func|var|let|static|enum|struct|title|question|prompt)\b", text):
                        above = text[:140]
                        break
                if above is None:
                    # An answer in a list: the question it belongs to.
                    for earlier in range(at - 1, max(at - 6, -1), -1):
                        if re.search(r'\?"\)?,?$', lines[earlier].strip()):
                            above = " ".join(lines[earlier].split())[:140]
                            break
            return code[:160], above
    return None, None


items = []
for key, where in places.items():
    # The 18 strings that were in the catalogue, translated, before this package.
    if catalogue.get(key, {}).get("extractionState") == "manual":
        continue
    if not re.search(r"[^\W\d_]{2}", key) and key not in KEEP_SHORT:
        continue
    where = sorted(set(where), key=lambda place: (any(mark in place[0] for mark in LATE), place))
    source, line = where[0]
    late = any(mark in source for mark in LATE)
    code, above = code_line(source, line, key)
    kind = next((name for mark, name in KINDS if code and mark in code), "text")
    arguments = ui.specifiers(key)
    item = {"k": kind, "p": "onboarding-paywall" if late else source.split("/")[1 if source.startswith("Ayura/") else 0],
            "s": key, "in": sorted({pathlib.Path(s).stem for s, _ in where})[:4], "code": code, "above": above}
    if any(s.startswith("AyuraLiveActivityWidget/") for s, _ in where):
        # A separate bundle: apply.py writes these into the widget's own catalogue too.
        item["widget"] = True
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

work = here / "work"
kept, number = [], 0
if "--append" in sys.argv:
    paths = sorted(work.glob("batch-*.json"), key=lambda p: int(p.stem.split("-")[1]))
    kept = [json.loads(p.read_text()) for p in paths]
    number = max(item["i"] for batch in kept for item in batch) + 1
    known = {item["s"] for batch in kept for item in batch}
    gone = sorted(known - seen)
    unique = [item for item in unique if item["s"] not in known]
    print(f"{len(kept)} batches kept; {len(gone)} of their strings are no longer in the app")
else:
    for old in work.glob("batch-*.json"):
        old.unlink()

batches, current = [], []
for position, item in enumerate(unique):
    current.append(item)
    following = unique[position + 1]["p"] if position + 1 < len(unique) else None
    if following is None or (following != item["p"] and (len(current) >= BATCH or following == "onboarding-paywall")):
        batches.append(current)
        current = []

for index, batch in enumerate(batches, start=len(kept)):
    numbered = []
    for item in batch:
        numbered.append({"i": number, **{k: v for k, v in item.items() if v not in (None, "")}})
        number += 1
    (work / f"batch-{index}.json").write_text(json.dumps(numbered, ensure_ascii=False, indent=0))
    words = sum(len(item["s"].split()) for item in batch)
    print(f"batch {index}: {len(batch)} strings, {words} words, {sorted({item['p'] for item in batch})}")

# Everything any batch asks for, so that a translation of a string the app
# has since dropped is still accepted by assemble.py.
everything = seen | {item["s"] for batch in kept for item in batch}
(here / "strings.en.json").write_text(json.dumps(sorted(everything, key=lambda s: (s.lower(), s)), ensure_ascii=False, indent=0))
print(f"{len(seen)} strings in the app, {len(everything)} in the batches, "
      f"{sum(1 for item in unique if item.get('plural'))} new plural items")
