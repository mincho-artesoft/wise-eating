#!/usr/bin/env python3
"""Audit, compact, gzip, and split a completed Ayura build-time store."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import sqlite3
import tempfile
from pathlib import Path

from build_seed import (
    TARGET_AYURVEDA_LINKS,
    TARGET_FOODS,
    TARGET_INGREDIENT_LINKS,
    TARGET_INGREDIENT_OWNERS,
    TARGET_PROFILES,
    TARGET_RECIPES,
)


TARGET_EXPECTED = {
    "foods": TARGET_FOODS,
    "profiles": TARGET_PROFILES,
    "dravyas": 706,
    "recipes": TARGET_RECIPES,
    "nutritionFull": 1_508,
    "nutritionEstimated": 3,
    "links": TARGET_AYURVEDA_LINKS,
    "cacheFoods": TARGET_FOODS,
    "cacheVersion": 9,
    "inedibleFoods": 6,
    "facetFoods": 4_224,
    "metadataFoods": 4_224,
    "linkedFacetFoods": 2_007,
    "facetKeys": 89,
    "facetAssignments": 59_132,
    "seedVersion": 7,
    "ingredientLinks": TARGET_INGREDIENT_LINKS,
    "ingredientOwners": TARGET_INGREDIENT_OWNERS,
    "allergenTaggedDravyas": 155,
    "allergenTaggedRecipes": 1_190,
    "positiveEnforcedAgeDravyas": 391,
    "positiveEnforcedAgeRecipes": 5,
}

# Backward-compatible name for callers building a new target artifact.
EXPECTED = TARGET_EXPECTED
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
        default=repo_root / "Ayura",
    )
    return parser.parse_args()


def scalar(connection: sqlite3.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    return row[0] if row else None


def require_equal(label: str, actual, expected) -> None:
    if actual != expected:
        raise PreseedBuildError(f"{label}: expected {expected!r}, got {actual!r}")


def audit_store(path: Path, EXPECTED: dict[str, int] = TARGET_EXPECTED) -> dict[str, int]:
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
            "full recipe nutrition panels",
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
            EXPECTED["nutritionFull"],
        )
        require_equal(
            "estimated recipe nutrition panels",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZAYURVEDAPROFILE
                WHERE ZKIND = 'recipe'
                  AND ZNUTRITIONSTATUS = 'estimated'
                  AND ZNUTRITIONPERSERVINGJSON IS NOT NULL
                  AND ZNUTRITIONPER100GJSON IS NOT NULL
                  AND ZNUTRITIONUNITSJSON IS NOT NULL
                """,
            ),
            EXPECTED["nutritionEstimated"],
        )
        require_equal(
            "IngredientLink count",
            scalar(connection, "SELECT COUNT(*) FROM ZINGREDIENTLINK"),
            EXPECTED["ingredientLinks"],
        )
        require_equal(
            "IngredientLink recipe owners",
            scalar(
                connection,
                "SELECT COUNT(DISTINCT ZOWNER) FROM ZINGREDIENTLINK",
            ),
            EXPECTED["ingredientOwners"],
        )
        require_equal(
            "IngredientLink positive grams",
            scalar(
                connection,
                "SELECT COUNT(*) FROM ZINGREDIENTLINK WHERE ZGRAMS > 0",
            ),
            EXPECTED["ingredientLinks"],
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
        profile_food_ids = {
            row[0]
            for row in connection.execute(
                """
                SELECT ZFOODID FROM ZAYURVEDAPROFILE
                WHERE (ZKIND = 'dravya' AND ZID LIKE 'dravya.%')
                   OR (ZKIND = 'recipe' AND ZID LIKE 'recipe.%')
                """
            )
        }
        require_equal(
            "canonical profile food ids",
            len(profile_food_ids),
            EXPECTED["profiles"],
        )
        link_tiers = {
            food_id: tier
            for food_id, tier in connection.execute(
                "SELECT ZFDCID, ZTIER FROM ZAYURVEDALINK"
            )
        }
        linked_only_food_ids = set(link_tiers) - profile_food_ids
        ayurveda_food_ids = profile_food_ids | set(link_tiers)
        require_equal(
            "linked non-profile food ids",
            len(linked_only_food_ids),
            EXPECTED["linkedFacetFoods"],
        )
        require_equal(
            "all Ayurveda metadata food ids",
            len(ayurveda_food_ids),
            EXPECTED["metadataFoods"],
        )
        compact_by_id = {food["id"]: food for food in compact_foods}
        food_ages = {
            food_id: min_age
            for food_id, min_age in connection.execute(
                "SELECT ZID, ZMINAGEMONTHS FROM ZFOODITEM"
            )
        }
        require_equal(
            "compact display ages differ from FoodItem",
            sum(
                food.get("minAgeMonths") != food_ages[food_id]
                for food_id, food in compact_by_id.items()
            ),
            0,
        )
        require_equal(
            "invalid compact enforced ages",
            sum(
                food.get("enforcedMinAgeMonths") is not None
                and (
                    not isinstance(food["enforcedMinAgeMonths"], int)
                    or food["enforcedMinAgeMonths"] < 0
                )
                for food in compact_foods
            ),
            0,
        )
        inedible_food_ids = {
            food_id
            for food_id, is_edible in connection.execute(
                "SELECT ZID, ZISEDIBLE FROM ZFOODITEM"
            )
            if not is_edible
        }
        compact_inedible_food_ids = {
            food["id"] for food in compact_foods if food.get("isEdible") is False
        }
        compact_nil_age_ids = {
            food["id"]
            for food in compact_foods
            if food.get("enforcedMinAgeMonths") is None
        }
        require_equal(
            "inedible FoodItem count",
            len(inedible_food_ids),
            EXPECTED["inedibleFoods"],
        )
        require_equal(
            "compact edibility differs from FoodItem",
            compact_inedible_food_ids,
            inedible_food_ids,
        )
        require_equal(
            "compact nil enforced ages differ from inedible foods",
            compact_nil_age_ids,
            inedible_food_ids,
        )
        # A linked USDA row keeps its own legacy display age while inheriting
        # the canonical profile's safety floor. The inherited floor may
        # therefore exceed the unrelated display value; only non-negativity is
        # a universal invariant here. Canonical and linked inheritance are
        # checked independently below.
        dravya_food_ids = {
            row[0]
            for row in connection.execute(
                "SELECT ZFOODID FROM ZAYURVEDAPROFILE WHERE ZKIND = 'dravya'"
            )
        }
        recipe_food_ids = {
            row[0]
            for row in connection.execute(
                "SELECT ZFOODID FROM ZAYURVEDAPROFILE WHERE ZKIND = 'recipe'"
            )
        }
        require_equal(
            "allergen-tagged canonical dravyas",
            sum(bool(compact_by_id[food_id]["allergens"]) for food_id in dravya_food_ids),
            EXPECTED["allergenTaggedDravyas"],
        )
        require_equal(
            "allergen-tagged canonical recipes",
            sum(bool(compact_by_id[food_id]["allergens"]) for food_id in recipe_food_ids),
            EXPECTED["allergenTaggedRecipes"],
        )
        require_equal(
            "positive enforced-age canonical dravyas",
            sum(
                (compact_by_id[food_id].get("enforcedMinAgeMonths") or 0) > 0
                for food_id in dravya_food_ids
            ),
            EXPECTED["positiveEnforcedAgeDravyas"],
        )
        require_equal(
            "positive enforced-age canonical recipes",
            sum(
                (compact_by_id[food_id].get("enforcedMinAgeMonths") or 0) > 0
                for food_id in recipe_food_ids
            ),
            EXPECTED["positiveEnforcedAgeRecipes"],
        )
        require_equal(
            "canonical enforced-floor domain",
            {
                compact_by_id[food_id].get("enforcedMinAgeMonths")
                for food_id in profile_food_ids
            },
            {None, 0, 6, 12, 60},
        )
        require_equal(
            "non-Ayurveda age enforcement differs from display",
            sum(
                food["enforcedMinAgeMonths"] != food["minAgeMonths"]
                for food_id, food in compact_by_id.items()
                if food_id not in ayurveda_food_ids
            ),
            0,
        )
        metadata_by_id = {
            food_id: food.get("ayurvedaMetadata")
            for food_id, food in compact_by_id.items()
            if isinstance(food.get("ayurvedaMetadata"), dict)
        }
        require_equal(
            "foods with Ayurveda metadata",
            set(metadata_by_id),
            ayurveda_food_ids,
        )
        require_equal(
            "metadata facets differ from compact facets",
            sum(
                set(metadata["facets"]) != set(compact_by_id[food_id]["ayurvedaFacets"])
                for food_id, metadata in metadata_by_id.items()
            ),
            0,
        )
        require_equal(
            "metadata enforced ages differ from compact ages",
            sum(
                metadata.get("enforcedMinAgeMonths")
                != compact_by_id[food_id].get("enforcedMinAgeMonths")
                for food_id, metadata in metadata_by_id.items()
            ),
            0,
        )
        metadata_nil_age_ids = {
            food_id
            for food_id, metadata in metadata_by_id.items()
            if metadata.get("enforcedMinAgeMonths") is None
        }
        require_equal(
            "metadata nil enforced ages differ from inedible foods",
            metadata_nil_age_ids,
            inedible_food_ids,
        )
        require_equal(
            "edible Ayurveda metadata missing enforced ages",
            sum(
                metadata.get("enforcedMinAgeMonths") is None
                for food_id, metadata in metadata_by_id.items()
                if food_id not in inedible_food_ids
            ),
            0,
        )
        require_equal(
            "direct profile metadata unexpectedly has a source tier",
            sum(
                metadata_by_id[food_id].get("sourceTier") is not None
                for food_id in profile_food_ids
            ),
            0,
        )
        require_equal(
            "linked metadata source tier mismatches",
            sum(
                metadata_by_id[food_id].get("sourceTier") != link_tiers[food_id]
                for food_id in linked_only_food_ids
            ),
            0,
        )
        require_equal(
            "invalid Ayurveda metadata dosha values",
            sum(
                any(
                    not isinstance(metadata.get(key), int)
                    or metadata[key] < -2
                    or metadata[key] > 2
                    for key in ("doshaVata", "doshaPitta", "doshaKapha")
                )
                for metadata in metadata_by_id.values()
            ),
            0,
        )
        require_equal(
            "invalid Ayurveda metadata confidence values",
            sum(
                not isinstance(metadata.get("confidenceAyur"), (int, float))
                or metadata["confidenceAyur"] < 0
                or metadata["confidenceAyur"] > 1
                for metadata in metadata_by_id.values()
            ),
            0,
        )
        require_equal(
            "empty Ayurveda metadata source names",
            sum(
                not isinstance(metadata.get("sourceProfileName"), str)
                or not metadata["sourceProfileName"].strip()
                for metadata in metadata_by_id.values()
            ),
            0,
        )
        faceted_food_ids = {
            food_id
            for food_id, food in compact_by_id.items()
            if food.get("ayurvedaFacets")
        }
        require_equal(
            "faceted compact foods",
            faceted_food_ids,
            ayurveda_food_ids,
        )
        require_equal(
            "faceted compact food count",
            len(faceted_food_ids),
            EXPECTED["facetFoods"],
        )
        facet_index = payload.get("ayurvedaFacetIndex")
        if not isinstance(facet_index, dict):
            raise PreseedBuildError("search payload ayurvedaFacetIndex is not an object")
        allowed_facet_kinds = {
            "virya",
            "rasa",
            "vipaka",
            "guna",
            "pacifies",
            "aggravates",
            "agni",
            "digestibility",
            "season",
            "time",
            "category",
            "concept",
        }
        invalid_facet_keys = {
            key
            for key in facet_index
            if ":" not in key or key.split(":", 1)[0] not in allowed_facet_kinds
        }
        require_equal("invalid Ayurveda facet keys", invalid_facet_keys, set())
        expected_facet_index: dict[str, set[int]] = {}
        for food in compact_foods:
            for facet in food.get("ayurvedaFacets", []):
                expected_facet_index.setdefault(facet, set()).add(food["id"])
        actual_facet_index = {
            key: set(food_ids) for key, food_ids in facet_index.items()
        }
        require_equal(
            "Ayurveda facet inverted index",
            actual_facet_index,
            expected_facet_index,
        )
        require_equal(
            "Ayurveda facets leaked into text index",
            set(facet_index).intersection(payload.get("invertedIndex", {})),
            set(),
        )
        require_equal(
            "Ayurveda facet key count",
            len(facet_index),
            EXPECTED["facetKeys"],
        )
        facet_assignments = sum(
            len(food.get("ayurvedaFacets", [])) for food in compact_foods
        )
        require_equal(
            "Ayurveda facet assignment count",
            facet_assignments,
            EXPECTED["facetAssignments"],
        )
        return {
            "foods": EXPECTED["foods"],
            "profiles": EXPECTED["profiles"],
            "links": EXPECTED["links"],
            "ingredientLinks": EXPECTED["ingredientLinks"],
            "ingredientOwners": EXPECTED["ingredientOwners"],
            "nutritionFull": EXPECTED["nutritionFull"],
            "nutritionEstimated": EXPECTED["nutritionEstimated"],
            "cacheFoods": cache_foods,
            "cacheVersion": cache_version,
            "facetFoods": len(faceted_food_ids),
            "metadataFoods": len(metadata_by_id),
            "linkedFacetFoods": len(linked_only_food_ids),
            "facetKeys": len(facet_index),
            "facetAssignments": facet_assignments,
            "allergenTaggedDravyas": EXPECTED["allergenTaggedDravyas"],
            "allergenTaggedRecipes": EXPECTED["allergenTaggedRecipes"],
            "positiveEnforcedAgeDravyas": EXPECTED["positiveEnforcedAgeDravyas"],
            "positiveEnforcedAgeRecipes": EXPECTED["positiveEnforcedAgeRecipes"],
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
    with tempfile.TemporaryDirectory(prefix="ayura-preseed-") as temporary:
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
