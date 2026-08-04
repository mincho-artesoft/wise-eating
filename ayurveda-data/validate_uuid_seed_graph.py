#!/usr/bin/env python3
"""Validate that every persisted bundled identity and relationship is UUID based."""

from __future__ import annotations

import gzip
import json
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AYURA = ROOT / "Ayura"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_gzip_json(path: Path):
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        return json.load(handle)


def require_uuid(value, label: str) -> str:
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, TypeError, AttributeError) as error:
        raise AssertionError(f"{label}: not a UUID: {value!r}") from error


def add_unique(seen: set[str], value, label: str) -> str:
    identifier = require_uuid(value, label)
    if identifier in seen:
        raise AssertionError(f"{label}: duplicate UUID {identifier}")
    seen.add(identifier)
    return identifier


def validate_catalogs() -> tuple[set[str], dict[str, int]]:
    identities: set[str] = set()
    payload_ids: set[str] = set()
    foods = load_json(AYURA / "Legacy/foods.json")
    exercises = load_json(AYURA / "Legacy/exercises.json")
    catalog_numbers: set[int] = set()
    for row in foods:
        food_id = add_unique(identities, row["id"], "food.id")
        number = row["catalogNumber"]
        if number in catalog_numbers:
            raise AssertionError(f"duplicate food catalogNumber {number}")
        catalog_numbers.add(number)
        for key in (
            "macronutrients", "lipids", "vitamins", "minerals", "other",
            "aminoAcids", "carbDetails", "sterols",
        ):
            if row.get(key) is not None:
                add_unique(payload_ids, row[key]["id"], f"{food_id}.{key}.id")
    for row in exercises:
        add_unique(identities, row["id"], "exercise.id")
    return identities | payload_ids, {
        "foods": len(foods),
        "foodPayloads": len(payload_ids),
        "exercises": len(exercises),
    }


def validate_ayurveda(known_ids: set[str]) -> tuple[set[str], dict[str, int]]:
    document = load_gzip_json(AYURA / "ayurveda_seed.json.gz")
    if document.get("identitySchema") != "stable-uuid-v1":
        raise AssertionError("Ayurveda seed has no stable UUID schema")
    profile_ids: set[str] = set()
    food_ids = {
        require_uuid(row["id"], "food.id")
        for row in load_json(AYURA / "Legacy/foods.json")
    }
    ingredient_ids: set[str] = set()
    payload_ids: set[str] = set()
    for collection in ("dravyas", "recipes", "catalogProfiles"):
        for row in document[collection]:
            add_unique(profile_ids, row["id"], f"{collection}.id")
            food_ids.add(require_uuid(row["foodId"], f"{collection}.foodId"))
            for contributor in row.get("safety", {}).get("ageContributors", []):
                require_uuid(contributor["ingredientId"], "ageContributor.ingredientId")
            if collection == "dravyas" and row.get("nutrition"):
                for value in row["nutrition"]["payloadIds"].values():
                    add_unique(payload_ids, value, "dravya.payloadId")
            if collection == "recipes":
                for ingredient in row["ingredients"]:
                    add_unique(ingredient_ids, ingredient["id"], "ingredient.id")
                    target = require_uuid(ingredient["foodId"], "ingredient.foodId")
                    if target not in food_ids:
                        # Targets can be declared later in the same graph; checked below.
                        pass
    for recipe in document["recipes"]:
        for ingredient in recipe["ingredients"]:
            if require_uuid(ingredient["foodId"], "ingredient.foodId") not in food_ids:
                raise AssertionError(f"missing ingredient food {ingredient['foodId']}")
    link_ids: set[str] = set()
    for link in document["links"]:
        add_unique(link_ids, link["id"], "ayurvedaLink.id")
        if require_uuid(link["foodId"], "ayurvedaLink.foodId") not in food_ids:
            raise AssertionError(f"missing linked food {link['foodId']}")
        if require_uuid(link["dravyaProfileId"], "ayurvedaLink.dravyaProfileId") not in profile_ids:
            raise AssertionError(f"missing linked profile {link['dravyaProfileId']}")

    frame_index = load_json(AYURA / "Food/frame_index.json")
    if not set(map(require_uuid_key, frame_index)).issubset(food_ids):
        raise AssertionError("frame_index contains unknown food UUIDs")
    concepts = load_gzip_json(AYURA / "food_concepts.json.gz")
    roles = load_gzip_json(AYURA / "food_roles.json.gz")
    for members in concepts["membership"].values():
        for value in members:
            if require_uuid(value, "concept.foodId") not in food_ids:
                raise AssertionError(f"concept contains unknown food {value}")
    for row in roles["items"]:
        if require_uuid(row["foodId"], "role.foodId") not in food_ids:
            raise AssertionError(f"role contains unknown food {row['foodId']}")
    return known_ids | profile_ids | food_ids | ingredient_ids | payload_ids | link_ids, {
        "profiles": len(profile_ids),
        "ingredientLinks": len(ingredient_ids),
        "ayurvedaLinks": len(link_ids),
        "dravyaPayloads": len(payload_ids),
    }


def require_uuid_key(value: str) -> str:
    return require_uuid(value, "frame_index.foodId")


def validate_auxiliary(known_ids: set[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for filename, index_key in (
        ("vocabulary.json", "tokenIndex"),
        ("product_buckets.json", "bucketKey"),
    ):
        rows = load_json(AYURA / "Legacy" / filename)
        ids: set[str] = set()
        indexes: set[object] = set()
        for row in rows:
            add_unique(ids, row["id"], f"{filename}.id")
            if row[index_key] in indexes:
                raise AssertionError(f"{filename}: duplicate {index_key}")
            indexes.add(row[index_key])
        known_ids.update(ids)
        counts[filename.removesuffix(".json")] = len(rows)

    references = load_json(AYURA / "Legacy/reference_ids.json")
    reference_ids: set[str] = set()
    for rows in references["entities"].values():
        for row in rows:
            add_unique(reference_ids, row["id"], "reference.id")
            for requirement_id in row["requirementIds"]:
                add_unique(reference_ids, requirement_id, "requirement.id")
    known_ids.update(reference_ids)
    counts["referenceIdentities"] = len(reference_ids)
    return counts


def main() -> int:
    known_ids, counts = validate_catalogs()
    known_ids, ayurveda_counts = validate_ayurveda(known_ids)
    counts.update(ayurveda_counts)
    counts.update(validate_auxiliary(known_ids))
    print(
        "UUID seed graph valid: "
        + ", ".join(f"{key}={value}" for key, value in counts.items())
        + f", totalIdentities={len(known_ids)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
