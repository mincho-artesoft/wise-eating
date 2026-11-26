"""Shared by tools/yoga-names, tools/yoga-content and tools/practice-content.

The same hand-off as tools/food-names and tools/recipe-content:

  <folder>/strings.en.json (or segments.en.json)   the distinct English strings, sorted
  <folder>/work/batch-N.json                       what a translator is given
  <folder>/work/<language>/out-N.json              the translations, aligned with batch-N
  <folder>/work/<language>/fixes-N.json            a reviewer's corrections (optional)
  <folder>/<language>.json                         { "English": "translation" }, written by assemble
"""
import json
import pathlib
import re
import sys


def order(strings):
    return sorted(set(strings), key=lambda s: (s.lower(), s))


def clean(text):
    return " ".join(text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split())


def numbers(text):
    return sorted(re.findall(r"\d+(?:[.,/–-]\d+)*", text))


def write_batches(here, items, batch_count, strings_file="strings.en.json"):
    """items: dicts with "s" (the English string) and context keys, in the
    order a translator should read them. A string is given once, at its first
    place. Batches are cut at a change of the "p" key when the items have one,
    so that one practice is never split between two translators."""
    seen, unique = set(), []
    for item in items:
        if item["s"] and item["s"] not in seen:
            seen.add(item["s"])
            unique.append(item)
    (here / strings_file).write_text(json.dumps(order(seen), ensure_ascii=False, indent=0))
    work = here / "work"
    work.mkdir(exist_ok=True)
    for old in work.glob("batch-*.json"):
        old.unlink()
    target = -(-len(unique) // batch_count)
    batches, current = [], []
    for position, item in enumerate(unique):
        current.append(item)
        last = position + 1 == len(unique)
        same_group = not last and "p" in item and unique[position + 1].get("p") == item["p"]
        if last or (len(current) >= target and not same_group and len(batches) < batch_count - 1):
            batches.append(current)
            current = []
    number = 0
    for index, batch in enumerate(batches):
        numbered = []
        for item in batch:
            numbered.append({"i": number, **{k: v for k, v in item.items() if v not in (None, "")}})
            number += 1
        batches[index] = numbered
        (work / f"batch-{index}.json").write_text(json.dumps(numbered, ensure_ascii=False, indent=0))
    words = [sum(len(item["s"].split()) for item in batch) for batch in batches]
    print(f"{here.name}: {len(unique)} strings, {sum(words)} words, batches of "
          f"{[len(b) for b in batches]} strings / {words} words")


def load_batches(here):
    work = here / "work"
    paths = sorted(work.glob("batch-*.json"), key=lambda p: int(p.stem.split("-")[1]))
    return [json.loads(p.read_text()) for p in paths]


def assemble(here, strings_file="strings.en.json", arguments=None):
    """Writes <language>.json for every language folder under work/ (or the
    ones named) whose batches are all translated."""
    arguments = sys.argv[1:] if arguments is None else arguments
    strings = json.loads((here / strings_file).read_text())
    batches = load_batches(here)
    assert {item["s"] for batch in batches for item in batch} == set(strings), "batches are stale: run extract"
    work = here / "work"
    languages = [a for a in arguments if not a.startswith("--")] or sorted(p.name for p in work.iterdir() if p.is_dir())
    for language in languages:
        folder, table, problems = work / language, {}, []
        applied = rejected = number_issues = 0
        for index, batch in enumerate(batches):
            path = folder / f"out-{index}.json"
            if not path.exists():
                problems.append(f"batch {index}: no translation")
                continue
            try:
                out = json.loads(path.read_text())
            except json.JSONDecodeError as error:
                problems.append(f"batch {index}: does not parse ({error})")
                continue
            if len(out) != len(batch) or not all(isinstance(x, str) and x.strip() for x in out):
                problems.append(f"batch {index}: {len(out)} translations for {len(batch)} strings")
                continue
            for item, text in zip(batch, out):
                table[item["s"]] = clean(text)
            fixes = folder / f"fixes-{index}.json"
            if fixes.exists():
                by_number = {item["i"]: item["s"] for item in batch}
                for fix in json.loads(fixes.read_text()):
                    english, new = by_number.get(fix.get("i")), clean(str(fix.get("fix", "")))
                    if english is None or english != fix.get("en") or not new:
                        rejected += 1
                    elif table[english] != new:
                        table[english] = new
                        applied += 1
        for english, text in list(table.items()):
            if numbers(text) != numbers(english):
                number_issues += 1
        status = (f"{language}: {len(table)} of {len(strings)} strings, {applied} corrections applied, "
                  f"{rejected} rejected, {number_issues} with different numbers (check them)")
        if problems:
            print(status + " -- NOT WRITTEN: " + "; ".join(problems))
            continue
        (here / f"{language}.json").write_text(json.dumps(
            dict(sorted(table.items(), key=lambda kv: (kv[0].lower(), kv[0]))), ensure_ascii=False, indent=0))
        print(status)


if __name__ == "__main__":
    # translation_batches.py assemble <folder> [languages]
    command, folder, *rest = sys.argv[1:]
    assert command == "assemble"
    here = pathlib.Path(folder).resolve()
    assemble(here, "segments.en.json" if (here / "segments.en.json").exists() else "strings.en.json", rest)
