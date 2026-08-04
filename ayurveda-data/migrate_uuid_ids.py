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
    template_day_uuid,
    template_exercise_uuid,
    template_plan_uuid,
    template_set_uuid,
    template_workout_uuid,
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


def _extract_day_index(title: str) -> int | None:
    match = re.search(r"\bDay\s*(\d+)\b", title, re.IGNORECASE)
    return int(match.group(1)) if match else None


def _workout_display_name(plan_name: str, title: str) -> str:
    prefix = plan_name + " - "
    if title.startswith(prefix):
        rest = title[len(prefix):].strip()
        if rest:
            return rest
    return "Workout"


def migrate_workout_templates(path: Path) -> int:
    document = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(document, dict) and document.get("identitySchema") == "stable-uuid-v1":
        for plan in document["plans"]:
            if plan["id"] != template_plan_uuid(plan["name"]):
                raise ValueError(f"{path}: plan UUID mismatch for {plan['name']}")
        compact_json(path, document)
        return 0
    if not isinstance(document, list):
        raise ValueError(f"{path}: expected legacy array or UUID document")

    grouped: dict[str, list[dict]] = {}
    for item in document:
        plan_name = item["title"].split(" - ", 1)[0]
        grouped.setdefault(plan_name, []).append(item)

    plans: list[dict] = []
    for plan_name in sorted(grouped, key=str.casefold):
        plan_id = template_plan_uuid(plan_name)
        mapped = [(_extract_day_index(row["title"]), row) for row in grouped[plan_name]]
        has_explicit_day = any(day is not None for day, _ in mapped)
        buckets: dict[int, list[dict]] = {}
        if has_explicit_day:
            for day, row in mapped:
                buckets.setdefault(day or 0, []).append(row)
        else:
            for ordinal, (_, row) in enumerate(
                sorted(mapped, key=lambda value: value[1]["title"].casefold()),
                start=1,
            ):
                buckets.setdefault(ordinal, []).append(row)
        zero = buckets.pop(0, [])
        if zero:
            max_day = max(buckets, default=0)
            for offset, row in enumerate(
                sorted(zero, key=lambda value: value["title"].casefold()),
                start=1,
            ):
                buckets.setdefault(max_day + offset, []).append(row)

        max_day = max(buckets, default=0)
        days: list[dict] = []
        for day_index in range(1, max_day + 1 if max_day else 2):
            day_id = template_day_uuid(plan_id, day_index)
            source_workouts = sorted(
                buckets.get(day_index, []),
                key=lambda value: value["title"].casefold(),
            )
            workouts: list[dict] = []
            for workout_ordinal, source in enumerate(source_workouts):
                workout_id = template_workout_uuid(
                    plan_id,
                    day_index,
                    workout_ordinal,
                    source["title"],
                )
                exercises: list[dict] = []
                for exercise_ordinal, exercise in enumerate(source["exercises"]):
                    exercise_id = template_exercise_uuid(
                        workout_id, exercise_ordinal, exercise["name"]
                    )
                    sets = [
                        {
                            "id": template_set_uuid(exercise_id, order_index),
                            "exerciseId": exercise_id,
                            "reps": exercise.get("reps"),
                            "isToFailure": exercise.get("to_failure", False),
                            "isTimeBased": exercise.get("is_time_based", False),
                            "timeUnitString": exercise.get("unit") or "sec",
                            "orderIndex": order_index,
                        }
                        for order_index in range(max(exercise.get("sets", 0), 0))
                    ]
                    exercises.append(
                        {
                            "id": exercise_id,
                            "workoutId": workout_id,
                            "exerciseName": exercise["name"],
                            "durationMinutes": float(exercise.get("duration", 0)),
                            "sets": sets,
                        }
                    )
                workouts.append(
                    {
                        "id": workout_id,
                        "dayId": day_id,
                        "workoutName": _workout_display_name(plan_name, source["title"]),
                        "exercises": exercises,
                    }
                )
            days.append(
                {
                    "id": day_id,
                    "planId": plan_id,
                    "dayIndex": day_index,
                    "isRestDay": not bool(source_workouts),
                    "workouts": workouts,
                }
            )
        plans.append({"id": plan_id, "name": plan_name, "days": days})

    compact_json(
        path,
        {"identitySchema": "stable-uuid-v1", "plans": plans},
    )
    return len(plans)


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
        "templatePlans": migrate_workout_templates(
            root / "Ayura/Legacy/workouts.json"
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
