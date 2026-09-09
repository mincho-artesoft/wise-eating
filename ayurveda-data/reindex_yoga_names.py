#!/usr/bin/env python3
"""Compose seeded Yoga names and rebuild their persisted search metadata."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sqlite3
import unicodedata
from pathlib import Path


EXPECTED_ASANAS = 908
CATALOGUE_RANGE = set(range(800_000, 800_908))


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--store", required=True, type=Path)
    parser.add_argument(
        "--asanas",
        type=Path,
        default=repo_root / "ayurveda-data" / "yoga" / "asanas.json",
    )
    return parser.parse_args()


def folded_search_key(value: str) -> str:
    decomposed = unicodedata.normalize("NFD", value)
    without_diacritics = "".join(
        character
        for character in decomposed
        if unicodedata.category(character) != "Mn"
    )
    return without_diacritics.lower()


def composed_name(title: str, sanskrit: str) -> str:
    title = title.strip()
    sanskrit = sanskrit.strip()
    if not sanskrit or title.casefold() == sanskrit.casefold():
        return title
    suffix = f"({sanskrit})"
    if suffix.casefold() in title.casefold():
        return title
    return f"{title} {suffix}"


def words(value: str) -> list[str]:
    return re.findall(r"[^\W_]+", value, flags=re.UNICODE)


def make_tokens(value: str) -> list[str]:
    normalized = re.sub(r"[-/_]", " ", value.lower())
    normalized = folded_search_key(normalized)
    raw = words(normalized)
    stopwords = {
        "and", "or", "with", "without", "in", "of", "the", "a", "an",
        "style", "type", "made", "from", "plus", "no", "low", "reduced",
    }
    negators = {"excluding", "except", "without", "no"}
    searchable = [word for word in raw if word not in stopwords]
    tokens = list(searchable)
    tokens.extend(
        " ".join(searchable[index:index + 2])
        for index in range(max(0, len(searchable) - 1))
    )
    tokens.extend(
        " ".join(searchable[index:index + 3])
        for index in range(max(0, len(searchable) - 2))
    )
    tokens.extend(word for word in raw if word in negators)
    return tokens


def make_tokens2(value: str) -> list[str]:
    return words(folded_search_key(value.lower()))


def keyed_string_array(values: list[str]) -> bytes:
    string_start = 2
    class_index = string_start + len(values)
    archive = {
        "$version": 100_000,
        "$archiver": "NSKeyedArchiver",
        "$top": {"root": plistlib.UID(1)},
        "$objects": [
            "$null",
            {
                "NS.objects": [
                    plistlib.UID(index)
                    for index in range(string_start, class_index)
                ],
                "$class": plistlib.UID(class_index),
            },
            *values,
            {
                "$classname": "NSArray",
                "$classes": ["NSArray", "NSObject"],
            },
        ],
    }
    return plistlib.dumps(
        archive,
        fmt=plistlib.FMT_BINARY,
        sort_keys=False,
    )


def main() -> int:
    args = parse_args()
    rows = json.loads(args.asanas.read_text(encoding="utf-8"))
    by_catalogue = {row["catalogNumber"]: row for row in rows}
    if len(rows) != EXPECTED_ASANAS or set(by_catalogue) != CATALOGUE_RANGE:
        raise RuntimeError("Yoga source catalogue is incomplete")

    store = args.store.resolve()
    with sqlite3.connect(store) as connection:
        stored_catalogue = {
            row[0]
            for row in connection.execute(
                """
                SELECT ZCATALOGNUMBER FROM ZEXERCISEITEM
                WHERE ZCATALOGNUMBER BETWEEN 800000 AND 800907
                """
            )
        }
        if stored_catalogue != CATALOGUE_RANGE:
            raise RuntimeError("Persisted Yoga catalogue is incomplete")

        for catalog_number, row in sorted(by_catalogue.items()):
            name = composed_name(row["title"], row["sanskrit"])
            searchable_text = " ".join(
                (name, row["sanskrit"].strip(), row["family"].strip())
            )
            connection.execute(
                """
                UPDATE ZEXERCISEITEM
                SET ZNAME = ?,
                    ZNAMENORMALIZED = ?,
                    ZSEARCHTOKENS = ?,
                    ZSEARCHTOKENS2 = ?,
                    Z_OPT = Z_OPT + 1
                WHERE ZCATALOGNUMBER = ?
                """,
                (
                    name,
                    folded_search_key(searchable_text),
                    sqlite3.Binary(keyed_string_array(make_tokens(searchable_text))),
                    sqlite3.Binary(keyed_string_array(make_tokens2(searchable_text))),
                    catalog_number,
                ),
            )
        connection.commit()

        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"SQLite integrity check failed: {integrity}")
        separate_names = connection.execute(
            """
            SELECT COUNT(*) FROM ZEXERCISEITEM
            WHERE ZCATALOGNUMBER BETWEEN 800000 AND 800907
              AND ZNAME != ZSANSKRIT
              AND ZNAME NOT LIKE '% (' || ZSANSKRIT || ')'
            """
        ).fetchone()[0]
        if separate_names != 0:
            raise RuntimeError(
                f"{separate_names} Yoga rows still use a separate Sanskrit name"
            )

    print(f"reindexed Yoga display names: {EXPECTED_ASANAS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
