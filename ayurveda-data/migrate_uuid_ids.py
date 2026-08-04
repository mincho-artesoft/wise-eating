#!/usr/bin/env python3
"""Materialize stable UUIDs in runtime seed JSON files."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from stable_ids import (
    exercise_uuid,
    food_payload_uuid,
    food_uuid,
    product_bucket_uuid,
    reference_entity_uuid,
    reference_requirement_uuid,
    vocabulary_entry_uuid,
)


ROOT = Path(__file__).resolve().parents[1]


def compact_json(path: Path, value: object) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )


FOOD_PAYLOAD_KEYS = (
    "macronutrients",
    "lipids",
    "vitamins",
    "minerals",
    "other",
    "aminoAcids",
    "carbDetails",
    "sterols",
)


def migrate_catalog(path: Path, uuid_for_number, *, payload_ids: bool = False) -> int:
    rows = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise ValueError(f"{path}: expected an array")
    changed = 0
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError(f"{path}: non-object row")
        raw_id = row.get("id")
        if isinstance(raw_id, int):
            catalog_number = raw_id
            row["catalogNumber"] = catalog_number
            row["id"] = uuid_for_number(catalog_number)
            changed += 1
        else:
            catalog_number = row.get("catalogNumber")
            if not isinstance(catalog_number, int):
                raise ValueError(f"{path}: row has no integer catalogNumber")
            expected = uuid_for_number(catalog_number)
            if raw_id != expected:
                raise ValueError(
                    f"{path}: catalog {catalog_number} UUID mismatch: "
                    f"expected {expected}, got {raw_id}"
                )
        if row["id"] in seen:
            raise ValueError(f"{path}: duplicate UUID {row['id']}")
        seen.add(row["id"])
        if payload_ids:
            for payload_key in FOOD_PAYLOAD_KEYS:
                payload = row.get(payload_key)
                if payload is None:
                    continue
                expected_payload_id = food_payload_uuid(row["id"], payload_key)
                if payload.get("id") not in (None, expected_payload_id):
                    raise ValueError(
                        f"{path}: {row['id']} {payload_key} UUID mismatch"
                    )
                if payload.get("id") != expected_payload_id:
                    payload["id"] = expected_payload_id
                    changed += 1
    compact_json(path, rows)
    return changed


def migrate_vocabulary(path: Path) -> int:
    document = json.loads(path.read_text(encoding="utf-8"))
    changed = 0
    if isinstance(document, dict):
        document = [
            {
                "id": vocabulary_entry_uuid(int(token_index)),
                "tokenIndex": int(token_index),
                "word": word,
            }
            for token_index, word in sorted(
                document.items(), key=lambda item: int(item[0])
            )
        ]
        changed = len(document)
    if not isinstance(document, list):
        raise ValueError(f"{path}: expected an array")
    for row in document:
        expected = vocabulary_entry_uuid(row["tokenIndex"])
        if row.get("id") != expected:
            raise ValueError(f"{path}: token {row['tokenIndex']} UUID mismatch")
    compact_json(path, document)
    return changed


def migrate_product_buckets(path: Path) -> int:
    document = json.loads(path.read_text(encoding="utf-8"))
    changed = 0
    if isinstance(document, dict):
        document = [
            {
                "id": product_bucket_uuid(int(bucket_key)),
                "bucketKey": str(int(bucket_key)),
                "compressedData": compressed_data,
            }
            for bucket_key, compressed_data in sorted(
                document.items(), key=lambda item: int(item[0])
            )
        ]
        changed = len(document)
    if not isinstance(document, list):
        raise ValueError(f"{path}: expected an array")
    for row in document:
        row["bucketKey"] = str(row["bucketKey"])
        expected = product_bucket_uuid(int(row["bucketKey"]))
        if row.get("id") != expected:
            raise ValueError(f"{path}: bucket {row['bucketKey']} UUID mismatch")
    compact_json(path, document)
    return changed


def _reference_source_records(path: Path, constructor: str) -> list[tuple[str, int]]:
    text = path.read_text(encoding="utf-8")
    starts = list(re.finditer(rf"\b{constructor}\s*\(\s*\n\s*id:\s*\"([^\"]+)\"", text))
    records: list[tuple[str, int]] = []
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        records.append((match.group(1), text[match.end():end].count("Requirement(")))
    return records


def migrate_reference_ids(root: Path) -> int:
    kinds = {
        "vitamin": _reference_source_records(
            root / "Ayura/Food/FoodStruct/Vitamins/defaultVitaminsList.swift",
            "Vitamin",
        ),
        "mineral": _reference_source_records(
            root / "Ayura/Food/FoodStruct/Minerals/defaultMineralsList.swift",
            "Mineral",
        ),
    }
    document = {"identitySchema": "stable-uuid-v1", "entities": {}}
    count = 0
    for kind, records in kinds.items():
        document["entities"][kind] = [
            {
                "id": reference_entity_uuid(kind, key),
                "key": key,
                "requirementIds": [
                    reference_requirement_uuid(kind, key, ordinal)
                    for ordinal in range(requirement_count)
                ],
            }
            for key, requirement_count in records
        ]
        count += len(records) + sum(value for _, value in records)
    compact_json(root / "Ayura/Legacy/reference_ids.json", document)
    return count


def migrate_frame_index(path: Path) -> int:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"{path}: expected an object")
    migrated: dict[str, int] = {}
    changed = 0
    for key, frame in raw.items():
        if key.isdigit():
            key = food_uuid(int(key))
            changed += 1
        migrated[key] = frame
    compact_json(path, dict(sorted(migrated.items())))
    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    changed = {
        "foods": migrate_catalog(
            root / "Ayura/Legacy/foods.json", food_uuid, payload_ids=True
        ),
        "exercises": migrate_catalog(
            root / "Ayura/Legacy/exercises.json", exercise_uuid
        ),
        "frameIndex": migrate_frame_index(
            root / "Ayura/Food/frame_index.json"
        ),
        "vocabulary": migrate_vocabulary(
            root / "Ayura/Legacy/vocabulary.json"
        ),
        "productBuckets": migrate_product_buckets(
            root / "Ayura/Legacy/product_buckets.json"
        ),
        "referenceIDs": migrate_reference_ids(root),
    }
    print(
        "UUID migration: "
        + ", ".join(f"{name}={count}" for name, count in changed.items())
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
