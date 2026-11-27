#!/usr/bin/env python3
"""Writes <language>.json from work/<language>/out-N.json (and fixes-N.json).

  assemble.py            every language folder under work/
  assemble.py de ja      only these

An answer is a string, or for an item marked "plural" an object with that
language's plural categories. A language is written only when every translation
in the batches that are there takes the same arguments as the English: a wrong
format specifier crashes the app. A batch without an out file is reported and
waited for. Strings translated in an earlier round are kept.
"""
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(here))
import ui_strings as ui

strings = set(json.loads((here / "strings.en.json").read_text()))
work = here / "work"
batches = [json.loads(p.read_text())
           for p in sorted(work.glob("batch-*.json"), key=lambda p: int(p.stem.split("-")[1]))]
languages = sys.argv[1:] or sorted(p.name for p in work.iterdir() if p.is_dir() and p.name != "stringsdata")


def checked(item, answer, language, problems):
    """The answer in its stored form, or None after noting what is wrong."""
    english, drop = item["s"], "plural ending" in item.get("note", "")
    if isinstance(answer, dict):
        wanted = ui.CATEGORIES.get(language)
        if not item.get("plural") or wanted is None or tuple(sorted(answer)) != tuple(sorted(wanted)):
            problems.append(f"i {item['i']}: plural forms {sorted(answer)}, expected {wanted} on a plural item")
            return None
        forms = answer
    elif isinstance(answer, str) and answer.strip():
        forms = {"": answer}
    else:
        problems.append(f"i {item['i']}: empty or not a string")
        return None
    result = {}
    for form, text in forms.items():
        if not isinstance(text, str) or not text.strip():
            problems.append(f"i {item['i']}: empty {form}")
            return None
        wrong = ui.format_problem(english, text, drop)
        if wrong:
            problems.append(f"i {item['i']} {english[:40]!r}: {wrong}")
            return None
        if text.count("\n") != english.count("\n"):
            problems.append(f"i {item['i']} {english[:40]!r}: {text.count(chr(10))} line breaks, English has "
                            f"{english.count(chr(10))}")
            return None
        result[form] = ui.edges(english, text)
    return result[""] if "" in result else result


for language in languages:
    folder, problems, waiting, applied, rejected = work / language, [], [], 0, 0
    path = here / f"{language}.json"
    table = json.loads(path.read_text()) if path.exists() else {}
    table = {english: text for english, text in table.items() if english in strings}
    for index, batch in enumerate(batches):
        out_path = folder / f"out-{index}.json"
        if not out_path.exists():
            waiting.append(index)
            continue
        try:
            out = json.loads(out_path.read_text())
        except json.JSONDecodeError as error:
            problems.append(f"batch {index}: does not parse ({error})")
            continue
        if len(out) != len(batch):
            problems.append(f"batch {index}: {len(out)} translations for {len(batch)} strings")
            continue
        for item, answer in zip(batch, out):
            value = checked(item, answer, language, problems)
            if value is not None:
                table[item["s"]] = value
        fixes = folder / f"fixes-{index}.json"
        if fixes.exists():
            by_number = {item["i"]: item for item in batch}
            for fix in json.loads(fixes.read_text()):
                item, skipped = by_number.get(fix.get("i")), []
                value = checked(item, fix.get("fix"), language, skipped) if item and item["s"] == fix.get("en") else None
                if value is None:
                    rejected += 1
                elif table.get(item["s"]) != value:
                    table[item["s"]] = value
                    applied += 1
    status = f"{language}: {len(table)} of {len(strings)} strings, {applied} corrections applied, {rejected} rejected"
    if waiting:
        status += f", batches not translated yet: {waiting}"
    if problems:
        print(status + " -- NOT WRITTEN:")
        for problem in problems[:40]:
            print("   " + problem)
        continue
    path.write_text(json.dumps(dict(sorted(table.items(), key=lambda kv: (kv[0].lower(), kv[0]))),
                               ensure_ascii=False, indent=0))
    print(status)
