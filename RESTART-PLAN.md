# Ayurveda Yoga & Meditations — Restart Plan (data-first, on wise-eating)

Approved 2026-07-21. Base: this repo (wise-eating original). App structure is
preserved; the database is extended first, visualization later.

## Decisions locked

1. Base = wise-eating original (12,601-food store, search, media, recipe machinery).
2. All USDA foods get Ayurvedic properties via three tiers: classical (750
   hand-authored dravyas) → derived (crosswalk inheritance) → estimated
   (category rules). Tier always visible in UI.
3. Viruddha/forbidden foods: warn, don't block (badges + explanations).
4. Recipes: 1,500 AI-authored, classical-first, ingredients linked to
   dravyas/USDA IDs, dosha effect computed from ingredients.

## Current state

- `ayurveda-data/` created: spec (README), canon index rescued from the
  previous project (631 dravya stubs + 133 recipe stubs + 125 named in
  DRAVYA-CANON-LIST-V1), 10 + 25 seed exemplars.
- `dravyas/batch-01.json`: first 25 full-facet dravyas, validated — all enum
  ranges pass and every USDA binding verified against the actual preseeded
  store (ZFOODITEM.ZID). Store even contains Indian items (jaggery, hing,
  ajwain), so bindings are largely `exact`.
- Preseeded store confirmed: 12,601 foods, 0 recipes (recipe machinery unused
  — `isRecipe`, `IngredientLink` exist and work).

## Milestones

| # | Milestone | Output |
|---|---|---|
| D1 | Pipeline + spec + batch 01 | done |
| D2 | Dravya batches 02–30 | 750 full-facet dravyas (25/batch, validated per batch) |
| D3 | USDA→dravya crosswalk | name-match script + reviewed crosswalk.csv (~2–4k generic rows) |
| D4 | Category estimation rules | `rules/` for remaining processed/branded foods |
| D5 | Recipe batches 01–30 | 1,500 recipes (50/batch), classical first |
| D6 | Swift: schema + seeder | `AyurvedaProfile` model (additive), recipes as `FoodItem(isRecipe)` + `IngredientLink`, one-time seeder from bundled `ayurveda_seed.json.gz` |
| D7 | Validation suite | referential integrity, ranges, fdcId existence, duplicate detection — run in CI |
| D8 | Strip barcode/fitness + Ayurveda UI | separate phase, after data is in |

D2–D5 are pure content sessions (no code risk, resumable batch by batch).
D6 is the only code milestone needed to make data live in the app.

## Quality policy

Everything AI-authored starts `aiDraft` with provenance + confidence per item;
entries where classical sources disagree carry `reviewNote`. An expert review
pass before App Store release is recommended for health-adjacent claims.
