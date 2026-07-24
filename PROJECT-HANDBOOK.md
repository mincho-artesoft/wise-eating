# PROJECT HANDBOOK — Ayurveda app built on WiseEating
**Read this first. It is the knowledge-transfer document for anyone (human or AI)
taking over direction of this project. Update it at the end of every milestone —
that is a standing rule baked into all task packets.**
Last updated: 2026-07-24 (WE-5 complete — FoodSearch border cases closed; next: expert review).

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
`WiseEating/ayurveda_seed.json.gz` (seedVersion 3; sha-verifiable) +
`WiseEating/ayurveda_rules.json`. `ayurveda-data/build_preseeded_store.py`
audits/compacts a completed 14,484-row store and emits the two bundled gzip
parts, including the version-4 search cache. `ayurveda-data/validate.py --store
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
- `WiseEating/FoodSearch/` (WE-4/WE-5): version-4 compact cache persists canonical
  virya/dosha/agni/digestibility/season/category/concept facet sets and a
  separate inverted facet index on exactly the 2,214 seeded profiles.
  `CanonicalFacetParser` removes only validated natural/explicit facet speech
  before the existing tokenizer; plain USDA rows remain un-faceted. Constrained
  nutrient columns are always visible (`—` means no data; stored zero remains
  `0.0`), both constraint parsers feed query-ordered display context, and pH
  uses one exclusive boundary definition (`low < 7`, `high > 7`, neutral
  6.5…7.5). Unknown-pH filtered rows are counted, pH sort-only mode exposes its
  column, and command heuristics use token boundaries so phosphorus/sulphate/
  phyllo/freeze do not accidentally activate pH or negation modes.
- `WiseEating/Ayurveda/AyurvedaRecommendationGate.swift` (D9): set-driven
  never-recommend enforcement (engineExcluded profiles + linked fdcIds + AI
  free-text name screen) wired into all AI generation paths and the Siri intent;
  search deliberately NOT filtered (decision 3).
- Test/automation support: launch argument `-uiTestNoAds` (SubscriptionManager
  returns .removeAds for that launch); banner ads gated on plan (was a real bug).
- `WiseEating/Main/DBSeed/AyurvedaSeeder.swift` + hooks in `SeedManager.swift`
  (after `seedFoodsIfNeeded`) and `DatabaseSetup.swift` (mainTypes): the shipped
  store already contains 383 placeholder FoodItems (reserved ID band
  **900001–900383**), 1,500 recipe FoodItems/IngredientLinks, 2,214 profiles,
  2,305 links, and the final version-4 search cache. Fresh install verifies the
  seed-v3 profile stamps and is a zero-insert/zero-update no-op. Existing stores
  use a canonical-slug/fdcId upsert delta; ownership ambiguity aborts without
  touching user data. Post-seed food total: 14,484.

## 3. Fixed decisions (do not relitigate without the founder)

1. Base = WiseEating engine; extension is additive; lightweight migration only.
2. Tiered honesty: never hand-author dosha for processed/branded foods; label
   every value classical/derived/estimated.
3. Viruddha = warn, don't block. Badges + explanations; engine may avoid, UI never hides.
4. **Engine exclusions** (display with health warning, NEVER recommend):
   `dravya.betel-nut` (IARC 1 carcinogen), `dravya.vanaspati` (trans fats).
5. All content ships `qualityState: aiDraft` until an Ayurveda expert reviews;
   `reviewNote` fields mark every classical disagreement. No medicinal claims anywhere.
6. Dosha model is signed effects (−2…+2 per dosha), richer than percentages;
   percentage views are derived in UI, never stored.
7. No beef dravya (deliberate); ~991 beef foods classify via estimated tier.
8. Recipes ARE FoodItems (`isRecipe=true`) — not a separate table.

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
| AyurvedaLink rows (v3) | 2,305 = 278 exact + 58 near + 1,969 derived |
| Tier coverage | classical 336 · derived 1,969 · estimated 10,296 = 12,601 |
| Placeholder FoodItems | 383 (IDs 900001–900383) |
| Post-seed ZFOODITEM total | 14,484 (12,601 + 383 + 1,500) |
| Category rules / modifiers | 187 / 14 (modifiers fire on 6,357 foods) |
| Crosswalk distinct dravyas | 166; contested 67; curated denies 2 |
| Recipe nutrition | 1,500 full · 0 estimated · 0 none; 39 fields × two bases |
| Search cache | version 4 · 14,484 DB/compact rows · 2,214 canonical faceted rows · 64 keys / 20,114 assignments |
| Seed | seedVersion 3, deterministic SHA-256 `1830a191…509b6` |

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
