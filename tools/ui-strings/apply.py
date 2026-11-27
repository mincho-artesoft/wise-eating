#!/usr/bin/env python3
"""Puts the assembled translations into the app's string catalogues.

  apply.py             every <language>.json in this folder
  apply.py de ja       only these
  apply.py --partial   also languages that do not have every string yet
  apply.py --to DIR    write the catalogues into DIR instead of Ayura/ (to try it)

Interface strings go to Ayura/Localizable.xcstrings under their English key,
the Live Activity widget's also to AyuraLiveActivityWidget/Localizable.xcstrings;
permission texts go to Ayura/InfoPlist.xcstrings under their Info.plist key.
Nothing already in a catalogue is removed; a language's entry for a key is
replaced. A language that does not have every string is skipped unless
--partial is given.
"""
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
repo = here.parent.parent
sys.path.insert(0, str(here))
import ui_strings as ui

arguments = sys.argv[1:]
target = repo / "Ayura"
if "--to" in arguments:
    target = pathlib.Path(arguments.pop(arguments.index("--to") + 1))
    arguments.remove("--to")
partial = "--partial" in arguments
arguments = [a for a in arguments if a != "--partial"]
keys = json.loads((here / "keys.en.json").read_text())
languages = arguments or sorted(p.stem for p in here.glob("*.json") if p.stem not in ("keys.en", "strings.en"))


def load(path):
    if path.exists():
        return json.loads(path.read_text())
    return {"sourceLanguage": "en", "strings": {}, "version": "1.0"}


def unit(text):
    return {"stringUnit": {"state": "translated", "value": text}}


def localization(value):
    if isinstance(value, str):
        return unit(value)
    return {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}


interface = load(repo / "Ayura" / "Localizable.xcstrings")
# The Live Activity widget is its own bundle and reads its own catalogue.
widget = load(repo / "AyuraLiveActivityWidget" / "Localizable.xcstrings")
permissions = load(repo / "Ayura" / "InfoPlist.xcstrings")
for item in keys:
    if item["k"] == "permission":
        entry = permissions["strings"].setdefault(item["key"], {"extractionState": "extracted_with_value"})
        entry.setdefault("localizations", {})["en"] = {"stringUnit": {"state": "new", "value": item["s"]}}
    else:
        interface["strings"].setdefault(item["s"], {})
        if item.get("widget"):
            widget["strings"].setdefault(item["s"], {})

written = []
for language in languages:
    table = json.loads((here / f"{language}.json").read_text())
    missing = [item["s"] for item in keys if item["s"] not in table]
    if missing and not partial:
        print(f"{language}: skipped, {len(missing)} strings missing (first: {missing[0][:50]!r})")
        continue
    for item in keys:
        if item["s"] not in table:
            continue
        catalogue, key = (permissions, item["key"]) if item["k"] == "permission" else (interface, item["s"])
        catalogue["strings"][key].setdefault("localizations", {})[language] = localization(table[item["s"]])
        if item.get("widget"):
            widget["strings"][key].setdefault("localizations", {})[language] = localization(table[item["s"]])
    written.append(language)

target.mkdir(parents=True, exist_ok=True)
widget_target = target if "--to" in sys.argv else repo
(widget_target / "AyuraLiveActivityWidget").mkdir(parents=True, exist_ok=True)
for name, catalogue in (("Localizable.xcstrings", interface), ("InfoPlist.xcstrings", permissions),
                        ("../AyuraLiveActivityWidget/Localizable.xcstrings", widget)):
    if "--to" in sys.argv:
        name = name.replace("../", "")
    (target / name).write_text(json.dumps(catalogue, ensure_ascii=False, indent=2,
                                          separators=(",", ": ")) + "\n")
print(f"{len(written)} languages written to {target}: {' '.join(written)}")
