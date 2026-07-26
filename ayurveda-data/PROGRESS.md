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

WE-2 adds build-derived nutrition without changing authored content: all 1,500
recipes resolve to full ingredient coverage (0 estimated, 0 none) across energy,
macros/fiber/sugars, 22 vitamins, and 11 minerals, stored per serving and per
100g. The Classic Mung Kitchari independent gate is 379.67 kcal/serving.

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

The reconstructed store is the full build-time artifact: 14,484
foods, 2,214 seed-v5 canonical profiles, 2,305 links, 10,571 recipe ingredient
links, 1,500 full recipe panels, and a version-5 search cache for exactly 14,484
foods, including canonical facets on 2,214 rows. Fresh install performs zero
Ayurveda inserts/updates and no index rebuild. WE-8c is complete; see
`REPORT-WE8c.md`.

WE-3 restyles the read-only Ayurveda card with semantic center-zero dosha
scales, wrapping property chips, always-visible warning rows, explicit
light/dark tokens, and largest-Dynamic-Type layouts. The four deterministic
light/dark × default/accessibility snapshots and all contrast evidence are in
`REPORT-WE3.md`; editor behavior and content remain unchanged.

WE-4 upgrades the shipped search cache to version 4 with 64 canonical Ayurveda
facet keys / 20,114 assignments on exactly the 2,214 seeded profiles. Natural
virya, dosha, agni/digestibility, season/ritu, and category speech plus
`ushna`, `sheeta`, and `deepana` compose with existing text/nutrient queries.
All 25 legacy golden queries remain exact; plain USDA rows have no facets;
fresh install still performs zero inserts and no rebuild. See `REPORT-WE4.md`.

WE-5 closes the bounded FoodSearch display/parser edges without changing the
index or content. Searched nutrient columns now always render with distinct
missing (`—`) and stored-zero (`0.0`) states; Tokenizer and ConstraintMapper
nutrients share query-ordered display context; pH boundary, unknown-data
exclusion counting, and sort-only visibility are centralized; and command
heuristics require word/token boundaries. All 25 WE-4 goldens remain exact and
the WE-4 median-latency budget remains green. The active engine source is
`WiseEating/FoodSearch/VM/SmartFoodSearchEngine.swift`; `WiseEating/Legacy/`
was not touched. See `REPORT-WE5.md`.

WE-6 signpost profiling re-established the cold-process baseline at 3.405s and
identified the persisted search-index decode as the dominant 1.591s launch
phase. The same version-checked cache now loads on first FoodSearch use instead
of before the root view. Median launch is 1.662s (−51.2%); the first lazy
load-plus-query returns real results in 1.691s, all 25 goldens remain exact, and
the worst warm-query median delta is +3.4%. Fresh install remains zero Ayurveda
inserts/updates and no search rebuild. See `REPORT-WE6.md`.

WE-7 audited every shipping member under `WiseEating/Legacy/`. Nine Swift files
were compiler inputs but consisted entirely of 2,288 commented lines, declared
no compiled symbols, and had no static, interface, Objective-C runtime, selector,
or string-based inbound reference; that single dead cluster was removed. The
five JSON resources remain live runtime fallback inputs. Debug and Release
builds, 38/38 tests, 25/25 goldens, all 15 WE-5 border methods, the latency
budget, and fresh-install gates remain green; cold launch remeasured at 1.504s
median. See `REPORT-WE7.md`.

WE-8 derives conservative, expert-reviewable safety/search metadata at build
time for all 2,214 canonical profiles. The 1,500 recipes now receive ingredient
union allergens, ingredient intersection diets, maximum ingredient age, and
the 12-month honey floor; every derivation is `scaffold-default` with mandatory
review provenance. The final artifact has 1,182 allergen-bearing recipes and
exactly 10,571 IngredientLinks across all 1,500 owners. The founder-approved
`vegan curry` golden history is explicit, all 25 updated legacy goldens plus two
negative safety goldens pass in production, and the worst search-latency delta
is +4.3%. Fresh install remains zero-insert/no-rebuild and cold launch is 1.592s
median. See `REPORT-WE8.md`.

WE-8c implements provenance-gated age enforcement: legacy-import
ingredient floors remain unchanged for display, while only the authored
12-month honey floor hard-filters canonical dravyas and recipes. The exact
recipe visibility gates (1,496/1,500/1,500 at 9/24/60 months), display
histogram, 25+2 goldens, 62 tests, deterministic v5 artifacts, fresh install,
and Debug/Release builds pass. A same-session N=12 ABAB re-measurement records
WE-8c at 1.607s median versus WE-8b at 1.569s, with a +0.048s paired median
delta. It passes the absolute 1.700s launch ceiling and is below the 1.650s
profiling-paydown trigger. The pre-existing shipping-`main` USDA age issue is
recorded separately in `ISSUE-MAIN-AGE-GATING.md`. See `REPORT-WE8c.md`.

FC-1 adds a deterministic food-concept substrate without wiring a product
consumer: 25 director-authored concepts and 75 aliases are matched at build
time across all 14,484 catalogue rows, persisted in a 29,740-byte artifact, and
served by a lazy immutable Swift lookup. After the director's rev2 exclusion
corpus correction, the non-contested must-exclude and must-not-exclude gates
have zero resolved failures; eight contested cases are reported separately and
remain founder/vaidya decisions. All 71 tests, 25+2 search goldens, validator,
Debug/Release builds, fresh no-insert/no-rebuild, and two-build determinism
pass. Same-session N=10 ABAB launch is 1.584s median versus 1.584s at the branch
point. G12's 1,217 WE-8 disagreements reduce to five systematic causes covering
93.9% of rows. See `REPORT-FC1.md`.

INT-1 integrates the complete MP-1→MP-3c chain and FC-1/FC-1b into
`ayurveda-app` without rebasing or squashing. The combined suite reconciles at
95/95 (62 shared + 23 MP + 9 FC + one INT launch regression), all 25+2 search
goldens remain exact, the validator and resolution/exclusion corpora retain
their branch-local values, and rebuilt seed/preseed/concept artifacts are
deterministic. Fresh install remains zero-insert/no-rebuild. The initial
integrated 1.697s launch median triggered a bounded full-seed-decode paydown;
final launch is 1.461s median versus 1.654s at `d393bda`. Physical-device
generation evidence is not waived: every outstanding item and commit endpoint
is recorded in `DEFERRED-VALIDATION.md`. See `REPORT-INT1.md`.

## Next milestones

1. **Host/simulator engineering integration through INT-1 COMPLETE** — D6 (models+seeder), D34 (all 12,601 foods
   classified), D8/D8.1/D8.2 (UI end to end incl. computed tier + editors),
   D9 (engineExcluded enforcement), WE-2 (full recipe nutrition + build-time
   projection/search cache), WE-3 (founder-approved read-only display card),
   WE-4 (canonical indexed Ayurveda search facets), and WE-5 (FoodSearch
   border-case closure), WE-6 (cold-launch profiling + lazy index load), and
   WE-7 (legacy target audit + proven-dead Swift cluster removal), and WE-8
   (conservative derived safety metadata + IngredientLink parity), and WE-8c
   (provenance-gated age enforcement), plus FC-1 (deterministic food-concept
   ontology and unused runtime lookup service), and INT-1 (unsquashed MP/FC
   branch integration, deterministic artifact refresh, and launch paydown).
   See PROJECT-HANDBOOK.md §6 ledger and `REPORT-WE2.md` / `REPORT-WE3.md` /
   `REPORT-WE4.md` / `REPORT-WE5.md` / `REPORT-WE6.md` for gates, timing,
   screenshots, accessibility, search, `REPORT-WE7.md` for legacy audit
   evidence, `REPORT-WE8.md` for safety derivation/audit evidence, and
   `REPORT-FC1.md` for concept gates and WE-8 disagreement triage, and
   `REPORT-INT1.md` for integrated evidence.
2. **Physical-device validation — explicitly pending.** Run the MP-1 nine-run
   matrix/G6/G8, MP-2 twenty-food error table/runtime counters, and MP-3 runtime
   zero-model-call confirmation exactly as registered in
   `DEFERRED-VALIDATION.md`. Integration did not waive these gates.
3. **Expert review — the remaining content item.** Work aiDraft→reviewed across
   dravyas/recipes/rules, resolve all reviewNote flags, optional batch-31
   top-up to 750. Director can generate a reviewer packet on request.
4. **Residual founder checks** (minutes, not milestones): physical-device AI
   generation run (D9 G3 environmental residual), Computed/User card
   screenshots, and physical-device VoiceOver smoke. WE-3's deterministic
   default/largest-type light/dark matrix is complete.
5. **Optional future scope** (new product decisions, not leftovers): visible
   search facet chips, prakriti assessment/personalization, physical-device
   launch signpost capture, and off-main first-search index decoding — best
   after expert review.


Git note (sandbox sessions): stale locks workaround — `GIT_INDEX_FILE=/tmp/ayur_index`,
`git add` → `write-tree` → `commit-tree` → write SHA to `.git/refs/heads/main`.
On the Mac: `rm -f .git/*.lock .git/refs/heads/main.lock && git reset`.
