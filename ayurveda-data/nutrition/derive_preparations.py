#!/usr/bin/env python3
"""Project approved preparation nutrition from the existing recipe engine output.

The recipe engine remains the sole formula implementation. This tool only copies its
full, ingredient-weighted per-100 g panel onto a same-preparation dravya review row.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
DATA = HERE.parent
sys.path.insert(0, str(DATA))
from build_seed import NUTRIENT_CATALOG  # noqa: E402


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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--seed", required=True, type=Path)
    parser.add_argument("--foods", default=HERE / "dravya_foods.json", type=Path)
    args = parser.parse_args()

    repo = args.repo.expanduser().resolve()
    seed = load_json(args.seed.expanduser())
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
