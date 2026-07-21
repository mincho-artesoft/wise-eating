#!/usr/bin/env python3
"""Validate dravya batches against schema rules and the preseeded store.

Usage: python3 validate.py [--store /path/to/preseeded.sqlite]
Run from the ayurveda-data directory (or pass paths). Exits non-zero on errors.
"""
import json, sqlite3, sys, glob, os

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


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    store = None
    if "--store" in sys.argv:
        store = sys.argv[sys.argv.index("--store") + 1]
    fdc_ids = None
    if store and os.path.exists(store):
        c = sqlite3.connect(store)
        fdc_ids = {r[0] for r in c.execute("select ZID from ZFOODITEM")}

    errs, seen, total = [], {}, 0
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

    print(f"Checked {total} items across {len(glob.glob(os.path.join(here, 'dravyas', 'batch-*.json')))} batches"
          + ("" if fdc_ids else " (store not checked — pass --store)"))
    if errs:
        print(f"\n{len(errs)} ERRORS:")
        for e in errs:
            print(" -", e)
        sys.exit(1)
    print("All checks passed.")


if __name__ == "__main__":
    main()
