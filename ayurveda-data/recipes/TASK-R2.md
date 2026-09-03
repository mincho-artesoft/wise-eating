# TASK R2 — Everyday & International Recipes (executor: Codex / Sonnet 4.5+)

R1 is approved. Same rules, format, validation and process as
`ayurveda-data/recipes/TASK-R1.md` — read it first. This file lists only what
changes for R2.

## Mission

Batches r07–r18, 50 recipes each = 600 recipes. Category `everyday` (Indian
daily cooking) or `international`. All recipes LACTO-VEGETARIAN (no meat, fish
or eggs — the animal-food dravyas don't exist yet).

## Coverage plan (50 each)

- r07: everyday Indian mains — sabzi-dal combos, pulaos, simple curries, khichdi variants beyond r01
- r08: everyday Indian tiffin/breakfast — parathas, chillas, uttapam, pongal, sevai
- r09: soups & stews — international vegetable, lentil, grain soups, dosha-tagged
- r10: warm grain bowls & salads — quinoa/millet/rice bowls, oil-lemon dressings
- r11: Mediterranean — mezze, pilafs, bakes, bean dishes
- r12: East/Southeast Asian — stir-fries, curries, noodle and rice dishes (tofu/tempeh mains)
- r13: Latin American — beans, corn dishes, stews, salsas
- r14: Continental comfort — pastas, gratins, roasted-vegetable mains
- r15: international breakfasts — porridges, pancakes, granolas (warm preparations preferred)
- r16: snacks & sides — roasted chickpeas, energy balls, dips, breads
- r17: drinks & smoothies — plant-milk based; any fruit+dairy combination MUST carry a viruddhaFlag
- r18: international desserts — fruit-based, grain-based, dairy sweets

## R2-specific rules (in addition to R1's hard rules)

1. IDs must not collide with r01–r06 (extract existing recipe ids first).
2. `viruddhaFlags` are now permitted and REQUIRED wherever a modern dish breaks a
   traditional rule (fruit+dairy smoothies, cheese+tomato bakes, etc.). Flag as a
   short string, e.g. "fruit combined with dairy (traditional viruddha)". The
   `guidance` must offer the compliant variant (e.g., "use almond milk instead").
3. Nightshade-heavy and fusion dishes are fine — score doshas honestly rather than
   avoiding the ingredients.
4. International dishes still need season/timeOfDay tags and per-dosha guidance.
5. Where no dravya exists for a signature ingredient (e.g., nutritional yeast),
   bind fdcId from the store, or choose a different ingredient. Never invent IDs.
   Keep ≥50% dravya-linked per recipe (validator enforces).

## Process & report

Same loop as R1: one batch → validate (`python3 ayurveda-data/validate.py --store /tmp/pre`)
→ commit → next. Do not push. Final report appended to
`ayurveda-data/recipes/REPORT-R2.md` with the same sections as R1's report, plus:
count of viruddha-flagged recipes per batch.
