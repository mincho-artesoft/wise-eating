# Content authoring progress

> **Orientation for new sessions/models: read `/PROJECT-HANDBOOK.md` (repo root)
> first.** It is the knowledge-transfer document — architecture, decisions,
> number registry, working process, milestone ledger. Update it after every task.

## Recipes: COMPLETE ✅

**1,500 recipes done and director-verified** (batches r01–r30): 300 classical
(R1), 600 everyday/international (R2), 600 completion tier (R3 + R3-FIX).
All validated (`validate.py --store`), viruddha-flagged where required,
qualityState aiDraft pending expert review. Task packets and reports in
`recipes/TASK-R*.md`, `recipes/REPORT-R*.md`.

## Dravyas: COMPLETE ✅ (714 authored; 750 target reachable via review top-up)

**All 30 predrafts promoted to `dravyas/batch-01..30.json`, validator green at
714 dravyas + 1,500 recipes.** ~15 predraft items were skipped as duplicates of
already-authored dravyas (documented in batch commit messages and reviewNotes).
A final ~36-item batch-31 can be selected during expert review to hit 750.

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
| 12 | Medicinal rasayanas & bitters (triphala trio, ashwagandha, neem…) | 25 |
| 13 | Vegetables & gourds (parwal, suran, mooli, brinjal, raw banana…) | 25 |
| 14 | Vegetables II — pods, flowers, tubers, shoots (sem, bamboo, kachnar…) | 25 |
| 15 | Fruits I (mango, banana, draksha, bael, jamun, phalsa…) | 25 |
| 16 | Fruits II & dry fruits (fig, dadima, ikshu, makhana, munakka…) | 24 |
| 17 | Rices, millets, flours, mung (rakta shali, navara, kodrava…) | 24 |
| 18 | Regional specials (ker-sangri, mahua, tulsi/nettle, vinegars, betel nut⚠) | 25 |
| 19 | Regional dairy + classical beverages (yak dairy, ushnodaka, sherbets, chai) | 25 |
| 20 | Juices, spice waters, regional ferments (kanji, pakhala, gundruk, neera) | 25 |
| 21 | Regional preparations I (idli batter, aranala, mamsa rasa, dadhyodana) | 25 |
| 22 | Snacks, festival sweets, medicinals (vataka, shrikhand, shilajit, gulkand) | 25 |
| 23 | Cooling roots & murabbas (sariva, ushira, five murabbas) | 25 |
| 24 | Legume varga (masha, chanas, kulattha, saktu, rasona) | 25 |
| 25 | Legumes II + spice blends (trikatu, chaturjata, panch phoron, shahi jeera) | 25 |
| 26 | Rare spices & aromatics (betel leaf, karpura, tumburu, goda masala) | 25 |
| 27 | Spices II + leafy greens (hingvastak, bathua, gongura, moringa leaf) | 22 |
| 28 | Greens II, dry fruits, char magaz seeds (upodika, chhuara, krishna tila) | 21 |
| 29 | Dairy varga + specialty oils (mahisha/ushtra milk, mastu, khoya, eranda) | 19 |
| 30 | Oils II, sweetener ladder, salts & gums (nolen gur, purana madhu, vark, vanaspati⚠) | 19 |

⚠ Engine-exclusion items (display with health warning, NEVER recommend):
**betel nut** (batch 18, carcinogen) and **vanaspati** (batch 30, trans fats).

Notes: predraft-16's langsat placeholder dropped per D10 review; scaffold
servings corrected to realistic per-piece grams during authoring; reviewNotes
mark every place classical sources disagree or near-duplicates need reviewer
cross-linking.

## Validation

`python3 ayurveda-data/validate.py --store /tmp/pre` (store from
`cat WiseEating/preseeded_db.store.gz.part-aa WiseEating/preseeded_db.store.gz.part-ab > /tmp/pre.gz && gunzip -f /tmp/pre.gz`).
Current status: **714 dravyas, 1,500 recipes — all checks pass.**

## Next milestones

1. **Engineering track COMPLETE** — D6 (models+seeder), D34 (all 12,601 foods
   classified), D8/D8.1/D8.2 (UI end to end incl. computed tier + editors),
   D9 (engineExcluded enforcement). See PROJECT-HANDBOOK.md §6 ledger for
   details, commits, and residuals.
2. **Expert review — the remaining item.** Work aiDraft→reviewed across
   dravyas/recipes/rules, resolve all reviewNote flags, optional batch-31
   top-up to 750. Director can generate a reviewer packet on request.
3. **Residual founder checks** (minutes, not milestones): physical-device AI
   generation run (D9 G3 environmental residual), Computed/User card
   screenshots, VoiceOver + dark-mode smoke.
4. **Optional future scope** (new product decisions, not leftovers): dosha-based
   search filters, prakriti assessment/personalization — best after expert review.


Git note (sandbox sessions): stale locks workaround — `GIT_INDEX_FILE=/tmp/ayur_index`,
`git add` → `write-tree` → `commit-tree` → write SHA to `.git/refs/heads/main`.
On the Mac: `rm -f .git/*.lock .git/refs/heads/main.lock && git reset`.
