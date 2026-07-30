#!/usr/bin/env python3
"""Validate dravya batches against schema rules and the preseeded store.

Usage: python3 validate.py [--store /path/to/preseeded.sqlite]
Run from the ayurveda-data directory (or pass paths). Exits non-zero on errors.
"""
import csv, glob, gzip, json, os, re, sqlite3, subprocess, sys
from collections import Counter

import build_seed
import build_preseeded_store

RASA = {"sweet", "sour", "salty", "pungent", "bitter", "astringent"}
GUNA = {"heavy", "light", "oily", "dry", "sharp", "soft", "smooth", "rough",
        "penetrating", "dense", "liquid", "slimy"}
RITU = {"vasanta", "grishma", "varsha", "sharad", "hemanta", "shishira"}
TIME = {"morning", "midday", "evening", "night"}
VIRYA = {"heating", "cooling", "neutral"}
VIPAKA = {"sweet", "sour", "pungent"}
TIER = {"exact", "near"}
CATEGORY = {"spice", "herb", "medicinal", "grain", "legume", "vegetable",
            "leafy-green", "fruit", "dry-fruit-nut", "seed", "dairy",
            "oil-fat", "sweetener", "preparation", "beverage", "fermented",
            "animal", "salt-mineral", "regional"}
REQUIRED = ["id", "name", "category", "rasa", "virya", "vipaka", "gunas",
            "prabhava", "dosha", "agniEffect", "digestibility", "seasons",
            "timeOfDay", "combinations", "viruddha", "contraindications",
            "preparation", "usda", "servings", "provenance", "confidence"]

D34_RULE_GUNA = {"dense", "dry", "heavy", "light", "liquid", "oily",
                 "rough", "sharp", "smooth", "soft"}
D34_VIRYA = {"heating", "cooling", "neutral"}
D34_RULES = {"M1", "M2", "F"}
D34_EXPECTED_MODIFIERS = {
    "raw": 1356,
    "dry-heat": 1031,
    "moist-heat": 771,
    "sweetened": 643,
    "canned": 640,
    "rich": 565,
    "frozen": 548,
    "processed": 424,
    "lowfat": 344,
    "fried": 329,
    "cured": 212,
    "dried": 206,
    "fermented-sour": 63,
    "pungent": 26,
}
d34_normalized_tokens = build_seed.modifier_normalized_tokens
TRACKED_FILE_SPLIT_LIMIT_BYTES = 90_000_000


def tracked_file_sizes(repo_root):
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=repo_root,
        check=True,
        capture_output=True,
    )
    sizes = {}
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative_path = os.fsdecode(raw_path)
        absolute_path = os.path.join(repo_root, relative_path)
        if os.path.isfile(absolute_path):
            sizes[relative_path] = os.path.getsize(absolute_path)
    return sizes


def validate_tracked_file_sizes(repo_root, errs):
    try:
        sizes = tracked_file_sizes(repo_root)
    except (OSError, subprocess.CalledProcessError) as error:
        errs.append(f"tracked-file size gate could not enumerate Git files: {error}")
        return {}

    oversized = sorted(
        (
            (relative_path, size)
            for relative_path, size in sizes.items()
            if size > TRACKED_FILE_SPLIT_LIMIT_BYTES
        ),
        key=lambda item: (-item[1], item[0]),
    )
    for relative_path, size in oversized:
        errs.append(
            f"tracked-file size gate: {relative_path} is {size} bytes; "
            f"split at {TRACKED_FILE_SPLIT_LIMIT_BYTES} bytes"
        )

    reportable = sorted(
        (
            (relative_path, size)
            for relative_path, size in sizes.items()
            if size >= 1_000_000
        ),
        key=lambda item: (-item[1], item[0]),
    )
    print(
        f"Git-tracked file size gate: {len(sizes)} files; "
        f"{len(reportable)} files at least 1 MB"
    )
    for relative_path, size in reportable:
        print(f" - {size} bytes: {relative_path}")
    return sizes


def d34_primary_category(blob, fdc_id, errs):
    if isinstance(blob, bytes):
        try:
            blob = blob.decode("utf-8")
        except UnicodeDecodeError as error:
            errs.append(f"D34/store/{fdc_id}: category is not UTF-8: {error}")
            return None
    try:
        categories = json.loads(blob)
    except (TypeError, json.JSONDecodeError) as error:
        errs.append(f"D34/store/{fdc_id}: invalid category JSON: {error}")
        return None
    if not isinstance(categories, list) or not categories or not isinstance(categories[0], str):
        errs.append(f"D34/store/{fdc_id}: missing primary category")
        return None
    return categories[0]


def d34_modifier_applies(food_tokens, phrase_tokens):
    if not phrase_tokens or len(phrase_tokens) > len(food_tokens):
        return False
    width = len(phrase_tokens)
    return any(food_tokens[index:index + width] == phrase_tokens
               for index in range(len(food_tokens) - width + 1))


def d34_applied_modifiers(name, modifiers):
    food_tokens = d34_normalized_tokens(name)
    applied = []
    for modifier in modifiers:
        if any(d34_modifier_applies(food_tokens, d34_normalized_tokens(phrase))
               for phrase in modifier.get("phrases", [])):
            applied.append(modifier)
    return applied


def d34_adjusted_vpk(base, modifiers):
    result = list(base)
    for modifier in modifiers:
        result = [value + delta for value, delta in zip(result, modifier["vpk"])]
    return [max(-2, min(2, value)) for value in result]


def d34_check_vector(value, label, errs):
    if (not isinstance(value, list) or len(value) != 3
            or any(not isinstance(item, int) or isinstance(item, bool)
                   or not -2 <= item <= 2 for item in value)):
        errs.append(f"{label}: vpk must contain three integers in [-2,2]")


def d34_load_dravyas(here, errs):
    items = {}
    v1_bound = set()
    for path in sorted(glob.glob(os.path.join(here, "dravyas", "batch-*.json"))):
        try:
            batch = json.load(open(path))
        except Exception as error:
            errs.append(f"D34/{os.path.basename(path)}: cannot reload: {error}")
            continue
        for item in batch.get("items", []):
            items[item["id"]] = item
            for binding in item.get("usda", []):
                if isinstance(binding.get("fdcId"), int):
                    v1_bound.add(binding["fdcId"])
    if len(v1_bound) != 336:
        errs.append(f"D34/v1 bindings: expected 336 distinct fdcIds, got {len(v1_bound)}")
    return items, v1_bound


def d34_validate(here, store, errs):
    dravyas, v1_bound = d34_load_dravyas(here, errs)
    denied = {8244, 12546}
    crosswalk_path = os.path.join(here, "crosswalk", "crosswalk.csv")
    try:
        with open(crosswalk_path, newline="", encoding="utf-8") as source:
            rows = list(csv.DictReader(source))
    except Exception as error:
        errs.append(f"D34/crosswalk.csv: cannot read: {error}")
        return

    expected_header = ["fdcId", "name", "category", "dravyaId", "rule", "key",
                       "contested", "losers"]
    if rows and list(rows[0]) != expected_header:
        errs.append(f"D34/crosswalk.csv: unexpected header {list(rows[0])}")
    if len(rows) != 1969:
        errs.append(f"D34/crosswalk.csv: expected 1969 rows, got {len(rows)}")
    crosswalk = {}
    for row in rows:
        try:
            fdc_id = int(row["fdcId"])
        except (TypeError, ValueError):
            errs.append(f"D34/crosswalk.csv: invalid fdcId {row.get('fdcId')!r}")
            continue
        if fdc_id in crosswalk:
            errs.append(f"D34/crosswalk.csv: duplicate fdcId {fdc_id}")
        crosswalk[fdc_id] = row
        if fdc_id in v1_bound:
            errs.append(f"D34/crosswalk.csv: fdcId {fdc_id} overlaps v1")
        if fdc_id in denied:
            errs.append(f"D34/crosswalk.csv: denied fdcId {fdc_id} is present")
        if row["dravyaId"] not in dravyas:
            errs.append(f"D34/crosswalk.csv/{fdc_id}: unknown dravyaId {row['dravyaId']}")
        if row["rule"] not in D34_RULES:
            errs.append(f"D34/crosswalk.csv/{fdc_id}: invalid rule {row['rule']}")

    try:
        connection = sqlite3.connect(store)
        total_store_foods = connection.execute(
            "SELECT COUNT(*) FROM ZFOODITEM"
        ).fetchone()[0]
        store_rows = connection.execute(
            """
            SELECT ZID, ZNAME, ZCATEGORY FROM ZFOODITEM
            WHERE ZID BETWEEN 1 AND 12601
            ORDER BY ZID
            """
        ).fetchall()
        connection.close()
    except sqlite3.Error as error:
        errs.append(f"D34/store: cannot query foods: {error}")
        return
    foods = {}
    for fdc_id, name, category_blob in store_rows:
        category = d34_primary_category(category_blob, fdc_id, errs)
        foods[fdc_id] = {"name": name, "category": category}
    store_ids = set(foods)
    if len(store_ids) != 12601:
        errs.append(f"D34/store: expected 12601 foods, got {len(store_ids)}")
    if total_store_foods == 14484:
        try:
            build_preseeded_store.audit_store(os.path.abspath(store))
        except (build_preseeded_store.PreseedBuildError, sqlite3.Error) as error:
            errs.append(f"WE2/preseed: {error}")
    elif total_store_foods != 12601:
        errs.append(
            f"WE2/preseed: expected 12601 base or 14484 projected foods, "
            f"got {total_store_foods}"
        )
    missing_crosswalk_ids = sorted(set(crosswalk) - store_ids)
    if missing_crosswalk_ids:
        errs.append(f"D34/crosswalk.csv: fdcIds absent from store {missing_crosswalk_ids[:10]}")

    category_path = os.path.join(here, "rules", "category-rules.json")
    modifier_path = os.path.join(here, "rules", "modifiers.json")
    bundle_path = os.path.join(here, "..", "Ayura", "ayurveda_rules.json")
    try:
        category_source = json.load(open(category_path))
        modifier_source = json.load(open(modifier_path))
        rules_bundle = json.load(open(bundle_path))
    except Exception as error:
        errs.append(f"D34/rules: cannot read rule inputs/bundle: {error}")
        return
    expected_bundle = {
        "rulesVersion": category_source.get("rulesVersion"),
        "categories": category_source.get("categories"),
        "default": category_source.get("default"),
        "modifiers": modifier_source.get("modifiers"),
    }
    if rules_bundle != expected_bundle:
        errs.append("D34/ayurveda_rules.json: content does not match authored rule inputs")

    category_rules = rules_bundle.get("categories", [])
    default_rule = rules_bundle.get("default", {})
    modifiers = rules_bundle.get("modifiers", [])
    category_map = {}
    for rule in category_rules:
        category = rule.get("category")
        if category in category_map:
            errs.append(f"D34/rules: duplicate category rule {category}")
        category_map[category] = rule
        d34_check_vector(rule.get("vpk"), f"D34/rules/{category}", errs)
        if rule.get("virya") not in D34_VIRYA:
            errs.append(f"D34/rules/{category}: invalid virya {rule.get('virya')}")
        if set(rule.get("gunas", [])) - D34_RULE_GUNA:
            errs.append(f"D34/rules/{category}: invalid gunas")
    d34_check_vector(default_rule.get("vpk"), "D34/rules/default", errs)
    if default_rule.get("virya") not in D34_VIRYA:
        errs.append(f"D34/rules/default: invalid virya {default_rule.get('virya')}")
    if set(default_rule.get("gunas", [])) - D34_RULE_GUNA:
        errs.append("D34/rules/default: invalid gunas")

    store_categories = {food["category"] for food in foods.values() if food["category"]}
    rule_categories = set(category_map)
    uncovered = sorted(store_categories - rule_categories)
    dead = sorted(rule_categories - store_categories)
    if len(store_categories) != 187:
        errs.append(f"D34/store: expected 187 primary categories, got {len(store_categories)}")
    if len(category_rules) != 187 or uncovered or dead:
        errs.append(
            f"D34/rules: expected 187 rules / 0 dead / 0 uncovered; got "
            f"{len(category_rules)} / {len(dead)} / {len(uncovered)}"
        )

    modifier_ids = []
    for modifier in modifiers:
        modifier_id = modifier.get("id")
        modifier_ids.append(modifier_id)
        d34_check_vector(modifier.get("vpk"), f"D34/modifiers/{modifier_id}", errs)
        if set(modifier.get("gunas", [])) - D34_RULE_GUNA:
            errs.append(f"D34/modifiers/{modifier_id}: invalid gunas")
    if len(modifiers) != 14:
        errs.append(f"D34/modifiers: expected 14, got {len(modifiers)}")
    if len(set(modifier_ids)) != len(modifier_ids):
        errs.append("D34/modifiers: ids are not unique")

    seed_path = os.path.join(here, "..", "Ayura", "ayurveda_seed.json.gz")
    try:
        with gzip.open(seed_path, "rt", encoding="utf-8") as source:
            seed = json.load(source)
    except Exception as error:
        errs.append(f"D34/ayurveda_seed.json.gz: cannot read: {error}")
        return
    if seed.get("seedVersion") != 5:
        errs.append(f"D34/seed: expected seedVersion 5, got {seed.get('seedVersion')}")
    counts = seed.get("counts", {})
    expected_counts = {
        "dravyas": 714, "recipes": 1500, "links": 2305,
        "derivedLinks": 1969, "placeholders": 383,
        "categoryRules": 187, "modifiers": 14,
        "nutrition": {"full": 1500, "estimated": 0, "none": 0},
        "safety": {
            "profiles": 2214,
            "allergenTaggedDravyas": 156,
            "allergenTaggedRecipes": 1182,
            "honeyMinAgeDravyas": 4,
            "honeyMinAgeRecipes": 4,
            "authoredAgeDravyas": 4,
            "legacyImportAgeDravyas": 710,
            "authoredAgeRecipes": 4,
            "legacyImportAgeRecipes": 1496,
            "ageContributors": 10571,
        },
    }
    if counts != expected_counts:
        errs.append(f"D34/seed: counts block differs: {counts}")
    links = seed.get("links", [])
    if len(links) != 2305:
        errs.append(f"D34/seed: expected 2305 links, got {len(links)}")
    link_map = {}
    for link in links:
        fdc_id = link.get("fdcId")
        if fdc_id in link_map:
            errs.append(f"D34/seed: duplicate link fdcId {fdc_id}")
        link_map[fdc_id] = link
        if fdc_id not in store_ids:
            errs.append(f"D34/seed: link fdcId {fdc_id} absent from store")
        if link.get("dravyaId") not in dravyas:
            errs.append(f"D34/seed: link {fdc_id} has unknown dravyaId")
    seed_derived = {fdc_id: link for fdc_id, link in link_map.items()
                    if link.get("tier") == "derived"}
    seed_classical = {fdc_id: link for fdc_id, link in link_map.items()
                      if link.get("tier") in {"exact", "near"}}
    if len(seed_classical) != 336 or len(seed_derived) != 1969:
        errs.append(
            f"D34/seed: expected 336 classical / 1969 derived links, got "
            f"{len(seed_classical)} / {len(seed_derived)}"
        )
    if set(seed_derived) != set(crosswalk):
        errs.append("D34/seed: derived fdcIds differ from crosswalk.csv")

    safety_rows = seed.get("dravyas", []) + seed.get("recipes", [])
    for item in safety_rows:
        safety = item.get("safety")
        item_id = item.get("id", "?")
        if not isinstance(safety, dict):
            errs.append(f"WE8/seed/{item_id}: missing safety metadata")
            continue
        if safety.get("provenance") != "scaffold-default":
            errs.append(f"WE8/seed/{item_id}: safety provenance differs")
        if safety.get("reviewRequired") is not True:
            errs.append(f"WE8/seed/{item_id}: safety review flag differs")
        if not isinstance(safety.get("rules"), list) or not safety["rules"]:
            errs.append(f"WE8/seed/{item_id}: safety rules are empty")
        if not isinstance(safety.get("minAgeMonths"), int) or safety["minAgeMonths"] < 0:
            errs.append(f"WE8/seed/{item_id}: invalid minimum age")
        enforced_age = safety.get("enforcedMinAgeMonths")
        if (
            not isinstance(enforced_age, int)
            or enforced_age < 0
            or enforced_age > safety.get("minAgeMonths", -1)
        ):
            errs.append(f"WE8c/seed/{item_id}: invalid enforced minimum age")
        if safety.get("ageProvenance") not in {
            build_seed.AGE_PROVENANCE_AUTHORED,
            build_seed.AGE_PROVENANCE_LEGACY_IMPORT,
        }:
            errs.append(f"WE8c/seed/{item_id}: invalid age provenance")
        contributors = safety.get("ageContributors")
        if not isinstance(contributors, list) or not contributors:
            errs.append(f"WE8c/seed/{item_id}: missing age contributors")
        else:
            for contributor in contributors:
                if contributor.get("ageProvenance") not in {
                    build_seed.AGE_PROVENANCE_AUTHORED,
                    build_seed.AGE_PROVENANCE_LEGACY_IMPORT,
                }:
                    errs.append(
                        f"WE8c/seed/{item_id}: invalid contributor provenance"
                    )
                    break
                if not isinstance(contributor.get("minAgeMonths"), int):
                    errs.append(f"WE8c/seed/{item_id}: invalid contributor age")
                    break
                if not isinstance(
                    contributor.get("enforcedMinAgeMonths"), int
                ):
                    errs.append(
                        f"WE8c/seed/{item_id}: invalid contributor enforced age"
                    )
                    break
        if set(safety.get("allergens", [])) - build_seed.ALLERGEN_VOCABULARY:
            errs.append(f"WE8/seed/{item_id}: unsupported allergen")
        if set(safety.get("diets", [])) - build_seed.DIET_VOCABULARY:
            errs.append(f"WE8/seed/{item_id}: unsupported diet")

    nutrition_counts = Counter()
    nutrient_keys = set(build_seed.NUTRIENT_CATALOG)
    kitchari_energy = None
    for recipe in seed.get("recipes", []):
        recipe_id = recipe.get("id", "?")
        nutrition = recipe.get("nutrition")
        if not isinstance(nutrition, dict):
            errs.append(f"WE2/seed/{recipe_id}: missing nutrition panel")
            continue
        status = nutrition.get("status")
        nutrition_counts[status] += 1
        if status not in {"full", "estimated", "none"}:
            errs.append(f"WE2/seed/{recipe_id}: invalid nutrition status {status!r}")
        missing = nutrition.get("missingIngredients")
        if not isinstance(missing, list) or any(not isinstance(item, str) for item in missing):
            errs.append(f"WE2/seed/{recipe_id}: invalid missing ingredient slugs")
        elif status == "full" and missing:
            errs.append(f"WE2/seed/{recipe_id}: full panel lists missing ingredients")
        total_weight = nutrition.get("totalWeightG")
        ingredient_weight = sum(
            ingredient.get("grams", 0) for ingredient in recipe.get("ingredients", [])
        )
        if not isinstance(total_weight, (int, float)) or total_weight <= 0:
            errs.append(f"WE2/seed/{recipe_id}: invalid total weight")
            continue
        if abs(total_weight - ingredient_weight) > 1e-9:
            errs.append(
                f"WE2/seed/{recipe_id}: total weight {total_weight} "
                f"differs from ingredients {ingredient_weight}"
            )
        units = nutrition.get("units", {})
        if set(units) != nutrient_keys:
            errs.append(f"WE2/seed/{recipe_id}: nutrient unit catalog differs")
        per_serving = nutrition.get("perServing", {})
        per_100g = nutrition.get("per100g", {})
        if not isinstance(per_serving, dict) or not isinstance(per_100g, dict):
            errs.append(f"WE2/seed/{recipe_id}: invalid nutrient value dictionaries")
            continue
        if set(per_serving) != set(per_100g) or set(per_serving) - nutrient_keys:
            errs.append(f"WE2/seed/{recipe_id}: nutrient panel keys differ")
        servings = recipe.get("servings")
        if not isinstance(servings, (int, float)) or servings <= 0:
            continue
        for nutrient in per_serving:
            expected_serving = per_100g[nutrient] * total_weight / (100 * servings)
            if abs(per_serving[nutrient] - expected_serving) > 1e-8:
                errs.append(
                    f"WE2/seed/{recipe_id}: {nutrient} serving/100g math differs"
                )
                break
        if recipe_id == "recipe.classic-mung-kitchari":
            kitchari_energy = per_serving.get("energyKcal")

    expected_nutrition_counts = Counter({"full": 1500, "estimated": 0, "none": 0})
    if nutrition_counts != expected_nutrition_counts:
        errs.append(f"WE2/seed: nutrition coverage differs: {dict(nutrition_counts)}")
    if nutrition_counts["none"] > 375:
        errs.append(
            f"WE2/seed: no-nutrition coverage exceeds 25%: {nutrition_counts['none']}"
        )
    if not isinstance(kitchari_energy, (int, float)) or abs(kitchari_energy - 379.67) > 0.5:
        errs.append(f"WE2/seed: kitchari energy gate differs: {kitchari_energy}")

    tier_counts = Counter()
    modifier_histogram = Counter()
    modified_foods = 0
    resolutions = {}
    for fdc_id, food in foods.items():
        link = link_map.get(fdc_id)
        if link and link.get("tier") in {"exact", "near"}:
            tier = "classical"
            applied = []
            dravya = dravyas[link["dravyaId"]]
            base = [dravya["dosha"][key] for key in ("vata", "pitta", "kapha")]
        elif link and link.get("tier") == "derived":
            tier = "derived"
            applied = d34_applied_modifiers(food["name"], modifiers)
            dravya = dravyas[link["dravyaId"]]
            base = [dravya["dosha"][key] for key in ("vata", "pitta", "kapha")]
        else:
            tier = "estimated"
            rule = category_map.get(food["category"], default_rule)
            applied = d34_applied_modifiers(food["name"], modifiers)
            base = rule["vpk"]
        tier_counts[tier] += 1
        if applied:
            modified_foods += 1
        for modifier in applied:
            modifier_histogram[modifier["id"]] += 1
        resolutions[fdc_id] = {
            "tier": tier,
            "link": link,
            "base": list(base),
            "modifiers": [modifier["id"] for modifier in applied],
            "vpk": d34_adjusted_vpk(base, applied),
        }

    expected_tiers = Counter({"classical": 336, "derived": 1969, "estimated": 10296})
    if tier_counts != expected_tiers:
        errs.append(f"D34/resolver: tier totals differ: {dict(tier_counts)}")
    if sum(tier_counts.values()) != 12601:
        errs.append(f"D34/resolver: unresolved foods {12601 - sum(tier_counts.values())}")
    if modified_foods != 6357:
        errs.append(f"D34/resolver: expected 6357 modified foods, got {modified_foods}")
    if modifier_histogram != Counter(D34_EXPECTED_MODIFIERS):
        errs.append(f"D34/resolver: modifier histogram differs: {dict(modifier_histogram)}")

    review_path = os.path.join(here, "crosswalk", "REVIEW-D3.md")
    try:
        review = open(review_path, encoding="utf-8").read()
    except OSError as error:
        review = ""
        errs.append(f"D34/REVIEW-D3.md: cannot read: {error}")

    spot_checks = []
    def spot(fdc_id, label, condition):
        passed = bool(condition)
        spot_checks.append((fdc_id, label, passed))
        if not passed:
            errs.append(f"D34/G4/{fdc_id}: {label} failed; got {resolutions.get(fdc_id)}")

    spot(8641, "broiler-chicken [-1,1,2] (fried)",
         resolutions[8641]["tier"] == "derived"
         and resolutions[8641]["link"]["dravyaId"] == "dravya.broiler-chicken"
         and resolutions[8641]["base"] == [-1, 0, 1]
         and resolutions[8641]["modifiers"] == ["fried"]
         and resolutions[8641]["vpk"] == [-1, 1, 2])
    spot(6556, "orange-juice over orange (R2)",
         crosswalk[6556]["dravyaId"] == "dravya.orange-juice"
         and crosswalk[6556]["losers"] == "dravya.orange"
         and "| 6556 |" in review and "| R2 |" in review.split("| 6556 |", 1)[1].splitlines()[0])
    spot(4106, "sweet-potato over potato (R1)",
         crosswalk[4106]["dravyaId"] == "dravya.sweet-potato"
         and crosswalk[4106]["losers"] == "dravya.potato"
         and "| 4106 |" in review and "| R1 |" in review.split("| 4106 |", 1)[1].splitlines()[0])
    spot(11971, "garlic over garlic-fresh-bulb (R3)",
         crosswalk[11971]["dravyaId"] == "dravya.garlic"
         and crosswalk[11971]["losers"] == "dravya.garlic-fresh-bulb"
         and "| 11971 |" in review and "| R3 |" in review.split("| 11971 |", 1)[1].splitlines()[0])
    spot(3623, "apricot [0,1,-1] (dried)",
         resolutions[3623]["tier"] == "derived"
         and resolutions[3623]["link"]["dravyaId"] == "dravya.apricot"
         and resolutions[3623]["modifiers"] == ["dried"]
         and resolutions[3623]["vpk"] == [0, 1, -1])
    spot(3923, "estimated [1,0,1] (processed)",
         resolutions[3923]["tier"] == "estimated"
         and resolutions[3923]["modifiers"] == ["processed"]
         and resolutions[3923]["vpk"] == [1, 0, 1])
    spot(68, "estimated [2,-1,2] (frozen)",
         resolutions[68]["tier"] == "estimated"
         and resolutions[68]["modifiers"] == ["frozen"]
         and resolutions[68]["vpk"] == [2, -1, 2])
    spot(6148, "estimated [0,2,0] (dry-heat)",
         resolutions[6148]["tier"] == "estimated"
         and resolutions[6148]["modifiers"] == ["dry-heat"]
         and resolutions[6148]["vpk"] == [0, 2, 0])
    spot(2655, "estimated [2,0,-1] (none)",
         resolutions[2655]["tier"] == "estimated"
         and resolutions[2655]["modifiers"] == []
         and resolutions[2655]["vpk"] == [2, 0, -1])

    print("D34 resolver simulation")
    print("tiers: classical 336 · derived 1969 · estimated 10296")
    print(f"resolved foods: {sum(tier_counts.values())}/12601")
    print(f"foods firing modifiers: {modified_foods}/12265")
    print("modifier histogram: " + " · ".join(
        f"{modifier_id} {modifier_histogram[modifier_id]}"
        for modifier_id in D34_EXPECTED_MODIFIERS
    ))
    print("G4 spot values:")
    for fdc_id, label, passed in spot_checks:
        print(f" - {fdc_id}: {'PASS' if passed else 'FAIL'} — {label}")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(here)
    store = None
    if "--store" in sys.argv:
        store = sys.argv[sys.argv.index("--store") + 1]
    fdc_ids = None
    if store and os.path.exists(store):
        c = sqlite3.connect(store)
        fdc_ids = {r[0] for r in c.execute("select ZID from ZFOODITEM")}

    errs, seen, total = [], {}, 0
    validate_tracked_file_sizes(repo_root, errs)
    for path in sorted(glob.glob(os.path.join(here, "dravyas", "batch-*.json"))):
        b = os.path.basename(path)
        try:
            data = json.load(open(path))
        except Exception as e:
            errs.append(f"{b}: JSON parse error: {e}")
            continue
        for it in data.get("items", []):
            total += 1
            i = it.get("id", "?")
            for f in REQUIRED:
                if f not in it:
                    errs.append(f"{b}/{i}: missing field '{f}'")
            if i in seen:
                errs.append(f"{b}/{i}: duplicate id (also in {seen[i]})")
            seen[i] = b
            if set(it.get("rasa", [])) - RASA:
                errs.append(f"{b}/{i}: invalid rasa {set(it['rasa']) - RASA}")
            if it.get("virya") not in VIRYA:
                errs.append(f"{b}/{i}: invalid virya {it.get('virya')}")
            if it.get("vipaka") not in VIPAKA:
                errs.append(f"{b}/{i}: invalid vipaka {it.get('vipaka')}")
            if set(it.get("gunas", [])) - GUNA:
                errs.append(f"{b}/{i}: invalid guna {set(it['gunas']) - GUNA}")
            if it.get("category") not in CATEGORY:
                errs.append(f"{b}/{i}: invalid category {it.get('category')}")
            for k, v in it.get("dosha", {}).items():
                if k not in ("vata", "pitta", "kapha") or not -2 <= v <= 2:
                    errs.append(f"{b}/{i}: bad dosha {k}={v}")
            if not -2 <= it.get("agniEffect", 99) <= 2:
                errs.append(f"{b}/{i}: agniEffect out of range")
            if not 1 <= it.get("digestibility", 0) <= 5:
                errs.append(f"{b}/{i}: digestibility out of range")
            if set(it.get("seasons", [])) - RITU:
                errs.append(f"{b}/{i}: invalid season {set(it['seasons']) - RITU}")
            if set(it.get("timeOfDay", [])) - TIME:
                errs.append(f"{b}/{i}: invalid timeOfDay")
            for u in it.get("usda", []):
                if u.get("tier") not in TIER:
                    errs.append(f"{b}/{i}: invalid usda tier {u.get('tier')}")
                if fdc_ids is not None and u.get("fdcId") not in fdc_ids:
                    errs.append(f"{b}/{i}: fdcId {u.get('fdcId')} not in store")
            for s in it.get("servings", []):
                if not (isinstance(s.get("grams"), (int, float)) and s["grams"] > 0):
                    errs.append(f"{b}/{i}: bad serving grams")
            cf = it.get("confidence", {})
            if not (0 <= cf.get("ayur", -1) <= 1 and 0 <= cf.get("sci", -1) <= 1):
                errs.append(f"{b}/{i}: confidence out of range")

    # ---- recipes ----
    dravya_ids = set(seen.keys())
    r_total, r_seen = 0, {}
    MEAL = {"breakfast", "lunch", "dinner", "snack", "drink", "dessert"}
    RCAT = {"classical", "everyday", "international"}
    R_REQUIRED = ["id", "name", "category", "meal", "servings", "prepMinutes",
                  "cookMinutes", "ingredients", "steps", "dosha", "seasons",
                  "timeOfDay", "viruddhaFlags", "guidance", "provenance", "confidence"]
    for path in sorted(glob.glob(os.path.join(here, "recipes", "batch-*.json"))):
        b = os.path.basename("recipes/" + os.path.basename(path))
        try:
            data = json.load(open(path))
        except Exception as e:
            errs.append(f"{b}: JSON parse error: {e}")
            continue
        for r in data.get("items", []):
            r_total += 1
            i = r.get("id", "?")
            for f in R_REQUIRED:
                if f not in r:
                    errs.append(f"{b}/{i}: missing field '{f}'")
            if i in r_seen:
                errs.append(f"{b}/{i}: duplicate recipe id")
            r_seen[i] = b
            if r.get("category") not in RCAT:
                errs.append(f"{b}/{i}: invalid category {r.get('category')}")
            if r.get("meal") not in MEAL:
                errs.append(f"{b}/{i}: invalid meal {r.get('meal')}")
            ings = r.get("ingredients", [])
            if len(ings) < 2:
                errs.append(f"{b}/{i}: fewer than 2 ingredients")
            linked = 0
            for ing in ings:
                d, f_ = ing.get("dravyaId"), ing.get("fdcId")
                if d:
                    linked += 1
                    if d not in dravya_ids:
                        errs.append(f"{b}/{i}: unknown dravyaId {d}")
                elif f_:
                    if fdc_ids is not None and f_ not in fdc_ids:
                        errs.append(f"{b}/{i}: fdcId {f_} not in store")
                else:
                    errs.append(f"{b}/{i}: ingredient '{ing.get('name')}' has no dravyaId or fdcId")
                if not (isinstance(ing.get("grams"), (int, float)) and ing["grams"] > 0):
                    errs.append(f"{b}/{i}: ingredient '{ing.get('name')}' bad grams")
            if ings and linked / len(ings) < 0.5:
                errs.append(f"{b}/{i}: under 50% of ingredients linked to dravyas ({linked}/{len(ings)})")
            steps = r.get("steps", [])
            if not 3 <= len(steps) <= 15:
                errs.append(f"{b}/{i}: steps count {len(steps)} outside 3-15")
            for k, v in r.get("dosha", {}).items():
                if k not in ("vata", "pitta", "kapha") or not -2 <= v <= 2:
                    errs.append(f"{b}/{i}: bad dosha {k}={v}")
            if set(r.get("seasons", [])) - RITU:
                errs.append(f"{b}/{i}: invalid season")
            if set(r.get("timeOfDay", [])) - TIME:
                errs.append(f"{b}/{i}: invalid timeOfDay")
            if not (isinstance(r.get("servings"), (int, float)) and r["servings"] > 0):
                errs.append(f"{b}/{i}: bad servings")
            cf = r.get("confidence", {})
            if not (0 <= cf.get("ayur", -1) <= 1):
                errs.append(f"{b}/{i}: confidence out of range")

    if fdc_ids is not None:
        d34_validate(here, store, errs)

    print(f"Checked {total} dravyas, {r_total} recipes"
          + ("" if fdc_ids else " (store not checked — pass --store)"))
    if errs:
        print(f"\n{len(errs)} ERRORS:")
        for e in errs:
            print(" -", e)
        sys.exit(1)
    print("All checks passed.")


if __name__ == "__main__":
    main()
