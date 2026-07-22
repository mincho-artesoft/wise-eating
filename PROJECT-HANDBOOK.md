# PROJECT HANDBOOK — Ayurveda app built on WiseEating
**Read this first. It is the knowledge-transfer document for anyone (human or AI)
taking over direction of this project. Update it at the end of every milestone —
that is a standing rule baked into all task packets.**
Last updated: 2026-07-22 (D34 complete; D8 next).

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
- **Classification rules** (`rules/category-rules.json` 187 categories,
  `rules/modifiers.json` 14 name-modifiers, `crosswalk/overrides.json`).
- **Crosswalk** (`crosswalk/crosswalk.csv`): 1,969 deterministic USDA→dravya
  derived-tier matches (matcher: `match_crosswalk.py`).

**Three-tier dosha coverage of ALL 12,601 USDA foods:**
classical 336 (direct dravya bindings) + derived 1,969 (crosswalk) +
estimated 10,296 (category rules × modifiers) = 12,601. Tier is always stored
and must always be shown in UI.

**Build pipeline:** `ayurveda-data/build_seed.py` → deterministic
`WiseEating/ayurveda_seed.json.gz` (seedVersion 2; sha-verifiable) +
`WiseEating/ayurveda_rules.json`. `ayurveda-data/validate.py --store /tmp/pre`
is the gatekeeper (content integrity + full resolver simulation; must always pass).

**App layer (Swift, additive only — `FoodItem` untouched):**
- `WiseEating/Ayurveda/AyurvedaProfile.swift`: `@Model AyurvedaProfile`
  (2,214 rows: 714 dravyas + 1,500 recipes; joined to FoodItem by plain `foodId`;
  `kind` = "dravya"|"recipe") and `@Model AyurvedaLink` (fdcId→dravya, 2,305 rows,
  tiers exact/near/derived).
- `WiseEating/Ayurveda/AyurvedaRules.swift`: Sendable value types; loads
  ayurveda_rules.json; computes estimated-tier VPK.
- `WiseEating/Ayurveda/AyurvedaResolver.swift`: single read API →
  `.classical / .recipe / .derived / .estimated` for any FoodItem.
- `WiseEating/Main/DBSeed/AyurvedaSeeder.swift` + hooks in `SeedManager.swift`
  (after `seedFoodsIfNeeded`) and `DatabaseSetup.swift` (mainTypes): versioned
  (UserDefaults `ayurvedaSeedVersion`), idempotent, fail-open; seeds 383
  placeholder FoodItems (reserved ID band **900001–900383**) for dravyas with no
  USDA analogue, and recipes as `FoodItem(isRecipe=true)` + `IngredientLink`
  (nutrition aggregation and search work unchanged). Post-seed food total: 14,484.

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
| AyurvedaLink rows (v2) | 2,305 = 278 exact + 58 near + 1,969 derived |
| Tier coverage | classical 336 · derived 1,969 · estimated 10,296 = 12,601 |
| Placeholder FoodItems | 383 (IDs 900001–900383) |
| Post-seed ZFOODITEM total | 14,484 (12,601 + 383 + 1,500) |
| Category rules / modifiers | 187 / 14 (modifiers fire on 6,357 foods) |
| Crosswalk distinct dravyas | 166; contested 67; curated denies 2 |
| Seed | seedVersion 2, deterministic sha-verifiable |

## 6. Milestone ledger (update after every task)

| Milestone | Status |
|---|---|
| Content: 714 dravyas + 1,500 recipes | ✅ done, validator green |
| D10 predrafts (Codex) | ✅ done, director-verified |
| D6 models+seeder | ✅ done; Mac gates green (Run 3) |
| Branch split main/ayurveda-app + author normalization | ✅ done |
| D34 crosswalk+rules (all 12,601 classified) | ✅ COMPLETE — Mac founder gates green (Run 6, report `15cb1b2`): build, fresh install 2214/2305/383/1500/14484, idempotency, v1→v2 top-up 336→2305. Fixes: Sendable (`b96c014`), ObserversHub splits (`1159729`, `1bc94fc`) |
| D8 Ayurveda UI | 🚀 DESIGN DISPATCHED 2026-07-22 — `DESIGN-D8.md` (U1–U12) + `TASK-D8.md` (gates G1–G6, 31-assertion math check, 9 runtime spot foods) + `DISPATCH-D8.md` (Codex prompt). Editability policy RATIFIED by founder 2026-07-22: user-added foods fully editable → `AyurvedaProfile` kind/tier "user" (resolver gains `.user` case); catalog foods read-only (already structurally enforced — editor only reachable for `isUserAdded`); override-with-provenance deferred. Tier display mapping: link exact/near → "Classical", link derived → "Derived". Awaiting Codex run → director re-verification |
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
