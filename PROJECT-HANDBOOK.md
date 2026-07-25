# PROJECT HANDBOOK — Ayurveda app built on WiseEating
**Read this first. It is the knowledge-transfer document for anyone (human or AI)
taking over direction of this project. Update it at the end of every milestone —
that is a standing rule baked into all task packets.**
Last updated: 2026-07-26 (WE-8c complete; same-session N=12 cold-launch
median 1.607s under the absolute 1.700s ceiling — see
`ayurveda-data/REPORT-WE8c.md`).

## 1. Mission and the two applications

One repository, two products:
- **`main` branch = WiseEating, the original app, pristine** (tip `9a5429d`,
  pre-Ayurveda). Never receives Ayurveda commits. Builds and ships as-is.
- **`ayurveda-app` branch = the new Ayurveda application**: WiseEating's proven
  engine (12,601-food USDA database, search, HEVC media, SwiftData) extended with
  a full Ayurvedic knowledge layer. All new work happens here. Single-author
  history: `Mincho Milev <mincho.milev@gmail.com>`.

## 2. What has been built (architecture in one pass)

**Content (source of truth = JSON in `ayurveda-data/`):**
- **714 dravyas** (`dravyas/batch-01..30.json`): classical foods, each with 16+
  fields — rasa, virya, vipaka, gunas, prabhava, dosha effects (V/P/K each
  −2…+2 signed scale: − pacifies, + aggravates), agniEffect, digestibility,
  seasons (6 ritus), timeOfDay, combinations, viruddha, contraindications,
  preparation, USDA bindings (fdcId+tier), servings, provenance, confidence.
- **1,500 recipes** (`recipes/batch-r01..r30.json`): 300 classical + 1,200
  everyday/international; ingredients link to dravyas/fdcIds; computed dosha;
  viruddha-flagged where a modern dish breaks a rule (with compliant variant).
  The seed build derives honest per-serving and per-100g panels from bound
  ingredient nutrition: energy, macros, fiber, sugars, 22 vitamins, 11 minerals.
- **Classification rules** (`rules/category-rules.json` 187 categories,
  `rules/modifiers.json` 14 name-modifiers, `crosswalk/overrides.json`).
- **Crosswalk** (`crosswalk/crosswalk.csv`): 1,969 deterministic USDA→dravya
  derived-tier matches (matcher: `match_crosswalk.py`).

**Three-tier dosha coverage of ALL 12,601 USDA foods:**
classical 336 (direct dravya bindings) + derived 1,969 (crosswalk) +
estimated 10,296 (category rules × modifiers) = 12,601. Tier is always stored
and must always be shown in UI.

**Build pipeline:** `ayurveda-data/build_seed.py` → deterministic
`WiseEating/ayurveda_seed.json.gz` (seedVersion 5; sha-verifiable) +
`WiseEating/ayurveda_rules.json`. `ayurveda-data/build_preseeded_store.py`
audits/compacts a completed 14,484-row store and emits the two bundled gzip
parts, including the version-5 search cache. `ayurveda-data/validate.py --store
/tmp/pre` is the gatekeeper (content integrity + full resolver and preseed
simulation; must always pass).

**App layer (Swift, additive only — `FoodItem` untouched):**
- `WiseEating/Ayurveda/AyurvedaProfile.swift`: `@Model AyurvedaProfile`
  (2,214 rows: 714 dravyas + 1,500 recipes; joined to FoodItem by plain `foodId`;
  `kind` = "dravya"|"recipe") and `@Model AyurvedaLink` (fdcId→dravya, 2,305 rows,
  tiers exact/near/derived).
- `WiseEating/Ayurveda/AyurvedaRules.swift`: Sendable value types; loads
  ayurveda_rules.json; computes estimated-tier VPK.
- `WiseEating/Ayurveda/AyurvedaResolver.swift`: single read API for any FoodItem →
  `.classical / .recipe / .user / .derived / .estimated / computed` (computed =
  grams-weighted aggregation over ingredients for user recipes/menus; coverage-
  gated ≥0.5; precedence: direct profile > link > computed > estimated > none).
- `WiseEating/Ayurveda/Views/`: D8 + WE-3 UI — AyurvedaSectionView (detail card:
  tier/source/confidence, accessible center-zero dosha scales with ±/% toggle,
  semantic light/dark tokens, glyph-bearing wrapping chips, always-visible
  viruddha/contraindication warnings, engineExcluded banner, plain aiDraft
  disclaimer), DoshaBarsView,
  AyurvedaDisplay(+Math), AyurvedaEditorSection (manual form; recipe/menu editors
  show live computed preview + optional "Set manually" override → kind "user").
  ⚠ SwiftUI gotcha fixed in D8: an empty Group = EmptyView = no render node, so
  .task never fires — always anchor conditional sections with Color.clear.
- `RecipeNutritionPanelView` (WE-2): existing glass-card/flow-layout language;
  switches per serving/per 100g and displays the full 39-field nutrient catalog,
  coverage state, and honest missing-slug evidence.
- `WiseEating/FoodSearch/` (WE-4/WE-5/WE-8c): the version-5 compact cache persists canonical
  virya/dosha/agni/digestibility/season/category/concept facet sets and a
  separate inverted facet index on exactly the 2,214 seeded profiles.
  `CanonicalFacetParser` removes only validated natural/explicit facet speech
  before the existing tokenizer; plain USDA rows remain un-faceted. Constrained
  nutrient columns are always visible (`—` means no data; stored zero remains
  `0.0`), both constraint parsers feed query-ordered display context, and pH
  uses one exclusive boundary definition (`low < 7`, `high > 7`, neutral
  6.5…7.5). Unknown-pH filtered rows are counted, pH sort-only mode exposes its
  column, and command heuristics use token boundaries so phosphorus/sulphate/
  phyllo/freeze do not accidentally activate pH or negation modes. WE-6 keeps
  the 28 MB persisted index off the cold-launch path: views start loading it
  nonblockingly on entry, while programmatic `searchCompact`/`searchResults`
  await the same version-checked load before taking an index snapshot. Version 5
  also persists display and enforced age floors separately: badges
  retain the display floor; canonical age filters use only authored floors.
- `WiseEating/Ayurveda/AyurvedaRecommendationGate.swift` (D9): set-driven
  never-recommend enforcement (engineExcluded profiles + linked fdcIds + AI
  free-text name screen) wired into all AI generation paths and the Siri intent;
  search deliberately NOT filtered (decision 3).
- Test/automation support: launch argument `-uiTestNoAds` (SubscriptionManager
  returns .removeAds for that launch); banner ads gated on plan (was a real bug).
  `-we6LaunchProfile` enables opt-in Points of Interest plus monotonic launch
  timestamps through the first interactive frame; ordinary launches emit no
  WE-6 probe output.
- `WiseEating/Main/DBSeed/AyurvedaSeeder.swift` + hooks in `SeedManager.swift`
  (after `seedFoodsIfNeeded`) and `DatabaseSetup.swift` (mainTypes): the shipped
  store already contains 383 placeholder FoodItems (reserved ID band
  **900001–900383**), 1,500 recipe FoodItems/IngredientLinks, 2,214 profiles,
  2,305 links, and the version-5 search cache. Fresh install verifies the
  seed-v5 profile stamps and is a zero-insert/zero-update no-op. Existing stores
  use a canonical-slug/fdcId upsert delta; ownership ambiguity aborts without
  touching user data. Post-seed food total: 14,484.
- WE-8/WE-8c safety projection is build-time and canonical-only: each of the 2,214
  seed rows carries `scaffold-default`, review-required provenance; recipe
  allergens are ingredient unions, composition diets are ingredient
  intersections, and display `minAgeMonths` is the ingredient maximum with a
  12-month honey floor. WE-8c carries per-ingredient
  `ageProvenance`: cited `authored` rules hard-filter through
  `enforcedMinAgeMonths`, while values imported from `Legacy/foods.json` remain
  unchanged display-only badges. The artifact contains 10,571 positive-gram IngredientLinks for
  all 1,500 recipes. Ghee remains conservatively `Milk`; unresolved safety
  inputs abort the build rather than receiving permissive defaults. Plain USDA
  rows receive no Ayurveda profile, facet, claim, or derived Ayurveda metadata.
- `WiseEating/Legacy/` after WE-7 contains only five live JSON fallback
  resources (`foods`, `product_buckets`, `sports`, `vocabulary`, `workouts`).
  The nine former Swift compiler inputs were entirely commented, had no inbound
  references, and were removed as one proven-dead cluster. The synchronized
  Xcode group now contributes zero Legacy Swift sources.

## 3. Fixed decisions (do not relitigate without the founder)

1. Base = WiseEating engine; extension is additive; lightweight migration only.
2. Tiered honesty: never hand-author dosha for processed/branded foods; label
   every value classical/derived/estimated.
3. Viruddha = warn, don't block. Badges + explanations; engine may avoid, UI never hides.
4. **Engine exclusions** (display with health warning, NEVER recommend):
   `dravya.betel-nut` (IARC 1 carcinogen), `dravya.vanaspati` (trans fats).
5. All content ships `qualityState: aiDraft` until an Ayurveda expert reviews;
   `reviewNote` fields mark every classical disagreement. Derived safety fields
   are conservative `scaffold-default` metadata pending the same expert review;
   never weaken them merely to preserve search ordering. No medicinal claims
   anywhere.
6. Dosha model is signed effects (−2…+2 per dosha), richer than percentages;
   percentage views are derived in UI, never stored.
7. No beef dravya (deliberate); ~991 beef foods classify via estimated tier.
8. Recipes ARE FoodItems (`isRecipe=true`) — not a separate table.
9. Unresolved safety metadata fails the build rather than defaulting
   permissively.
10. Age enforcement is provenance-gated: cited `authored` floors may hard-hide;
    untraced `legacyImport` values remain display metadata. Today the only
    authored age rule is honey at 12 months. Ingredient values and max
    propagation remain unchanged.
11. Cold launch is governed by an absolute product budget, not a per-task
    percentage. HARD CEILING 1.700s median. Any task whose measured median
    exceeds 1.650s must include a profiling paydown in the same task. Per-task
    deltas are always reported; they are not individually gated.
    Percentage-of-previous gates are forbidden for launch because they ratchet.

## 4. Working process (the pattern that built all of this)

**Director / executor split.** The director (AI with strong Ayurveda + design
knowledge) writes designs, rules, and task packets with **pre-simulated count
gates**; executors (Codex on the founder's Mac, or fresh director sessions)
implement mechanically. Executors follow a hard **stop-and-report rule**: any
failed gate or unexpected state → capture verbatim, stop, never improvise.
The director independently re-verifies every report (rerun gates, sample-audit,
diff-check scope) before approving. Gates are exact numbers, not vibes —
executors must not tune constants to force them.

Task packets and reports live in `ayurveda-data/` (`TASK-*.md`, `REPORT-*.md`,
`DESIGN-*.md`). Read `TASK-D6.md`/`TASK-D34.md` as templates.

**Environment facts:**
- The Claude/Cowork sandbox has **no Xcode/Swift compiler** — Swift can only be
  parse-checked there; building/booting is a Mac-side (Codex) gate.
- Sandbox git can't unlink lock files. Workaround: `GIT_INDEX_FILE=/tmp/ayur_index`,
  `git add` → `write-tree` → `commit-tree` → write SHA directly to
  `.git/refs/heads/<branch>`. On the Mac: `rm -f .git/*.lock && git reset`.
- Store access: `cat WiseEating/preseeded_db.store.gz.part-aa
  WiseEating/preseeded_db.store.gz.part-ab > /tmp/pre.gz && gunzip -f /tmp/pre.gz`
  → SQLite at /tmp/pre, table ZFOODITEM (ZID, ZNAME…).
- **This codebase sits near the Swift type-checker's budget.** ObserversHub.swift
  has needed two mechanical splits. Rule for all new SwiftUI: small sub-views,
  extracted closure handlers, explicit Sendable on shared value types.

## 5. Number registry (every verified gate)

| Thing | Count |
|---|---|
| Dravyas / recipes / profiles | 714 / 1,500 / 2,214 |
| AyurvedaLink rows (v4 seed) | 2,305 = 278 exact + 58 near + 1,969 derived |
| Tier coverage | classical 336 · derived 1,969 · estimated 10,296 = 12,601 |
| Placeholder FoodItems | 383 (IDs 900001–900383) |
| Post-seed ZFOODITEM total | 14,484 (12,601 + 383 + 1,500) |
| Category rules / modifiers | 187 / 14 (modifiers fire on 6,357 foods) |
| Crosswalk distinct dravyas | 166; contested 67; curated denies 2 |
| Recipe nutrition | 1,500 full · 0 estimated · 0 none; 39 fields × two bases |
| Recipe IngredientLinks | 10,571 positive-gram rows · 1,500 owners |
| WE-8 safety projection | 2,214 review-required rows · 156 allergen dravyas · 1,182 allergen recipes · 749 Vegan recipes |
| Search cache | version 5 · 14,484 DB/compact rows · 2,214 canonical faceted rows · 64 keys / 20,114 assignments · separate display/enforced age floors |
| Seed | seedVersion 5, deterministic SHA-256 `886c6a39…872e` |
| Age provenance (WE-8c) | dravyas 4 authored / 710 legacyImport · recipes 4 / 1,496 · ingredient contributors 4 / 10,567 |
| Cold launch (WE-6/WE-7/WE-8/WE-8c, Debug simulator) | WE-8c registry median **1.607s** (N=12); same-session WE-8b 1.569s, paired median delta +0.048s. Absolute hard ceiling 1.700s; profiling paydown required above 1.650s |
| Legacy target (WE-7) | 9 dead Swift inputs removed · 5 live JSON fallback resources retained |

## 6. Milestone ledger (update after every task)

| Milestone | Status |
|---|---|
| Content: 714 dravyas + 1,500 recipes | ✅ done, validator green |
| D10 predrafts (Codex) | ✅ done, director-verified |
| D6 models+seeder | ✅ done; Mac gates green (Run 3) |
| Branch split main/ayurveda-app + author normalization | ✅ done |
| D34 crosswalk+rules (all 12,601 classified) | ✅ COMPLETE — Mac founder gates green (Run 6, report `15cb1b2`): build, fresh install 2214/2305/383/1500/14484, idempotency, v1→v2 top-up 336→2305. Fixes: Sendable (`b96c014`), ObserversHub splits (`1159729`, `1bc94fc`) |
| D8 Ayurveda UI (incl. D8.1 computed tier, D8.2 live editor preview) | ✅ COMPLETE (67e6983, pushed) — Ayurveda card on all food/recipe details (tier chip, center-zero dosha bars, ±/% toggle, rasa/virya/vipaka/guna chips, viruddha + contraindication warnings, engineExcluded banner, aiDraft disclaimer); computed tier for user recipes/menus (grams-weighted, coverage-gated, math-gated); editors: Add Food manual (neutral defaults), recipe/menu = live computed preview + optional manual override → kind "user". Fixes en route: render-node bug (empty Group killed .task), FoodItemCopy id type, banner-ad gating (real prod bug), -uiTestNoAds flag. Residuals: final Computed/User card screenshots skipped by founder decision; VoiceOver + dark-mode smoke deferred; catalog override-with-provenance deferred |
| D9 engineExcluded recommendation enforcement | ✅ COMPLETE (`2a5dccf`, `f9394dc`) — data-driven gate excludes effective seed-v2 set `{900039, 900360}` across active meal-plan, diet, menu, recipe, and food generation; resolved IDs plus AI free-text aliases are screened; search remains visible. G1/G2/G4 green and G3 generation-path gate proven under the director amendment. Residual: on-device AI generation unverifiable on simulator; physical-device check pending — same residual class as prior founder gates. See `ayurveda-data/REPORT-D9.md` |
| WE-2 recipe nutrition + build-time seed/index | ✅ COMPLETE — T1 `f545569`; all 1,500 recipes have USDA-component panels; final artifact is 14,484 foods / 2,214 profiles / 2,305 links with matching search cache; fresh install logs zero Ayurveda inserts/updates and no rebuild; first index-ready launch 499.74s→15.65s. See `ayurveda-data/REPORT-WE2.md` |
| WE-3 Ayurveda display card redesign | ✅ COMPLETE — founder-approved warm read-only card; signed word/value dosha rows, semantic center-zero scales, wrapping glyph chips, always-visible warnings, plain disclaimer, Reduce Motion, and one-element dosha accessibility. Four light/dark × default/largest-type snapshots pass; minimum measured contrast 5.52:1. Editor behavior and lifecycle/claims boundaries unchanged. See `ayurveda-data/REPORT-WE3.md` |
| WE-4 Ayurvedic FoodSearch facets | ✅ COMPLETE — version-4 prebuilt index carries 64 canonical keys / 20,114 assignments on exactly 2,214 seeded dravya/recipe rows; natural virya/dosha/agni/digestibility/season/category queries and three conservative Sanskrit aliases compose with existing search. All 25 legacy goldens are unchanged; worst pure-text median delta +0.3%; fresh install still performs zero inserts and no rebuild. See `ayurveda-data/REPORT-WE4.md` |
| WE-5 FoodSearch border cases | ✅ COMPLETE — constrained nutrient and pH columns now remain visible with honest missing/zero semantics; Tokenizer + ConstraintMapper display provenance is unified; pH boundary/sentinel/count/sort behavior is centralized; command heuristics are token-boundary safe. All 25 WE-4 goldens remain exact, 34/34 repository tests pass, and pure-text median latency stays within the WE-4 +10% budget. Engine source is `VM/SmartFoodSearchEngine.swift`; `Legacy/` is untouched. See `ayurveda-data/REPORT-WE5.md` |
| WE-6 cold-launch profiling | ✅ COMPLETE — opt-in signposts account for the full launch path; re-established baseline 3.405s, persisted-index phase 1.591s, final median 1.662s (−51.2%). Index version/count and rebuild rules are unchanged; awaited lazy loading preserves programmatic search, 25/25 goldens remain exact, worst latency delta +3.4%, and fresh install remains zero-insert/no-rebuild. See `ayurveda-data/REPORT-WE6.md` |
| WE-7 Legacy target audit | ✅ COMPLETE — all 14 files classified before removal. Nine comment-only Swift compiler inputs formed one closed dead cluster and were removed; five JSON fallback resources remain live. Debug/Release builds, 38/38 tests, 25/25 goldens, 15/15 WE-5 border methods, fresh no-insert/no-rebuild, search latency, and 1.504s median cold launch are green. Release executable −416 bytes. See `ayurveda-data/REPORT-WE7.md` |
| WE-8 derived safety/search metadata | ✅ COMPLETE — all 2,214 canonical profiles carry conservative review-required safety provenance; 1,500 recipes derive allergen union, diet intersection, maximum ingredient age/honey floor, and retain exact 10,571 IngredientLinks. Founder-approved `vegan curry` history is auditable; 25/25 production legacy goldens plus 2/2 negative safety goldens pass, worst latency delta +4.3%, fresh install remains zero-insert/no-rebuild, and cold launch is 1.592s median. See `ayurveda-data/REPORT-WE8.md` |
| WE-8c provenance-gated age enforcement | ✅ COMPLETE — authored honey floors alone hard-filter canonical profiles; legacy-import floors remain unchanged display metadata. Honey protection, 1,496/1,500/1,500 recipe visibility, unchanged display histogram, dravya deltas, 25+2 goldens, 62/62 tests, deterministic v5 artifacts, fresh no-insert/no-rebuild, and Debug/Release builds pass. Same-session N=12 ABAB launch median is 1.607s vs WE-8b 1.569s (paired +0.048s), under the absolute 1.700s ceiling and 1.650s paydown trigger. The separate pre-existing `main` USDA issue is recorded in `ayurveda-data/ISSUE-MAIN-AGE-GATING.md`. See `ayurveda-data/REPORT-WE8c.md` |
| Expert review pass | ⏳ pending human reviewer: work aiDraft→reviewed, resolve reviewNotes, optional batch-31 top-up to 750 |
| Later roadmap | media (yoga/meditation content), recommendation engine, dosha assessment — see ayurveda-data/RESTART-PLAN.md history |

## 7. How to take over as director (for a fresh model)

1. Read this file, then `ayurveda-data/PROGRESS.md` (content detail),
   then the latest `REPORT-*.md` for current state.
2. Confirm branch: work happens on `ayurveda-app`; `main` is untouchable.
3. Run the validator (§4 store command) — it must pass before and after anything.
4. Follow the director/executor pattern (§4): design with simulated gates →
   dispatch Codex → independently verify → fix or approve → **update §5/§6 here
   and PROGRESS.md → commit**.
5. Costly knowledge lives in: dravya batches (Ayurvedic facets), rules JSONs
   (classification judgment), DESIGN-D6/D34 (architecture rationale). Never let
   an executor rewrite those; they are director/founder artifacts.
