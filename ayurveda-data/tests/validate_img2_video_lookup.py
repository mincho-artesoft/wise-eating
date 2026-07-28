#!/usr/bin/env python3
"""IMG-2 three-tier video lookup, coverage, and stability gates."""

from __future__ import annotations

import glob
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FOODS = ROOT / "WiseEating" / "Legacy" / "foods.json"
FOOD_RESOURCES = ROOT / "WiseEating" / "Food"
FRAME_MAP = FOOD_RESOURCES / "frame_map.json"
REUSE_MAP = FOOD_RESOURCES / "reuse-map.json"
FRAME_MAP2 = FOOD_RESOURCES / "frame_map2.json"
TIMESTAMPS2 = FOOD_RESOURCES / "frame_timestamps2.json"
SOURCE = FOOD_RESOURCES / "FoodVideoSource.swift"
ACCEPTED_GLOB = str(
    ROOT / "ayurveda-data" / "imagery" / "accepted" / "batch-*.json"
)

UNSAFE = frozenset('/\\:*?"<>|')


@dataclass(frozen=True)
class Resolution:
    archive: int
    index: int
    route: str


def frame_key(name: str) -> str:
    return "".join("_" if character in UNSAFE else character for character in name)


def frame_index(name: str, mapping: dict[str, int]) -> int | None:
    return mapping.get(name, mapping.get(frame_key(name)))


def resolve(
    name: str,
    frame_map: dict[str, int],
    reuse_map: dict[str, dict[str, str]],
    frame_map2: dict[str, int],
) -> Resolution | None:
    index = frame_index(name, frame_map)
    if index is not None:
        return Resolution(archive=1, index=index, route="map1")

    reference = reuse_map.get(name, reuse_map.get(frame_key(name)))
    if reference is not None:
        index = frame_index(reference["frameKey"], frame_map)
        if index is not None:
            return Resolution(archive=1, index=index, route="reuse")

    index = frame_index(name, frame_map2)
    if index is not None:
        return Resolution(archive=2, index=index, route="map2")
    return None


def canonical_json_hash(value: object) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return hashlib.sha256(payload).hexdigest()


def main() -> None:
    foods = json.loads(FOODS.read_text(encoding="utf-8"))
    frame_map = json.loads(FRAME_MAP.read_text(encoding="utf-8"))
    reuse_map = json.loads(REUSE_MAP.read_text(encoding="utf-8"))
    frame_map2 = (
        json.loads(FRAME_MAP2.read_text(encoding="utf-8"))
        if FRAME_MAP2.exists()
        else {}
    )
    source = SOURCE.read_text(encoding="utf-8")

    assert len(foods) == 12_601
    assert len(frame_map) == 12_601
    assert len(reuse_map) == 324

    # I6: capture the FIX-1 result independently of the new tiers, then prove
    # the production tier order retains every index exactly.
    tier1_before = {
        int(food["id"]): frame_index(food["name"], frame_map)
        for food in foods
    }
    assert all(index is not None for index in tier1_before.values())
    tier1_after = {
        int(food["id"]): resolve(
            food["name"],
            frame_map,
            reuse_map,
            frame_map2,
        )
        for food in foods
    }
    changed_tier1 = [
        food_id
        for food_id, before_index in tier1_before.items()
        if tier1_after[food_id] is None
        or tier1_after[food_id].archive != 1
        or tier1_after[food_id].index != before_index
    ]
    assert changed_tier1 == []

    # I1: all delivered reuse entries must traverse reuse -> archive 1.
    reuse_resolutions = {
        name: resolve(name, frame_map, reuse_map, frame_map2)
        for name in reuse_map
    }
    bad_reuse = [
        name
        for name, resolution in reuse_resolutions.items()
        if resolution is None
        or resolution.archive != 1
        or resolution.route != "reuse"
        or resolution.index
        != frame_index(reuse_map[name]["frameKey"], frame_map)
    ]
    assert bad_reuse == []

    # I3: archive 2 may never shadow archive 1.
    shared_keys = sorted(set(frame_map).intersection(frame_map2))
    assert shared_keys == [], f"map collision(s): {shared_keys}"

    accepted: list[dict[str, object]] = []
    for path in sorted(glob.glob(ACCEPTED_GLOB)):
        accepted.extend(
            json.loads(Path(path).read_text(encoding="utf-8")).get(
                "accepted",
                []
            )
        )

    map2_resolvable = 0
    if frame_map2:
        accepted_keys = [str(row["frameKey"]) for row in accepted]
        assert len(accepted_keys) == len(frame_map2)
        assert set(accepted_keys) == set(frame_map2)
        map2_resolvable = sum(
            resolve(key, frame_map, reuse_map, frame_map2)
            == Resolution(archive=2, index=frame_map2[key], route="map2")
            for key in frame_map2
        )
        assert map2_resolvable == len(frame_map2)

        timestamps2 = json.loads(TIMESTAMPS2.read_text(encoding="utf-8"))
        assert len(timestamps2) == len(frame_map2)

    # Source-level order checks complement the exhaustive data model above.
    map1_branch = source.index("frameIndex(for: name, in: frameMap)")
    reuse_branch = source.index("reuseReference(for: name)")
    map2_branch = source.index("frameIndex(for: name, in: frameMap2)")
    assert map1_branch < reuse_branch < map2_branch
    assert "resolution(for: foodName) != nil" in source
    assert "resolution(for: name) == nil ? nil : frameKey(name)" in source
    assert 'charactersIn: "/\\\\:*?\\"<>|"' in source

    print(
        json.dumps(
            {
                "I1": {
                    "reuseEntries": len(reuse_map),
                    "resolvedViaReuseIntoArchive1": len(reuse_resolutions),
                    "bad": len(bad_reuse),
                },
                "I2": {
                    "accepted": len(accepted),
                    "map2": len(frame_map2),
                    "resolvable": map2_resolvable,
                },
                "I3": {
                    "sharedKeys": len(shared_keys),
                    "collisions": shared_keys,
                },
                "I6": {
                    "tier1Rows": len(tier1_before),
                    "changedIndices": len(changed_tier1),
                    "beforeMapSHA256": canonical_json_hash(tier1_before),
                    "afterMapSHA256": canonical_json_hash(
                        {
                            food_id: resolution.index
                            for food_id, resolution in tier1_after.items()
                            if resolution is not None
                        }
                    ),
                },
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
