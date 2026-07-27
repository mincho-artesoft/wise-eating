#!/usr/bin/env python3
"""Build the deterministic Ayurveda seed bundle consumed by the app."""

from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


SEED_VERSION = 5
GENERATED_AT = "2026-07-25T00:00:00Z"
EXPECTED_COUNTS = {
    "dravyas": 714,
    "recipes": 1500,
    "links": 2305,
    "derivedLinks": 1969,
    "placeholders": 383,
    "primaries": 331,
    "categoryRules": 187,
    "modifiers": 14,
}
V1_LINK_COUNT = 336
ENGINE_EXCLUDED_IDS = {"dravya.betel-nut", "dravya.vanaspati"}
PLACEHOLDER_BASE = 900_000
RECIPE_BASE = 1_000_000
RESERVED_BAND_END = 1_002_000
TIER_RANK = {"exact": 0, "near": 1}
EXPECTED_CATALOG_COUNT = 14_484
EXPECTED_CONCEPT_COUNT = 25
EXPECTED_ALIAS_COUNT = 75
EXPECTED_FOOD_ROLE_COUNT = 14
EXPECTED_FOOD_ROLE_RULE_COUNT = 28
RECIPE_PROPAGATION_DEPTH_CAP = 16
MODIFIER_PARENTHETICAL = re.compile(r"\([^)]*\)")
MODIFIER_INVALID = re.compile(r"[^a-z0-9,;'\- ]")
MODIFIER_TOKEN_SPLIT = re.compile(r"[\s\-'/]+")
NUTRIENT_CATALOG = {
    "energyKcal": ("other", "kcal"),
    "carbohydrates": ("macronutrients", "g"),
    "protein": ("macronutrients", "g"),
    "fat": ("macronutrients", "g"),
    "fiber": ("macronutrients", "g"),
    "totalSugars": ("macronutrients", "g"),
    "vitaminA_RAE": ("vitamins", "µg"),
    "retinol": ("vitamins", "µg"),
    "caroteneAlpha": ("vitamins", "µg"),
    "caroteneBeta": ("vitamins", "µg"),
    "cryptoxanthinBeta": ("vitamins", "µg"),
    "luteinZeaxanthin": ("vitamins", "µg"),
    "lycopene": ("vitamins", "µg"),
    "vitaminB1_Thiamin": ("vitamins", "mg"),
    "vitaminB2_Riboflavin": ("vitamins", "mg"),
    "vitaminB3_Niacin": ("vitamins", "mg"),
    "vitaminB5_PantothenicAcid": ("vitamins", "mg"),
    "vitaminB6": ("vitamins", "mg"),
    "folateDFE": ("vitamins", "µg"),
    "folateFood": ("vitamins", "µg"),
    "folateTotal": ("vitamins", "µg"),
    "folicAcid": ("vitamins", "µg"),
    "vitaminB12": ("vitamins", "µg"),
    "vitaminC": ("vitamins", "mg"),
    "vitaminD": ("vitamins", "µg"),
    "vitaminE": ("vitamins", "mg"),
    "vitaminK": ("vitamins", "µg"),
    "choline": ("vitamins", "mg"),
    "calcium": ("minerals", "mg"),
    "iron": ("minerals", "mg"),
    "magnesium": ("minerals", "mg"),
    "phosphorus": ("minerals", "mg"),
    "potassium": ("minerals", "mg"),
    "sodium": ("minerals", "mg"),
    "selenium": ("minerals", "µg"),
    "zinc": ("minerals", "mg"),
    "copper": ("minerals", "mg"),
    "manganese": ("minerals", "mg"),
    "fluoride": ("minerals", "µg"),
}
SAFETY_PROVENANCE = "scaffold-default"
SAFETY_REVIEW_REQUIRED = True
AGE_PROVENANCE_AUTHORED = "authored"
AGE_PROVENANCE_LEGACY_IMPORT = "legacyImport"
DIET_VOCABULARY = {
    "Dairy-Free",
    "Egg-Free",
    "Fat-Free",
    "Gluten-Free",
    "Halal",
    "High-Protein",
    "Keto",
    "Kosher",
    "Lactose-Free",
    "Low Sodium",
    "Low-Carb",
    "Low-Fat",
    "Mineral-Rich",
    "No Added Sugar",
    "Nut-Free",
    "Paleo",
    "Pescatarian",
    "Soy-Free",
    "Vegan",
    "Vegetarian",
    "Vitamin-Rich",
}
COMPOSITION_DIETS = {
    "Dairy-Free",
    "Egg-Free",
    "Gluten-Free",
    "Lactose-Free",
    "Nut-Free",
    "Pescatarian",
    "Soy-Free",
    "Vegan",
    "Vegetarian",
}
ALLERGEN_VOCABULARY = {
    "Celery",
    "Cereals containing gluten",
    "Cereals containing gluten (barley)",
    "Cereals containing gluten (oats)",
    "Cereals containing gluten (rye)",
    "Crustaceans",
    "Eggs",
    "Fish",
    "Low Sodium",
    "Milk",
    "Molluscs",
    "Mustard",
    "Nuts",
    "Nuts (Brazil nuts)",
    "Nuts (almonds)",
    "Nuts (cashews)",
    "Nuts (chestnuts)",
    "Nuts (coconut)",
    "Nuts (hazelnuts)",
    "Nuts (macadamia nuts)",
    "Nuts (pecans)",
    "Nuts (pine nuts)",
    "Nuts (pistachio nuts)",
    "Nuts (walnuts)",
    "Peanuts",
    "Sesame seeds",
    "Soybeans",
    "Sulphur dioxide/sulphites",
}

# Reviewed, exact-slug rules. Broad substring matching is deliberately forbidden:
# e.g. buckwheat is not wheat, water chestnut is not a tree nut, and eggplant is
# not egg. Category rules are used only where the category itself is decisive.
CATEGORY_ALLERGEN_RULES = {
    "dairy": {"Milk"},
}
ALLERGEN_DRAVYA_RULES = {
    "Celery": {
        "dravya.celery",
        "dravya.celery-seed",
        "dravya.celery-stalk",
        "dravya.wild-celery-seed",
    },
    "Milk": {
        "dravya.badam-milk",
        "dravya.basundi",
        "dravya.besan-ladoo",
        "dravya.chhurpi",
        "dravya.chyawanprash",
        "dravya.curd-rice",
        "dravya.filter-coffee",
        "dravya.ghee",
        "dravya.ghee-cultured",
        "dravya.ghee-spiced",
        "dravya.golden-milk",
        "dravya.halwa-carrot",
        "dravya.kadhi",
        "dravya.kefir",
        "dravya.kharvas",
        "dravya.kheer-rice",
        "dravya.lassi-digestive",
        "dravya.lassi-sweet",
        "dravya.masala-chai",
        "dravya.moong-dal-halwa",
        "dravya.panchamrita",
        "dravya.payasam-mung",
        "dravya.pongal-sweet",
        "dravya.pongal-ven",
        "dravya.rabri",
        "dravya.rose-milk",
        "dravya.shrikhand",
        "dravya.sooji-halwa",
        "dravya.takra",
        "dravya.thandai",
        "dravya.yak-butter",
        "dravya.yak-milk",
    },
    "Cereals containing gluten": {
        "dravya.emmer-wheat",
        "dravya.khakhra",
        "dravya.paratha-plain",
        "dravya.puran-poli",
        "dravya.puri",
        "dravya.refined-flour",
        "dravya.roti",
        "dravya.semolina",
        "dravya.sooji-halwa",
        "dravya.thepla",
        "dravya.upma",
        "dravya.vermicelli",
        "dravya.wheat-broken",
        "dravya.wheatgrass",
        "dravya.whole-wheat",
        "dravya.whole-wheat-flour",
    },
    "Cereals containing gluten (barley)": {
        "dravya.barley",
        "dravya.barley-water",
    },
    "Cereals containing gluten (oats)": {
        "dravya.oat-milk",
        "dravya.oats",
    },
    "Nuts": {
        "dravya.chironji",
        "dravya.panchmeva",
        "dravya.thandai",
    },
    "Nuts (Brazil nuts)": {"dravya.brazil-nut"},
    "Nuts (almonds)": {
        "dravya.almond",
        "dravya.almond-milk",
        "dravya.almond-oil",
        "dravya.badam-milk",
    },
    "Nuts (cashews)": {
        "dravya.cashew",
        "dravya.tender-cashew-fruit",
    },
    "Nuts (chestnuts)": {"dravya.chestnut"},
    "Nuts (coconut)": {
        "dravya.coconut-chutney",
        "dravya.coconut-dried",
        "dravya.coconut-fresh",
        "dravya.coconut-oil",
        "dravya.coconut-rice",
        "dravya.coconut-sugar",
        "dravya.coconut-vinegar",
        "dravya.coconut-water",
        "dravya.desiccated-coconut",
        "dravya.dry-coconut",
        "dravya.tender-coconut-flesh",
    },
    "Nuts (hazelnuts)": {"dravya.hazelnut"},
    "Nuts (macadamia nuts)": {"dravya.macadamia"},
    "Nuts (pecans)": {"dravya.pecan"},
    "Nuts (pine nuts)": {"dravya.pine-nut"},
    "Nuts (pistachio nuts)": {"dravya.pistachio"},
    "Nuts (walnuts)": {
        "dravya.walnut",
        "dravya.walnut-oil",
    },
    "Peanuts": {
        "dravya.peanut",
        "dravya.peanut-chikki",
        "dravya.peanut-oil",
        "dravya.peanut-raw",
        "dravya.peanut-roasted",
    },
    "Sesame seeds": {
        "dravya.black-sesame",
        "dravya.sesame-oil",
        "dravya.sesame-seed",
        "dravya.sesame-spice-blend",
        "dravya.til-ladoo",
        "dravya.til-oil-pickle",
        "dravya.white-sesame",
    },
    "Eggs": {
        "dravya.chicken-egg",
        "dravya.desi-egg",
        "dravya.duck-egg",
        "dravya.egg-bhurji",
        "dravya.quail-egg",
    },
    "Fish": {
        "dravya.catla",
        "dravya.dried-fish",
        "dravya.hilsa",
        "dravya.mackerel",
        "dravya.pomfret",
        "dravya.rohu",
        "dravya.salmon",
        "dravya.sardine",
        "dravya.seer-fish",
        "dravya.tuna",
    },
    "Crustaceans": {
        "dravya.crab",
        "dravya.prawn",
    },
    "Soybeans": {
        "dravya.bhatt-soybean",
        "dravya.hawaijar",
        "dravya.kinema",
        "dravya.miso",
        "dravya.soy-milk",
        "dravya.soybean",
        "dravya.soybean-oil",
        "dravya.tempeh",
        "dravya.tofu",
    },
    "Mustard": {
        "dravya.mustard-greens",
        "dravya.mustard-oil",
        "dravya.mustard-pods",
        "dravya.mustard-powder",
        "dravya.mustard-seed",
        "dravya.mustard-seed-black",
        "dravya.mustard-seed-yellow",
        "dravya.panch-phoron",
        "dravya.wild-mustard",
    },
}
HONEY_DRAVYA_IDS = {
    "dravya.chyawanprash",
    "dravya.honey",
    "dravya.honey-aged",
    "dravya.panchamrita",
}


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
    parser.add_argument(
        "--rules-output",
        type=Path,
        default=repo_root / "WiseEating" / "ayurveda_rules.json",
        help="Destination category-rule bundle",
    )
    parser.add_argument(
        "--concepts-output",
        type=Path,
        default=repo_root / "WiseEating" / "food_concepts.json.gz",
        help="Destination deterministic food-concept membership bundle",
    )
    parser.add_argument(
        "--roles-output",
        type=Path,
        default=repo_root / "WiseEating" / "food_roles.json.gz",
        help="Destination deterministic food-role resolution bundle",
    )
    parser.add_argument(
        "--foods",
        type=Path,
        default=repo_root / "WiseEating" / "Legacy" / "foods.json",
        help="USDA-backed per-100g nutrient source used to build the shipped store",
    )
    return parser.parse_args()


def store_path(path: Path) -> Path:
    candidate = path / "default.store" if path.is_dir() else path
    if not candidate.is_file():
        raise BuildError(f"store does not exist: {candidate}")
    return candidate


def modifier_normalized_tokens(value: str) -> tuple[str, ...]:
    """The modifiers.json token contract, shared verbatim with validate.py."""
    value = value.lower()
    value = MODIFIER_PARENTHETICAL.sub("", value)
    value = value.replace("&", " and ")
    value = MODIFIER_INVALID.sub(" ", value)
    value = value.replace(",", " ").replace(";", " ")
    return tuple(token for token in MODIFIER_TOKEN_SPLIT.split(value) if token)


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


def load_food_nutrition(
    path: Path, store_ids: set[int]
) -> dict[int, dict[str, float]]:
    try:
        foods = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load USDA nutrient source {path}: {error}") from error
    if not isinstance(foods, list):
        raise BuildError(f"{path}: expected a top-level array")

    nutrition_by_id: dict[int, dict[str, float]] = {}
    for food in foods:
        if not isinstance(food, dict) or not isinstance(food.get("id"), int):
            raise BuildError(f"{path}: food has no integer id")
        food_id = food["id"]
        if food_id in nutrition_by_id:
            raise BuildError(f"{path}: duplicate food id {food_id}")

        panel: dict[str, float] = {}
        for nutrient, (section, expected_unit) in NUTRIENT_CATALOG.items():
            entry = food.get(section, {}).get(nutrient)
            if not isinstance(entry, dict):
                raise BuildError(f"{path}: food {food_id} is missing {section}.{nutrient}")
            unit = entry.get("unit")
            if unit != expected_unit:
                raise BuildError(
                    f"{path}: food {food_id} {nutrient} uses {unit!r}, "
                    f"expected {expected_unit!r}"
                )
            value = entry.get("value")
            if value is not None:
                if not isinstance(value, (int, float)) or value < 0:
                    raise BuildError(
                        f"{path}: food {food_id} {nutrient} has invalid value {value!r}"
                    )
                panel[nutrient] = float(value)
        nutrition_by_id[food_id] = panel

    missing_source_ids = sorted(nutrition_by_id.keys() - store_ids)
    if missing_source_ids:
        preview = ", ".join(str(food_id) for food_id in missing_source_ids[:10])
        raise BuildError(f"{path}: nutrient source food ids are absent from store: {preview}")
    return nutrition_by_id


def load_food_safety(
    path: Path, store_ids: set[int]
) -> dict[int, dict[str, Any]]:
    try:
        foods = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load USDA safety source {path}: {error}") from error
    if not isinstance(foods, list):
        raise BuildError(f"{path}: expected a top-level array")

    safety_by_id: dict[int, dict[str, Any]] = {}
    for food in foods:
        if not isinstance(food, dict) or not isinstance(food.get("id"), int):
            raise BuildError(f"{path}: food has no integer id")
        food_id = food["id"]
        if food_id in safety_by_id:
            raise BuildError(f"{path}: duplicate food id {food_id}")

        allergens = food.get("allergens") or []
        diets = food.get("diets") or []
        min_age = food.get("minAgeMonths", 0)
        if not isinstance(allergens, list) or not all(
            isinstance(value, str) for value in allergens
        ):
            raise BuildError(f"{path}: food {food_id} has invalid allergens")
        if not isinstance(diets, list) or not all(
            isinstance(value, str) for value in diets
        ):
            raise BuildError(f"{path}: food {food_id} has invalid diets")
        unknown_allergens = set(allergens) - ALLERGEN_VOCABULARY
        unknown_diets = set(diets) - DIET_VOCABULARY
        if unknown_allergens:
            raise BuildError(
                f"{path}: food {food_id} has unsupported allergens "
                + f"{sorted(unknown_allergens)}"
            )
        if unknown_diets:
            raise BuildError(
                f"{path}: food {food_id} has unsupported diets {sorted(unknown_diets)}"
            )
        if not isinstance(min_age, int) or min_age < 0:
            raise BuildError(f"{path}: food {food_id} has invalid minAgeMonths")

        safety_by_id[food_id] = {
            "allergens": sorted(set(allergens)),
            "diets": sorted(set(diets)),
            "minAgeMonths": min_age,
        }

    missing_source_ids = sorted(safety_by_id.keys() - store_ids)
    if missing_source_ids:
        preview = ", ".join(str(food_id) for food_id in missing_source_ids[:10])
        raise BuildError(f"{path}: safety source food ids are absent from store: {preview}")
    return safety_by_id


def load_food_names(path: Path, store_ids: set[int]) -> dict[int, str]:
    return {
        food_id: record["name"]
        for food_id, record in load_food_catalog(path, store_ids).items()
    }


def load_food_catalog(
    path: Path, store_ids: set[int]
) -> dict[int, dict[str, Any]]:
    try:
        foods = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load food catalogue from {path}: {error}") from error
    if not isinstance(foods, list):
        raise BuildError(f"{path}: expected a top-level array")

    catalog: dict[int, dict[str, Any]] = {}
    for food in foods:
        if (
            not isinstance(food, dict)
            or not isinstance(food.get("id"), int)
            or not isinstance(food.get("name"), str)
            or not food["name"].strip()
        ):
            raise BuildError(f"{path}: food has no integer id and non-empty name")
        food_id = food["id"]
        if food_id in catalog:
            raise BuildError(f"{path}: duplicate food id {food_id}")
        categories = food.get("category") or []
        if not isinstance(categories, list) or not all(
            isinstance(value, str) and value for value in categories
        ):
            raise BuildError(f"{path}: food {food_id} has invalid category values")
        catalog[food_id] = {
            "name": food["name"],
            "category": categories[0] if categories else None,
        }

    if set(catalog) != store_ids:
        missing = sorted(store_ids - set(catalog))
        extra = sorted(set(catalog) - store_ids)
        raise BuildError(
            f"{path}: food-catalog/store id mismatch; "
            f"missing={missing[:10]}, extra={extra[:10]}"
        )
    return catalog


def load_suffix_negation_terms(path: Path) -> set[str]:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as error:
        raise BuildError(f"cannot load suffix-negation vocabulary {path}: {error}") from error
    match = re.search(
        r"let suffixNegationTerms:\s*Set<String>\s*=\s*\[([^\]]+)\]",
        source,
    )
    if match is None:
        raise BuildError(f"{path}: suffixNegationTerms declaration is missing")
    terms = set(re.findall(r'"([^"]+)"', match.group(1)))
    if not terms:
        raise BuildError(f"{path}: suffixNegationTerms is empty")
    return terms


def load_food_concept_sources(
    ontology_path: Path,
    overrides_path: Path,
) -> tuple[dict[str, Any], dict[str, Any]]:
    try:
        ontology = json.loads(ontology_path.read_text(encoding="utf-8"))
        overrides = json.loads(overrides_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load food-concept sources: {error}") from error
    validate_food_concept_sources(ontology, overrides)
    return ontology, overrides


def food_concept_ancestors(
    concepts_by_id: dict[str, dict[str, Any]],
) -> dict[str, set[str]]:
    resolved: dict[str, set[str]] = {}
    visiting: list[str] = []

    def visit(concept_id: str) -> set[str]:
        if concept_id in resolved:
            return resolved[concept_id]
        if concept_id in visiting:
            start = visiting.index(concept_id)
            cycle = visiting[start:] + [concept_id]
            raise BuildError("food-concept hierarchy cycle: " + " -> ".join(cycle))
        visiting.append(concept_id)
        ancestors: set[str] = set()
        for parent in concepts_by_id[concept_id]["parents"]:
            if parent not in concepts_by_id:
                raise BuildError(f"{concept_id}: dangling concept parent {parent}")
            ancestors.add(parent)
            ancestors.update(visit(parent))
        visiting.pop()
        resolved[concept_id] = ancestors
        return ancestors

    for concept_id in concepts_by_id:
        visit(concept_id)
    return resolved


def validate_food_concept_sources(
    ontology: dict[str, Any],
    overrides: dict[str, Any],
) -> None:
    if not isinstance(ontology, dict):
        raise BuildError("food-concepts.json must contain an object")
    concepts = ontology.get("concepts")
    aliases = ontology.get("aliases")
    if not isinstance(concepts, list) or len(concepts) != EXPECTED_CONCEPT_COUNT:
        raise BuildError(
            f"food-concept gate failed: expected {EXPECTED_CONCEPT_COUNT} concepts"
        )
    if not isinstance(aliases, list) or len(aliases) != EXPECTED_ALIAS_COUNT:
        raise BuildError(
            f"food-concept alias gate failed: expected {EXPECTED_ALIAS_COUNT} aliases"
        )

    concepts_by_id: dict[str, dict[str, Any]] = {}
    for concept in concepts:
        if not isinstance(concept, dict) or not isinstance(concept.get("id"), str):
            raise BuildError("food concept is missing a string id")
        concept_id = concept["id"]
        if concept_id in concepts_by_id:
            raise BuildError(f"duplicate food concept: {concept_id}")
        parents = concept.get("parents")
        phrases = concept.get("phrases")
        negatives = concept.get("negativePhrases")
        veto_groups = concept.get("vetoTokens", [])
        if not isinstance(parents, list) or not all(
            isinstance(parent, str) for parent in parents
        ):
            raise BuildError(f"{concept_id}: parents must be strings")
        if not isinstance(phrases, list) or not phrases or not all(
            isinstance(phrase, str) and modifier_normalized_tokens(phrase)
            for phrase in phrases
        ):
            raise BuildError(f"{concept_id}: phrases must be non-empty strings")
        if not isinstance(negatives, list) or not all(
            isinstance(phrase, str) and modifier_normalized_tokens(phrase)
            for phrase in negatives
        ):
            raise BuildError(f"{concept_id}: negativePhrases must be strings")
        if (
            not isinstance(veto_groups, list)
            or not all(
                isinstance(group, list)
                and bool(group)
                and all(
                    isinstance(token, str)
                    and len(modifier_normalized_tokens(token)) == 1
                    for token in group
                )
                for group in veto_groups
            )
        ):
            raise BuildError(
                f"{concept_id}: vetoTokens must contain non-empty groups "
                "of individual tokens"
            )
        normalized_veto_groups = [
            tuple(
                modifier_normalized_tokens(token)[0]
                for token in group
            )
            for group in veto_groups
        ]
        if any(len(group) != len(set(group)) for group in normalized_veto_groups):
            raise BuildError(f"{concept_id}: vetoTokens group contains duplicates")
        if len(normalized_veto_groups) != len(set(normalized_veto_groups)):
            raise BuildError(f"{concept_id}: duplicate vetoTokens group")
        positive_keys = {modifier_normalized_tokens(phrase) for phrase in phrases}
        negative_keys = {
            modifier_normalized_tokens(phrase) for phrase in negatives
        }
        conflicts = positive_keys.intersection(negative_keys)
        if conflicts:
            raise BuildError(
                f"{concept_id}: phrase/negative self-conflict {sorted(conflicts)}"
            )
        concepts_by_id[concept_id] = concept
    food_concept_ancestors(concepts_by_id)

    alias_map: dict[str, str] = {}
    for alias in aliases:
        if (
            not isinstance(alias, dict)
            or not isinstance(alias.get("surface"), str)
            or not isinstance(alias.get("canonical"), str)
        ):
            raise BuildError("food-concept alias needs surface and canonical strings")
        surface = " ".join(modifier_normalized_tokens(alias["surface"]))
        canonical = " ".join(modifier_normalized_tokens(alias["canonical"]))
        if not surface or not canonical:
            raise BuildError("food-concept alias normalizes to an empty value")
        if surface in alias_map:
            raise BuildError(f"duplicate normalized alias surface: {surface}")
        alias_map[surface] = canonical

    for surface in alias_map:
        seen: list[str] = []
        current = surface
        while current in alias_map:
            if current in seen:
                start = seen.index(current)
                cycle = seen[start:] + [current]
                raise BuildError("food-concept alias cycle: " + " -> ".join(cycle))
            seen.append(current)
            current = alias_map[current]

    if not isinstance(overrides, dict) or overrides.get("schemaVersion") != 1:
        raise BuildError("concept-overrides.json must use schemaVersion 1")
    entries = overrides.get("overrides")
    if not isinstance(entries, list):
        raise BuildError("concept-overrides.json must contain an overrides array")
    for entry in entries:
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("foodId"), int)
            or not isinstance(entry.get("add"), list)
            or not isinstance(entry.get("remove"), list)
            or not all(isinstance(value, str) for value in entry["add"])
            or not all(isinstance(value, str) for value in entry["remove"])
        ):
            raise BuildError("invalid food-concept override entry")
        unknown = set(entry["add"] + entry["remove"]) - set(concepts_by_id)
        if unknown:
            raise BuildError(f"food-concept override uses unknown concepts {sorted(unknown)}")
        conflicts = set(entry["add"]).intersection(entry["remove"])
        if conflicts:
            raise BuildError(
                f"food-concept override both adds and removes {sorted(conflicts)}"
            )


def _phrase_spans(
    tokens: tuple[str, ...],
    phrase_tokens: tuple[str, ...],
    *,
    plural_tolerance: str = "exact",
    irregular_plurals: dict[str, str] | None = None,
) -> list[tuple[int, int]]:
    if not phrase_tokens or len(phrase_tokens) > len(tokens):
        return []
    width = len(phrase_tokens)
    return [
        (start, start + width)
        for start in range(len(tokens) - width + 1)
        if all(
            _food_token_matches(
                authored,
                observed,
                plural_tolerance=plural_tolerance,
                irregular_plurals=irregular_plurals,
            )
            for authored, observed in zip(
                phrase_tokens,
                tokens[start : start + width],
            )
        )
    ]


def _plural_forms(
    token: str,
    irregular_plurals: dict[str, str] | None = None,
) -> set[str]:
    forms = {token, f"{token}s", f"{token}es"}
    if token.endswith("y") and len(token) > 1:
        forms.add(f"{token[:-1]}ies")
    if irregular_plurals and token in irregular_plurals:
        forms.add(irregular_plurals[token])
    return forms


def _equivalent_token_forms(
    token: str,
    irregular_plurals: dict[str, str] | None = None,
) -> set[str]:
    forms = _plural_forms(token, irregular_plurals)
    inverse = {
        plural: singular
        for singular, plural in (irregular_plurals or {}).items()
    }
    singular: str | None = inverse.get(token)
    if singular is None and token.endswith("ies") and len(token) > 3:
        singular = f"{token[:-3]}y"
    if singular is None and token.endswith("es") and len(token) > 3:
        candidate = token[:-2]
        if candidate.endswith(("s", "x", "z", "ch", "sh", "o")):
            singular = candidate
    if (
        singular is None
        and token.endswith("s")
        and len(token) > 3
        and not token.endswith("ss")
    ):
        singular = token[:-1]
    if singular is not None:
        forms.update(_plural_forms(singular, irregular_plurals))
    return forms


def _food_token_matches(
    authored_token: str,
    observed_token: str,
    *,
    plural_tolerance: str,
    irregular_plurals: dict[str, str] | None = None,
) -> bool:
    if authored_token == observed_token:
        return True
    if plural_tolerance == "exact":
        return False
    if plural_tolerance == "trailing_s":
        return f"{authored_token}s" == observed_token
    if plural_tolerance != "full":
        raise BuildError(f"unsupported plural tolerance {plural_tolerance!r}")
    return observed_token in _equivalent_token_forms(
        authored_token,
        irregular_plurals,
    )


def _tokens_contain_group(
    tokens: tuple[str, ...],
    group: tuple[str, ...],
    *,
    plural_tolerance: str,
    irregular_plurals: dict[str, str] | None = None,
) -> bool:
    return all(
        any(
            _food_token_matches(
                authored,
                observed,
                plural_tolerance=plural_tolerance,
                irregular_plurals=irregular_plurals,
            )
            for observed in tokens
        )
        for authored in group
    )


def _longest_positive_matches(
    tokens: tuple[str, ...],
    phrases: list[tuple[str, tuple[str, ...]]],
    suffix_negation_terms: set[str],
    *,
    plural_tolerance: str = "exact",
    irregular_plurals: dict[str, str] | None = None,
) -> list[str]:
    candidates: list[tuple[int, int, int, str]] = []
    for phrase, phrase_tokens in phrases:
        for start, end in _phrase_spans(
            tokens,
            phrase_tokens,
            plural_tolerance=plural_tolerance,
            irregular_plurals=irregular_plurals,
        ):
            if end < len(tokens) and tokens[end] in suffix_negation_terms:
                continue
            candidates.append((-(end - start), start, end, phrase))

    selected: list[str] = []
    occupied: set[int] = set()
    for _negative_width, start, end, phrase in sorted(candidates):
        positions = set(range(start, end))
        if occupied.intersection(positions):
            continue
        selected.append(phrase)
        occupied.update(positions)
    return selected


def _matching_veto_token_groups(
    tokens: tuple[str, ...],
    groups: list[tuple[str, ...]],
    *,
    plural_tolerance: str = "trailing_s",
    irregular_plurals: dict[str, str] | None = None,
) -> list[str]:
    return [
        " ".join(group)
        for group in groups
        if _tokens_contain_group(
            tokens,
            group,
            plural_tolerance=plural_tolerance,
            irregular_plurals=irregular_plurals,
        )
    ]


def build_food_concepts(
    envelope: dict[str, Any],
    source_food_names: dict[int, str],
    ontology: dict[str, Any],
    overrides: dict[str, Any],
    suffix_negation_terms: set[str],
) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_food_concept_sources(ontology, overrides)
    concepts_by_id = {
        concept["id"]: concept for concept in ontology["concepts"]
    }
    ancestors = food_concept_ancestors(concepts_by_id)

    catalog_names = dict(source_food_names)
    for dravya in envelope["dravyas"]:
        food_id = dravya["foodId"]
        if dravya["foodIsPlaceholder"]:
            if food_id in catalog_names:
                raise BuildError(f"placeholder food id already exists: {food_id}")
            catalog_names[food_id] = dravya["name"]
        elif food_id not in catalog_names:
            raise BuildError(f"dravya primary food id has no source name: {food_id}")
    for recipe in envelope["recipes"]:
        food_id = recipe["foodId"]
        if food_id in catalog_names:
            raise BuildError(f"recipe food id already exists: {food_id}")
        catalog_names[food_id] = recipe["name"]
    if len(catalog_names) != EXPECTED_CATALOG_COUNT:
        raise BuildError(
            f"food-concept catalog gate failed: expected {EXPECTED_CATALOG_COUNT}, "
            f"got {len(catalog_names)}"
        )

    compiled: dict[
        str,
        tuple[
            list[tuple[str, tuple[str, ...]]],
            list[tuple[str, tuple[str, ...]]],
            list[tuple[str, ...]],
        ],
    ] = {}
    for concept_id, concept in concepts_by_id.items():
        positives = [
            (phrase, modifier_normalized_tokens(phrase))
            for phrase in concept["phrases"]
        ]
        negatives = [
            (phrase, modifier_normalized_tokens(phrase))
            for phrase in concept["negativePhrases"]
        ]
        veto_groups = [
            tuple(
                modifier_normalized_tokens(token)[0]
                for token in group
            )
            for group in concept.get("vetoTokens", [])
        ]
        compiled[concept_id] = (positives, negatives, veto_groups)

    membership = {concept_id: set() for concept_id in concepts_by_id}
    direct_membership = {concept_id: set() for concept_id in concepts_by_id}
    ingredient_membership = {concept_id: set() for concept_id in concepts_by_id}
    reasons: dict[str, dict[int, set[str]]] = {
        concept_id: defaultdict(set) for concept_id in concepts_by_id
    }
    negative_vetoes: dict[str, dict[int, list[str]]] = {
        concept_id: {} for concept_id in concepts_by_id
    }

    for food_id, name in sorted(catalog_names.items()):
        tokens = modifier_normalized_tokens(name)
        for concept_id, (positives, negatives, veto_groups) in compiled.items():
            token_vetoes = _matching_veto_token_groups(tokens, veto_groups)
            if token_vetoes:
                negative_vetoes[concept_id][food_id] = [
                    f"tokens:{group}" for group in sorted(token_vetoes)
                ]
                continue
            vetoes = [
                phrase
                for phrase, phrase_tokens in negatives
                if _phrase_spans(tokens, phrase_tokens)
            ]
            if vetoes:
                negative_vetoes[concept_id][food_id] = sorted(vetoes)
                continue
            matches = _longest_positive_matches(
                tokens,
                positives,
                suffix_negation_terms,
            )
            if not matches:
                continue
            membership[concept_id].add(food_id)
            direct_membership[concept_id].add(food_id)
            reasons[concept_id][food_id].update(
                f"name:{phrase}" for phrase in matches
            )

    for child_id, child_members in direct_membership.items():
        for ancestor_id in ancestors[child_id]:
            eligible_members = child_members - set(negative_vetoes[ancestor_id])
            membership[ancestor_id].update(eligible_members)
            for food_id in eligible_members:
                reasons[ancestor_id][food_id].add(f"hierarchy:{child_id}")

    recipe_ids = {recipe["foodId"] for recipe in envelope["recipes"]}
    ingredients_by_recipe: dict[int, list[int]] = {}
    for recipe in envelope["recipes"]:
        ingredient_ids = [ingredient["foodId"] for ingredient in recipe["ingredients"]]
        if not ingredient_ids:
            raise BuildError(f"{recipe['id']}: no ingredient links for concepts")
        ingredients_by_recipe[recipe["foodId"]] = ingredient_ids
    link_count = sum(len(values) for values in ingredients_by_recipe.values())
    if link_count != 10_571 or len(ingredients_by_recipe) != 1_500:
        raise BuildError(
            "IngredientLink coverage insufficient for food-concept propagation: "
            f"{link_count} links / {len(ingredients_by_recipe)} owners"
        )
    nested_links = sum(
        ingredient_id in recipe_ids
        for ingredient_ids in ingredients_by_recipe.values()
        for ingredient_id in ingredient_ids
    )

    depth_used = 0
    for depth in range(1, RECIPE_PROPAGATION_DEPTH_CAP + 1):
        snapshot = {
            concept_id: set(food_ids)
            for concept_id, food_ids in membership.items()
        }
        additions: dict[str, dict[int, list[int]]] = {
            concept_id: {} for concept_id in concepts_by_id
        }
        for owner_id, ingredient_ids in sorted(ingredients_by_recipe.items()):
            for concept_id in concepts_by_id:
                if owner_id in negative_vetoes[concept_id]:
                    continue
                matching_ingredients = sorted(
                    ingredient_id
                    for ingredient_id in ingredient_ids
                    if ingredient_id in snapshot[concept_id]
                )
                if matching_ingredients:
                    additions[concept_id][owner_id] = matching_ingredients

        changed = False
        for concept_id, owners in additions.items():
            for owner_id, ingredient_ids in owners.items():
                reasons[concept_id][owner_id].update(
                    f"ingredient:{ingredient_id}" for ingredient_id in ingredient_ids
                )
                ingredient_membership[concept_id].add(owner_id)
                if owner_id not in membership[concept_id]:
                    membership[concept_id].add(owner_id)
                    changed = True
        depth_used = depth
        if nested_links == 0 or not changed:
            break
    else:
        raise BuildError(
            "recipe concept propagation exceeded depth cap "
            f"{RECIPE_PROPAGATION_DEPTH_CAP}"
        )

    seen_override_food_ids: set[int] = set()
    for entry in sorted(overrides["overrides"], key=lambda value: value["foodId"]):
        food_id = entry["foodId"]
        if food_id not in catalog_names:
            raise BuildError(f"food-concept override has unknown foodId {food_id}")
        if food_id in seen_override_food_ids:
            raise BuildError(f"duplicate food-concept override foodId {food_id}")
        seen_override_food_ids.add(food_id)
        for concept_id in entry["remove"]:
            membership[concept_id].discard(food_id)
            reasons[concept_id].pop(food_id, None)
        for concept_id in entry["add"]:
            membership[concept_id].add(food_id)
            reasons[concept_id][food_id].add("override:add")

    alias_map = {
        " ".join(modifier_normalized_tokens(alias["surface"])): alias["canonical"]
        for alias in ontology["aliases"]
    }
    artifact = {
        "conceptsVersion": ontology["conceptsVersion"],
        "catalogCount": len(catalog_names),
        "conceptCount": len(concepts_by_id),
        "aliasCount": len(alias_map),
        "matching": ontology["matching"],
        "membership": {
            concept_id: sorted(membership[concept_id])
            for concept_id in sorted(concepts_by_id)
        },
        "aliases": {
            surface: alias_map[surface] for surface in sorted(alias_map)
        },
        "propagation": {
            "ingredientLinks": link_count,
            "recipeOwners": len(ingredients_by_recipe),
            "nestedRecipeLinks": nested_links,
            "depthCap": RECIPE_PROPAGATION_DEPTH_CAP,
            "depthUsed": depth_used,
        },
    }
    diagnostics = {
        "catalogNames": catalog_names,
        "directMembership": direct_membership,
        "ingredientMembership": ingredient_membership,
        "membership": membership,
        "reasons": reasons,
        "negativeVetoes": negative_vetoes,
        "ancestors": ancestors,
    }
    return artifact, diagnostics


def load_food_role_source(path: Path) -> dict[str, Any]:
    try:
        source = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load food-role source {path}: {error}") from error
    validate_food_role_source(source)
    return source


def validate_food_role_source(source: dict[str, Any]) -> None:
    if not isinstance(source, dict) or source.get("rolesVersion") != 2:
        raise BuildError("food-roles.json must use rolesVersion 2")
    roles = source.get("roles")
    rules = source.get("rules")
    if not isinstance(roles, list) or len(roles) != EXPECTED_FOOD_ROLE_COUNT:
        raise BuildError(
            f"food-role gate failed: expected {EXPECTED_FOOD_ROLE_COUNT} roles"
        )
    if not isinstance(rules, list) or len(rules) != EXPECTED_FOOD_ROLE_RULE_COUNT:
        raise BuildError(
            f"food-role gate failed: expected {EXPECTED_FOOD_ROLE_RULE_COUNT} rules"
        )

    role_ids: set[str] = set()
    for role in roles:
        if (
            not isinstance(role, dict)
            or not isinstance(role.get("id"), str)
            or not isinstance(role.get("anchor"), bool)
            or not isinstance(role.get("minPerMeal"), int)
            or not isinstance(role.get("maxPerMeal"), int)
            or not isinstance(role.get("portionGrams"), dict)
        ):
            raise BuildError("invalid food-role definition")
        role_id = role["id"]
        if role_id in role_ids:
            raise BuildError(f"duplicate food role {role_id}")
        role_ids.add(role_id)
        portion = role["portionGrams"]
        values = [portion.get(key) for key in ("min", "typical", "max")]
        if not all(isinstance(value, (int, float)) for value in values):
            raise BuildError(f"{role_id}: invalid portion range")
        if not float(values[0]) <= float(values[1]) <= float(values[2]):
            raise BuildError(f"{role_id}: unordered portion range")

    rule_ids: set[str] = set()
    allowed_dynamic_roles = {"<fromCategoryMap>", "<fromDravyaMap>", "<fromMealMap>"}
    for rule in rules:
        if (
            not isinstance(rule, dict)
            or not isinstance(rule.get("id"), str)
            or not isinstance(rule.get("role"), str)
            or not isinstance(rule.get("priority"), int)
        ):
            raise BuildError("invalid food-role rule")
        rule_id = rule["id"]
        if rule_id in rule_ids:
            raise BuildError(f"duplicate food-role rule {rule_id}")
        rule_ids.add(rule_id)
        if rule["role"] not in role_ids | allowed_dynamic_roles:
            raise BuildError(f"{rule_id}: unknown role {rule['role']}")
        for key in ("phrases",):
            values = rule.get(key, [])
            if not isinstance(values, list) or not all(
                isinstance(value, str) and modifier_normalized_tokens(value)
                for value in values
            ):
                raise BuildError(f"{rule_id}: {key} must contain strings")
        for key in ("tokenGroups", "vetoTokens"):
            groups = rule.get(key, [])
            if (
                not isinstance(groups, list)
                or not all(
                    isinstance(group, list)
                    and bool(group)
                    and all(
                        isinstance(token, str)
                        and len(modifier_normalized_tokens(token)) == 1
                        for token in group
                    )
                    for group in groups
                )
            ):
                raise BuildError(f"{rule_id}: {key} must contain token groups")

    rules_by_id = {rule["id"]: rule for rule in rules}
    required = {
        "A-RECIPE-MEAL",
        "A-RECIPE-COMPOSED",
        "U-CATEGORY",
        "D-DRAVYA-CATEGORY",
    }
    if not required.issubset(rules_by_id):
        raise BuildError(f"food-role rules missing {sorted(required - set(rules_by_id))}")
    if rules_by_id["A-RECIPE-MEAL"]["priority"] != 85:
        raise BuildError("A-RECIPE-MEAL must remain priority 85")
    if rules_by_id["A-RECIPE-COMPOSED"]["priority"] != 45:
        raise BuildError("A-RECIPE-COMPOSED must remain priority 45")
    name_priorities = [
        rule["priority"]
        for rule in rules
        if rule.get("phrases") or rule.get("tokenGroups")
    ]
    if not name_priorities or min(name_priorities) <= 45:
        raise BuildError("A-RECIPE-COMPOSED must remain below every name rule")

    plural = source.get("matching", {}).get("pluralTolerance", {})
    irregular = plural.get("irregularPlurals")
    if not isinstance(irregular, dict) or not all(
        isinstance(singular, str)
        and isinstance(plural_value, str)
        and len(modifier_normalized_tokens(singular)) == 1
        and len(modifier_normalized_tokens(plural_value)) == 1
        for singular, plural_value in irregular.items()
    ):
        raise BuildError("food-role irregularPlurals must map individual tokens")


def _singularized_food_token(
    token: str,
    irregular_plurals: dict[str, str],
) -> str:
    inverse = {plural: singular for singular, plural in irregular_plurals.items()}
    if token in inverse:
        return inverse[token]
    if token.endswith("ies") and len(token) > 3:
        return f"{token[:-3]}y"
    if token.endswith("es") and len(token) > 3:
        base = token[:-2]
        if base.endswith(("s", "x", "z", "ch", "sh", "o")):
            return base
    if token.endswith("s") and len(token) > 3 and not token.endswith("ss"):
        return token[:-1]
    return token


def _food_role_headword(
    name: str,
    *,
    matched_label: str | None,
    prefix_tokens: set[str],
    modifier_tokens: set[str],
    irregular_plurals: dict[str, str],
) -> str:
    tokens = list(modifier_normalized_tokens(name))
    dropped_prefix: str | None = None
    first_segment = name.split(",", 1)[0]
    first_tokens = modifier_normalized_tokens(first_segment)
    if (
        len(first_tokens) == 1
        and first_tokens[0] in prefix_tokens
        and tokens
        and tokens[0] == first_tokens[0]
    ):
        dropped_prefix = tokens.pop(0)

    surviving = [token for token in tokens if token not in modifier_tokens]
    matched_tokens = [
        token
        for token in modifier_normalized_tokens(matched_label or "")
        if token not in modifier_tokens
    ]
    matched_set = set(matched_tokens)
    if surviving and matched_set and surviving[0] not in matched_set:
        matched_survivor = next(
            (token for token in surviving if token in matched_set),
            None,
        )
        if matched_survivor is not None:
            return _singularized_food_token(
                matched_survivor,
                irregular_plurals,
            )
    if surviving:
        return _singularized_food_token(surviving[0], irregular_plurals)
    return _singularized_food_token(
        dropped_prefix or (tokens[0] if tokens else "unknown"),
        irregular_plurals,
    )


def _food_requires_cooking(
    tokens: tuple[str, ...],
    source: dict[str, Any],
    irregular_plurals: dict[str, str],
) -> bool:
    flag = source["flags"]["requiresCooking"]
    veto_tokens = flag["veto"]
    if any(
        any(
            _food_token_matches(
                authored,
                observed,
                plural_tolerance="full",
                irregular_plurals=irregular_plurals,
            )
            for observed in tokens
        )
        for authored in veto_tokens
    ):
        return False

    groups = [
        tuple(modifier_normalized_tokens(token)[0] for token in group)
        for group in flag["positive"]["tokenGroups"]
    ]
    if any(
        _tokens_contain_group(
            tokens,
            group,
            plural_tolerance="full",
            irregular_plurals=irregular_plurals,
        )
        for group in groups
    ):
        return True

    headwords = tuple(flag["dryStapleHeadwords"])
    state_description = flag["positive"]["orAllOf"]["state"]
    states = tuple(re.findall(r"'([^']+)'", state_description))
    return (
        any(
            any(
                _food_token_matches(
                    authored,
                    observed,
                    plural_tolerance="full",
                    irregular_plurals=irregular_plurals,
                )
                for observed in tokens
            )
            for authored in headwords
        )
        and any(state in tokens for state in states)
    )


def _resolve_food_role(
    record: dict[str, Any],
    compiled_rules: list[dict[str, Any]],
    suffix_negation_terms: set[str],
    irregular_plurals: dict[str, str],
) -> dict[str, Any]:
    tokens = modifier_normalized_tokens(record["name"])
    candidates: list[tuple[int, int, int, str, str, str | None]] = []

    for compiled in compiled_rules:
        rule = compiled["rule"]
        token_vetoes = _matching_veto_token_groups(
            tokens,
            compiled["vetoGroups"],
            plural_tolerance="full",
            irregular_plurals=irregular_plurals,
        )
        veto_phrase_candidates = {
            phrase: (phrase, phrase_tokens)
            for token in tokens
            for phrase, phrase_tokens in compiled["vetoPhraseIndex"].get(
                token,
                [],
            )
        }.values()
        phrase_vetoes = [
            phrase
            for phrase, phrase_tokens in veto_phrase_candidates
            if _phrase_spans(
                tokens,
                phrase_tokens,
                plural_tolerance="full",
                irregular_plurals=irregular_plurals,
            )
        ]
        if token_vetoes or phrase_vetoes:
            continue

        phrase_candidates = list(
            {
                phrase: (phrase, phrase_tokens)
                for token in tokens
                for phrase, phrase_tokens in compiled["phraseIndex"].get(
                    token,
                    [],
                )
            }.values()
        )
        matches = _longest_positive_matches(
            tokens,
            phrase_candidates,
            suffix_negation_terms,
            plural_tolerance="full",
            irregular_plurals=irregular_plurals,
        )
        group_matches = [
            " ".join(group)
            for group in compiled["tokenGroups"]
            if _tokens_contain_group(
                tokens,
                group,
                plural_tolerance="full",
                irregular_plurals=irregular_plurals,
            )
        ]
        matched_labels = matches + group_matches
        resolved_role: str | None = None
        signal_label: str | None = None

        signal = rule.get("signal")
        if signal == "FoodItem.category[0]":
            category = record.get("category")
            resolved_role = rule["categoryMap"].get(category)
            signal_label = f"category:{category}" if resolved_role else None
        elif signal == "dravya.category":
            category = record.get("dravyaCategory")
            resolved_role = rule["dravyaMap"].get(category)
            signal_label = f"dravya:{category}" if resolved_role else None
        elif signal == "recipe.meal":
            meal = record.get("recipeMeal")
            resolved_role = rule["mealMap"].get(meal)
            signal_label = f"meal:{meal}" if resolved_role else None
        elif signal == "recipe.isAuthored":
            meal = record.get("recipeMeal")
            if (
                record.get("isAuthoredRecipe") is True
                and int(record.get("ingredientCount", 0)) >= 2
                and int(record.get("stepCount", 0)) >= 1
            ):
                resolved_role = rule["mealMap"].get(meal)
                signal_label = f"composed:{meal}" if resolved_role else None
        elif signal is not None:
            raise BuildError(f"{rule['id']}: unsupported food-role signal {signal}")

        if rule["role"].startswith("<"):
            if resolved_role is None:
                continue
        elif matched_labels:
            resolved_role = rule["role"]
        else:
            continue

        longest_label = max(
            matched_labels,
            key=lambda value: (
                len(modifier_normalized_tokens(value)),
                -matched_labels.index(value),
            ),
            default=signal_label,
        )
        match_length = len(modifier_normalized_tokens(longest_label or ""))
        candidates.append(
            (
                -rule["priority"],
                -match_length,
                compiled["index"],
                resolved_role,
                rule["id"],
                longest_label or signal_label,
            )
        )

    if not candidates:
        return {
            "role": "other",
            "ruleId": "default",
            "matched": None,
        }
    _priority, _length, _index, role, rule_id, matched = min(candidates)
    return {
        "role": role,
        "ruleId": rule_id,
        "matched": matched,
    }


def _compile_food_role_rules(role_source: dict[str, Any]) -> list[dict[str, Any]]:
    irregular_plurals = role_source["matching"]["pluralTolerance"][
        "irregularPlurals"
    ]
    compiled: list[dict[str, Any]] = []
    for index, rule in enumerate(role_source["rules"]):
        phrases = [
            (phrase, modifier_normalized_tokens(phrase))
            for phrase in rule.get("phrases", [])
        ]
        veto_phrases = [
            (phrase, modifier_normalized_tokens(phrase))
            for phrase in rule.get("vetoPhrases", [])
        ]

        def indexed(
            values: list[tuple[str, tuple[str, ...]]],
        ) -> dict[str, list[tuple[str, tuple[str, ...]]]]:
            result: dict[str, list[tuple[str, tuple[str, ...]]]] = defaultdict(
                list
            )
            for value in values:
                for token in _equivalent_token_forms(
                    value[1][0],
                    irregular_plurals,
                ):
                    result[token].append(value)
            return dict(result)

        compiled.append({
            "index": index,
            "rule": rule,
            "phraseIndex": indexed(phrases),
            "tokenGroups": [
                tuple(
                    modifier_normalized_tokens(token)[0]
                    for token in group
                )
                for group in rule.get("tokenGroups", [])
            ],
            "vetoGroups": [
                tuple(
                    modifier_normalized_tokens(token)[0]
                    for token in group
                )
                for group in rule.get("vetoTokens", [])
            ],
            "vetoPhraseIndex": indexed(veto_phrases),
        })
    return compiled


def resolve_food_role_fixture(
    name: str,
    role_source: dict[str, Any],
    modifiers: list[dict[str, Any]],
    suffix_negation_terms: set[str],
    *,
    category: str | None = None,
    dravya_category: str | None = None,
    recipe_meal: str | None = None,
    ingredient_count: int = 0,
    step_count: int = 0,
) -> dict[str, Any]:
    irregular_plurals = role_source["matching"]["pluralTolerance"][
        "irregularPlurals"
    ]
    record = {
        "name": name,
        "category": category,
        "dravyaCategory": dravya_category,
        "recipeMeal": recipe_meal,
        "isAuthoredRecipe": recipe_meal is not None,
        "ingredientCount": ingredient_count,
        "stepCount": step_count,
    }
    resolved = _resolve_food_role(
        record,
        _compile_food_role_rules(role_source),
        suffix_negation_terms,
        irregular_plurals,
    )
    modifier_tokens = {
        token
        for modifier in modifiers
        for phrase in modifier["phrases"]
        for token in modifier_normalized_tokens(phrase)
    }
    return {
        **resolved,
        "requiresCooking": _food_requires_cooking(
            modifier_normalized_tokens(name),
            role_source,
            irregular_plurals,
        ),
        "headword": _food_role_headword(
            name,
            matched_label=resolved["matched"],
            prefix_tokens=set(
                role_source["flags"]["isNearDuplicateOf"][
                    "categoryPrefixTokens"
                ]
            ),
            modifier_tokens=modifier_tokens,
            irregular_plurals=irregular_plurals,
        ),
    }


def build_food_roles(
    envelope: dict[str, Any],
    source_food_catalog: dict[int, dict[str, Any]],
    role_source: dict[str, Any],
    modifiers: list[dict[str, Any]],
    suffix_negation_terms: set[str],
) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_food_role_source(role_source)
    records = {
        food_id: {
            "foodId": food_id,
            "name": source["name"],
            "category": source["category"],
        }
        for food_id, source in source_food_catalog.items()
    }
    dravya_categories: set[str] = set()
    for dravya in envelope["dravyas"]:
        food_id = dravya["foodId"]
        if food_id not in records:
            if not dravya["foodIsPlaceholder"]:
                raise BuildError(f"{dravya['id']}: role food id is absent")
            records[food_id] = {
                "foodId": food_id,
                "name": dravya["name"],
                "category": None,
            }
        records[food_id]["dravyaCategory"] = dravya["category"]
        dravya_categories.add(dravya["category"])

    recipe_meals: set[str] = set()
    for recipe in envelope["recipes"]:
        food_id = recipe["foodId"]
        if food_id in records:
            raise BuildError(f"{recipe['id']}: duplicate role food id {food_id}")
        records[food_id] = {
            "foodId": food_id,
            "name": recipe["name"],
            "category": None,
            "isAuthoredRecipe": True,
            "recipeMeal": recipe["meal"],
            "ingredientCount": len(recipe["ingredients"]),
            "stepCount": len(recipe["steps"]),
        }
        recipe_meals.add(recipe["meal"])

    if len(records) != EXPECTED_CATALOG_COUNT:
        raise BuildError(
            f"food-role catalog gate failed: expected {EXPECTED_CATALOG_COUNT}, "
            f"got {len(records)}"
        )

    rules_by_id = {rule["id"]: rule for rule in role_source["rules"]}
    actual_categories = {
        record["category"]
        for record in records.values()
        if record.get("category") is not None
    }
    category_map = set(rules_by_id["U-CATEGORY"]["categoryMap"])
    if actual_categories != category_map:
        raise BuildError(
            "food-role category signal mismatch; "
            f"missing={sorted(actual_categories - category_map)}, "
            f"extra={sorted(category_map - actual_categories)}"
        )
    dravya_map = set(rules_by_id["D-DRAVYA-CATEGORY"]["dravyaMap"])
    if dravya_categories != dravya_map:
        raise BuildError(
            "food-role dravya signal mismatch; "
            f"missing={sorted(dravya_categories - dravya_map)}, "
            f"extra={sorted(dravya_map - dravya_categories)}"
        )
    if recipe_meals != {"breakfast", "lunch", "dinner", "snack", "drink", "dessert"}:
        raise BuildError(f"food-role recipe meal signal mismatch: {sorted(recipe_meals)}")

    irregular_plurals = role_source["matching"]["pluralTolerance"][
        "irregularPlurals"
    ]
    compiled_rules = _compile_food_role_rules(role_source)

    modifier_tokens = {
        token
        for modifier in modifiers
        for phrase in modifier["phrases"]
        for token in modifier_normalized_tokens(phrase)
    }
    duplicate_source = role_source["flags"]["isNearDuplicateOf"]
    prefix_tokens = set(duplicate_source["categoryPrefixTokens"])
    items: list[dict[str, Any]] = []
    reasons: dict[int, dict[str, Any]] = {}
    membership: dict[str, set[int]] = {
        role["id"]: set() for role in role_source["roles"]
    }
    for food_id, record in sorted(records.items()):
        resolved = _resolve_food_role(
            record,
            compiled_rules,
            suffix_negation_terms,
            irregular_plurals,
        )
        tokens = modifier_normalized_tokens(record["name"])
        requires_cooking = _food_requires_cooking(
            tokens,
            role_source,
            irregular_plurals,
        )
        headword = _food_role_headword(
            record["name"],
            matched_label=resolved["matched"],
            prefix_tokens=prefix_tokens,
            modifier_tokens=modifier_tokens,
            irregular_plurals=irregular_plurals,
        )
        item = {
            "foodId": food_id,
            "role": resolved["role"],
            "ruleId": resolved["ruleId"],
            "requiresCooking": requires_cooking,
            "headword": headword,
        }
        items.append(item)
        membership[resolved["role"]].add(food_id)
        reasons[food_id] = {
            **resolved,
            "name": record["name"],
            "category": record.get("category"),
            "dravyaCategory": record.get("dravyaCategory"),
            "recipeMeal": record.get("recipeMeal"),
        }

    definitions = []
    for role in role_source["roles"]:
        definitions.append(
            {
                "id": role["id"],
                "anchor": role["anchor"],
                "minPerMeal": role["minPerMeal"],
                "maxPerMeal": role["maxPerMeal"],
                "portionGrams": role["portionGrams"],
                "eligibleAsComponent": role.get("eligibleAsComponent", True),
            }
        )
    artifact = {
        "rolesVersion": role_source["rolesVersion"],
        "catalogCount": len(items),
        "roleCount": len(definitions),
        "ruleCount": len(role_source["rules"]),
        "definitions": definitions,
        "items": items,
    }
    diagnostics = {
        "records": records,
        "reasons": reasons,
        "membership": membership,
        "categoryValues": actual_categories,
        "dravyaCategoryValues": dravya_categories,
        "recipeMealValues": recipe_meals,
    }
    return artifact, diagnostics


def preferred_nutrition_bindings(
    bindings_by_dravya: dict[str, list[tuple[int, str, int]]],
) -> dict[str, int]:
    preferred: dict[str, int] = {}
    for dravya_id, bindings in bindings_by_dravya.items():
        ordered = sorted(
            bindings,
            key=lambda binding: (TIER_RANK[binding[1]], binding[2]),
        )
        if ordered:
            preferred[dravya_id] = ordered[0][0]
    return preferred


def rounded(value: float) -> float:
    return round(value, 12)


def reviewed_allergens(dravya: dict[str, Any]) -> set[str]:
    allergens = set(CATEGORY_ALLERGEN_RULES.get(dravya["category"], set()))
    dravya_id = dravya["id"]
    for allergen, dravya_ids in ALLERGEN_DRAVYA_RULES.items():
        if dravya_id in dravya_ids:
            allergens.add(allergen)
    return allergens


def composition_diets_for_dravya(
    dravya: dict[str, Any],
    allergens: set[str],
) -> set[str]:
    dravya_id = dravya["id"]
    is_animal = dravya["category"] == "animal"
    is_egg = dravya_id in ALLERGEN_DRAVYA_RULES["Eggs"]
    is_fish_or_shellfish = (
        dravya_id in ALLERGEN_DRAVYA_RULES["Fish"]
        or dravya_id in ALLERGEN_DRAVYA_RULES["Crustaceans"]
    )
    is_terrestrial_animal = is_animal and not is_egg and not is_fish_or_shellfish
    contains_honey = dravya_id in HONEY_DRAVYA_IDS

    diets: set[str] = set()
    if not is_animal and "Milk" not in allergens and not contains_honey:
        diets.add("Vegan")
    if not is_animal or is_egg:
        diets.add("Vegetarian")
    if not is_terrestrial_animal:
        diets.add("Pescatarian")
    if "Milk" not in allergens:
        diets.update({"Dairy-Free", "Lactose-Free"})
    if "Eggs" not in allergens:
        diets.add("Egg-Free")
    if not any(
        allergen == "Peanuts"
        or allergen == "Nuts"
        or allergen.startswith("Nuts (")
        for allergen in allergens
    ):
        diets.add("Nut-Free")
    if "Soybeans" not in allergens:
        diets.add("Soy-Free")
    if not any(allergen.startswith("Cereals containing gluten") for allergen in allergens):
        diets.add("Gluten-Free")
    return diets


def derive_dravya_safety(
    dravya: dict[str, Any],
    food_id: int,
    source_safety_by_id: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    source = source_safety_by_id.get(
        food_id,
        {"allergens": [], "diets": [], "minAgeMonths": 0},
    )
    reviewed = reviewed_allergens(dravya)
    allergens = set(source["allergens"]).union(reviewed)
    controlled_diets = composition_diets_for_dravya(dravya, allergens)
    preserved_source_diets = set(source["diets"]) - COMPOSITION_DIETS
    min_age = int(source["minAgeMonths"])
    enforced_min_age = 0
    age_provenance = AGE_PROVENANCE_LEGACY_IMPORT
    if dravya["id"] in HONEY_DRAVYA_IDS:
        min_age = max(min_age, 12)
        enforced_min_age = 12
        age_provenance = AGE_PROVENANCE_AUTHORED

    rules = [f"category:{dravya['category']}"]
    rules.extend(f"reviewed-allergen:{allergen}" for allergen in sorted(reviewed))
    if food_id in source_safety_by_id:
        rules.append(f"existing-usda:{food_id}")
    if dravya["id"] in HONEY_DRAVYA_IDS:
        rules.append("honey-min-age:12")

    return {
        "allergens": sorted(allergens),
        "diets": sorted(preserved_source_diets.union(controlled_diets)),
        "minAgeMonths": min_age,
        "enforcedMinAgeMonths": enforced_min_age,
        "ageProvenance": age_provenance,
        "ageContributors": [
            {
                "ingredientId": dravya["id"],
                "minAgeMonths": min_age,
                "enforcedMinAgeMonths": enforced_min_age,
                "ageProvenance": age_provenance,
            }
        ],
        "provenance": SAFETY_PROVENANCE,
        "reviewRequired": SAFETY_REVIEW_REQUIRED,
        "rules": sorted(rules),
        "reviewFlags": [],
    }


def normalized_direct_food_safety(source: dict[str, Any]) -> dict[str, Any]:
    allergens = set(source["allergens"])
    diets = set(source["diets"])
    if "Milk" not in allergens:
        diets.update({"Dairy-Free", "Lactose-Free"})
    if "Eggs" not in allergens:
        diets.add("Egg-Free")
    if not any(
        allergen == "Peanuts"
        or allergen == "Nuts"
        or allergen.startswith("Nuts (")
        for allergen in allergens
    ):
        diets.add("Nut-Free")
    if "Soybeans" not in allergens:
        diets.add("Soy-Free")
    if not any(allergen.startswith("Cereals containing gluten") for allergen in allergens):
        diets.add("Gluten-Free")
    if "Vegan" in diets:
        diets.update({"Vegetarian", "Pescatarian"})
    elif "Vegetarian" in diets:
        diets.add("Pescatarian")
    return {
        "allergens": sorted(allergens),
        "diets": sorted(diets),
        "minAgeMonths": int(source["minAgeMonths"]),
        "enforcedMinAgeMonths": 0,
        "ageProvenance": AGE_PROVENANCE_LEGACY_IMPORT,
    }


def derive_recipe_safety(
    recipe: dict[str, Any],
    dravya_safety: dict[str, dict[str, Any]],
    source_safety_by_id: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    ingredient_safety: list[dict[str, Any]] = []
    age_contributors: list[dict[str, Any]] = []
    contains_honey = False
    for ingredient in recipe.get("ingredients", []):
        if "dravyaId" in ingredient:
            dravya_id = ingredient["dravyaId"]
            safety = dravya_safety.get(dravya_id)
            if safety is None:
                raise BuildError(
                    f"{recipe['id']}: no safety metadata for ingredient {dravya_id}"
                )
            contains_honey = contains_honey or dravya_id in HONEY_DRAVYA_IDS
            ingredient_id = dravya_id
        else:
            fdc_id = ingredient.get("fdcId")
            source_safety = source_safety_by_id.get(fdc_id)
            if source_safety is None:
                raise BuildError(
                    f"{recipe['id']}: no USDA safety metadata for ingredient {fdc_id}"
                )
            safety = normalized_direct_food_safety(source_safety)
            ingredient_id = f"fdc:{fdc_id}"
        ingredient_safety.append(safety)
        age_contributors.append(
            {
                "ingredientId": ingredient_id,
                "grams": ingredient["grams"],
                "minAgeMonths": int(safety["minAgeMonths"]),
                "enforcedMinAgeMonths": int(safety["enforcedMinAgeMonths"]),
                "ageProvenance": safety["ageProvenance"],
            }
        )

    if not ingredient_safety:
        raise BuildError(f"{recipe['id']}: cannot derive safety from no ingredients")

    allergens: set[str] = set()
    for safety in ingredient_safety:
        allergens.update(safety["allergens"])

    diets = set(COMPOSITION_DIETS)
    for safety in ingredient_safety:
        diets.intersection_update(set(safety["diets"]))

    min_age = max(int(safety["minAgeMonths"]) for safety in ingredient_safety)
    enforced_min_age = max(
        int(safety["enforcedMinAgeMonths"]) for safety in ingredient_safety
    )
    if contains_honey:
        min_age = max(min_age, 12)
        enforced_min_age = max(enforced_min_age, 12)

    rules = [
        "ingredient-union:allergens",
        "ingredient-intersection:diets",
        "ingredient-maximum:minAgeMonths",
    ]
    if contains_honey:
        rules.append("honey-min-age:12")
    return {
        "allergens": sorted(allergens),
        "diets": sorted(diets),
        "minAgeMonths": min_age,
        "enforcedMinAgeMonths": enforced_min_age,
        "ageProvenance": (
            AGE_PROVENANCE_AUTHORED
            if enforced_min_age > 0
            else AGE_PROVENANCE_LEGACY_IMPORT
        ),
        "ageContributors": age_contributors,
        "provenance": SAFETY_PROVENANCE,
        "reviewRequired": SAFETY_REVIEW_REQUIRED,
        "rules": sorted(rules),
        "reviewFlags": [],
    }


def validate_safety_rule_ids(dravyas: list[dict[str, Any]]) -> None:
    dravya_ids = {dravya["id"] for dravya in dravyas}
    configured_ids = set(HONEY_DRAVYA_IDS)
    for allergen, ids in ALLERGEN_DRAVYA_RULES.items():
        if allergen not in ALLERGEN_VOCABULARY:
            raise BuildError(f"unsupported reviewed allergen rule: {allergen}")
        configured_ids.update(ids)
    unknown_ids = configured_ids - dravya_ids
    if unknown_ids:
        raise BuildError(f"safety rules reference unknown dravyas: {sorted(unknown_ids)}")


def derive_recipe_nutrition(
    recipe: dict[str, Any],
    nutrition_by_id: dict[int, dict[str, float]],
    preferred_bindings: dict[str, int],
) -> tuple[dict[str, Any], list[int | None]]:
    servings = recipe.get("servings")
    if not isinstance(servings, (int, float)) or servings <= 0:
        raise BuildError(f"{recipe['id']}: servings must be greater than zero")

    totals: dict[str, float] = defaultdict(float)
    observed: set[str] = set()
    missing_slugs: list[str] = []
    nutrition_source_ids: list[int | None] = []
    total_weight = 0.0

    for ingredient in recipe.get("ingredients", []):
        grams = ingredient.get("grams")
        if not isinstance(grams, (int, float)) or grams < 0:
            raise BuildError(f"{recipe['id']}: invalid ingredient grams {grams!r}")
        total_weight += float(grams)

        nutrition_id: int | None
        missing_slug: str
        if "dravyaId" in ingredient:
            missing_slug = str(ingredient["dravyaId"])
            nutrition_id = preferred_bindings.get(missing_slug)
        else:
            candidate = ingredient.get("fdcId")
            nutrition_id = candidate if isinstance(candidate, int) else None
            missing_slug = f"fdc.{candidate}" if candidate is not None else ingredient["name"]

        panel = nutrition_by_id.get(nutrition_id) if nutrition_id is not None else None
        if panel is None:
            missing_slugs.append(missing_slug)
            nutrition_source_ids.append(None)
            continue

        nutrition_source_ids.append(nutrition_id)
        factor = float(grams) / 100.0
        for nutrient, value in panel.items():
            totals[nutrient] += factor * value
            observed.add(nutrient)

    if total_weight <= 0:
        raise BuildError(f"{recipe['id']}: total ingredient weight must be greater than zero")

    if not totals:
        status = "none"
    elif missing_slugs:
        status = "estimated"
    else:
        status = "full"

    per_serving = {
        nutrient: rounded(totals[nutrient] / float(servings))
        for nutrient in NUTRIENT_CATALOG
        if nutrient in observed
    }
    per_100g = {
        nutrient: rounded(totals[nutrient] * 100.0 / total_weight)
        for nutrient in NUTRIENT_CATALOG
        if nutrient in observed
    }
    return (
        {
            "status": status,
            "missingIngredients": sorted(set(missing_slugs)),
            "totalWeightG": rounded(total_weight),
            "perServing": per_serving,
            "per100g": per_100g,
            "units": {
                nutrient: unit
                for nutrient, (_section, unit) in NUTRIENT_CATALOG.items()
            },
        },
        nutrition_source_ids,
    )


def load_crosswalk_links(
    path: Path,
    store_ids: set[int],
    dravya_ids: set[str],
    v1_fdc_ids: set[int],
) -> list[dict[str, Any]]:
    links: list[dict[str, Any]] = []
    seen: set[int] = set()
    try:
        with path.open(encoding="utf-8", newline="") as source:
            rows = csv.DictReader(source)
            expected_fields = [
                "fdcId", "name", "category", "dravyaId", "rule", "key",
                "contested", "losers",
            ]
            if rows.fieldnames != expected_fields:
                raise BuildError(f"{path}: unexpected crosswalk header {rows.fieldnames}")
            for row in rows:
                try:
                    fdc_id = int(row["fdcId"])
                except (TypeError, ValueError) as error:
                    raise BuildError(f"{path}: invalid fdcId {row.get('fdcId')!r}") from error
                dravya_id = row["dravyaId"]
                if fdc_id not in store_ids:
                    raise BuildError(f"crosswalk fdcId {fdc_id} is absent from the store")
                if fdc_id in v1_fdc_ids:
                    raise BuildError(f"crosswalk fdcId {fdc_id} collides with a v1 link")
                if fdc_id in seen:
                    raise BuildError(f"duplicate crosswalk fdcId: {fdc_id}")
                if dravya_id not in dravya_ids:
                    raise BuildError(f"crosswalk fdcId {fdc_id}: unknown dravyaId {dravya_id}")
                seen.add(fdc_id)
                links.append({"fdcId": fdc_id, "dravyaId": dravya_id, "tier": "derived"})
    except OSError as error:
        raise BuildError(f"cannot read {path}: {error}") from error
    if len(links) != EXPECTED_COUNTS["derivedLinks"]:
        raise BuildError(
            f"derived-link gate failed: expected {EXPECTED_COUNTS['derivedLinks']}, got {len(links)}"
        )
    if [link["fdcId"] for link in links] != sorted(link["fdcId"] for link in links):
        raise BuildError("crosswalk rows are not sorted by fdcId")
    return links


def load_rules_bundle(data_root: Path) -> dict[str, Any]:
    category_path = data_root / "rules" / "category-rules.json"
    modifier_path = data_root / "rules" / "modifiers.json"
    try:
        category_source = json.loads(category_path.read_text(encoding="utf-8"))
        modifier_source = json.loads(modifier_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot load Ayurveda rules: {error}") from error
    categories = category_source.get("categories")
    modifiers = modifier_source.get("modifiers")
    if not isinstance(categories, list) or len(categories) != EXPECTED_COUNTS["categoryRules"]:
        raise BuildError(
            f"category-rule gate failed: expected {EXPECTED_COUNTS['categoryRules']}"
        )
    if not isinstance(modifiers, list) or len(modifiers) != EXPECTED_COUNTS["modifiers"]:
        raise BuildError(f"modifier gate failed: expected {EXPECTED_COUNTS['modifiers']}")
    return {
        "rulesVersion": category_source.get("rulesVersion"),
        "categories": categories,
        "default": category_source.get("default"),
        "modifiers": modifiers,
    }


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
    dravyas: list[dict[str, Any]],
    recipes: list[dict[str, Any]],
    store_ids: set[int],
    derived_links: list[dict[str, Any]],
    nutrition_by_id: dict[int, dict[str, float]],
    source_safety_by_id: dict[int, dict[str, Any]],
    preferred_bindings: dict[str, int],
) -> tuple[dict[str, Any], list[tuple[int, str, str, list[str]]], list[str]]:
    validate_safety_rule_ids(dravyas)
    assert_reserved_band_free(store_ids)
    assignments, links, contested, placeholder_ids = resolve_primary_foods(dravyas, store_ids)
    if len(links) != V1_LINK_COUNT:
        raise BuildError(f"v1-link gate failed: expected {V1_LINK_COUNT}, got {len(links)}")
    v1_fdc_ids = {link["fdcId"] for link in links}
    derived_fdc_ids = {link["fdcId"] for link in derived_links}
    if v1_fdc_ids & derived_fdc_ids:
        raise BuildError("derived links overlap v1 links")
    links.extend(derived_links)

    output_dravyas: list[dict[str, Any]] = []
    dravya_safety: dict[str, dict[str, Any]] = {}
    for dravya in sorted(dravyas, key=lambda item: item["id"]):
        output = dict(dravya)
        output["foodId"], output["foodIsPlaceholder"] = assignments[dravya["id"]]
        output["engineExcluded"] = dravya["id"] in ENGINE_EXCLUDED_IDS
        output["safety"] = derive_dravya_safety(
            dravya,
            output["foodId"],
            source_safety_by_id,
        )
        dravya_safety[dravya["id"]] = output["safety"]
        output_dravyas.append(output)

    output_recipes: list[dict[str, Any]] = []
    unresolved: list[str] = []
    for ordinal, recipe in enumerate(sorted(recipes, key=lambda item: item["id"]), start=1):
        output = dict(recipe)
        output["foodId"] = RECIPE_BASE + ordinal
        nutrition, nutrition_source_ids = derive_recipe_nutrition(
            recipe, nutrition_by_id, preferred_bindings
        )
        resolved_ingredients: list[dict[str, Any]] = []
        for ingredient, nutrition_source_id in zip(
            recipe.get("ingredients", []), nutrition_source_ids, strict=True
        ):
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
            resolved = {
                "foodId": food_id,
                "grams": ingredient["grams"],
                "name": ingredient["name"],
            }
            if nutrition_source_id is not None:
                resolved["nutritionFdcId"] = nutrition_source_id
            resolved_ingredients.append(resolved)
        output["ingredients"] = resolved_ingredients
        output["nutrition"] = nutrition
        output["safety"] = derive_recipe_safety(
            recipe,
            dravya_safety,
            source_safety_by_id,
        )
        output_recipes.append(output)

    if unresolved:
        raise BuildError("unresolved recipe ingredients:\n" + "\n".join(unresolved))

    primary_count = sum(not placeholder for _food_id, placeholder in assignments.values())
    excluded_count = sum(bool(item["engineExcluded"]) for item in output_dravyas)
    actual_counts = {
        "dravyas": len(output_dravyas),
        "recipes": len(output_recipes),
        "links": len(links),
        "derivedLinks": len(derived_links),
        "placeholders": len(placeholder_ids),
        "primaries": primary_count,
        "categoryRules": EXPECTED_COUNTS["categoryRules"],
        "modifiers": EXPECTED_COUNTS["modifiers"],
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
            "derivedLinks": actual_counts["derivedLinks"],
            "placeholders": actual_counts["placeholders"],
            "categoryRules": actual_counts["categoryRules"],
            "modifiers": actual_counts["modifiers"],
            "nutrition": {
                status: sum(
                    recipe["nutrition"]["status"] == status
                    for recipe in output_recipes
                )
                for status in ("full", "estimated", "none")
            },
            "safety": {
                "profiles": len(output_dravyas) + len(output_recipes),
                "allergenTaggedDravyas": sum(
                    bool(dravya["safety"]["allergens"])
                    for dravya in output_dravyas
                ),
                "allergenTaggedRecipes": sum(
                    bool(recipe["safety"]["allergens"])
                    for recipe in output_recipes
                ),
                "honeyMinAgeDravyas": sum(
                    dravya["id"] in HONEY_DRAVYA_IDS
                    and dravya["safety"]["enforcedMinAgeMonths"] >= 12
                    for dravya in output_dravyas
                ),
                "honeyMinAgeRecipes": sum(
                    "honey-min-age:12" in recipe["safety"]["rules"]
                    and recipe["safety"]["enforcedMinAgeMonths"] >= 12
                    for recipe in output_recipes
                ),
                "authoredAgeDravyas": sum(
                    dravya["safety"]["ageProvenance"]
                    == AGE_PROVENANCE_AUTHORED
                    for dravya in output_dravyas
                ),
                "legacyImportAgeDravyas": sum(
                    dravya["safety"]["ageProvenance"]
                    == AGE_PROVENANCE_LEGACY_IMPORT
                    for dravya in output_dravyas
                ),
                "authoredAgeRecipes": sum(
                    recipe["safety"]["ageProvenance"]
                    == AGE_PROVENANCE_AUTHORED
                    for recipe in output_recipes
                ),
                "legacyImportAgeRecipes": sum(
                    recipe["safety"]["ageProvenance"]
                    == AGE_PROVENANCE_LEGACY_IMPORT
                    for recipe in output_recipes
                ),
                "ageContributors": sum(
                    len(recipe["safety"]["ageContributors"])
                    for recipe in output_recipes
                ),
            },
        },
        "dravyas": output_dravyas,
        "recipes": output_recipes,
        "links": links,
    }
    return envelope, contested, placeholder_ids


def encode_deterministic_gzip(envelope: dict[str, Any]) -> bytes:
    plain = encode_deterministic_json(envelope)
    buffer = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buffer, mtime=0) as compressed:
        compressed.write(plain)
    return buffer.getvalue()


def encode_deterministic_json(value: dict[str, Any]) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def print_summary(
    envelope: dict[str, Any],
    contested: list[tuple[int, str, str, list[str]]],
    placeholder_ids: list[str],
    food_concepts: dict[str, Any],
    food_roles: dict[str, Any],
) -> None:
    counts = envelope["counts"]
    primaries = len(envelope["dravyas"]) - counts["placeholders"]
    excluded = sum(item["engineExcluded"] for item in envelope["dravyas"])
    print("build_seed summary")
    print(f"dravyas: {counts['dravyas']}")
    print(f"recipes: {counts['recipes']}")
    print(
        "recipe nutrition: "
        + ", ".join(
            f"{status}={counts['nutrition'][status]}"
            for status in ("full", "estimated", "none")
        )
    )
    print(
        "safety metadata: "
        + f"profiles={counts['safety']['profiles']}, "
        + f"allergen dravyas={counts['safety']['allergenTaggedDravyas']}, "
        + f"allergen recipes={counts['safety']['allergenTaggedRecipes']}, "
        + f"honey-age dravyas={counts['safety']['honeyMinAgeDravyas']}, "
        + f"honey-age recipes={counts['safety']['honeyMinAgeRecipes']}"
    )
    print(
        f"links: {counts['links']} "
        + f"({V1_LINK_COUNT} v1 + {counts['derivedLinks']} derived)"
    )
    print(f"placeholders: {counts['placeholders']}")
    print(f"primaries: {primaries}")
    print(f"categoryRules: {counts['categoryRules']}")
    print(f"modifiers: {counts['modifiers']}")
    print("unresolved ingredients: 0")
    print(f"engineExcluded: {excluded}")
    print(
        "food concepts: "
        + f"{food_concepts['conceptCount']} concepts, "
        + f"{food_concepts['aliasCount']} aliases, "
        + f"{food_concepts['catalogCount']} foods"
    )
    propagation = food_concepts["propagation"]
    print(
        "concept propagation: "
        + f"{propagation['ingredientLinks']} links / "
        + f"{propagation['recipeOwners']} recipes, "
        + f"nested={propagation['nestedRecipeLinks']}, "
        + f"depth={propagation['depthUsed']}/{propagation['depthCap']}"
    )
    role_counts = defaultdict(int)
    for item in food_roles["items"]:
        role_counts[item["role"]] += 1
    print(
        "food roles: "
        + f"{food_roles['roleCount']} roles, "
        + f"{food_roles['ruleCount']} rules, "
        + f"{food_roles['catalogCount']} foods; "
        + ", ".join(
            f"{role}={role_counts[role]}" for role in sorted(role_counts)
        )
    )
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
        nutrition_by_id = load_food_nutrition(args.foods, store_ids)
        source_safety_by_id = load_food_safety(args.foods, store_ids)
        source_food_catalog = load_food_catalog(args.foods, store_ids)
        source_food_names = {
            food_id: record["name"]
            for food_id, record in source_food_catalog.items()
        }
        dravyas = load_batches(data_root / "dravyas", "batch-*.json", "items")
        recipes = load_batches(data_root / "recipes", "batch-r*.json", "items")
        dravya_ids = {dravya["id"] for dravya in dravyas}
        _claims, bindings_by_dravya = validate_bindings(dravyas, store_ids)
        preferred_bindings = preferred_nutrition_bindings(bindings_by_dravya)
        v1_fdc_ids = {
            fdc_id
            for bindings in bindings_by_dravya.values()
            for fdc_id, _tier, _position in bindings
        }
        derived_links = load_crosswalk_links(
            data_root / "crosswalk" / "crosswalk.csv",
            store_ids,
            dravya_ids,
            v1_fdc_ids,
        )
        rules_bundle = load_rules_bundle(data_root)
        envelope, contested, placeholder_ids = build_envelope(
            dravyas,
            recipes,
            store_ids,
            derived_links,
            nutrition_by_id,
            source_safety_by_id,
            preferred_bindings,
        )
        ontology, concept_overrides = load_food_concept_sources(
            data_root / "rules" / "food-concepts.json",
            data_root / "crosswalk" / "concept-overrides.json",
        )
        suffix_negation_terms = load_suffix_negation_terms(
            Path(__file__).resolve().parent.parent
            / "WiseEating"
            / "FoodSearch"
            / "SearchKnowledgeBase.swift"
        )
        food_concepts, _concept_diagnostics = build_food_concepts(
            envelope,
            source_food_names,
            ontology,
            concept_overrides,
            suffix_negation_terms,
        )
        food_role_source = load_food_role_source(
            data_root / "rules" / "food-roles.json"
        )
        food_roles, _role_diagnostics = build_food_roles(
            envelope,
            source_food_catalog,
            food_role_source,
            rules_bundle["modifiers"],
            suffix_negation_terms,
        )
        compressed = encode_deterministic_gzip(envelope)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(compressed)
        args.rules_output.parent.mkdir(parents=True, exist_ok=True)
        args.rules_output.write_bytes(encode_deterministic_json(rules_bundle))
        args.concepts_output.parent.mkdir(parents=True, exist_ok=True)
        args.concepts_output.write_bytes(encode_deterministic_gzip(food_concepts))
        args.roles_output.parent.mkdir(parents=True, exist_ok=True)
        args.roles_output.write_bytes(encode_deterministic_gzip(food_roles))
        print_summary(
            envelope,
            contested,
            placeholder_ids,
            food_concepts,
            food_roles,
        )
        print()
        print(f"wrote: {args.output}")
        print(f"wrote: {args.rules_output}")
        print(f"wrote: {args.concepts_output}")
        print(f"wrote: {args.roles_output}")
        return 0
    except (BuildError, KeyError, TypeError, ValueError, OSError) as error:
        print(f"build_seed.py: error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
