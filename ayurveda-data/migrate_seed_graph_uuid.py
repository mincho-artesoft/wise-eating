#!/usr/bin/env python3
"""Migrate shipped seed graphs from numeric/slug identities to stable UUIDs."""

from __future__ import annotations

import gzip
import json
from pathlib import Path

from stable_ids import (
    ayurveda_link_uuid,
    ayurveda_profile_uuid,
    dravya_payload_uuid,
    food_uuid,
    ingredient_link_uuid,
)


ROOT = Path(__file__).resolve().parents[1]
AYURVEDA_DIR = ROOT / "Ayura"


def read_gzip_json(path: Path):
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        return json.load(handle)


def write_gzip_json(path: Path, document) -> None:
    payload = json.dumps(
        document,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    with path.open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as handle:
            handle.write(payload)


def profile_identity(row: dict) -> tuple[str, str]:
    key = row.get("key") or row["id"]
    return ayurveda_profile_uuid(key), key


def migrate_safety(safety: dict) -> None:
    for contributor in safety.get("ageContributors", []):
        value = contributor.get("ingredientId")
        if value and not _is_uuid(value):
            contributor["ingredientId"] = ayurveda_profile_uuid(value)


def migrate_profile(row: dict, *, recipe: bool = False) -> None:
    profile_id, key = profile_identity(row)
    old_food_id = row["foodId"]
    row["id"] = profile_id
    row["key"] = key
    if isinstance(old_food_id, int):
        row["foodId"] = food_uuid(old_food_id)
    migrate_safety(row.get("safety", {}))

    nutrition = row.get("nutrition")
    if nutrition and not recipe:
        payload_ids = nutrition.setdefault("payloadIds", {})
        for payload_kind in ("macronutrients", "vitamins", "minerals", "other"):
            expected = dravya_payload_uuid(key, payload_kind)
            if payload_ids.get(payload_kind) not in (None, expected):
                raise ValueError(
                    f"{key}: {payload_kind} nutrition payload UUID mismatch"
                )
            payload_ids[payload_kind] = expected

    if recipe:
        for ordinal, ingredient in enumerate(row.get("ingredients", [])):
            old_ingredient_food_id = ingredient["foodId"]
            if isinstance(old_ingredient_food_id, int):
                ingredient["foodId"] = food_uuid(old_ingredient_food_id)
                ingredient["id"] = ingredient_link_uuid(
                    key, ordinal, old_ingredient_food_id
                )
            elif "id" not in ingredient:
                ingredient["id"] = ingredient_link_uuid(
                    key, ordinal, ingredient["foodId"]
                )


def migrate_ayurveda_seed(path: Path) -> dict[str, int]:
    document = read_gzip_json(path)
    for row in document["dravyas"]:
        migrate_profile(row)
    for row in document["recipes"]:
        migrate_profile(row, recipe=True)
    for row in document["catalogProfiles"]:
        migrate_profile(row)

    for link in document["links"]:
        if "foodId" in link:
            continue
        old_food_id = link.pop("fdcId")
        old_profile_key = link.pop("dravyaId")
        food_id = food_uuid(old_food_id)
        profile_id = ayurveda_profile_uuid(old_profile_key)
        link["id"] = ayurveda_link_uuid(food_id, profile_id, link["tier"])
        link["foodId"] = food_id
        link["dravyaProfileId"] = profile_id

    document["seedVersion"] = max(document["seedVersion"], 10)
    document["identitySchema"] = "stable-uuid-v1"
    write_gzip_json(path, document)
    return {
        "dravyas": len(document["dravyas"]),
        "recipes": len(document["recipes"]),
        "catalogProfiles": len(document["catalogProfiles"]),
        "links": len(document["links"]),
    }


def migrate_concepts(path: Path) -> int:
    document = read_gzip_json(path)
    for key, members in document["membership"].items():
        document["membership"][key] = sorted(
            food_uuid(value) if isinstance(value, int) else value
            for value in members
        )
    document["identitySchema"] = "stable-uuid-v1"
    write_gzip_json(path, document)
    return sum(len(values) for values in document["membership"].values())


def migrate_roles(path: Path) -> int:
    document = read_gzip_json(path)
    missing_catalog_numbers = [
        row for row in document["items"] if "catalogNumber" not in row
    ]
    recovered: dict[str, int] = {}
    if missing_catalog_numbers:
        wanted = {row["foodId"] for row in missing_catalog_numbers}
        candidates = list(range(0, 20_000)) + list(range(900_000, 1_002_000))
        for value in candidates:
            identifier = food_uuid(value)
            if identifier in wanted:
                recovered[identifier] = value
                if len(recovered) == len(wanted):
                    break
    for row in document["items"]:
        if isinstance(row["foodId"], int):
            catalog_number = row["foodId"]
            row["catalogNumber"] = catalog_number
            row["foodId"] = food_uuid(catalog_number)
        elif "catalogNumber" not in row:
            row["catalogNumber"] = recovered[row["foodId"]]
    document["identitySchema"] = "stable-uuid-v1"
    write_gzip_json(path, document)
    return len(document["items"])


def _is_uuid(value: str) -> bool:
    try:
        import uuid

        uuid.UUID(value)
        return True
    except (ValueError, TypeError, AttributeError):
        return False


def main() -> None:
    counts = migrate_ayurveda_seed(AYURVEDA_DIR / "ayurveda_seed.json.gz")
    concept_memberships = migrate_concepts(
        AYURVEDA_DIR / "food_concepts.json.gz"
    )
    role_items = migrate_roles(AYURVEDA_DIR / "food_roles.json.gz")
    print(
        "UUID seed graph migrated: "
        f"{counts}, conceptMemberships={concept_memberships}, roles={role_items}"
    )


if __name__ == "__main__":
    main()
