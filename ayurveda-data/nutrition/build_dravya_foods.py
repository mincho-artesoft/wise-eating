#!/usr/bin/env python3
"""Emit the 376 placeholder dravyas in Legacy/foods.json shape, for review.

    python3 build_dravya_foods.py --repo ~/work/wise-eating \
        --store /path/to/preseeded.store --out dravya_foods.json

WHY THESE 376
    They are the dravyas with no USDA match, so their food row was synthesised
    and carries no nutrition, no category and no description. Every other food
    in the catalogue inherits all three from USDA.

WHAT IS REAL HERE AND WHAT IS NOT — read before trusting a number
    id, name, minAgeMonths, allergens, diets  : taken from the built store.
        Already computed by the seeder from authored rules. Not invented.
    desctiption (schema's spelling, kept)     : the dravya's own prabhava and
        preparation text, already authored. Not invented.
    category                                  : mapped from the dravya category.
        Deterministic, no judgement.
    macronutrients / vitamins / minerals /
    lipids / aminoAcids / carbDetails /
    sterols / other                           : NULL unless listed in VALUES
        below. A null means "not established here", never zero.

    Every food carries `_review` with the provenance of its numbers and a note
    on how much published sources disagree. That block is for review only and
    must be stripped before ingest.
"""
import argparse, glob, json, os, sqlite3, sys

SHAPE = {
 "macronutrients": ["carbohydrates","protein","fat","fiber","totalSugars"],
 "vitamins": ["vitaminA_RAE","retinol","caroteneAlpha","caroteneBeta","cryptoxanthinBeta",
   "luteinZeaxanthin","lycopene","vitaminB1_Thiamin","vitaminB2_Riboflavin","vitaminB3_Niacin",
   "vitaminB5_PantothenicAcid","vitaminB6","vitaminB12","folateDFE","folateFood","folateTotal",
   "folicAcid","vitaminC","vitaminD","vitaminE","vitaminK","choline"],
 "minerals": ["calcium","iron","magnesium","phosphorus","potassium","sodium","selenium","zinc",
   "copper","manganese","fluoride"],
 "carbDetails": ["starch","sucrose","glucose","fructose","lactose","maltose","galactose"],
 "sterols": ["phytosterols","betaSitosterol","campesterol","stigmasterol"],
 "other": ["alcoholEthyl","caffeine","theobromine","cholesterol","energyKcal","water","weightG",
   "ash","betaine","alkalinityPH"],
 "aminoAcids": ["alanine","arginine","asparticAcid","cystine","glutamicAcid","glycine","histidine",
   "isoleucine","leucine","lysine","methionine","phenylalanine","proline","threonine","tryptophan",
   "tyrosine","valine","serine","hydroxyproline"],
}
UNITS = {"macronutrients":"g","carbDetails":"g","sterols":"mg","aminoAcids":"g",
         "lipids":"g","minerals":"mg","vitamins":"mg"}
MG = {"vitaminA_RAE":"ug","caroteneBeta":"ug","vitaminB12":"ug","folateDFE":"ug","folateFood":"ug",
      "folateTotal":"ug","folicAcid":"ug","vitaminD":"ug","vitaminK":"ug","selenium":"ug",
      "cryptoxanthinBeta":"ug","caroteneAlpha":"ug","luteinZeaxanthin":"ug","lycopene":"ug",
      "retinol":"ug"}
OTHER_UNITS = {"energyKcal":"kcal","water":"g","weightG":"g","ash":"g","cholesterol":"mg",
               "caffeine":"mg","theobromine":"mg","alcoholEthyl":"g","betaine":"mg","alkalinityPH":""}
CATEGORY = {
 "grain":["Grains"], "legume":["Legumes"], "vegetable":["Vegetables"],
 "leafy-green":["Vegetables","leafy green"], "fruit":["Fruits"], "spice":["Spices and Herbs"],
 "medicinal":["Spices and Herbs","medicinal"], "dairy":["Dairy"], "oil-fat":["Fats and Oils"],
 "sweetener":["Sweets"], "seed":["Nuts and Seeds"], "dry-fruit-nut":["Nuts and Seeds"],
 "beverage":["Beverages"], "preparation":["Prepared Dishes"], "fermented":["Fermented Foods"],
 "animal":["Animal Products"], "salt-mineral":["Spices and Herbs","salt or mineral"],
 "regional":["Regional Foods"],
}

# ---------------------------------------------------------------- batch 1 ----
# Per 100 g edible portion. `src` says where the figure comes from and `spread`
# flags how far published sources disagree — that is the number to argue with,
# not mine. Values I could not source are simply absent, never zero.
VALUES = {
 "dravya.bajra": {"_src":"IFCT 2017 pearl millet; USDA millet raw for cross-check",
   "_spread":"iron varies 6-8 mg between IFCT 2017 and older ICMR tables",
   "macronutrients":{"protein":11.0,"fat":5.0,"carbohydrates":61.8,"fiber":11.5},
   "other":{"energyKcal":348,"water":8.9,"ash":1.4},
   "minerals":{"calcium":27,"iron":6.4,"magnesium":124,"phosphorus":289,"potassium":307,"zinc":2.8}},
 "dravya.ragi": {"_src":"IFCT 2017 finger millet",
   "_spread":"calcium is the headline figure and is consistently 300-364 mg",
   "macronutrients":{"protein":7.2,"fat":1.9,"carbohydrates":66.8,"fiber":11.2},
   "other":{"energyKcal":320,"water":10.9,"ash":2.0},
   "minerals":{"calcium":364,"iron":4.6,"magnesium":146,"phosphorus":210,"potassium":408,"zinc":2.5}},
 "dravya.barnyard-millet": {"_src":"IFCT 2017 barnyard millet",
   "_spread":"fibre 10-14 g depending on dehulling",
   "macronutrients":{"protein":6.2,"fat":2.2,"carbohydrates":65.5,"fiber":13.6},
   "other":{"energyKcal":307,"water":11.0,"ash":4.4},
   "minerals":{"calcium":20,"iron":5.0,"magnesium":82,"phosphorus":280}},
 "dravya.chickpea-black": {"_src":"IFCT 2017 bengal gram whole (kala chana)",
   "_spread":"protein 18-21 g across cultivars",
   "macronutrients":{"protein":20.5,"fat":5.3,"carbohydrates":54.6,"fiber":15.1},
   "other":{"energyKcal":360,"water":9.9,"ash":3.0},
   "minerals":{"calcium":202,"iron":4.6,"magnesium":79,"phosphorus":312,"potassium":808,"zinc":3.0}},
 "dravya.chana-dal": {"_src":"IFCT 2017 bengal gram dal (split, dehusked)",
   "_spread":"fibre much lower than whole chana because the husk is removed",
   "macronutrients":{"protein":21.6,"fat":5.6,"carbohydrates":57.4,"fiber":8.3},
   "other":{"energyKcal":372,"water":9.2,"ash":2.7},
   "minerals":{"calcium":56,"iron":5.3,"magnesium":139,"phosphorus":331,"potassium":720,"zinc":2.8}},
 "dravya.buffalo-ghee": {"_src":"IFCT 2017 ghee, buffalo",
   "_spread":"essentially pure milk fat; energy 897-900 kcal in every source",
   "macronutrients":{"protein":0.0,"fat":100.0,"carbohydrates":0.0},
   "other":{"energyKcal":900,"water":0.2,"cholesterol":250}},
 "dravya.camel-milk": {"_src":"published camel milk composition, FAO and Indian dairy literature",
   "_spread":"fat 2.0-4.5 g is genuinely variable by breed and season",
   "macronutrients":{"protein":3.0,"fat":3.0,"carbohydrates":4.4},
   "other":{"energyKcal":60,"water":88.5},
   "minerals":{"calcium":114,"iron":0.3,"phosphorus":86,"potassium":156,"sodium":59},
   "vitamins":{"vitaminC":3.5}},
 "dravya.black-rice": {"_src":"published black (purple) rice composition",
   "_spread":"anthocyanin content varies hugely; macros are stable",
   "macronutrients":{"protein":8.9,"fat":3.3,"carbohydrates":72.0,"fiber":4.9},
   "other":{"energyKcal":356,"water":11.5},
   "minerals":{"iron":2.4,"magnesium":143,"zinc":2.2}},
}
# ---------------------------------------------------------------------------


# minAgeMonths of 0 means "from birth", which is what 373 of these 376 carry
# today because only the honey rule ever fired. Classical Ayurveda does have a
# framework — exclusive stanyapana to about six months, then annaprashana, the
# first solid food, in the sixth month (Kashyapa Samhita is the paediatric text)
# — and it agrees with modern weaning practice on the floor. Where they disagree
# is honey: the classical texts give madhu to newborns, and modern paediatrics
# forbids it before twelve months because of infant botulism. This project
# already sides with modern safety there, correctly, and nothing below changes
# that. These are PROPOSALS carried in _review, never written into the record.
AGE_RULES = [
    (("medicinal", "salt-mineral"), 48,
     "pharmacologically active or mineral; not an infant food in any tradition"),
    (("dry-fruit-nut", "seed"), 48, "whole nuts and seeds are a choking risk"),
    (("spice",), 24, "pungent and heating; introduced late in every tradition"),
    (("fermented",), 24, "fermented and sour; also a histamine consideration"),
    (("animal",), 12, "animal food, later introduction"),
    (("beverage", "preparation"), 12, "compound preparation, often sweetened"),
    (("grain", "legume", "vegetable", "leafy-green", "fruit", "dairy",
      "oil-fat", "sweetener", "regional"), 6,
     "annaprashana in the sixth month, matching the modern weaning floor"),
]


def propose_age(d):
    cat = d.get("category")
    for cats, months, why in AGE_RULES:
        if cat in cats:
            return months, why
    return 6, "default weaning floor"


def blank(group):
    out = {}
    for f in SHAPE[group]:
        if group == "other":
            unit = OTHER_UNITS.get(f, "g")
        elif group == "vitamins":
            unit = MG.get(f, "mg")
        elif group == "minerals":
            unit = MG.get(f, "mg")
        else:
            unit = UNITS[group]
        out[f] = {"value": None, "unit": unit}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--store", required=True)
    ap.add_argument("--lipids-from", help="a foods.json to copy the 44-field lipid shape from")
    ap.add_argument("--out", default="dravya_foods.json")
    a = ap.parse_args()
    repo = os.path.expanduser(a.repo)

    dr = {it["id"]: it for f in glob.glob(f"{repo}/ayurveda-data/dravyas/batch-*.json")
          for it in json.load(open(f))["items"]}
    c = sqlite3.connect(os.path.expanduser(a.store))
    prof = {r[0]: r[1] for r in c.execute(
        "select ZFOODID, ZID from ZAYURVEDAPROFILE where ZKIND='dravya' and ZFOODID>=900000")}
    lip = SHAPE.get("lipids")
    if a.lipids_from:
        src = json.load(open(os.path.expanduser(a.lipids_from)))[0]
        SHAPE["lipids"] = list(src["lipids"])
    elif not lip:
        SHAPE["lipids"] = []

    out, filled = [], 0
    for fid, did in sorted(prof.items()):
        d = dr.get(did, {})
        desc = "\n\n".join(x for x in (d.get("prabhava"), d.get("preparation")) if x)
        row = c.execute("select ZNAME, ZMINAGEMONTHS from ZFOODITEM where ZID=?", (fid,)).fetchone()
        # category and diets are deliberately absent. The app does not use
        # category, and default diets were dropped on the reasoning that
        # Ayurveda is itself a dietary system and a fixed diet label can
        # contradict a constitution.
        prop, why = propose_age(d)
        rec = {"id": fid, "name": row[0], "dravyaId": did,
               "minAgeMonths": row[1], "allergens": [], "desctiption": desc}
        for g in ("macronutrients","lipids","vitamins","minerals","aminoAcids",
                  "carbDetails","sterols","other"):
            rec[g] = blank(g) if g in SHAPE else {}
        v = VALUES.get(did)
        if v:
            filled += 1
            for g, fields in v.items():
                if g.startswith("_"): continue
                for k, val in fields.items():
                    if k in rec.get(g, {}): rec[g][k]["value"] = val
            rec["_review"] = {"source": v.get("_src"), "spread": v.get("_spread"),
                              "status": "proposed — verify before ingest",
                              "currentMinAgeMonths": row[1],
                              "proposedMinAgeMonths": prop, "ageReason": why}
        else:
            rec["_review"] = {"source": None, "spread": None,
                              "status": "NOT YET SOURCED — every nutrient is null, not zero",
                              "currentMinAgeMonths": row[1],
                              "proposedMinAgeMonths": prop, "ageReason": why}
        out.append(rec)
    json.dump(out, open(a.out, "w"), indent=1, ensure_ascii=False)
    print(f"wrote {a.out}: {len(out)} dravya foods, {filled} with proposed nutrition, "
          f"{len(out)-filled} awaiting sourcing")
    print(f"description present on {sum(1 for r in out if r['desctiption'])} of {len(out)}")


if __name__ == "__main__":
    main()
