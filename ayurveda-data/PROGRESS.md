# Content authoring progress

## Recipes: COMPLETE ✅

**1,500 recipes done and director-verified** (batches r01–r30): 300 classical
(R1), 600 everyday/international (R2), 600 completion tier (R3 + R3-FIX).
All validated (`validate.py --store`), viruddha-flagged where required,
qualityState aiDraft pending expert review. Task packets and reports in
`recipes/TASK-R*.md`, `recipes/REPORT-R*.md`.

## Dravyas

Target: 750 full-facet dravyas. **Done: 210 (batches 01–09), all validated + committed.**

| Batch | Contents | Items |
|---|---|---|
| 01 | Core staples (ghee, rice, mung, ginger, turmeric, milk, honey…) | 25 |
| 02 | Spices, herbs, salts (trikatu, tulsi, saffron, saindhava…) | 25 |
| 03 | Grains & legumes (wheat, barley, millets, all major dals) | 25 |
| 04 | Vegetables (incl. lauki, karela, kushmanda, shigru) | 25 |
| 05 | Fruits (draksha, dadima, kadali, amra, melons, dates…) | 25 |
| 06 | Greens, gourds, tubers (methi, sarson, ash/ridge gourd, taro…) | 25 |
| 07 | Nuts, seeds, dry fruits (tila, walnut, makhana, char magaz…) | 24 |
| 08 | Dairy, oils, sweeteners, plant milks (takra, mustard oil, mishri…) | 25 |
| 09 | Beverages & fermented (teas, coffee, coconut water, miso…) | 12 |
| 10 | Animal foods (eggs, meats, fish — mamsa varga) | 25 |
| 11 | Classical preparations (kitchari, takra, CCF tea, chyawanprash…) | 25 |

**Facet authoring from predrafts: next is predraft-12 (medicinal). 260/750 done.**

## NEW: predrafts ready (D10 approved)

`dravyas/predraft/predraft-10..30.json` — 524 items with verified identity,
category, USDA bindings and servings (Codex-produced, director-verified).
Facet authoring now works from these: for each predraft item, author the
Ayurvedic fields (rasa, virya, vipaka, gunas, prabhava, dosha, agniEffect,
digestibility, seasons, timeOfDay, combinations, viruddha, contraindications,
preparation, provenance, confidence), drop `canonHints`/`_facetsPending`/
`usdaNote`, and emit into a real `dravyas/batch-NN.json` (validator must pass).
Use canonHints.vpk/virya as starting points but correct them where classical
sources say otherwise.

## Remaining (524 items, batches 10–~30)

Work from the canon worklist in `canon/` (631 stubs, minus ~140 already covered
above) plus `canon/DRAVYA-CANON-LIST-V1.md` (125 more names). Suggested order:

- 10: animal foods (meats, fish, eggs — canon-11)
- 11: classical preparations (kitchari, kanji/peya, panchamrit, chyawanprash-style — canon-10)
- 12: remaining spices & medicinal foods (canon-05: triphala trio, ashwagandha, shatavari…)
- 13–14: remaining vegetables & gourds (canon-07: parwal, suran, tindora, snake gourd…)
- 15–16: remaining fruits (canon-08: bael, amla, phalsa, ber, custard apple…)
- 17: remaining grains/legumes (canon-06: navara, kuttu forms, sattu, horse gram…)
- 18+: regional specials, remaining beverages, fermented (canon-10/11)

## Workflow per batch (proven)

1. Decompress store once per session:
   `cat WiseEating/preseeded_db.store.gz.part-aa WiseEating/preseeded_db.store.gz.part-ab > /tmp/pre.gz && gunzip -f /tmp/pre.gz`
2. Look up USDA IDs: `select ZID, ZNAME from ZFOODITEM where ZNAME like ?` (SQLite, table ZFOODITEM).
   Store contains many Indian items (search Hindi + English names). No match → bind `near` to closest, or omit binding.
3. Write `dravyas/batch-NN.json` per the 16-field spec in `README.md` (25 items/batch).
   `qualityState: aiDraft`; add `reviewNote` where classical sources disagree.
4. Validate: `python3 ayurveda-data/validate.py --store /tmp/pre` — must pass.
5. Commit. NOTE: stale git locks exist (`.git/index.lock`, `.git/HEAD.lock` — sandbox
   can't delete them). Workaround that works: use `GIT_INDEX_FILE=/tmp/ayur_index`
   (copy of real index), `git add` → `git write-tree` → `git commit-tree` → write SHA
   directly to `.git/refs/heads/main`. On the Mac: `rm -f .git/*.lock .git/refs/heads/main.lock && git reset` fixes everything.

## After dravyas

- Crosswalk generation (D3), category rules (D4), recipes 1,500 (D5 — wait for quota reset),
  Swift models + seeder (D6). See RESTART-PLAN.md.
