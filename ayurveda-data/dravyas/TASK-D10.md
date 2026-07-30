# TASK D10 — Dravya pre-drafts for batches 10–30 (executor: Codex / Sonnet 4.5+)

You prepare the MECHANICAL half of the remaining ~540 dravyas. The director
(Fable 5) authors the Ayurvedic facets on top of your pre-drafts. You do NOT
write Ayurvedic properties.

## Inputs

- Worklist: `ayurveda-data/canon/canon-*.json` (batches 5–12 stubs) and
  `ayurveda-data/canon/DRAVYA-CANON-LIST-V1.md` (batches 1–4 names).
- Already covered: every `id` in `ayurveda-data/dravyas/batch-*.json` (210 items).
  Skip those (match by id AND by name similarity — some ids differ slightly,
  e.g. canon `dravya.ginger` vs authored `dravya.ginger-fresh`; when unsure,
  list the pair in the report instead of duplicating).
- USDA store: `cat Ayura/preseeded_db.store.gz.part-aa Ayura/preseeded_db.store.gz.part-ab > /tmp/pre.gz && gunzip -f /tmp/pre.gz`
  → SQLite at /tmp/pre, table ZFOODITEM (ZID, ZNAME). It contains many Indian
  items — search English, Hindi and Sanskrit names before giving up.

## Output

Files `ayurveda-data/dravyas/predraft/predraft-NN.json` (25 items each, grouped
by canon category order: 10 animal foods, 11 classical preparations, 12 medicinal,
13–14 vegetables/gourds, 15–16 fruits, 17 grains/legumes, 18+ regional/beverages/
fermented — follow PROGRESS.md order). Per item:

```json
{
  "id": "dravya.<kebab>",
  "name": "English name",
  "sanskrit": "Sanskrit/Hindi or null",
  "aliases": ["..."],
  "category": "one of the 19 categories in validate.py",
  "canonHints": {"vpk": [0,0,0], "virya": "heating", "note": "from canon stub if present"},
  "usda": [{"fdcId": 123, "name": "exact ZNAME from store", "tier": "exact|near"}],
  "servings": [{"label": "1 cup", "grams": 240}],
  "_facetsPending": true
}
```

Rules:
1. Every fdcId MUST exist in the store and `name` must be the verbatim ZNAME.
   Verify programmatically — invented IDs are grounds for rejection.
2. If no plausible USDA row exists, set `"usda": []` and add `"usdaNote"`
   explaining what you searched. Do not force bad matches; `near` must be the
   same food in a different form, not a lookalike.
3. Servings: standard reference amounts (measure conventions from existing
   batches 01–09).
4. No Ayurvedic fields beyond copying canon's vpk/virya into `canonHints`.
5. Do not modify `dravyas/batch-*.json`, the validator, or anything outside
   `ayurveda-data/dravyas/predraft/`.

## Verification you must run

Write `predraft/check.py`: JSON parses; ids unique across predrafts AND against
authored batches; fdcIds exist in store; categories valid; no item missing
name/category/servings. Paste its output in the report.

## Process & report

One file at a time, commit each ("Dravya predraft NN: <category> (25 items)").
Do not push. Final report `ayurveda-data/dravyas/predraft/REPORT-D10.md`:
items produced, USDA match rate (exact/near/none) per file, ambiguous
id-overlap pairs, unmatched items list.
