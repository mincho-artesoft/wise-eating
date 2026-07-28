#!/usr/bin/env python3
"""FIX-1 frame-key coverage and stability gate."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FOODS = ROOT / "WiseEating" / "Legacy" / "foods.json"
FRAME_MAP = ROOT / "WiseEating" / "Food" / "frame_map.json"
SOURCE = ROOT / "WiseEating" / "Food" / "FoodVideoSource.swift"

UNSAFE = frozenset('/\\:*?"<>|')
OLD_GUESS = frozenset("/%")


def frame_key(name: str, unsafe: frozenset[str] = UNSAFE) -> str:
    return "".join("_" if character in unsafe else character for character in name)


def resolve(
    name: str,
    frame_map: dict[str, int],
    unsafe: frozenset[str] = UNSAFE,
) -> int | None:
    # Production order is load-bearing: preserve every raw hit first.
    return frame_map.get(name, frame_map.get(frame_key(name, unsafe)))


def main() -> None:
    foods = json.loads(FOODS.read_text(encoding="utf-8"))
    frame_map = json.loads(FRAME_MAP.read_text(encoding="utf-8"))
    source = SOURCE.read_text(encoding="utf-8")

    assert len(foods) == 12_601
    assert len(frame_map) == 12_601

    resolved = {
        int(food["id"]): resolve(food["name"], frame_map)
        for food in foods
    }
    assert all(index is not None for index in resolved.values())

    raw_before = {
        int(food["id"]): frame_map[food["name"]]
        for food in foods
        if food["name"] in frame_map
    }
    old_guess_before = {
        int(food["id"]): index
        for food in foods
        if (
            index := resolve(food["name"], frame_map, OLD_GUESS)
        ) is not None
    }
    food_item_fetch_before = {
        int(food["id"]): frame_map[
            frame_key(food["name"], frozenset('/":'))
        ]
        for food in foods
    }

    shifted_raw = [
        food_id
        for food_id, index in raw_before.items()
        if resolved[food_id] != index
    ]
    shifted_old_guess = [
        food_id
        for food_id, index in old_guess_before.items()
        if resolved[food_id] != index
    ]
    shifted_fetch = [
        food_id
        for food_id, index in food_item_fetch_before.items()
        if resolved[food_id] != index
    ]
    assert shifted_raw == []
    assert shifted_old_guess == []
    assert shifted_fetch == []

    resolved_indices = set(resolved.values())
    assert len(resolved_indices) == 12_601

    newly_resolving = [
        food
        for food in foods
        if resolve(food["name"], frame_map, OLD_GUESS) is None
        and resolved[int(food["id"])] is not None
    ]
    assert len(newly_resolving) == 1_023

    hot = [
        food
        for food in newly_resolving
        if "Hot chocolate / cocoa" in food["name"]
    ][:5]
    one_eighth = [
        food
        for food in newly_resolving
        if '1/8" fat' in food["name"]
    ][:5]
    spot_checks = hot + one_eighth
    assert len(hot) == 5
    assert len(one_eighth) == 5

    raw_lookup = source.index("mapping[name]")
    normalized_lookup = source.index("mapping[frameKey(name)]")
    assert raw_lookup < normalized_lookup
    assert 'charactersIn: "/\\\\:*?\\"<>|"' in source
    assert "Set(frameMap.keys)" in source
    assert "resolution(for: name) == nil ? nil : frameKey(name)" in source

    print(
        json.dumps(
            {
                "F1": {
                    "resolved": len(resolved),
                    "catalogue": len(foods),
                },
                "F2": {
                    "rawBaseline": len(raw_before),
                    "oldSlashPercentGuessBaseline": len(old_guess_before),
                    "existingFoodItemFetchBaseline": len(
                        food_item_fetch_before
                    ),
                    "shiftedRaw": len(shifted_raw),
                    "shiftedOldGuess": len(shifted_old_guess),
                    "shiftedExistingFetch": len(shifted_fetch),
                },
                "F3": {
                    "distinctResolvedIndices": len(resolved_indices),
                },
                "newlyResolvingAgainstSlashPercentGuess": len(
                    newly_resolving
                ),
                "F4SpotChecks": [
                    {
                        "foodId": int(food["id"]),
                        "name": food["name"],
                        "frameKey": frame_key(food["name"]),
                        "index": resolved[int(food["id"])],
                    }
                    for food in spot_checks
                ],
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
