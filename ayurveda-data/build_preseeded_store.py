#!/usr/bin/env python3
"""Audit, compact, gzip, and split a completed WiseEating build-time store."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import sqlite3
import tempfile
from pathlib import Path


EXPECTED = {
    "foods": 14_484,
    "profiles": 2_214,
    "dravyas": 714,
    "recipes": 1_500,
    "links": 2_305,
    "cacheFoods": 14_484,
    "cacheVersion": 3,
    "seedVersion": 3,
}
PART_SIZE = 70 * 1024 * 1024


class PreseedBuildError(RuntimeError):
    """Raised when a candidate store is not safe to ship."""


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-store", required=True, type=Path)
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=repo_root / "WiseEating",
    )
    return parser.parse_args()


def scalar(connection: sqlite3.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    return row[0] if row else None


def require_equal(label: str, actual, expected) -> None:
    if actual != expected:
        raise PreseedBuildError(f"{label}: expected {expected!r}, got {actual!r}")


def audit_store(path: Path) -> dict[str, int]:
    path = Path(path)
    if not path.is_file():
        raise PreseedBuildError(f"store does not exist: {path}")
    with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as connection:
        require_equal(
            "integrity_check",
            scalar(connection, "PRAGMA integrity_check"),
            "ok",
        )
        require_equal(
            "FoodItem count",
            scalar(connection, "SELECT COUNT(*) FROM ZFOODITEM"),
            EXPECTED["foods"],
        )
        require_equal(
            "FoodItem duplicate ids",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM (
                  SELECT ZID FROM ZFOODITEM GROUP BY ZID HAVING COUNT(*) > 1
                )
                """,
            ),
            0,
        )
        require_equal(
            "AyurvedaProfile count",
            scalar(connection, "SELECT COUNT(*) FROM ZAYURVEDAPROFILE"),
            EXPECTED["profiles"],
        )
        require_equal(
            "AyurvedaProfile duplicate slugs",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM (
                  SELECT ZID FROM ZAYURVEDAPROFILE
                  GROUP BY ZID HAVING COUNT(*) > 1
                )
                """,
            ),
            0,
        )
        require_equal(
            "AyurvedaProfile duplicate food/kind",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM (
                  SELECT ZFOODID, ZKIND FROM ZAYURVEDAPROFILE
                  GROUP BY ZFOODID, ZKIND HAVING COUNT(*) > 1
                )
                """,
            ),
            0,
        )
        require_equal(
            "dravya count",
            scalar(
                connection,
                "SELECT COUNT(*) FROM ZAYURVEDAPROFILE WHERE ZKIND = 'dravya'",
            ),
            EXPECTED["dravyas"],
        )
        require_equal(
            "recipe count",
            scalar(
                connection,
                "SELECT COUNT(*) FROM ZAYURVEDAPROFILE WHERE ZKIND = 'recipe'",
            ),
            EXPECTED["recipes"],
        )
        require_equal(
            "canonical slug prefixes",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZAYURVEDAPROFILE
                WHERE (ZKIND = 'dravya' AND ZID NOT LIKE 'dravya.%')
                   OR (ZKIND = 'recipe' AND ZID NOT LIKE 'recipe.%')
                """,
            ),
            0,
        )
        require_equal(
            "canonical aiDraft lifecycle",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZAYURVEDAPROFILE
                WHERE COALESCE(ZQUALITYSTATE, '') != 'aiDraft'
                """,
            ),
            0,
        )
        require_equal(
            "seed version stamp",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZAYURVEDAPROFILE
                WHERE ZSEEDVERSION != ?
                """,
                (EXPECTED["seedVersion"],),
            ),
            0,
        )
        require_equal(
            "recipe nutrition panels",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZAYURVEDAPROFILE
                WHERE ZKIND = 'recipe'
                  AND ZNUTRITIONSTATUS = 'full'
                  AND ZNUTRITIONPERSERVINGJSON IS NOT NULL
                  AND ZNUTRITIONPER100GJSON IS NOT NULL
                  AND ZNUTRITIONUNITSJSON IS NOT NULL
                """,
            ),
            EXPECTED["recipes"],
        )
        require_equal(
            "AyurvedaLink count",
            scalar(connection, "SELECT COUNT(*) FROM ZAYURVEDALINK"),
            EXPECTED["links"],
        )
        require_equal(
            "AyurvedaLink duplicate fdcIds",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM (
                  SELECT ZFDCID FROM ZAYURVEDALINK
                  GROUP BY ZFDCID HAVING COUNT(*) > 1
                )
                """,
            ),
            0,
        )
        cache_rows = connection.execute(
            """
            SELECT ZFOODSCOUNT, ZVERSION, ZPAYLOADDATA
            FROM ZSEARCHINDEXCACHE WHERE ZKEY = 'main'
            """
        ).fetchall()
        require_equal("main search cache rows", len(cache_rows), 1)
        cache_foods, cache_version, payload_data = cache_rows[0]
        require_equal("cache foodsCount", cache_foods, EXPECTED["cacheFoods"])
        require_equal("cache version", cache_version, EXPECTED["cacheVersion"])
        try:
            payload = json.loads(payload_data)
        except (TypeError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise PreseedBuildError(f"search cache payload cannot decode: {error}") from error
        compact_foods = payload.get("compactFoods")
        if not isinstance(compact_foods, list):
            raise PreseedBuildError("search cache compactFoods is not an array")
        require_equal(
            "search payload compactFoods",
            len(compact_foods),
            EXPECTED["cacheFoods"],
        )
        require_equal(
            "search payload duplicate food ids",
            len(compact_foods) - len({food["id"] for food in compact_foods}),
            0,
        )
        return {
            "foods": EXPECTED["foods"],
            "profiles": EXPECTED["profiles"],
            "links": EXPECTED["links"],
            "cacheFoods": cache_foods,
            "cacheVersion": cache_version,
            "payloadBytes": len(payload_data),
        }


def compact_store(source: Path, destination: Path) -> None:
    with sqlite3.connect(source) as connection:
        connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        escaped = str(destination).replace("'", "''")
        connection.execute(f"VACUUM INTO '{escaped}'")


def deterministic_gzip(source: Path, destination: Path) -> None:
    with source.open("rb") as input_file, destination.open("wb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0) as output:
            while chunk := input_file.read(1024 * 1024):
                output.write(chunk)


def write_parts(gzip_path: Path, output_directory: Path) -> tuple[Path, Path]:
    size = gzip_path.stat().st_size
    if size > PART_SIZE * 2:
        raise PreseedBuildError(
            f"compressed store is {size} bytes; two 70 MiB parts are insufficient"
        )
    output_directory.mkdir(parents=True, exist_ok=True)
    outputs = (
        output_directory / "preseeded_db.store.gz.part-aa",
        output_directory / "preseeded_db.store.gz.part-ab",
    )
    with gzip_path.open("rb") as source:
        for output in outputs:
            temporary = output.with_suffix(output.suffix + ".tmp")
            with temporary.open("wb") as destination:
                destination.write(source.read(PART_SIZE))
            os.replace(temporary, output)
    return outputs


def main() -> int:
    args = parse_args()
    source = args.source_store.resolve()
    with tempfile.TemporaryDirectory(prefix="wise-eating-preseed-") as temporary:
        temporary_root = Path(temporary)
        compacted = temporary_root / "default.store"
        compressed = temporary_root / "preseeded_db.store.gz"
        compact_store(source, compacted)
        audit = audit_store(compacted)
        deterministic_gzip(compacted, compressed)
        parts = write_parts(compressed, args.output_directory)

    print("build_preseeded_store summary")
    for key, value in audit.items():
        print(f"{key}: {value}")
    for part in parts:
        print(f"wrote: {part} ({part.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, sqlite3.Error, PreseedBuildError) as error:
        raise SystemExit(f"build_preseeded_store.py: error: {error}")
