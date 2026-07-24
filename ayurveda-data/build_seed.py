#!/usr/bin/env python3
"""Build the deterministic Ayurveda seed bundle consumed by the app."""

from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


SEED_VERSION = 3
GENERATED_AT = "2026-07-24T00:00:00Z"
EXPECTED_COUNTS = {
    "dravyas": 714,
    "recipes": 1500,
    "links": 2305,
    "derivedLinks": 1969,
    "placeholders": 383,
    "primaries": 331,
    "categoryRules": 187,
    "modifiers": 14,
}
V1_LINK_COUNT = 336
ENGINE_EXCLUDED_IDS = {"dravya.betel-nut", "dravya.vanaspati"}
PLACEHOLDER_BASE = 900_000
RECIPE_BASE = 1_000_000
RESERVED_BAND_END = 1_002_000
TIER_RANK = {"exact": 0, "near": 1}
NUTRIENT_CATALOG = {
    "energyKcal": ("other", "kcal"),
    "carbohydrates": ("macronutrients", "g"),
    "protein": ("macronutrients", "g"),
    "fat": ("macronutrients", "g"),
    "fiber": ("macronutrients", "g"),
    "totalSugars": ("macronutrients", "g"),
    "vitaminA_RAE": ("vitamins", "µg"),
    "retinol": ("vitamins", "µg"),
    "caroteneAlpha": ("vitamins", "µg"),
    "caroteneBeta": ("vitamins", "µg"),
    "cryptoxanthinBeta": ("vitamins", "µg"),
    "luteinZeaxanthin": ("vitamins", "µg"),
    "lycopene": ("vitamins", "µg"),
    "vitaminB1_Thiamin": ("vitamins", "mg"),
    "vitaminB2_Riboflavin": ("vitamins", "mg"),
    "vitaminB3_Niacin": ("vitamins", "mg"),
    "vitaminB5_PantothenicAcid": ("vitamins", "mg"),
    "vitaminB6": ("vitamins", "mg"),
    "folateDFE": ("vitamins", "µg"),
    "folateFood": ("vitamins", "µg"),
    "folateTotal": ("vitamins", "µg"),
    "folicAcid": ("vitamins", "µg"),
    "vitaminB12": ("vitamins", "µg"),
    "vitaminC": ("vitamins", "mg"),
    "vitaminD": ("vitamins", "µg"),
    "vitaminE": ("vitamins", "mg"),
    "vitaminK": ("vitamins", "µg"),
    "choline": ("vitamins", "mg"),
    "calcium": ("minerals", "mg"),
    "iron": ("minerals", "mg"),
    "magnesium": ("minerals", "mg"),
    "phosphorus": ("minerals", "mg"),
    "potassium": ("minerals", "mg"),
    "sodium": ("minerals", "mg"),
    "selenium": ("minerals", "µg"),
    "zinc": ("minerals", "mg"),
    "copper": ("minerals", "mg"),
    "manganese": ("minerals", "mg"),
    "fluoride": ("minerals", "µg"),
}


class BuildError(RuntimeError):
    """Raised when source data cannot produce the approved seed layout."""


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--store",
        type=Path,
        required=True,
        help="Directory containing default.store, or the store file itself",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "WiseEating" / "ayurveda_seed.json.gz",
        help="Destination gzip bundle",
    )
    parser.add_argument(
        "--rules-output",
        type=Path,
        default=repo_root / "WiseEating" / "ayurveda_rules.json",
        help="Destination category-rule bundle",
    )
    parser.add_argument(
        "--foods",
        type=Path,
        default=repo_root / "WiseEating" / "Legacy" / "foods.json",
        help="USDA-backed per-100g nutrient source used to build the shipped store",
    )
    return parser.parse_args()


def store_path(path: Path) -> Path:
    candidate = path / "default.store" if path.is_dir() else path
    if not candidate.is_file():
        raise BuildError(f"store does not exist: {candidate}")
    return candidate


def load_batches(directory: Path, pattern: str, collection_key: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    seen: set[str] = set()
    paths = sorted(directory.glob(pattern))
    if not paths:
        raise BuildError(f"no inputs matched {directory / pattern}")

    for path in paths:
        try:
            envelope = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise BuildError(f"cannot read {path}: {error}") from error
        quality_state = envelope.get("qualityState")
        if not isinstance(quality_state, str):
            raise BuildError(f"{path}: missing envelope qualityState")
        batch_items = envelope.get(collection_key)
        if not isinstance(batch_items, list):
            raise BuildError(f"{path}: missing {collection_key} array")
        for item in batch_items:
            item_id = item.get("id") if isinstance(item, dict) else None
            if not isinstance(item_id, str):
                raise BuildError(f"{path}: item has no string id")
            if item_id in seen:
                raise BuildError(f"duplicate id: {item_id}")
            seen.add(item_id)
            copied = dict(item)
            copied["qualityState"] = quality_state
            items.append(copied)
    return items


def load_store_ids(path: Path) -> set[int]:
    try:
        with sqlite3.connect(path) as connection:
            rows = connection.execute("SELECT ZID FROM ZFOODITEM").fetchall()
    except sqlite3.Error as error:
        raise BuildError(f"cannot query ZFOODITEM.ZID in {path}: {error}") from error
    return {int(row[0]) for row in rows}


def load_food_nutrition(
    path: Path, store_ids: set[int]
) -> dict[int, dict[str, float]]:
    try:
        foods = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load USDA nutrient source {path}: {error}") from error
    if not isinstance(foods, list):
        raise BuildError(f"{path}: expected a top-level array")

    nutrition_by_id: dict[int, dict[str, float]] = {}
    for food in foods:
        if not isinstance(food, dict) or not isinstance(food.get("id"), int):
            raise BuildError(f"{path}: food has no integer id")
        food_id = food["id"]
        if food_id in nutrition_by_id:
            raise BuildError(f"{path}: duplicate food id {food_id}")

        panel: dict[str, float] = {}
        for nutrient, (section, expected_unit) in NUTRIENT_CATALOG.items():
            entry = food.get(section, {}).get(nutrient)
            if not isinstance(entry, dict):
                raise BuildError(f"{path}: food {food_id} is missing {section}.{nutrient}")
            unit = entry.get("unit")
            if unit != expected_unit:
                raise BuildError(
                    f"{path}: food {food_id} {nutrient} uses {unit!r}, "
                    f"expected {expected_unit!r}"
                )
            value = entry.get("value")
            if value is not None:
                if not isinstance(value, (int, float)) or value < 0:
                    raise BuildError(
                        f"{path}: food {food_id} {nutrient} has invalid value {value!r}"
                    )
                panel[nutrient] = float(value)
        nutrition_by_id[food_id] = panel

    missing_source_ids = sorted(nutrition_by_id.keys() - store_ids)
    if missing_source_ids:
        preview = ", ".join(str(food_id) for food_id in missing_source_ids[:10])
        raise BuildError(f"{path}: nutrient source food ids are absent from store: {preview}")
    return nutrition_by_id


def preferred_nutrition_bindings(
    bindings_by_dravya: dict[str, list[tuple[int, str, int]]],
) -> dict[str, int]:
    preferred: dict[str, int] = {}
    for dravya_id, bindings in bindings_by_dravya.items():
        ordered = sorted(
            bindings,
            key=lambda binding: (TIER_RANK[binding[1]], binding[2]),
        )
        if ordered:
            preferred[dravya_id] = ordered[0][0]
    return preferred


def rounded(value: float) -> float:
    return round(value, 12)


def derive_recipe_nutrition(
    recipe: dict[str, Any],
    nutrition_by_id: dict[int, dict[str, float]],
    preferred_bindings: dict[str, int],
) -> tuple[dict[str, Any], list[int | None]]:
    servings = recipe.get("servings")
    if not isinstance(servings, (int, float)) or servings <= 0:
        raise BuildError(f"{recipe['id']}: servings must be greater than zero")

    totals: dict[str, float] = defaultdict(float)
    observed: set[str] = set()
    missing_slugs: list[str] = []
    nutrition_source_ids: list[int | None] = []
    total_weight = 0.0

    for ingredient in recipe.get("ingredients", []):
        grams = ingredient.get("grams")
        if not isinstance(grams, (int, float)) or grams < 0:
            raise BuildError(f"{recipe['id']}: invalid ingredient grams {grams!r}")
        total_weight += float(grams)

        nutrition_id: int | None
        missing_slug: str
        if "dravyaId" in ingredient:
            missing_slug = str(ingredient["dravyaId"])
            nutrition_id = preferred_bindings.get(missing_slug)
        else:
            candidate = ingredient.get("fdcId")
            nutrition_id = candidate if isinstance(candidate, int) else None
            missing_slug = f"fdc.{candidate}" if candidate is not None else ingredient["name"]

        panel = nutrition_by_id.get(nutrition_id) if nutrition_id is not None else None
        if panel is None:
            missing_slugs.append(missing_slug)
            nutrition_source_ids.append(None)
            continue

        nutrition_source_ids.append(nutrition_id)
        factor = float(grams) / 100.0
        for nutrient, value in panel.items():
            totals[nutrient] += factor * value
            observed.add(nutrient)

    if total_weight <= 0:
        raise BuildError(f"{recipe['id']}: total ingredient weight must be greater than zero")

    if not totals:
        status = "none"
    elif missing_slugs:
        status = "estimated"
    else:
        status = "full"

    per_serving = {
        nutrient: rounded(totals[nutrient] / float(servings))
        for nutrient in NUTRIENT_CATALOG
        if nutrient in observed
    }
    per_100g = {
        nutrient: rounded(totals[nutrient] * 100.0 / total_weight)
        for nutrient in NUTRIENT_CATALOG
        if nutrient in observed
    }
    return (
        {
            "status": status,
            "missingIngredients": sorted(set(missing_slugs)),
            "totalWeightG": rounded(total_weight),
            "perServing": per_serving,
            "per100g": per_100g,
            "units": {
                nutrient: unit
                for nutrient, (_section, unit) in NUTRIENT_CATALOG.items()
            },
        },
        nutrition_source_ids,
    )


def load_crosswalk_links(
    path: Path,
    store_ids: set[int],
    dravya_ids: set[str],
    v1_fdc_ids: set[int],
) -> list[dict[str, Any]]:
    links: list[dict[str, Any]] = []
    seen: set[int] = set()
    try:
        with path.open(encoding="utf-8", newline="") as source:
            rows = csv.DictReader(source)
            expected_fields = [
                "fdcId", "name", "category", "dravyaId", "rule", "key",
                "contested", "losers",
            ]
            if rows.fieldnames != expected_fields:
                raise BuildError(f"{path}: unexpected crosswalk header {rows.fieldnames}")
            for row in rows:
                try:
                    fdc_id = int(row["fdcId"])
                except (TypeError, ValueError) as error:
                    raise BuildError(f"{path}: invalid fdcId {row.get('fdcId')!r}") from error
                dravya_id = row["dravyaId"]
                if fdc_id not in store_ids:
                    raise BuildError(f"crosswalk fdcId {fdc_id} is absent from the store")
                if fdc_id in v1_fdc_ids:
                    raise BuildError(f"crosswalk fdcId {fdc_id} collides with a v1 link")
                if fdc_id in seen:
                    raise BuildError(f"duplicate crosswalk fdcId: {fdc_id}")
                if dravya_id not in dravya_ids:
                    raise BuildError(f"crosswalk fdcId {fdc_id}: unknown dravyaId {dravya_id}")
                seen.add(fdc_id)
                links.append({"fdcId": fdc_id, "dravyaId": dravya_id, "tier": "derived"})
    except OSError as error:
        raise BuildError(f"cannot read {path}: {error}") from error
    if len(links) != EXPECTED_COUNTS["derivedLinks"]:
        raise BuildError(
            f"derived-link gate failed: expected {EXPECTED_COUNTS['derivedLinks']}, got {len(links)}"
        )
    if [link["fdcId"] for link in links] != sorted(link["fdcId"] for link in links):
        raise BuildError("crosswalk rows are not sorted by fdcId")
    return links


def load_rules_bundle(data_root: Path) -> dict[str, Any]:
    category_path = data_root / "rules" / "category-rules.json"
    modifier_path = data_root / "rules" / "modifiers.json"
    try:
        category_source = json.loads(category_path.read_text(encoding="utf-8"))
        modifier_source = json.loads(modifier_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load Ayurveda rules: {error}") from error
    categories = category_source.get("categories")
    modifiers = modifier_source.get("modifiers")
    if not isinstance(categories, list) or len(categories) != EXPECTED_COUNTS["categoryRules"]:
        raise BuildError(
            f"category-rule gate failed: expected {EXPECTED_COUNTS['categoryRules']}"
        )
    if not isinstance(modifiers, list) or len(modifiers) != EXPECTED_COUNTS["modifiers"]:
        raise BuildError(f"modifier gate failed: expected {EXPECTED_COUNTS['modifiers']}")
    return {
        "rulesVersion": category_source.get("rulesVersion"),
        "categories": categories,
        "default": category_source.get("default"),
        "modifiers": modifiers,
    }


def validate_bindings(
    dravyas: list[dict[str, Any]], store_ids: set[int]
) -> tuple[dict[int, list[tuple[str, str, int]]], dict[str, list[tuple[int, str, int]]]]:
    claims: dict[int, list[tuple[str, str, int]]] = defaultdict(list)
    bindings_by_dravya: dict[str, list[tuple[int, str, int]]] = {}
    for dravya in dravyas:
        dravya_id = dravya["id"]
        bindings: list[tuple[int, str, int]] = []
        for position, binding in enumerate(dravya.get("usda", [])):
            fdc_id = binding.get("fdcId")
            tier = binding.get("tier")
            if not isinstance(fdc_id, int) or fdc_id not in store_ids:
                raise BuildError(f"{dravya_id}: fdcId {fdc_id!r} is absent from the store")
            if tier not in TIER_RANK:
                raise BuildError(f"{dravya_id}: unsupported USDA tier {tier!r}")
            claims[fdc_id].append((dravya_id, tier, position))
            bindings.append((fdc_id, tier, position))
        bindings_by_dravya[dravya_id] = bindings
    return claims, bindings_by_dravya


def resolve_primary_foods(
    dravyas: list[dict[str, Any]], store_ids: set[int]
) -> tuple[
    dict[str, tuple[int, bool]],
    list[dict[str, Any]],
    list[tuple[int, str, str, list[str]]],
    list[str],
]:
    claims, bindings_by_dravya = validate_bindings(dravyas, store_ids)

    winners: dict[int, tuple[str, str]] = {}
    contested: list[tuple[int, str, str, list[str]]] = []
    for fdc_id, fdc_claims in sorted(claims.items()):
        ranked = sorted(fdc_claims, key=lambda claim: (TIER_RANK[claim[1]], claim[0]))
        winner_id, winner_tier, _ = ranked[0]
        winners[fdc_id] = (winner_id, winner_tier)
        if len(fdc_claims) > 1:
            losers = sorted(claim[0] for claim in fdc_claims if claim[0] != winner_id)
            contested.append((fdc_id, winner_id, winner_tier, losers))

    assignments: dict[str, tuple[int, bool]] = {}
    placeholder_ids: list[str] = []
    for dravya in sorted(dravyas, key=lambda item: item["id"]):
        dravya_id = dravya["id"]
        ordered_bindings = sorted(
            bindings_by_dravya[dravya_id],
            key=lambda binding: (TIER_RANK[binding[1]], binding[2]),
        )
        won = next(
            (
                fdc_id
                for fdc_id, _tier, _position in ordered_bindings
                if winners[fdc_id][0] == dravya_id
            ),
            None,
        )
        if won is None:
            placeholder_ids.append(dravya_id)
        else:
            assignments[dravya_id] = (won, False)

    for ordinal, dravya_id in enumerate(placeholder_ids, start=1):
        assignments[dravya_id] = (PLACEHOLDER_BASE + ordinal, True)

    links = [
        {"fdcId": fdc_id, "dravyaId": winner_id, "tier": tier}
        for fdc_id, (winner_id, tier) in sorted(winners.items())
    ]
    return assignments, links, contested, placeholder_ids


def assert_reserved_band_free(store_ids: set[int]) -> None:
    collisions = sorted(
        food_id for food_id in store_ids if PLACEHOLDER_BASE <= food_id < RESERVED_BAND_END
    )
    if collisions:
        preview = ", ".join(str(food_id) for food_id in collisions[:10])
        raise BuildError(f"reserved Ayurveda food id band is not empty: {preview}")


def build_envelope(
    dravyas: list[dict[str, Any]],
    recipes: list[dict[str, Any]],
    store_ids: set[int],
    derived_links: list[dict[str, Any]],
    nutrition_by_id: dict[int, dict[str, float]],
    preferred_bindings: dict[str, int],
) -> tuple[dict[str, Any], list[tuple[int, str, str, list[str]]], list[str]]:
    assert_reserved_band_free(store_ids)
    assignments, links, contested, placeholder_ids = resolve_primary_foods(dravyas, store_ids)
    if len(links) != V1_LINK_COUNT:
        raise BuildError(f"v1-link gate failed: expected {V1_LINK_COUNT}, got {len(links)}")
    v1_fdc_ids = {link["fdcId"] for link in links}
    derived_fdc_ids = {link["fdcId"] for link in derived_links}
    if v1_fdc_ids & derived_fdc_ids:
        raise BuildError("derived links overlap v1 links")
    links.extend(derived_links)

    output_dravyas: list[dict[str, Any]] = []
    for dravya in sorted(dravyas, key=lambda item: item["id"]):
        output = dict(dravya)
        output["foodId"], output["foodIsPlaceholder"] = assignments[dravya["id"]]
        output["engineExcluded"] = dravya["id"] in ENGINE_EXCLUDED_IDS
        output_dravyas.append(output)

    output_recipes: list[dict[str, Any]] = []
    unresolved: list[str] = []
    for ordinal, recipe in enumerate(sorted(recipes, key=lambda item: item["id"]), start=1):
        output = dict(recipe)
        output["foodId"] = RECIPE_BASE + ordinal
        nutrition, nutrition_source_ids = derive_recipe_nutrition(
            recipe, nutrition_by_id, preferred_bindings
        )
        resolved_ingredients: list[dict[str, Any]] = []
        for ingredient, nutrition_source_id in zip(
            recipe.get("ingredients", []), nutrition_source_ids, strict=True
        ):
            food_id: int | None = None
            if "dravyaId" in ingredient:
                assignment = assignments.get(ingredient["dravyaId"])
                if assignment is not None:
                    food_id = assignment[0]
            elif "fdcId" in ingredient:
                candidate = ingredient["fdcId"]
                if isinstance(candidate, int) and candidate in store_ids:
                    food_id = candidate
            if food_id is None:
                unresolved.append(f"{recipe['id']}: {ingredient!r}")
                continue
            resolved = {
                "foodId": food_id,
                "grams": ingredient["grams"],
                "name": ingredient["name"],
            }
            if nutrition_source_id is not None:
                resolved["nutritionFdcId"] = nutrition_source_id
            resolved_ingredients.append(resolved)
        output["ingredients"] = resolved_ingredients
        output["nutrition"] = nutrition
        output_recipes.append(output)

    if unresolved:
        raise BuildError("unresolved recipe ingredients:\n" + "\n".join(unresolved))

    primary_count = sum(not placeholder for _food_id, placeholder in assignments.values())
    excluded_count = sum(bool(item["engineExcluded"]) for item in output_dravyas)
    actual_counts = {
        "dravyas": len(output_dravyas),
        "recipes": len(output_recipes),
        "links": len(links),
        "derivedLinks": len(derived_links),
        "placeholders": len(placeholder_ids),
        "primaries": primary_count,
        "categoryRules": EXPECTED_COUNTS["categoryRules"],
        "modifiers": EXPECTED_COUNTS["modifiers"],
    }
    if actual_counts != EXPECTED_COUNTS:
        raise BuildError(f"director count gate failed: expected {EXPECTED_COUNTS}, got {actual_counts}")
    if excluded_count != len(ENGINE_EXCLUDED_IDS):
        raise BuildError(f"engine exclusion gate failed: expected 2, got {excluded_count}")
    if len(contested) != 40:
        raise BuildError(f"contested fdcId gate failed: expected 40, got {len(contested)}")

    all_assigned_ids = [food_id for food_id, _placeholder in assignments.values()]
    if len(set(all_assigned_ids)) != len(all_assigned_ids):
        raise BuildError("dravya primary/placeholder foodId assignments are not unique")

    envelope = {
        "seedVersion": SEED_VERSION,
        "generatedAt": GENERATED_AT,
        "counts": {
            "dravyas": actual_counts["dravyas"],
            "recipes": actual_counts["recipes"],
            "links": actual_counts["links"],
            "derivedLinks": actual_counts["derivedLinks"],
            "placeholders": actual_counts["placeholders"],
            "categoryRules": actual_counts["categoryRules"],
            "modifiers": actual_counts["modifiers"],
            "nutrition": {
                status: sum(
                    recipe["nutrition"]["status"] == status
                    for recipe in output_recipes
                )
                for status in ("full", "estimated", "none")
            },
        },
        "dravyas": output_dravyas,
        "recipes": output_recipes,
        "links": links,
    }
    return envelope, contested, placeholder_ids


def encode_deterministic_gzip(envelope: dict[str, Any]) -> bytes:
    plain = encode_deterministic_json(envelope)
    buffer = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buffer, mtime=0) as compressed:
        compressed.write(plain)
    return buffer.getvalue()


def encode_deterministic_json(value: dict[str, Any]) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def print_summary(
    envelope: dict[str, Any],
    contested: list[tuple[int, str, str, list[str]]],
    placeholder_ids: list[str],
) -> None:
    counts = envelope["counts"]
    primaries = len(envelope["dravyas"]) - counts["placeholders"]
    excluded = sum(item["engineExcluded"] for item in envelope["dravyas"])
    print("build_seed summary")
    print(f"dravyas: {counts['dravyas']}")
    print(f"recipes: {counts['recipes']}")
    print(
        "recipe nutrition: "
        + ", ".join(
            f"{status}={counts['nutrition'][status]}"
            for status in ("full", "estimated", "none")
        )
    )
    print(
        f"links: {counts['links']} "
        + f"({V1_LINK_COUNT} v1 + {counts['derivedLinks']} derived)"
    )
    print(f"placeholders: {counts['placeholders']}")
    print(f"primaries: {primaries}")
    print(f"categoryRules: {counts['categoryRules']}")
    print(f"modifiers: {counts['modifiers']}")
    print("unresolved ingredients: 0")
    print(f"engineExcluded: {excluded}")
    print()
    print("Contested fdcIds")
    print("fdcId | winner | tier | losers")
    print("--- | --- | --- | ---")
    for fdc_id, winner, tier, losers in contested:
        print(f"{fdc_id} | {winner} | {tier} | {', '.join(losers)}")
    print()
    print(f"Placeholder dravyas ({len(placeholder_ids)})")
    for dravya_id in placeholder_ids:
        print(dravya_id)


def main() -> int:
    args = parse_args()
    data_root = Path(__file__).resolve().parent
    try:
        actual_store_path = store_path(args.store)
        store_ids = load_store_ids(actual_store_path)
        nutrition_by_id = load_food_nutrition(args.foods, store_ids)
        dravyas = load_batches(data_root / "dravyas", "batch-*.json", "items")
        recipes = load_batches(data_root / "recipes", "batch-r*.json", "items")
        dravya_ids = {dravya["id"] for dravya in dravyas}
        _claims, bindings_by_dravya = validate_bindings(dravyas, store_ids)
        preferred_bindings = preferred_nutrition_bindings(bindings_by_dravya)
        v1_fdc_ids = {
            fdc_id
            for bindings in bindings_by_dravya.values()
            for fdc_id, _tier, _position in bindings
        }
        derived_links = load_crosswalk_links(
            data_root / "crosswalk" / "crosswalk.csv",
            store_ids,
            dravya_ids,
            v1_fdc_ids,
        )
        rules_bundle = load_rules_bundle(data_root)
        envelope, contested, placeholder_ids = build_envelope(
            dravyas,
            recipes,
            store_ids,
            derived_links,
            nutrition_by_id,
            preferred_bindings,
        )
        compressed = encode_deterministic_gzip(envelope)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(compressed)
        args.rules_output.parent.mkdir(parents=True, exist_ok=True)
        args.rules_output.write_bytes(encode_deterministic_json(rules_bundle))
        print_summary(envelope, contested, placeholder_ids)
        print()
        print(f"wrote: {args.output}")
        print(f"wrote: {args.rules_output}")
        return 0
    except (BuildError, KeyError, TypeError, ValueError, OSError) as error:
        print(f"build_seed.py: error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
