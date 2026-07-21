#!/usr/bin/env python3
"""Build the deterministic Ayurveda seed bundle consumed by the app."""

from __future__ import annotations

import argparse
import gzip
import io
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


SEED_VERSION = 1
GENERATED_AT = "2026-07-21T00:00:00Z"
EXPECTED_COUNTS = {
    "dravyas": 714,
    "recipes": 1500,
    "links": 336,
    "placeholders": 383,
    "primaries": 331,
}
ENGINE_EXCLUDED_IDS = {"dravya.betel-nut", "dravya.vanaspati"}
PLACEHOLDER_BASE = 900_000
RECIPE_BASE = 1_000_000
RESERVED_BAND_END = 1_002_000
TIER_RANK = {"exact": 0, "near": 1}


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
    dravyas: list[dict[str, Any]], recipes: list[dict[str, Any]], store_ids: set[int]
) -> tuple[dict[str, Any], list[tuple[int, str, str, list[str]]], list[str]]:
    assert_reserved_band_free(store_ids)
    assignments, links, contested, placeholder_ids = resolve_primary_foods(dravyas, store_ids)

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
        resolved_ingredients: list[dict[str, Any]] = []
        for ingredient in recipe.get("ingredients", []):
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
            resolved_ingredients.append(
                {
                    "foodId": food_id,
                    "grams": ingredient["grams"],
                    "name": ingredient["name"],
                }
            )
        output["ingredients"] = resolved_ingredients
        output_recipes.append(output)

    if unresolved:
        raise BuildError("unresolved recipe ingredients:\n" + "\n".join(unresolved))

    primary_count = sum(not placeholder for _food_id, placeholder in assignments.values())
    excluded_count = sum(bool(item["engineExcluded"]) for item in output_dravyas)
    actual_counts = {
        "dravyas": len(output_dravyas),
        "recipes": len(output_recipes),
        "links": len(links),
        "placeholders": len(placeholder_ids),
        "primaries": primary_count,
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
            "placeholders": actual_counts["placeholders"],
        },
        "dravyas": output_dravyas,
        "recipes": output_recipes,
        "links": links,
    }
    return envelope, contested, placeholder_ids


def encode_deterministic_gzip(envelope: dict[str, Any]) -> bytes:
    plain = json.dumps(
        envelope,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    buffer = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buffer, mtime=0) as compressed:
        compressed.write(plain)
    return buffer.getvalue()


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
    print(f"links: {counts['links']}")
    print(f"placeholders: {counts['placeholders']}")
    print(f"primaries: {primaries}")
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
        dravyas = load_batches(data_root / "dravyas", "batch-*.json", "items")
        recipes = load_batches(data_root / "recipes", "batch-r*.json", "items")
        envelope, contested, placeholder_ids = build_envelope(dravyas, recipes, store_ids)
        compressed = encode_deterministic_gzip(envelope)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(compressed)
        print_summary(envelope, contested, placeholder_ids)
        print()
        print(f"wrote: {args.output}")
        return 0
    except (BuildError, KeyError, TypeError, ValueError, OSError) as error:
        print(f"build_seed.py: error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
