#!/usr/bin/env python3
"""Project approved preparation nutrition from the existing recipe engine output.

The recipe engine remains the sole formula implementation. This tool only copies its
full, ingredient-weighted per-100 g panel onto a same-preparation dravya review row.
"""

from __future__ import annotations

import argparse
import collections
import gzip
import json
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
DATA = HERE.parent
sys.path.insert(0, str(DATA))
from build_seed import (  # noqa: E402
    NUTRIENT_CATALOG,
    TIER_RANK,
    derive_dravya_composition,
    load_dravya_food_nutrition,
    load_food_nutrition,
    preferred_nutrition_bindings,
)


PREPARATION_RECIPES = {
    "dravya.besan-ladoo": "recipe.besan-laddu",
    "dravya.golden-milk": "recipe.golden-milk",
    "dravya.moong-dal-halwa": "recipe.mung-dal-halwa",
    "dravya.panchamrita": "recipe.panchamrit-classic",
    "dravya.pongal-ven": "recipe.ven-pongal-ghee",
    "dravya.steamed-modak": "recipe.modak-ukadiche",
}


def load_json(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as handle:
        return json.load(handle)


def recipe_sources(repo: Path) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {}
    for path in sorted((repo / "ayurveda-data" / "recipes").glob("batch-*.json")):
        for recipe in json.loads(path.read_text())["items"]:
            result[recipe["id"]] = recipe["ingredients"]
    return result


def ingredient_label(ingredient: dict) -> str:
    if "dravyaId" in ingredient:
        return ingredient["dravyaId"]
    return f"fdc.{ingredient['fdcId']}"


def all_nutrient_entries(row: dict):
    for section in {
        section for section, _unit in NUTRIENT_CATALOG.values()
    }:
        yield from row.get(section, {}).values()


DERIVATION_LIMITATION = (
    "Uses the established recipe per-nutrient aggregation: when at least one "
    "ingredient measures a nutrient, an absent value on another ingredient "
    "contributes nothing. This can understate that nutrient and is inherited "
    "for consistency with all shipped recipes; it is not an assertion of zero."
)


def derive_authored_compositions(
    repo: Path,
    seed: dict,
    foods_path: Path,
    compositions_path: Path,
) -> None:
    source = json.loads(compositions_path.read_text(encoding="utf-8"))
    compositions = source.get("compositions")
    expected_count = source.get("_meta", {}).get("count")
    if not isinstance(compositions, list) or len(compositions) != expected_count:
        raise SystemExit(
            f"composition count mismatch: expected {expected_count}, "
            f"got {len(compositions) if isinstance(compositions, list) else 'invalid'}"
        )
    if expected_count != 34:
        raise SystemExit(f"NUT5 batch 1 must contain 34 compositions, got {expected_count}")

    foods = json.loads(foods_path.read_text(encoding="utf-8"))
    before = json.loads(json.dumps(foods, ensure_ascii=False))
    by_dravya = {food["dravyaId"]: food for food in foods}
    seed_dravyas = {dravya["id"]: dravya for dravya in seed["dravyas"]}
    composition_ids = [composition["dravyaId"] for composition in compositions]
    if len(set(composition_ids)) != len(composition_ids):
        raise SystemExit("compositions.json contains a duplicate dravyaId")

    legacy_path = repo / "Ayura" / "Legacy" / "foods.json"
    legacy_foods = json.loads(legacy_path.read_text(encoding="utf-8"))
    legacy_ids = {food["id"] for food in legacy_foods}
    nutrition_by_id = load_food_nutrition(legacy_path, legacy_ids)
    dravya_panels = load_dravya_food_nutrition(foods_path)
    bindings = collections.defaultdict(list)
    for ordinal, link in enumerate(seed["links"]):
        if link["tier"] not in TIER_RANK:
            continue
        bindings[link["dravyaId"]].append(
            (link["fdcId"], link["tier"], ordinal)
        )
    preferred = preferred_nutrition_bindings(bindings)
    for dravya in seed["dravyas"]:
        if not dravya["foodIsPlaceholder"]:
            continue
        panel = dravya_panels[dravya["id"]]
        preferred[dravya["id"]] = dravya["foodId"]
        if panel:
            nutrition_by_id[dravya["foodId"]] = panel

    status_before = collections.Counter(
        row.get("_review", {}).get("status", "<missing>") for row in foods
    )
    results = []
    derived_zero_traces = []
    for composition in compositions:
        dravya_id = composition["dravyaId"]
        row = by_dravya.get(dravya_id)
        seed_dravya = seed_dravyas.get(dravya_id)
        if row is None or seed_dravya is None:
            raise SystemExit(f"composition target is absent: {dravya_id}")
        if not seed_dravya["foodIsPlaceholder"]:
            raise SystemExit(f"composition target is not a placeholder: {dravya_id}")
        existing = [
            f"{section}.{nutrient}"
            for nutrient, (section, _unit) in NUTRIENT_CATALOG.items()
            if row[section][nutrient].get("value") is not None
        ]
        if existing:
            raise SystemExit(
                f"{dravya_id}: measured nutrition wins; refusing composition "
                f"over existing values {existing[:8]}"
            )

        payload, source_ids = derive_dravya_composition(
            composition, nutrition_by_id, preferred
        )
        if payload is None:
            missing = [
                ingredient["dravyaId"]
                for ingredient, source_id in zip(
                    composition["ingredients"], source_ids, strict=True
                )
                if source_id is None
            ]
            results.append((dravya_id, len(composition["ingredients"]), 0, missing))
            continue

        row_zero_traces = []
        for nutrient, value in payload["per100g"].items():
            if value != 0:
                continue
            source_values = [
                nutrition_by_id[source_id].get(nutrient)
                for source_id in source_ids
                if source_id is not None
            ]
            ingredients = composition["ingredients"]
            measured_zero = [
                ingredient["dravyaId"]
                for ingredient, source_value in zip(
                    ingredients, source_values, strict=True
                )
                if source_value == 0
            ]
            absent = [
                ingredient["dravyaId"]
                for ingredient, source_value in zip(
                    ingredients, source_values, strict=True
                )
                if source_value is None
            ]
            unexpected = [
                source_value
                for source_value in source_values
                if source_value not in (None, 0)
            ]
            if not measured_zero or unexpected:
                raise SystemExit(
                    f"{dravya_id}: derived zero for {nutrient} has no literal "
                    f"zero source or contains a positive input: {source_values}"
                )
            trace = {
                "nutrient": nutrient,
                "measuredZeroIngredients": measured_zero,
                "absentIngredients": absent,
            }
            row_zero_traces.append(trace)
            derived_zero_traces.append((dravya_id, trace))

        for nutrient, value in payload["per100g"].items():
            section, _unit = NUTRIENT_CATALOG[nutrient]
            row[section][nutrient]["value"] = value

        previous_review = row.get("_review", {})
        labels = [ingredient["dravyaId"] for ingredient in composition["ingredients"]]
        review = {
            "source": composition["basis"],
            "spread": "Deterministic authored composition; no analytical spread.",
            "status": f"derived — computed from {', '.join(labels)}",
            "provenance": "derived",
            "limitation": DERIVATION_LIMITATION,
            "formula": {
                "method": (
                    "build_seed.derive_recipe_nutrition ingredient accumulation "
                    "with authored finished-yield divisor"
                ),
                "yieldG": composition["yieldG"],
                "waterG": composition.get("waterG", 0),
                "inputs": composition["ingredients"],
            },
            "currentMinAgeMonths": previous_review.get("currentMinAgeMonths"),
            "proposedMinAgeMonths": previous_review.get("proposedMinAgeMonths"),
            "ageReason": previous_review.get("ageReason"),
        }
        if "note" in composition:
            review["note"] = composition["note"]
        if row_zero_traces:
            review["inheritedPartialObservationZeroes"] = row_zero_traces
        row["_review"] = review
        results.append(
            (dravya_id, len(composition["ingredients"]), len(payload["per100g"]), [])
        )

    changed_ids = {
        new["dravyaId"]
        for old, new in zip(before, foods, strict=True)
        if old != new
    }
    produced_ids = {dravya_id for dravya_id, _i, count, _m in results if count}
    if changed_ids != produced_ids:
        raise SystemExit(
            "composition apply changed the wrong rows: "
            f"expected={sorted(produced_ids)}, actual={sorted(changed_ids)}"
        )
    if produced_ids != set(composition_ids):
        missing = sorted(set(composition_ids) - produced_ids)
        raise SystemExit(f"not all 34 compositions produced full panels: {missing}")

    status_after = collections.Counter(
        row.get("_review", {}).get("status", "<missing>") for row in foods
    )
    print("authored dravya compositions")
    for dravya_id, ingredient_count, nutrient_count, missing in results:
        print(
            f"{dravya_id}|ingredients={ingredient_count}|"
            f"nutrients={nutrient_count}|missing={','.join(missing)}"
        )
    print(f"derived zero traces: {len(derived_zero_traces)}")
    for dravya_id, trace in derived_zero_traces:
        print(
            f"ZERO|{dravya_id}|{trace['nutrient']}|"
            f"measured-zero={','.join(trace['measuredZeroIngredients'])}|"
            f"absent={','.join(trace['absentIngredients'])}"
        )
    print("status histogram before:", json.dumps(status_before, ensure_ascii=False, sort_keys=True))
    print("status histogram after:", json.dumps(status_after, ensure_ascii=False, sort_keys=True))
    foods_path.write_text(
        json.dumps(foods, indent=1, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--seed", required=True, type=Path)
    parser.add_argument("--foods", default=HERE / "dravya_foods.json", type=Path)
    parser.add_argument("--compositions", type=Path)
    args = parser.parse_args()

    repo = args.repo.expanduser().resolve()
    seed = load_json(args.seed.expanduser())
    if args.compositions is not None:
        derive_authored_compositions(
            repo,
            seed,
            args.foods.expanduser().resolve(),
            args.compositions.expanduser().resolve(),
        )
        return
    recipes = {recipe["id"]: recipe for recipe in seed["recipes"]}
    authored_inputs = recipe_sources(repo)
    foods = json.loads(args.foods.read_text())
    by_dravya = {food["dravyaId"]: food for food in foods}

    for dravya_id, recipe_id in PREPARATION_RECIPES.items():
        row = by_dravya.get(dravya_id)
        recipe = recipes.get(recipe_id)
        if row is None or recipe is None:
            raise SystemExit(f"missing preparation mapping endpoint: {dravya_id} -> {recipe_id}")
        nutrition = recipe.get("nutrition") or {}
        if nutrition.get("status") != "full" or nutrition.get("missingIngredients") != []:
            raise SystemExit(f"{recipe_id}: recipe projection is not fully sourced")

        review = row.get("_review", {})
        previous_status = review.get("status", "")
        if not (
            previous_status.startswith("unsourced —")
            or previous_status.startswith("NOT YET SOURCED —")
            or previous_status.startswith("derived —")
        ):
            raise SystemExit(
                f"{dravya_id}: refusing to replace review status {previous_status!r}"
            )

        populated = 0
        for nutrient, value in nutrition["per100g"].items():
            if value == 0:
                continue
            section, _unit = NUTRIENT_CATALOG[nutrient]
            entry = row[section][nutrient]
            old_value = entry.get("value")
            if old_value is not None and old_value != value:
                raise SystemExit(
                    f"{dravya_id}: refusing to replace {section}.{nutrient} "
                    f"{old_value} with {value}"
                )
            entry["value"] = value
            populated += 1
        if not populated:
            raise SystemExit(f"{dravya_id}: projection populated no nutrients")

        inputs = authored_inputs[recipe_id]
        labels = [ingredient_label(item) for item in inputs]
        weighted = ", ".join(
            f"{ingredient_label(item)}={item['grams']}g" for item in inputs
        )
        row["_review"] = {
            "source": f"{recipe_id}; authored ingredient weights: {weighted}",
            "spread": "Deterministic recipe projection; no analytical spread and no yield correction beyond authored total ingredient mass.",
            "status": f"derived — computed from {', '.join(labels)}, see formula",
            "provenance": "derived",
            "formula": {
                "method": "existing build_seed.derive_recipe_nutrition weighted per-100g projection",
                "recipeId": recipe_id,
                "totalWeightG": nutrition["totalWeightG"],
                "inputs": [
                    {"id": ingredient_label(item), "grams": item["grams"]}
                    for item in inputs
                ],
            },
            "currentMinAgeMonths": review.get("currentMinAgeMonths"),
            "proposedMinAgeMonths": review.get("proposedMinAgeMonths"),
            "ageReason": review.get("ageReason"),
        }

    args.foods.write_text(json.dumps(foods, indent=1, ensure_ascii=False) + "\n")
    print(f"derived {len(PREPARATION_RECIPES)} preparations via existing recipe projections")


if __name__ == "__main__":
    main()
