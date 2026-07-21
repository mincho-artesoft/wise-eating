#!/usr/bin/env python3
"""Validate mechanical dravya predrafts against authored data and the USDA store."""

import argparse
import glob
import json
import os
import re
import sqlite3
import sys


CATEGORIES = {
    "spice", "herb", "medicinal", "grain", "legume", "vegetable",
    "leafy-green", "fruit", "dry-fruit-nut", "seed", "dairy",
    "oil-fat", "sweetener", "preparation", "beverage", "fermented",
    "animal", "salt-mineral", "regional",
}
ALLOWED_FIELDS = {
    "id", "name", "sanskrit", "aliases", "category", "canonHints",
    "usda", "usdaNote", "servings", "_facetsPending",
}
ALLOWED_HINTS = {"vpk", "virya", "note"}
FORBIDDEN_FACETS = {
    "rasa", "virya", "vipaka", "gunas", "dosha", "prabhava",
    "agniEffect", "digestibility", "seasons", "timeOfDay", "viruddha",
    "contraindications", "combinations", "preparation", "provenance",
    "confidence", "qualityState",
}


def normalized_name(value):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", value.lower()).split())


def load_json(path, errors):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception as exc:
        errors.append(f"{os.path.basename(path)}: JSON parse error: {exc}")
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", default="/tmp/pre")
    args = parser.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    authored_dir = os.path.dirname(here)
    errors = []
    warnings = []

    if not os.path.exists(args.store):
        errors.append(f"store not found: {args.store}")
        store_rows = {}
    else:
        connection = sqlite3.connect(args.store)
        store_rows = dict(connection.execute("select ZID, ZNAME from ZFOODITEM"))
        connection.close()

    authored_ids = {}
    authored_names = {}
    for path in sorted(glob.glob(os.path.join(authored_dir, "batch-*.json"))):
        data = load_json(path, errors)
        if not data:
            continue
        for item in data.get("items", []):
            authored_ids[item["id"]] = os.path.basename(path)
            authored_names.setdefault(normalized_name(item["name"]), []).append(
                (item["id"], item["name"], os.path.basename(path))
            )

    paths = sorted(glob.glob(os.path.join(here, "predraft-[0-9][0-9].json")))
    seen_ids = {}
    seen_names = {}
    file_stats = []
    total_items = 0

    for path in paths:
        basename = os.path.basename(path)
        data = load_json(path, errors)
        if not data:
            continue
        items = data.get("items")
        if not isinstance(items, list):
            errors.append(f"{basename}: top-level items must be a list")
            continue
        if len(items) != 25:
            if not (basename == "predraft-17.json" and len(items) == 24):
                errors.append(f"{basename}: expected 25 items, found {len(items)}")

        exact = near = none = 0
        for index, item in enumerate(items, 1):
            total_items += 1
            where = f"{basename}#{index}"
            if not isinstance(item, dict):
                errors.append(f"{where}: item must be an object")
                continue
            item_id = item.get("id", "?")
            where = f"{basename}/{item_id}"

            missing = [key for key in ("id", "name", "category", "servings") if not item.get(key)]
            if missing:
                errors.append(f"{where}: missing required value(s): {', '.join(missing)}")
            extra = set(item) - ALLOWED_FIELDS
            if extra:
                errors.append(f"{where}: unexpected field(s): {', '.join(sorted(extra))}")
            forbidden = set(item) & FORBIDDEN_FACETS
            if forbidden:
                errors.append(f"{where}: Ayurvedic facet(s) forbidden in predraft: {', '.join(sorted(forbidden))}")

            if item_id in authored_ids:
                errors.append(f"{where}: id already authored in {authored_ids[item_id]}")
            if item_id in seen_ids:
                errors.append(f"{where}: duplicate predraft id (also in {seen_ids[item_id]})")
            seen_ids[item_id] = basename

            name = item.get("name")
            if isinstance(name, str) and name.strip():
                normalized = normalized_name(name)
                if normalized in authored_names:
                    pairs = ", ".join(f"{row[0]} ({row[2]})" for row in authored_names[normalized])
                    errors.append(f"{where}: exact normalized name already authored as {pairs}")
                if normalized in seen_names:
                    warnings.append(
                        f"{where}: normalized predraft name also used by {seen_names[normalized]} "
                        "(retain as canon alias ambiguity for report)"
                    )
                seen_names[normalized] = item_id
            else:
                errors.append(f"{where}: name must be a non-empty string")

            if item.get("category") not in CATEGORIES:
                errors.append(f"{where}: invalid category {item.get('category')!r}")
            if item.get("sanskrit") is not None and not isinstance(item.get("sanskrit"), str):
                errors.append(f"{where}: sanskrit must be a string or null")
            if not isinstance(item.get("aliases"), list) or not all(isinstance(x, str) for x in item.get("aliases", [])):
                errors.append(f"{where}: aliases must be a string array")
            if item.get("_facetsPending") is not True:
                errors.append(f"{where}: _facetsPending must be true")

            hints = item.get("canonHints")
            if not isinstance(hints, dict):
                errors.append(f"{where}: canonHints must be an object")
            elif set(hints) - ALLOWED_HINTS:
                errors.append(f"{where}: unsupported canonHints keys: {sorted(set(hints) - ALLOWED_HINTS)}")

            usda = item.get("usda")
            if not isinstance(usda, list):
                errors.append(f"{where}: usda must be an array")
                usda = []
            if not usda:
                none += 1
                if not item.get("usdaNote"):
                    errors.append(f"{where}: empty usda requires usdaNote")
            for binding in usda:
                if not isinstance(binding, dict):
                    errors.append(f"{where}: USDA binding must be an object")
                    continue
                fdc_id = binding.get("fdcId")
                stored_name = store_rows.get(fdc_id)
                if stored_name is None:
                    errors.append(f"{where}: fdcId {fdc_id!r} not found in store")
                elif binding.get("name") != stored_name:
                    errors.append(
                        f"{where}: ZNAME mismatch for {fdc_id}: "
                        f"expected {stored_name!r}, got {binding.get('name')!r}"
                    )
                tier = binding.get("tier")
                if tier == "exact":
                    exact += 1
                elif tier == "near":
                    near += 1
                else:
                    errors.append(f"{where}: invalid USDA tier {tier!r}")

            servings = item.get("servings")
            if not isinstance(servings, list) or not servings:
                errors.append(f"{where}: servings must be a non-empty array")
            else:
                for serving in servings:
                    if not isinstance(serving, dict) or not isinstance(serving.get("label"), str) or not serving["label"].strip():
                        errors.append(f"{where}: serving label must be a non-empty string")
                    grams = serving.get("grams") if isinstance(serving, dict) else None
                    if not isinstance(grams, (int, float)) or isinstance(grams, bool) or grams <= 0:
                        errors.append(f"{where}: serving grams must be positive")

        file_stats.append((basename, len(items), exact, near, none))

    print(f"Store rows loaded: {len(store_rows)}")
    print(f"Authored ids loaded: {len(authored_ids)}")
    for basename, count, exact, near, none in file_stats:
        print(f"{basename}: items={count} exact={exact} near={near} none={none}")
    print(f"Predraft files checked: {len(paths)}")
    print(f"Predraft items checked: {total_items}")
    print(f"Warnings: {len(warnings)}")
    for warning in warnings:
        print(f"WARNING: {warning}")

    if errors:
        print(f"Errors: {len(errors)}")
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("Errors: 0")
    print("All predraft checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
