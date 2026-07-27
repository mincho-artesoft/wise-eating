#!/usr/bin/env python3
"""Director reference resolver for food-roles.json rev3.

NOT the shipping implementation — this exists so the director can measure a rule
change against the real catalogue before asking anyone to build it. Codex's Swift
resolver is the real one; this is the second, independent derivation of the same
spec, which is the point (see the cross-derivation gate G3).

Usage:  python3 ref_resolve.py <path to ayurveda-data> <path to foods.json>
"""
import json, re, sys, collections, random

BASE = sys.argv[1] if len(sys.argv) > 1 else "."
FOODS = sys.argv[2] if len(sys.argv) > 2 else "../WiseEating/Legacy/foods.json"

RULES = json.load(open(f"{BASE}/rules/food-roles.json"))
_SING = {}


def variants(w):
    """Every token this one may legitimately equal under the plural rule.

    Permissive on purpose: it feeds the prefilter only. `teq` remains the exact
    test. An earlier version canonicalised instead, which turned `sardines` into
    `sardin` and silently stopped it matching `sardine` — a fast path that
    changed answers is worse than no fast path.
    """
    v = _SING.get(w)
    if v is None:
        out = {w, w + "s", w + "es"}
        if w.endswith("y") and len(w) > 2:
            out.add(w[:-1] + "ies")
        if w.endswith("ies") and len(w) > 4:
            out.add(w[:-3] + "y")
        if w.endswith("es") and len(w) > 3:
            out.add(w[:-2])
        if w.endswith("s") and len(w) > 2:
            out.add(w[:-1])
        v = _SING[w] = out
    return v

IRREGULAR = RULES["matching"]["pluralTolerance"]["irregularPlurals"]
IRR = {(k, v) for k, v in IRREGULAR.items()}


def segments(s):
    s = s.lower()
    s = re.sub(r"\([^)]*\)", " ", s)
    return [re.sub(r"[^a-z0-9]+", " ", seg).split() for seg in s.split(",")]


def norm(s):
    return [t for seg in segments(s) for t in seg]


def teq(a, b):
    if a == b:
        return True
    for x, y in ((a, b), (b, a)):
        if y == x + "s" or y == x + "es" or (x.endswith("y") and y == x[:-1] + "ies"):
            return True
    return (a, b) in IRR or (b, a) in IRR


_PT = {}


def ptok(phrase):
    p = _PT.get(phrase)
    if p is None:
        p = _PT[phrase] = norm(phrase)
    return p


def seq(toks, phrase):
    p = ptok(phrase)
    if not p:
        return 0
    for i in range(len(toks) - len(p) + 1):
        if all(teq(p[j], toks[i + j]) for j in range(len(p))):
            return len(p)
    return 0


def group_hit(toks, grp):
    return all(any(teq(g, t) for t in toks) for g in grp)


def resolve(name, category=None, dravya_cat=None, recipe_meal=None, is_recipe=False):
    toks = norm(name)
    first = segments(name)[0] if segments(name) else []
    tset = set().union(*(variants(t) for t in toks)) if toks else set()
    best = None
    for r in RULES["rules"]:
        role, prio = r["role"], r["priority"]
        scope = first if r.get("matchScope") == "firstSegment" else toks
        if any(group_hit(toks, g) for g in r.get("vetoTokens", [])):
            continue
        hit, L = None, 0
        if "preparedIndicators" in r:                      # X-DRY-MIX evaluation order
            if any(group_hit(toks, g) for g in r.get("tokenGroups", [])):
                neg = r.get("negatedIndicator")
                if (neg and seq(toks, neg)) or not any(
                    seq(toks, p) for p in r["preparedIndicators"]
                ):
                    hit, L = role, 2
        elif role == "<fromCategoryMap>":
            if category and category in r["categoryMap"]:
                hit, L = r["categoryMap"][category], 1
        elif role == "<fromDravyaMap>":
            if dravya_cat and dravya_cat in r["dravyaMap"]:
                hit, L = r["dravyaMap"][dravya_cat], 1
        elif role == "<fromMealMap>":
            if is_recipe and recipe_meal in r["mealMap"]:
                hit, L = r["mealMap"][recipe_meal], 1
        else:
            for p in r.get("phrases", []):
                pt = ptok(p)
                if not pt or pt[0] not in tset:
                    continue
                L = max(L, seq(scope, p))
            for g in r.get("tokenGroups", []):
                if group_hit(scope, g):
                    L = max(L, len(g))
            if L:
                hit = role
        if hit:
            k = (prio, L)
            if best is None or k > best[0]:
                best = (k, hit, r["id"])
    return (best[1], best[2]) if best else ("other", "<default>")


PP = RULES["recipePostPass"]
_FORMS = sorted(
    ((ptok(p), role) for role, ps in PP["forms"].items() for p in ps),
    key=lambda x: -len(x[0]),
)


def resolve_recipe(title, meal, n_ingredients=2, n_steps=1):
    """Roles for authored composed dishes. Commodity rules are skipped entirely."""
    if n_ingredients < 2 or n_steps < 1:
        return None, "<not-composed>"
    if meal == "drink":
        return "beverage", "A-RECIPE-MEAL"
    if meal == "dessert":
        return "sweet", "A-RECIPE-MEAL"
    t = re.split(r"\bwith\b", title, maxsplit=1)[0]
    toks = norm(t) or norm(title)
    for p, role in _FORMS:                      # head-final: match the TRAILING tokens
        if len(p) <= len(toks) and all(teq(p[i], toks[len(toks) - len(p) + i]) for i in range(len(p))):
            if p == ["masala"] and n_ingredients > 6:
                continue                     # a masala with many ingredients is a curry, not a blend
            return role, f"POSTPASS-form:{role}"
    return ("side" if meal == "snack" else "main"), "POSTPASS-default"


F = RULES["flags"]["requiresCooking"]
HEAD, VETO = set(F["dryStapleHeadwords"]), set(F["veto"])
STATE = {"raw", "dry", "dried", "uncooked", "unprepared"}


def requires_cooking(name):
    t = norm(name)
    if any(any(teq(v, x) for x in t) for v in VETO):
        return False
    if any(group_hit(t, g) for g in F["positive"]["tokenGroups"]):
        return True
    return any(any(teq(h, x) for x in t) for h in HEAD) and any(
        any(teq(s, x) for x in t) for s in STATE
    )


if __name__ == "__main__":
    rows = json.load(open(FOODS))
    out = collections.Counter()
    byrule = collections.Counter()
    cook = 0
    for r in rows:
        cat = (r.get("category") or [None])[0]
        role, rid = resolve(r["name"], category=cat)
        out[role] += 1
        byrule[rid] += 1
        if requires_cooking(r["name"]):
            cook += 1
    n = len(rows)
    print(f"catalogue rows: {n}")
    print("role distribution:")
    for k, v in out.most_common():
        print(f"   {v:>6}  {100*v/n:>5.2f}%  {k}")
    print(f"\nrequiresCooking rows: {cook} ({100*cook/n:.2f}%)")
    print(f"unresolved `other`: {out['other']} ({100*out['other']/n:.2f}%)")
    print("\ntop firing rules:")
    for k, v in byrule.most_common(12):
        print(f"   {v:>6}  {k}")
