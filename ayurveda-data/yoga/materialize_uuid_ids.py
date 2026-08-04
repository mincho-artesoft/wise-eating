#!/usr/bin/env python3
"""Migrate yoga runtime JSON from numeric IDs to stable UUID identities."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


YOGA_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(YOGA_DIR.parent))

from stable_ids import yoga_asana_uuid, yoga_sequence_uuid  # noqa: E402


def load_rows(path: Path) -> list[dict[str, object]]:
    rows = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise ValueError(f"{path}: expected a JSON array")
    return rows


def stable_catalog_identity(row: dict[str, object], identity_for_number) -> int:
    raw_id = row.get("id")
    if isinstance(raw_id, int):
        catalog_number = raw_id
        row["catalogNumber"] = catalog_number
        row["id"] = identity_for_number(catalog_number)
        return catalog_number

    catalog_number = row.get("catalogNumber")
    if not isinstance(catalog_number, int):
        raise ValueError("UUID yoga row has no integer catalogNumber")
    expected = identity_for_number(catalog_number)
    if raw_id != expected:
        raise ValueError(
            f"Yoga row {catalog_number} UUID mismatch: expected {expected}, got {raw_id}"
        )
    return catalog_number


def write_rows(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text(
        json.dumps(rows, ensure_ascii=False, indent=1) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asanas", type=Path, default=YOGA_DIR / "asanas.json")
    parser.add_argument(
        "--sequences", type=Path, default=YOGA_DIR / "sequences.json"
    )
    args = parser.parse_args()

    asanas = load_rows(args.asanas)
    sequences = load_rows(args.sequences)

    asana_ids: dict[int, str] = {}
    for row in asanas:
        catalog_number = stable_catalog_identity(row, yoga_asana_uuid)
        # Yoga is the only supported activity catalogue. The former sports
        # classification is intentionally not shipped in the runtime data.
        row.pop("sports", None)
        if catalog_number in asana_ids:
            raise ValueError(f"Duplicate asana catalogNumber {catalog_number}")
        asana_ids[catalog_number] = str(row["id"])

    sequence_ids: set[int] = set()
    for row in sequences:
        catalog_number = stable_catalog_identity(row, yoga_sequence_uuid)
        if catalog_number in sequence_ids:
            raise ValueError(f"Duplicate sequence catalogNumber {catalog_number}")
        sequence_ids.add(catalog_number)

        poses = row.get("poses")
        if not isinstance(poses, list):
            raise ValueError(f"Sequence {catalog_number} has no poses array")
        for pose in poses:
            if not isinstance(pose, dict):
                raise ValueError(f"Sequence {catalog_number} has a non-object pose")
            raw_pose_id = pose.get("id")
            if isinstance(raw_pose_id, int):
                pose_catalog_number = raw_pose_id
                pose["catalogNumber"] = pose_catalog_number
                try:
                    pose["id"] = asana_ids[pose_catalog_number]
                except KeyError as error:
                    raise ValueError(
                        f"Sequence {catalog_number} references missing asana "
                        f"{pose_catalog_number}"
                    ) from error
            else:
                pose_catalog_number = pose.get("catalogNumber")
                if not isinstance(pose_catalog_number, int):
                    raise ValueError(
                        f"Sequence {catalog_number} UUID pose has no catalogNumber"
                    )
                expected = asana_ids.get(pose_catalog_number)
                if raw_pose_id != expected:
                    raise ValueError(
                        f"Sequence {catalog_number} pose UUID mismatch for "
                        f"{pose_catalog_number}"
                    )

    write_rows(args.asanas, asanas)
    write_rows(args.sequences, sequences)
    print(
        f"materialized stable UUIDs: {len(asanas)} asanas, "
        f"{len(sequences)} sequences"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
