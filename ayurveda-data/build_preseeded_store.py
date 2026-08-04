#!/usr/bin/env python3
"""Audit, compact, gzip, and split a completed Ayura build-time store."""

from __future__ import annotations

import argparse
import gzip
import json
import math
import os
import re
import sqlite3
import tempfile
import uuid
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
    "dravyas": 704,
    "recipes": TARGET_RECIPES,
    "nutritionFull": 1_508,
    "nutritionEstimated": 3,
    "links": TARGET_AYURVEDA_LINKS,
    "cacheFoods": TARGET_FOODS,
    "cacheVersion": 13,
    "inedibleFoods": 6,
    "facetFoods": TARGET_FOODS,
    "metadataFoods": TARGET_FOODS,
    "linkedFacetFoods": 2_007,
    "facetKeys": 45,
    "facetAssignments": 99_439,
    "seedVersion": 10,
    "ingredientLinks": TARGET_INGREDIENT_LINKS,
    "ingredientOwners": TARGET_INGREDIENT_OWNERS,
    "allergenTaggedDravyas": 155,
    "allergenTaggedRecipes": 1_190,
    "positiveEnforcedAgeDravyas": 389,
    "positiveEnforcedAgeRecipes": 5,
    "yogaAsanas": 908,
    "yogaSequences": 4_419,
}

# Backward-compatible name for callers building a new target artifact.
EXPECTED = TARGET_EXPECTED
PART_SIZE = 70 * 1024 * 1024
PART_SUFFIXES = ("aa", "ab", "ac")


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


def uuid_key(value) -> str:
    if isinstance(value, bytes):
        return str(uuid.UUID(bytes=value))
    return str(uuid.UUID(str(value)))


def require_equal(label: str, actual, expected) -> None:
    if actual != expected:
        raise PreseedBuildError(f"{label}: expected {expected!r}, got {actual!r}")


def normalized_modifier_tokens(value: str) -> list[str]:
    value = value.lower()
    value = re.sub(r"\([^)]*\)", "", value)
    value = value.replace("&", " and ")
    value = re.sub(r"[^a-z0-9,;'\- ]", " ", value)
    value = value.replace(",", " ").replace(";", " ")
    return [token for token in re.split(r"[\s\-'/]+", value) if token]


def modifier_applies(food_tokens: list[str], phrase: str) -> bool:
    phrase_tokens = normalized_modifier_tokens(phrase)
    width = len(phrase_tokens)
    if width == 0 or width > len(food_tokens):
        return False
    return any(
        food_tokens[index:index + width] == phrase_tokens
        for index in range(len(food_tokens) - width + 1)
    )


def normalized_facet_value(value: str) -> str:
    value = value.lower().strip().replace("_", "-").replace(" ", "-")
    return re.sub(r"-+", "-", value)


def estimated_search_metadata(
    *,
    food_name: str,
    enforced_min_age_months: int,
    default_rule: dict,
    modifiers: list[dict],
) -> dict:
    rule = default_rule
    food_tokens = normalized_modifier_tokens(food_name)
    applied = [
        modifier
        for modifier in modifiers
        if any(
            modifier_applies(food_tokens, phrase)
            for phrase in modifier.get("phrases", [])
        )
    ]
    modifier_totals = [0, 0, 0]
    gunas = list(rule["gunas"])
    for modifier in applied:
        modifier_totals = [
            total + delta
            for total, delta in zip(
                modifier_totals,
                modifier["vpk"],
                strict=True,
            )
        ]
        for guna in modifier.get("gunas", []):
            if guna not in gunas:
                gunas.append(guna)
    vpk = [
        max(-2, min(2, value + delta))
        for value, delta in zip(
            rule["vpk"],
            modifier_totals,
            strict=True,
        )
    ]

    facets = {f"virya:{normalized_facet_value(rule['virya'])}"}
    for guna in gunas:
        facets.add(f"guna:{normalized_facet_value(guna)}")
    for dosha, value in zip(("vata", "pitta", "kapha"), vpk, strict=True):
        if value < 0:
            facets.add(f"pacifies:{dosha}")
        elif value > 0:
            facets.add(f"aggravates:{dosha}")
    return {
        "contraindications": [],
        "sourceTier": "estimated",
        "sourceProfileName": "default Ayurveda rule",
        "doshaPitta": vpk[1],
        "confidenceAyur": 0.25,
        "virya": rule["virya"],
        "doshaVata": vpk[0],
        "facets": sorted(facets),
        "rasa": [],
        "doshaKapha": vpk[2],
        "timeOfDay": [],
        "gunas": gunas,
        "enforcedMinAgeMonths": enforced_min_age_months,
        "seasons": [],
    }


def add_estimated_search_fallbacks(store: Path) -> None:
    rules_path = Path(__file__).resolve().parent.parent / "Ayura" / "ayurveda_rules.json"
    rules = json.loads(rules_path.read_text(encoding="utf-8"))
    with sqlite3.connect(store) as connection:
        row = connection.execute(
            """
            SELECT ZPAYLOADDATA FROM ZSEARCHINDEXCACHE
            WHERE ZKEY = 'main'
            """
        ).fetchone()
        if row is None:
            raise PreseedBuildError("main search cache is missing")
        payload = json.loads(row[0])
        payload.pop("knownDiets", None)
        food_rows = {
            uuid_key(food_id): name
            for food_id, name in connection.execute(
                "SELECT ZID, ZNAME FROM ZFOODITEM"
            )
        }

        # Swift's UUID encoder emits upper-case strings. Canonicalize every
        # identity carried by the JSON cache so the shipped graph has one
        # byte-for-byte representation across repeated builds.
        for compact in payload["compactFoods"]:
            compact["id"] = uuid_key(compact["id"])
        for collection_key in ("invertedIndex", "nutrientRankings"):
            payload[collection_key] = {
                key: [uuid_key(value) for value in values]
                for key, values in payload.get(collection_key, {}).items()
            }

        for compact in payload["compactFoods"]:
            compact.pop("diets", None)
            existing_metadata = compact.get("ayurvedaMetadata")
            if isinstance(existing_metadata, dict):
                existing_metadata.pop("category", None)
                existing_metadata["facets"] = [
                    facet
                    for facet in existing_metadata.get("facets", [])
                    if not facet.startswith("category:")
                    and (
                        not facet.startswith("concept:")
                        or facet == "concept:digestion"
                    )
                ]
                compact["ayurvedaFacets"] = [
                    facet
                    for facet in compact.get("ayurvedaFacets", [])
                    if not facet.startswith("category:")
                    and (
                        not facet.startswith("concept:")
                        or facet == "concept:digestion"
                    )
                ]
                continue
            food_id = uuid_key(compact["id"])
            food_name = food_rows[food_id]
            metadata = estimated_search_metadata(
                food_name=food_name,
                enforced_min_age_months=compact["minAgeMonths"],
                default_rule=rules["default"],
                modifiers=rules["modifiers"],
            )
            compact["ayurvedaMetadata"] = metadata
            compact["ayurvedaFacets"] = metadata["facets"]

        facet_index: dict[str, list[str]] = {}
        for compact in payload["compactFoods"]:
            for facet in compact["ayurvedaFacets"]:
                facet_index.setdefault(facet, []).append(compact["id"])
        payload["ayurvedaFacetIndex"] = {
            facet: sorted(food_ids)
            for facet, food_ids in sorted(facet_index.items())
        }
        payload_data = json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        connection.execute(
            """
            UPDATE ZSEARCHINDEXCACHE
            SET ZVERSION = ?, ZPAYLOADDATA = ?, Z_OPT = Z_OPT + 1
            WHERE ZKEY = 'main'
            """,
            (EXPECTED["cacheVersion"], payload_data),
        )
        connection.commit()


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
        category_columns = [
            (table_name, column[1])
            for (table_name,) in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            for column in connection.execute(f'PRAGMA table_info("{table_name}")')
            if "CATEGORY" in column[1].upper()
        ]
        require_equal(
            "category columns",
            category_columns,
            [],
        )
        head_circumference_columns = [
            (table_name, column[1])
            for (table_name,) in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            for column in connection.execute(f'PRAGMA table_info("{table_name}")')
            if "HEADCIRCUMFERENCE" in column[1].upper()
        ]
        require_equal(
            "head circumference columns",
            head_circumference_columns,
            [],
        )
        badge_columns = [
            (table_name, column[1])
            for (table_name,) in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            for column in connection.execute(f'PRAGMA table_info("{table_name}")')
            if "BADGE" in column[1].upper()
        ]
        require_equal(
            "badge columns",
            badge_columns,
            [],
        )
        exercise_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(ZEXERCISEITEM)")
        }
        require_equal(
            "ExerciseItem removed fields",
            exercise_columns.intersection({"ZSPORT", "ZSPORTS"}),
            set(),
        )
        require_equal(
            "Yoga asana count",
            scalar(connection, "SELECT COUNT(*) FROM ZEXERCISEITEM"),
            EXPECTED["yogaAsanas"],
        )
        require_equal(
            "Yoga asana UUID count",
            scalar(connection, "SELECT COUNT(DISTINCT ZID) FROM ZEXERCISEITEM"),
            EXPECTED["yogaAsanas"],
        )
        require_equal(
            "Yoga asana catalogue range",
            connection.execute(
                "SELECT MIN(ZCATALOGNUMBER), MAX(ZCATALOGNUMBER) "
                "FROM ZEXERCISEITEM"
            ).fetchone(),
            (800_000, 800_907),
        )
        require_equal(
            "Yoga asanas missing search metadata",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZEXERCISEITEM
                WHERE ZFAMILY IS NULL OR ZSANSKRIT IS NULL
                   OR ZNAMENORMALIZED IS NULL OR LENGTH(ZNAMENORMALIZED) = 0
                   OR ZSEARCHTOKENS IS NULL OR LENGTH(ZSEARCHTOKENS) = 0
                   OR ZSEARCHTOKENS2 IS NULL OR LENGTH(ZSEARCHTOKENS2) = 0
                """,
            ),
            0,
        )
        require_equal(
            "Yoga sequence count",
            scalar(connection, "SELECT COUNT(*) FROM ZYOGASEQUENCE"),
            EXPECTED["yogaSequences"],
        )
        require_equal(
            "Yoga sequence UUID count",
            scalar(connection, "SELECT COUNT(DISTINCT ZID) FROM ZYOGASEQUENCE"),
            EXPECTED["yogaSequences"],
        )
        require_equal(
            "Yoga sequence catalogue range",
            connection.execute(
                "SELECT MIN(ZCATALOGNUMBER), MAX(ZCATALOGNUMBER) "
                "FROM ZYOGASEQUENCE"
            ).fetchone(),
            (700_001, 704_419),
        )
        require_equal(
            "Yoga sequences missing poses",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZYOGASEQUENCE
                WHERE ZPOSESDATA IS NULL OR LENGTH(ZPOSESDATA) = 0
                """,
            ),
            0,
        )
        profile_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(ZPROFILE)")
        }
        require_equal(
            "Profile removed fields",
            profile_columns.intersection(
                {"ZGOAL", "ZACTIVITYLEVEL", "ZSPORT", "ZSPORTS", "ZDIET", "ZDIETS"}
            ),
            set(),
        )
        diet_schema_objects = [
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE UPPER(name) LIKE '%DIET%'"
            )
        ]
        require_equal("diet schema objects", diet_schema_objects, [])
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
            "catalogue profile count",
            scalar(
                connection,
                "SELECT COUNT(*) FROM ZAYURVEDAPROFILE WHERE ZKIND = 'catalog'",
            ),
            TARGET_PROFILES - EXPECTED["dravyas"] - EXPECTED["recipes"],
        )
        require_equal(
            "canonical slug prefixes",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZAYURVEDAPROFILE
                WHERE (ZKIND = 'dravya' AND ZKEY NOT LIKE 'dravya.%')
                   OR (ZKIND = 'recipe' AND ZKEY NOT LIKE 'recipe.%')
                   OR (ZKIND = 'catalog' AND ZKEY NOT LIKE 'catalog.usda.%')
                """,
            ),
            0,
        )
        require_equal(
            "profile quality lifecycle",
            scalar(
                connection,
                """
                SELECT COUNT(*) FROM ZAYURVEDAPROFILE
                WHERE (ZKIND = 'catalog' AND COALESCE(ZQUALITYSTATE, '') != 'catalogRule')
                   OR (ZKIND != 'catalog' AND COALESCE(ZQUALITYSTATE, '') != 'aiDraft')
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
                  SELECT ZFOODID FROM ZAYURVEDALINK
                  GROUP BY ZFOODID HAVING COUNT(*) > 1
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
            len(compact_foods) - len({uuid_key(food["id"]) for food in compact_foods}),
            0,
        )
        require_equal(
            "search payload diet fields",
            sum("diets" in food for food in compact_foods),
            0,
        )
        profile_food_ids = {
            uuid_key(row[0])
            for row in connection.execute(
                """
                SELECT ZFOODID FROM ZAYURVEDAPROFILE
                WHERE (ZKIND = 'dravya' AND ZKEY LIKE 'dravya.%')
                   OR (ZKIND = 'recipe' AND ZKEY LIKE 'recipe.%')
                   OR (ZKIND = 'catalog' AND ZKEY LIKE 'catalog.usda.%')
                """
            )
        }
        require_equal(
            "canonical profile food ids",
            len(profile_food_ids),
            EXPECTED["profiles"],
        )
        link_tiers = {
            uuid_key(food_id): tier
            for food_id, tier in connection.execute(
                "SELECT ZFOODID, ZTIER FROM ZAYURVEDALINK"
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
            "direct and linked Ayurveda food ids",
            len(ayurveda_food_ids),
            EXPECTED["profiles"] + EXPECTED["linkedFacetFoods"],
        )
        compact_by_id = {uuid_key(food["id"]): food for food in compact_foods}
        food_ages = {
            uuid_key(food_id): min_age
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
            uuid_key(food_id)
            for food_id, is_edible in connection.execute(
                "SELECT ZID, ZISEDIBLE FROM ZFOODITEM"
            )
            if not is_edible
        }
        compact_inedible_food_ids = {
            uuid_key(food["id"])
            for food in compact_foods
            if food.get("isEdible") is False
        }
        compact_nil_age_ids = {
            uuid_key(food["id"])
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
            uuid_key(row[0])
            for row in connection.execute(
                "SELECT ZFOODID FROM ZAYURVEDAPROFILE WHERE ZKIND = 'dravya'"
            )
        }
        recipe_food_ids = {
            uuid_key(row[0])
            for row in connection.execute(
                "SELECT ZFOODID FROM ZAYURVEDAPROFILE WHERE ZKIND = 'recipe'"
            )
        }
        catalog_food_ids = {
            uuid_key(row[0])
            for row in connection.execute(
                "SELECT ZFOODID FROM ZAYURVEDAPROFILE WHERE ZKIND = 'catalog'"
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
            "authored canonical enforced-floor domain",
            {
                compact_by_id[food_id].get("enforcedMinAgeMonths")
                for food_id in dravya_food_ids | recipe_food_ids
            },
            {None, 0, 6, 12, 60},
        )
        require_equal(
            "non-Ayurveda age enforcement differs from display",
            sum(
                food.get("enforcedMinAgeMonths") != food["minAgeMonths"]
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
            set(compact_by_id),
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
            "authored profile metadata unexpectedly has a source tier",
            sum(
                metadata_by_id[food_id].get("sourceTier") is not None
                for food_id in dravya_food_ids | recipe_food_ids
            ),
            0,
        )
        require_equal(
            "catalogue metadata source tier mismatches",
            sum(
                metadata_by_id[food_id].get("sourceTier") != "catalog"
                for food_id in catalog_food_ids
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
        estimated_food_ids = set(compact_by_id) - ayurveda_food_ids
        require_equal(
            "estimated fallback metadata source tier mismatches",
            sum(
                metadata_by_id[food_id].get("sourceTier") != "estimated"
                for food_id in estimated_food_ids
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
        require_equal(
            "removed category metadata fields",
            sum("category" in metadata for metadata in metadata_by_id.values()),
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
            set(compact_by_id),
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
            "concept",
        }
        invalid_facet_keys = {
            key
            for key in facet_index
            if ":" not in key or key.split(":", 1)[0] not in allowed_facet_kinds
        }
        require_equal("invalid Ayurveda facet keys", invalid_facet_keys, set())
        require_equal(
            "removed category facets",
            {key for key in facet_index if key.startswith("category:")},
            set(),
        )
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
            "yogaAsanas": EXPECTED["yogaAsanas"],
            "yogaSequences": EXPECTED["yogaSequences"],
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


def write_parts(gzip_path: Path, output_directory: Path) -> tuple[Path, ...]:
    size = gzip_path.stat().st_size
    if size > PART_SIZE * len(PART_SUFFIXES):
        raise PreseedBuildError(
            f"compressed store is {size} bytes; "
            f"{len(PART_SUFFIXES)} 70 MiB parts are insufficient"
        )
    output_directory.mkdir(parents=True, exist_ok=True)
    part_count = max(2, math.ceil(size / PART_SIZE))
    outputs = tuple(
        output_directory / f"preseeded_db.store.gz.part-{suffix}"
        for suffix in PART_SUFFIXES[:part_count]
    )
    with gzip_path.open("rb") as source:
        for output in outputs:
            temporary = output.with_suffix(output.suffix + ".tmp")
            with temporary.open("wb") as destination:
                destination.write(source.read(PART_SIZE))
            os.replace(temporary, output)
    for suffix in PART_SUFFIXES[part_count:]:
        stale = output_directory / f"preseeded_db.store.gz.part-{suffix}"
        if stale.exists():
            stale.unlink()
    return outputs


def main() -> int:
    args = parse_args()
    source = args.source_store.resolve()
    with tempfile.TemporaryDirectory(prefix="ayura-preseed-") as temporary:
        temporary_root = Path(temporary)
        compacted = temporary_root / "default.store"
        compressed = temporary_root / "preseeded_db.store.gz"
        compact_store(source, compacted)
        add_estimated_search_fallbacks(compacted)
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
