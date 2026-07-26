# FC-1 — Food Concept Ontology Report

**Date:** 2026-07-26

**Branch:** `fc-1-food-concepts`

**Branch point:** `d0dfc38` (the local MP-1 telemetry commit on top of `d393bda`)

**Disposition:** **STOPPED at FC1-G6; evidence/candidate committed to the isolated branch, not pushed.**

## Executive result

A build-time concept-membership implementation and a lazy runtime lookup candidate were completed and focused-tested, but the director red-team corpus produced two resolved `mustNotExclude` false positives. Neither can be fixed with an existing `negativePhrase` while preserving the mandated token-boundary semantics. FC1-G6 is blocking, so later integration, build, launch, and fresh-install gates were deliberately not run. The stopped candidate and evidence are committed only to this isolated, unpushed branch for inspection.

- `tree_nuts` / `peanut`: 13 “mixed nuts” foods are members because `mixed nuts` is a positive phrase. The existing negative is singular `peanut`; it does not token-match `peanuts`. Several affected names explicitly say “without peanuts”, while others actually contain peanuts, so plural stemming would not be a safe general repair.
- `tree_nuts` / `chestnut`: 10 seeded Vrat Chestnut recipes are members because `chestnut` is an explicit positive ontology phrase. No negative exists. The ontology itself labels chestnut contested, while the golden places it in `mustNotExclude`. This is an authority contradiction, not a machinery defect that the executor may tune away.

## Input integrity and authority boundary

| Director artifact | Expected/observed SHA-256 | Status |
|---|---|---|
| `ayurveda-data/rules/food-concepts.json` | `2755da46ab2621d6ed4acb9204b4953d79eb03e8893f568c748e5abda9a48d24` | Unchanged |
| `ayurveda-data/tests/exclusion-goldens.json` | `8ab92be44d987aab86e14d69c5933b0eed428efdb7fc31bd7f2a516401c2bf27` | Unchanged |
| `ayurveda-data/tests/resolution-holdout.json` | `557fe9cd78e751522310ec520c2a94a8b19366f12c8405814566d38a517a7a9d` | Unchanged |

The candidate does not write WE-8 allergens or diets. On the 2,214-row overlap, its results are diagnostic only (FC1-G12); the 12,601 plain USDA rows use FC-1 concept membership. No planner, SmartFoodSearch engine, or ranking consumer was wired.

## Candidate implementation (uncommitted)

- Extended `ayurveda-data/build_seed.py` to validate the ontology/override schema, reject hierarchy and alias cycles, reuse the validator’s modifier normalization, load the existing suffix-negation vocabulary, match negatives first, select longest positive phrases, roll up the parent DAG, propagate through IngredientLinks, and apply overrides last.
- Created the empty documented override registry `ayurveda-data/crosswalk/concept-overrides.json`.
- Added `WiseEating/Ayurveda/FoodConcepts.swift`: immutable `Sendable` lazy lookup with `members(of:)`, `concepts(for:)`, and `canonical(alias:)`, plus unused `Requirement` and `Restriction` value types.
- Generated `WiseEating/food_concepts.json.gz`: 29,740 bytes, SHA-256 `44716a1990817318c837ef98103e2a3785745a15d27adc6a372a80e4846c6111`.
- The existing seed and rules artifacts remained byte-identical during generation: seed `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e`; rules `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c`.

## Gate ledger

| Gate | Result | Evidence |
|---|---|---|
| FC1-G1 Debug + Release | **INCOMPLETE after candidate** | Baseline generic-iOS Debug build succeeded with 46 unique pre-existing warning messages. Candidate Debug/Release was not run after the blocking G6 result. |
| FC1-G2 full suite | **INCOMPLETE after candidate** | Branch baseline: 62/62 in 17.486s. Candidate-focused FC-1 tests: 8/8 in 8.096s. Full post-change suite not run after stop. |
| FC1-G3 search goldens | **NOT RUN after candidate** | Search was intentionally untouched; exact 25/25 + 2/2 post-change rerun was withheld after G6 stopped the task. |
| FC1-G4 validator | **BASELINE PASS / AFTER NOT RUN** | Before: D34 and all validators green, 714 dravyas + 1,500 recipes. Post-candidate validator withheld after stop. |
| FC1-G5 must-exclude | **64/79 PASS; 1 FAIL; 14 UNRESOLVED** | Full worklist below. |
| FC1-G6 must-not-exclude | **BLOCKING: 26/38 PASS; 2 FAIL; 10 UNRESOLVED** | Both resolved failures are listed below and cannot be repaired using an existing negative phrase without violating frozen matching or editing director data. |
| FC1-G7 viaIngredient | **4/13 nominal; only 2 clean ingredient-only proofs** | Six resolved failures, three unresolved. `palak paneer` also matches directly; `lassi` is a raw-golden substring collision with “classic”. Details below. |
| FC1-G8 size sanity | **PASS WITH FLAG** | No concept exceeds 40%. `meat` is 26.857% and is explicitly explained below. |
| FC1-G9 cold launch | **NOT RUN** | G6 stopped the task before same-session ABAB measurement; no delta is claimed. |
| FC1-G10 fresh install | **NOT RUN after candidate** | Baseline permanent suite was green; no candidate no-insert/no-rebuild measurement is claimed. |
| FC1-G11 determinism | **FOCUSED PASS** | Two independent in-memory builds encoded to byte-identical deterministic gzip; bundled artifact equals the current build. A later end-to-end rerun was not performed after stop. |
| FC1-G12 cross-validation | **1,217 disagreements measured** | Neither derivation was modified. Every disagreement with both reason trails appears in the exhaustive appendix. |
| FC1-G13 alias coverage | **7/8** | Alias-only report; no resolver wiring. |

## FC1-G5 explicit must-exclude worklist

| # | Concept | Pattern | Status | Catalogue matches | Concept members | Finding |
|---:|---|---|---|---:|---:|---|
| 13 | `dairy` | `condensed milk` | **UNRESOLVED** | 0 | 0 | dairy concentrate |
| 16 | `dairy` | `butter chicken` | **UNRESOLVED** | 0 | 0 | viaIngredient — cream and butter |
| 25 | `pork` | `pancetta` | **UNRESOLVED** | 0 | 0 | cured pork belly |
| 28 | `pork` | `gammon` | **UNRESOLVED** | 0 | 0 | cured pork leg |
| 37 | `fish` | `caesar` | **FAIL** | 9 | 0 | viaIngredient — anchovy in dressing |
| 41 | `shellfish` | `prawn` | **UNRESOLVED** | 0 | 0 | crustacean |
| 48 | `gluten` | `seitan` | **UNRESOLVED** | 0 | 0 | pure wheat gluten; name contains no gluten keyword |
| 51 | `gluten` | `farro` | **UNRESOLVED** | 0 | 0 | wheat species |
| 54 | `gluten` | `panko` | **UNRESOLVED** | 0 | 0 | wheat breadcrumb |
| 55 | `gluten` | `orzo` | **UNRESOLVED** | 0 | 0 | wheat pasta shaped as rice |
| 56 | `gluten` | `udon` | **UNRESOLVED** | 0 | 0 | wheat noodle |
| 61 | `egg` | `aioli` | **UNRESOLVED** | 0 | 0 | viaIngredient — egg emulsion |
| 70 | `tree_nuts` | `marzipan` | **UNRESOLVED** | 0 | 0 | viaIngredient — almond paste |
| 77 | `alcohol` | `mirin` | **UNRESOLVED** | 0 | 0 | rice wine; planner currently bans by keyword list only |
| 78 | `alcohol` | `sherry` | **UNRESOLVED** | 0 | 0 | fortified wine |

`caesar` is the only resolved false negative: nine plain USDA catalogue names match the substring, but no matching recipe owner/IngredientLink fixture exists and none is a `fish` member. The other 14 patterns do not occur in this 14,484-row catalogue and are recorded as coverage gaps, not silently skipped tests.

Resolved `caesar` catalogue rows:

- `1345` — Chicken or turkey caesar garden salad, chicken and/or turkey, lettuce, tomato, cheese, no dressing
- `1346` — Chicken or turkey, breaded, fried, caesar garden salad, chicken and/or turkey, lettuce, tomatoes, cheese, no dressing
- `4006` — Caesar salad, with romaine, no dressing
- `4589` — Caesar dressing
- `4609` — Caesar dressing, light
- `4620` — Caesar dressing, fat free
- `6513` — Salad dressing, caesar dressing, regular
- `7264` — Salad dressing, caesar, low calorie
- `8255` — Salad dressing, caesar, fat-free

## FC1-G6 blocking must-not findings

### `tree_nuts` / `peanut`

Golden #19: legume; must be its own concept, not a tree nut Matching catalogue rows: 148; incorrectly excluded members: 13.

- `2015` — Mixed nuts, with peanuts, salted — FC-1 reason: `name:mixed nuts`
- `2016` — Mixed nuts, with peanuts, lightly salted — FC-1 reason: `name:mixed nuts`
- `2017` — Mixed nuts, with peanuts, unsalted — FC-1 reason: `name:mixed nuts`
- `2018` — Mixed nuts, without peanuts, salted — FC-1 reason: `name:mixed nuts`
- `2019` — Mixed nuts, without peanuts, unsalted — FC-1 reason: `name:mixed nuts`
- `6129` — Nuts, mixed nuts, dry roasted, with peanuts, with salt added — FC-1 reason: `name:mixed nuts`
- `6130` — Nuts, mixed nuts, oil roasted, with peanuts, with salt added — FC-1 reason: `name:mixed nuts`
- `6878` — Nuts, mixed nuts, oil roasted, without peanuts, with salt added — FC-1 reason: `name:mixed nuts`
- `6882` — Nuts, mixed nuts, oil roasted, with peanuts, lightly salted — FC-1 reason: `name:mixed nuts`
- `6883` — Nuts, mixed nuts, oil roasted, without peanuts, lightly salted — FC-1 reason: `name:mixed nuts`
- `7902` — Nuts, mixed nuts, dry roasted, with peanuts, without salt added — FC-1 reason: `name:mixed nuts`
- `7903` — Nuts, mixed nuts, oil roasted, with peanuts, without salt added — FC-1 reason: `name:mixed nuts`
- `7904` — Nuts, mixed nuts, oil roasted, without peanuts, without salt added — FC-1 reason: `name:mixed nuts`

### `tree_nuts` / `chestnut`

Golden #20: true tree nut but low allergenicity; founder decision Matching catalogue rows: 30; incorrectly excluded members: 10.

- `1001419` — Vrat Chestnut Cardamom Halwa — FC-1 reason: `name:chestnut`
- `1001420` — Vrat Chestnut Fennel Crepes — FC-1 reason: `ingredient:27, name:chestnut`
- `1001421` — Vrat Chestnut Milk Pudding — FC-1 reason: `ingredient:7570, name:chestnut`
- `1001422` — Vrat Chestnut Oat-Milk Porridge — FC-1 reason: `name:chestnut`
- `1001423` — Vrat Chestnut Potato Cakes — FC-1 reason: `name:chestnut`
- `1001424` — Vrat Chestnut Potato Flatbread — FC-1 reason: `name:chestnut`
- `1001425` — Vrat Chestnut Pumpkin Dumplings — FC-1 reason: `name:chestnut`
- `1001426` — Vrat Chestnut Pumpkin Pancakes — FC-1 reason: `ingredient:27, name:chestnut`
- `1001427` — Vrat Chestnut Sweet Potato Roti — FC-1 reason: `name:chestnut`
- `1001439` — Vrat Steamed Chestnut Cakes — FC-1 reason: `name:chestnut`

The 10 unresolved must-not patterns are `hamachi`, `milk thistle`, `apple butter`, `shea butter`, `fishcake, vegetarian`, `soy free`, `nutmeat`, `dairy free`, `chicken of the woods`, and `sea vegetable`. They match no catalogue row and therefore do not demonstrate either safety or failure in this corpus.

## Full 117-case corpus, grouped by concept

### alcohol

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 77 | `mirin` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 78 | `sherry` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 79 | `vanilla extract` | PASS | 3 | 2 | no | yes |
| mustNotExclude | 34 | `non-alcoholic` | PASS | 3 | 0 | no | no |
| mustNotExclude | 35 | `root beer` | PASS | 3 | 0 | no | no |
| mustNotExclude | 36 | `ginger ale` | PASS | 4 | 0 | no | no |

### corn

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustNotExclude | 21 | `corned beef` | PASS | 14 | 0 | no | no |

### dairy

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 1 | `paneer` | PASS | 28 | 28 | no | no |
| mustExclude | 2 | `ghee` | PASS | 11 | 11 | no | no |
| mustExclude | 3 | `butter,` | PASS | 67 | 26 | no | no |
| mustExclude | 4 | `whey` | PASS | 9 | 9 | no | no |
| mustExclude | 5 | `casein` | PASS | 1 | 1 | no | no |
| mustExclude | 6 | `kefir` | PASS | 1 | 1 | no | no |
| mustExclude | 7 | `buttermilk` | PASS | 27 | 23 | no | no |
| mustExclude | 8 | `ricotta` | PASS | 6 | 6 | no | no |
| mustExclude | 9 | `mozzarella` | PASS | 15 | 15 | no | no |
| mustExclude | 10 | `cheddar` | PASS | 21 | 21 | no | no |
| mustExclude | 11 | `custard` | PASS | 22 | 21 | no | no |
| mustExclude | 12 | `ice cream` | PASS | 79 | 64 | no | no |
| mustExclude | 13 | `condensed milk` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 14 | `curd` | PASS | 15 | 13 | no | no |
| mustExclude | 15 | `palak paneer` | PASS | 3 | 3 | yes | no |
| mustExclude | 16 | `butter chicken` | UNRESOLVED | 0 | 0 | yes | no |
| mustExclude | 17 | `raita` | PASS | 13 | 13 | yes | no |
| mustExclude | 18 | `lassi` | PASS | 22 | 5 | yes | no |
| mustExclude | 19 | `kheer` | PASS | 11 | 11 | yes | no |
| mustNotExclude | 4 | `cream of tartar` | PASS | 1 | 0 | no | no |
| mustNotExclude | 5 | `coconut cream` | PASS | 11 | 0 | no | no |
| mustNotExclude | 6 | `coconut milk` | PASS | 10 | 0 | no | no |
| mustNotExclude | 7 | `almond milk` | PASS | 9 | 0 | no | no |
| mustNotExclude | 8 | `soy milk` | PASS | 3 | 0 | no | no |
| mustNotExclude | 9 | `milk thistle` | UNRESOLVED | 0 | 0 | no | no |
| mustNotExclude | 10 | `peanut butter` | PASS | 71 | 0 | no | no |
| mustNotExclude | 11 | `apple butter` | UNRESOLVED | 0 | 0 | no | no |
| mustNotExclude | 12 | `cocoa butter` | PASS | 2 | 0 | no | no |
| mustNotExclude | 13 | `shea butter` | UNRESOLVED | 0 | 0 | no | no |
| mustNotExclude | 33 | `dairy free` | UNRESOLVED | 0 | 0 | no | no |

### egg

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 59 | `mayonnaise` | PASS | 57 | 57 | yes | no |
| mustExclude | 60 | `meringue` | PASS | 5 | 4 | yes | no |
| mustExclude | 61 | `aioli` | UNRESOLVED | 0 | 0 | yes | no |
| mustExclude | 62 | `hollandaise` | PASS | 1 | 1 | yes | no |
| mustNotExclude | 1 | `eggplant` | PASS | 36 | 0 | no | no |

### fish

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 35 | `anchovy` | PASS | 4 | 4 | no | no |
| mustExclude | 36 | `surimi` | PASS | 4 | 4 | no | no |
| mustExclude | 37 | `caesar` | FAIL | 9 | 0 | yes | yes |
| mustExclude | 38 | `worcestershire` | PASS | 2 | 2 | yes | no |
| mustExclude | 39 | `fish sauce` | PASS | 1 | 1 | no | no |
| mustNotExclude | 25 | `shellfish` | PASS | 7 | 0 | no | no |
| mustNotExclude | 26 | `fishcake, vegetarian` | UNRESOLVED | 0 | 0 | no | yes |

### gluten

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 48 | `seitan` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 49 | `couscous` | PASS | 4 | 4 | no | no |
| mustExclude | 50 | `bulgur` | PASS | 6 | 6 | no | no |
| mustExclude | 51 | `farro` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 52 | `spelt` | PASS | 2 | 2 | no | no |
| mustExclude | 53 | `semolina` | PASS | 14 | 14 | no | no |
| mustExclude | 54 | `panko` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 55 | `orzo` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 56 | `udon` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 57 | `malt` | PASS | 20 | 12 | no | no |
| mustExclude | 58 | `matzo` | PASS | 7 | 7 | no | no |
| mustNotExclude | 27 | `buckwheat` | PASS | 36 | 0 | no | no |
| mustNotExclude | 28 | `gluten free` | PASS | 19 | 0 | no | no |
| mustNotExclude | 29 | `rice flour` | PASS | 13 | 0 | no | no |

### grape

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustNotExclude | 23 | `grapefruit` | PASS | 25 | 0 | no | no |

### lamb

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustNotExclude | 22 | `lambsquarters` | PASS | 5 | 0 | no | no |

### meat

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustNotExclude | 31 | `meatless` | PASS | 39 | 0 | no | no |
| mustNotExclude | 32 | `nutmeat` | UNRESOLVED | 0 | 0 | no | no |

### pork

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 20 | `bacon` | PASS | 58 | 54 | no | no |
| mustExclude | 21 | `ham,` | PASS | 60 | 59 | no | no |
| mustExclude | 22 | `lard` | PASS | 27 | 10 | no | no |
| mustExclude | 23 | `chorizo` | PASS | 2 | 2 | no | no |
| mustExclude | 24 | `prosciutto` | PASS | 1 | 1 | no | no |
| mustExclude | 25 | `pancetta` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 26 | `salami` | PASS | 18 | 18 | no | yes |
| mustExclude | 27 | `pepperoni` | PASS | 32 | 32 | no | yes |
| mustExclude | 28 | `gammon` | UNRESOLVED | 0 | 0 | no | no |
| mustNotExclude | 2 | `hamburger` | PASS | 41 | 0 | no | no |
| mustNotExclude | 3 | `hamachi` | UNRESOLVED | 0 | 0 | no | no |

### poultry

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 29 | `chicken` | PASS | 730 | 730 | no | no |
| mustExclude | 30 | `turkey` | PASS | 347 | 347 | no | no |
| mustExclude | 31 | `duck` | PASS | 21 | 21 | no | no |
| mustExclude | 32 | `goose` | PASS | 16 | 12 | no | no |
| mustExclude | 33 | `broilers or fryers` | PASS | 117 | 117 | no | no |
| mustExclude | 34 | `capon` | PASS | 6 | 6 | no | no |
| mustNotExclude | 37 | `chicken of the woods` | UNRESOLVED | 0 | 0 | no | yes |

### shellfish

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 40 | `shrimp` | PASS | 67 | 67 | no | no |
| mustExclude | 41 | `prawn` | UNRESOLVED | 0 | 0 | no | no |
| mustExclude | 42 | `crab` | PASS | 26 | 24 | no | no |
| mustExclude | 43 | `lobster` | PASS | 11 | 11 | no | no |
| mustExclude | 44 | `crayfish` | PASS | 6 | 6 | no | no |
| mustExclude | 45 | `scallop` | PASS | 26 | 7 | no | yes |
| mustExclude | 46 | `oyster` | PASS | 34 | 23 | no | no |
| mustExclude | 47 | `mussel` | PASS | 3 | 2 | no | no |
| mustNotExclude | 38 | `sea vegetable` | UNRESOLVED | 0 | 0 | no | no |

### soy

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 72 | `tofu` | PASS | 80 | 80 | no | no |
| mustExclude | 73 | `tempeh` | PASS | 16 | 16 | no | no |
| mustExclude | 74 | `miso` | PASS | 5 | 4 | no | no |
| mustExclude | 75 | `edamame` | PASS | 3 | 3 | no | no |
| mustExclude | 76 | `tamari` | PASS | 18 | 1 | no | no |
| mustNotExclude | 30 | `soy free` | UNRESOLVED | 0 | 0 | no | no |

### tree_nuts

| Corpus | # | Pattern | Status | Matches | Members | viaIngredient | Contested |
|---|---:|---|---|---:|---:|---|---|
| mustExclude | 63 | `almond` | PASS | 101 | 82 | no | no |
| mustExclude | 64 | `cashew` | PASS | 18 | 12 | no | no |
| mustExclude | 65 | `walnut` | PASS | 26 | 19 | no | no |
| mustExclude | 66 | `pecan` | PASS | 14 | 4 | no | no |
| mustExclude | 67 | `pistachio` | PASS | 15 | 14 | no | no |
| mustExclude | 68 | `hazelnut` | PASS | 8 | 3 | no | no |
| mustExclude | 69 | `macadamia` | PASS | 6 | 6 | no | no |
| mustExclude | 70 | `marzipan` | UNRESOLVED | 0 | 0 | yes | no |
| mustExclude | 71 | `praline` | PASS | 1 | 1 | yes | no |
| mustNotExclude | 14 | `nutmeg` | PASS | 9 | 0 | no | no |
| mustNotExclude | 15 | `butternut` | PASS | 10 | 0 | no | no |
| mustNotExclude | 16 | `coconut` | PASS | 119 | 0 | no | yes |
| mustNotExclude | 17 | `water chestnut` | PASS | 3 | 0 | no | no |
| mustNotExclude | 18 | `doughnut` | PASS | 22 | 0 | no | no |
| mustNotExclude | 19 | `peanut` | FAIL | 148 | 13 | no | yes |
| mustNotExclude | 20 | `chestnut` | FAIL | 30 | 10 | no | yes |
| mustNotExclude | 24 | `pineapple` | PASS | 55 | 0 | no | no |

## FC1-G7 ingredient propagation corpus

| # | Concept | Pattern | Status | Catalogue matches | Recipe matches | Propagated recipe matches | Direct recipe matches |
|---:|---|---|---|---:|---:|---:|---:|
| 15 | `dairy` | `palak paneer` | PASS | 3 | 2 | 2 | 2 |
| 16 | `dairy` | `butter chicken` | UNRESOLVED | 0 | 0 | 0 | 0 |
| 17 | `dairy` | `raita` | PASS | 13 | 13 | 13 | 0 |
| 18 | `dairy` | `lassi` | PASS | 22 | 4 | 2 | 0 |
| 19 | `dairy` | `kheer` | PASS | 11 | 11 | 11 | 0 |
| 37 | `fish` | `caesar` | FAIL | 9 | 0 | 0 | 0 |
| 38 | `fish` | `worcestershire` | FAIL | 2 | 0 | 0 | 0 |
| 59 | `egg` | `mayonnaise` | FAIL | 57 | 0 | 0 | 0 |
| 60 | `egg` | `meringue` | FAIL | 5 | 0 | 0 | 0 |
| 61 | `egg` | `aioli` | UNRESOLVED | 0 | 0 | 0 | 0 |
| 62 | `egg` | `hollandaise` | FAIL | 1 | 0 | 0 | 0 |
| 70 | `tree_nuts` | `marzipan` | UNRESOLVED | 0 | 0 | 0 | 0 |
| 71 | `tree_nuts` | `praline` | FAIL | 1 | 0 | 0 | 0 |

Only `raita` and `kheer` are clean ingredient-only propagation proofs. `palak paneer` is propagated but also directly matched by the ontology phrase `paneer`, contrary to the golden note that it cannot pass by name. `lassi` nominally passes because the golden resolver uses lowercase substring matching and finds `lassi` inside **classic**; its two propagated rows are Classic Mung Kitchari and Classic Mixed Vegetable Sambar, not lassi recipes. Six patterns resolve only to non-recipe USDA rows (`caesar`, `worcestershire`, `mayonnaise`, `meringue`, `hollandaise`, `praline`) and three are absent (`butter chicken`, `aioli`, `marzipan`).

IngredientLink audit: 10,571 links across all 1,500 recipe owners. No IngredientLink targets another recipe (`nestedRecipeLinks = 0`), so recipes do not nest in this corpus. Propagation used depth 1; the guarded cap is 16 for future nested data.

## FC1-G8 concept sizes

| Concept | Members | Share of 14,484 |
|---|---:|---:|
| `alcohol` | 113 | 0.780% |
| `allium` | 106 | 0.732% |
| `beef` | 1,506 | 10.398% |
| `caffeine` | 141 | 0.973% |
| `chicken` | 734 | 5.068% |
| `crustacean` | 106 | 0.732% |
| `dairy` | 2,153 | 14.865% |
| `duck` | 33 | 0.228% |
| `egg` | 376 | 2.596% |
| `fish` | 450 | 3.107% |
| `game` | 88 | 0.608% |
| `gluten` | 489 | 3.376% |
| `honey` | 31 | 0.214% |
| `lamb` | 317 | 2.189% |
| `meat` | 3,890 | 26.857% **FLAG >25%** |
| `mollusc` | 68 | 0.469% |
| `nightshade` | 599 | 4.136% |
| `peanut` | 161 | 1.112% |
| `pork` | 712 | 4.916% |
| `poultry` | 1,039 | 7.173% |
| `sesame` | 169 | 1.167% |
| `shellfish` | 181 | 1.250% |
| `soy` | 245 | 1.692% |
| `tree_nuts` | 209 | 1.443% |
| `turkey` | 347 | 2.396% |

`meat` has 3,890 members (26.857%) because it is the hierarchy parent of beef, pork, lamb, game, and poultry, and also receives propagated recipe membership. It is above the 25% review threshold but below the 40% stop threshold. No other concept exceeds 25%.

## FC1-G12 cross-derivation agreement

| Concept | Disagreements |
|---|---:|
| `dairy` | 27 |
| `egg` | 1 |
| `gluten` | 120 |
| `soy` | 4 |
| `sesame` | 0 |
| `peanut` | 0 |
| `tree_nuts` | 163 |
| `fish` | 4 |
| `shellfish` | 1 |
| `crustacean` | 0 |
| `mollusc` | 1 |
| `meat` | 65 |
| `honey` | 831 |
| **Total** | **1,217** |

Interpretation matters: this is an equivalence audit, not a silent merge. For allergen concepts, WE-8 reasons are reviewed category/rule/ingredient derivations while FC-1 reasons are ontology name/hierarchy/ingredient matches. For `meat`, the compared WE-8 condition is non-pescatarian/non-vegetarian diet state. For `honey`, the available WE-8 comparison is non-vegan state, which is not logically equivalent to honey: dairy and other animal-derived ingredients also remove Vegan. That asymmetry accounts for much of the 831-row honey disagreement count and must not be “fixed” by copying either side.

### Exhaustive disagreement appendix

Every row below includes both boolean results and both recorded derivation reason trails. No row was reconciled.

#### dairy (27)

- `dravya.basundi` / `900032` — Basundi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.besan-ladoo` / `900036` — Besan ladoo: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.chaas-masala` / `900061` — Buttermilk masala: FC-1=`true` [name:buttermilk]; WE-8=`false` [category:spice]
- `dravya.chhena` / `900067` — Chhena (fresh curd cheese): FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.chhurpi` / `900068` — Chhurpi (Himalayan hard cheese): FC-1=`false` [no-match]; WE-8=`true` [category:regional; reviewed-allergen:Milk]
- `dravya.chyawanprash` / `900073` — Chyawanprash: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; honey-min-age:12; reviewed-allergen:Milk]
- `dravya.custard-apple` / `8851` — Custard apple (sitaphal): FC-1=`true` [name:custard]; WE-8=`false` [category:fruit; existing-usda:8851]
- `dravya.filter-coffee` / `900107` — South Indian filter coffee: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk]
- `dravya.halwa-carrot` / `900141` — Carrot halwa: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.kadhi` / `900166` — Kadhi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.kharvas` / `900178` — Kharvas (colostrum pudding): FC-1=`false` [no-match]; WE-8=`true` [category:regional; reviewed-allergen:Milk]
- `dravya.kheer-rice` / `239` — Rice kheer: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; existing-usda:239; reviewed-allergen:Milk]
- `dravya.lassi-digestive` / `900190` — Cumin lassi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.lassi-sweet` / `900191` — Sweet lassi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.masala-chai` / `900208` — Masala chai: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk]
- `dravya.moong-dal-halwa` / `900214` — Moong dal halwa: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.panchamrita` / `900236` — Panchamrita: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; honey-min-age:12; reviewed-allergen:Milk]
- `dravya.payasam-mung` / `900243` — Mung payasam: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.pongal-sweet` / `900253` — Sweet pongal: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.pongal-ven` / `900254` — Ven pongal: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.rabri` / `900262` — Rabri: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.shrikhand` / `900312` — Shrikhand: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.sooji-halwa` / `900320` — Sooji halwa (sheera): FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Cereals containing gluten; reviewed-allergen:Milk]
- `dravya.thandai` / `900343` — Thandai: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk; reviewed-allergen:Nuts]
- `recipe.beverage-cumin-oat-milk-tonic` / `1000134` — Cumin Oat-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-golden-oat-milk-tonic-ii` / `1000141` — Golden Oat-Milk Tonic II: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-turmeric-soy-milk-tonic` / `1000167` — Turmeric Soy-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]

#### egg (1)

- `dravya.custard-apple` / `8851` — Custard apple (sitaphal): FC-1=`true` [name:custard]; WE-8=`false` [category:fruit; existing-usda:8851]

#### gluten (120)

- `dravya.khakhra` / `900176` — Khakhra: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Cereals containing gluten]
- `dravya.oat-milk` / `29` — Oat milk: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; existing-usda:29; reviewed-allergen:Cereals containing gluten (oats)]
- `dravya.oats` / `2918` — Oats: FC-1=`false` [no-match]; WE-8=`true` [category:grain; existing-usda:2918; reviewed-allergen:Cereals containing gluten (oats)]
- `dravya.paratha-plain` / `900240` — Plain paratha: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Cereals containing gluten]
- `dravya.puran-poli` / `900260` — Puran poli: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Cereals containing gluten]
- `dravya.puri` / `2218` — Puri: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; existing-usda:2218; reviewed-allergen:Cereals containing gluten]
- `dravya.ragi-malt` / `900265` — Ragi malt (beverage): FC-1=`true` [name:malt]; WE-8=`false` [category:beverage]
- `dravya.rice-puffed` / `10657` — Puffed rice: FC-1=`false` [no-match]; WE-8=`true` [category:grain; existing-usda:10657]
- `dravya.roti` / `8965` — Roti (chapati): FC-1=`false` [no-match]; WE-8=`true` [category:preparation; existing-usda:8965; reviewed-allergen:Cereals containing gluten]
- `dravya.thepla` / `900346` — Methi thepla: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Cereals containing gluten]
- `dravya.upma` / `3554` — Semolina upma: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; existing-usda:3554; reviewed-allergen:Cereals containing gluten]
- `dravya.vermicelli` / `900362` — Vermicelli (seviyan): FC-1=`false` [no-match]; WE-8=`true` [category:grain; reviewed-allergen:Cereals containing gluten]
- `dravya.wheatgrass` / `900370` — Wheatgrass: FC-1=`false` [no-match]; WE-8=`true` [category:medicinal; reviewed-allergen:Cereals containing gluten]
- `recipe.asia-soba-mushroom-kale` / `1000059` — Soba with Mushroom and Kale: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-soba-tempeh-green-bean` / `1000060` — Soba with Tempeh and Green Beans: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-soba-tofu-carrot` / `1000061` — Soba with Tofu and Carrot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-apple-cinnamon-oat-drink` / `1000122` — Apple Cinnamon Oat Drink: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-banana-cinnamon-oat-drink` / `1000123` — Banana Cinnamon Oat Drink: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-carrot-fennel-oat-drink` / `1000128` — Carrot Fennel Oat Drink: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-cinnamon-oat-milk-tonic` / `1000131` — Cinnamon Oat-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-cumin-oat-milk-tonic` / `1000134` — Cumin Oat-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-golden-oat-milk-tonic-ii` / `1000141` — Golden Oat-Milk Tonic II: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-nutmeg-oat-milk-tonic` / `1000150` — Nutmeg Oat-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-papaya-fennel-oat-drink` / `1000152` — Papaya Fennel Oat Drink: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-pumpkin-fennel-oat-cup` / `1000160` — Pumpkin Fennel Oat Cup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-saffron-oat-milk-drink` / `1000162` — Saffron Oat-Milk Evening Drink: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-sweet-potato-cinnamon-oat-drink` / `1000165` — Sweet Potato Cinnamon Oat Drink: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-buckwheat-wheat-galette` / `1000198` — Buckwheat Wheat Galette: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-amaranth-date-porridge` / `1000228` — Amaranth Date Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-banana-dairy-oat-porridge` / `1000231` — Banana Dairy Oat Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-brown-rice-raisin-porridge` / `1000239` — Brown Rice Raisin Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-buckwheat-prune-porridge` / `1000242` — Buckwheat Prune Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-chia-apple-warm-porridge` / `1000244` — Warm Chia Apple Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-millet-peach-porridge` / `1000249` — Millet Peach Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-almond-raisin-granola` / `1000252` — Oat Almond Raisin Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apple-almond-porridge` / `1000253` — Warm Apple Almond Oat Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apple-pancakes` / `1000254` — Oat Apple Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apricot-granola` / `1000255` — Oat Apricot Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apricot-porridge` / `1000256` — Warm Apricot Oat Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-blueberry-porridge` / `1000257` — Warm Blueberry Oat Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-pear-porridge` / `1000258` — Warm Pear Oat Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-pumpkin-seed-granola` / `1000259` — Oat Pumpkin Seed Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-strawberry-pancakes` / `1000260` — Oat Strawberry Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-walnut-date-granola` / `1000261` — Oat Walnut Date Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-quinoa-blueberry-porridge` / `1000262` — Quinoa Blueberry Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-savory-oat-carrot` / `1000273` — Savory Oat Carrot Breakfast: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.curd-oats-bowl` / `1000417` — Curd Oats Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-almond-chia-pear-pudding` / `1000426` — Warm Almond Chia Pear Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-apple-oat-crumble` / `1000433` — Warm Apple Oat Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-apricot-pistachio-crisp` / `1000434` — Warm Apricot Pistachio Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-banana-dairy-oat-pudding` / `1000435` — Banana Dairy Oat Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-banana-oat-bake` / `1000436` — Warm Banana Oat Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-beet-pear-bake` / `1000437` — Beet Pear Dessert Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-blueberry-oat-crumble` / `1000439` — Warm Blueberry Oat Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-blueberry-peach-crisp` / `1000440` — Blueberry Peach Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-carrot-apple-bake` / `1000441` — Carrot Apple Dessert Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-cherry-almond-crisp` / `1000443` — Warm Cherry Almond Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-date-apple-bake` / `1000446` — Warm Date Apple Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-fig-walnut-bake` / `1000447` — Warm Fig Walnut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-grape-pear-bake` / `1000448` — Warm Grape Pear Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-mango-coconut-bake` / `1000449` — Warm Mango Coconut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-oat-amaranth-fig-pudding` / `1000451` — Oat-Milk Amaranth Fig Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-oat-date-truffles` / `1000452` — Oat Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-oat-quinoa-pudding` / `1000453` — Oat-Milk Quinoa Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-oat-ragi-date-pudding` / `1000454` — Oat-Milk Ragi Date Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-peach-almond-crisp` / `1000455` — Warm Peach Almond Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pear-walnut-crumble` / `1000458` — Warm Pear Walnut Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pineapple-coconut-bake` / `1000459` — Warm Pineapple Coconut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-plum-oat-crisp` / `1000462` — Warm Plum Oat Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pomegranate-pear-bake` / `1000463` — Warm Pomegranate Pear Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pumpkin-apple-crumble` / `1000464` — Pumpkin Apple Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-strawberry-apple-crisp` / `1000468` — Strawberry Apple Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-sweet-potato-pear-crumble` / `1000471` — Sweet Potato Pear Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-banana-oat-smoothie` / `1000481` — Banana Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-beet-apple-oat-smoothie` / `1000482` — Beet Apple Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-blueberry-pear-oat-smoothie` / `1000485` — Blueberry Pear Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-cinnamon-oat-warmer` / `1000490` — Cinnamon Oat-Milk Warmer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-fig-oat-smoothie` / `1000494` — Fig Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-fig-oat-warmer` / `1000495` — Fig Oat-Milk Warmer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-ginger-oat-warmer` / `1000496` — Ginger Oat-Milk Warmer: FC-1=`false` [no-match]; WE-8=`true` [honey-min-age:12; ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-kale-apple-oat-smoothie` / `1000498` — Kale Apple Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-oat-nutmeg-warmer` / `1000502` — Nutmeg Oat-Milk Warmer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-oat-rose-warmer` / `1000503` — Rose Oat-Milk Warmer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-peach-oat-smoothie` / `1000506` — Peach Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-pear-oat-smoothie` / `1000507` — Pear Oat Cardamom Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-pistachio-oat-warmer` / `1000510` — Pistachio Oat-Milk Warmer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-plum-oat-smoothie` / `1000511` — Plum Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-strawberry-oat-smoothie` / `1000520` — Strawberry Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-sweet-potato-oat-smoothie` / `1000522` — Sweet Potato Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-oat-zucchini-chilla` / `1000587` — Oat Zucchini Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-savory-oat-tiffin` / `1000607` — Savory Oat Tiffin Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-oat-sweet-potato-dal` / `1000685` — Hemanta Oat Sweet Potato Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-oat-carrot-pea-bowl` / `1000750` — Savory Warm Oat Carrot Pea Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-oat-spinach-tofu-bowl` / `1000751` — Savory Warm Oat Spinach Tofu Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kapha-oat-masoor-spinach-stew` / `1000814` — Kapha Oat Masoor Spinach Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kapha-oat-mung-turnip-bowl` / `1000815` — Kapha Oat Mung Turnip Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-oat-fennel-peya` / `1000932` — Oat Fennel Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-oat-pumpkin-peya` / `1000933` — Oat Pumpkin Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-zucchini-oat-mash` / `1000953` — Zucchini Oat Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-buckwheat-thyme-flatbread` / `1000974` — Buckwheat Thyme Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.murmura-chikki` / `1001035` — Murmura Chikki: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.oats-cardamom-kheer` / `1001038` — Oats Cardamom Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.oats-spiced-porridge` / `1001039` — Spiced Oats Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.puffed-rice-morning-chivda` / `1001088` — Warm Puffed Rice Morning Chivda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-oat-pumpkin-masoor` / `1001164` — Shishira Oat Pumpkin Masoor: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-buckwheat-dill-flatbread` / `1001178` — Buckwheat Dill Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-oat-date-energy-balls` / `1001199` — Oat Date Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-oat-masoor-carrot` / `1001321` — Tridoshic Oat Masoor Carrot Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-oat-mung-pumpkin-bowl` / `1001322` — Tridoshic Oat Mung Pumpkin Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-oat-carrot-masoor` / `1001348` — Varsha Oat Carrot Masoor Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vasanta-oat-spinach-masoor` / `1001358` — Vasanta Oat Spinach Masoor Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-oat-sweet-potato-dal-bowl` / `1001370` — Vata Oat Sweet Potato Dal Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-fennel-porridge` / `1001396` — Vrat Amaranth Fennel Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-oat-milk-porridge` / `1001422` — Vrat Chestnut Oat-Milk Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-carrot-masoor-oats` / `1001451` — Weeknight Carrot Masoor Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-chayote-masoor-oats` / `1001459` — Weeknight Chayote Masoor Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-pumpkin-mung-oats` / `1001473` — Weeknight Pumpkin Mung Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-spinach-mung-oats` / `1001477` — Weeknight Spinach Mung Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-tomato-masoor-oats` / `1001484` — Weeknight Tomato Masoor Oats: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-zucchini-masoor-oats` / `1001489` — Weeknight Zucchini Masoor Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]

#### soy (4)

- `dravya.hawaijar` / `900144` — Hawaijar (fermented soybean): FC-1=`false` [no-match]; WE-8=`true` [category:fermented; reviewed-allergen:Soybeans]
- `dravya.kinema` / `900183` — Kinema (fermented soybean): FC-1=`false` [no-match]; WE-8=`true` [category:fermented; reviewed-allergen:Soybeans]
- `dravya.soy-milk` / `10553` — Soy milk: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; existing-usda:10553; reviewed-allergen:Soybeans]
- `dravya.soybean` / `10976` — Soybean: FC-1=`false` [no-match]; WE-8=`true` [category:legume; existing-usda:10976; reviewed-allergen:Soybeans]

#### tree_nuts (163)

- `dravya.almond` / `7884` — Almond: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7884; reviewed-allergen:Nuts (almonds)]
- `dravya.badam-milk` / `900022` — Badam milk: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk; reviewed-allergen:Nuts (almonds)]
- `dravya.brazil-nut` / `7886` — Brazil nut: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7886; reviewed-allergen:Nuts (Brazil nuts)]
- `dravya.chestnut` / `7892` — Chestnut: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7892; reviewed-allergen:Nuts (chestnuts)]
- `dravya.chironji` / `900072` — Chironji (charoli): FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; reviewed-allergen:Nuts]
- `dravya.coconut-chutney` / `900076` — Coconut chutney: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Nuts (coconut)]
- `dravya.coconut-dried` / `7896` — Coconut, dried: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7896; reviewed-allergen:Nuts (coconut)]
- `dravya.coconut-fresh` / `7556` — Coconut, fresh: FC-1=`false` [no-match]; WE-8=`true` [category:fruit; existing-usda:7556; reviewed-allergen:Nuts (coconut)]
- `dravya.coconut-oil` / `8580` — Coconut oil: FC-1=`false` [no-match]; WE-8=`true` [category:oil-fat; existing-usda:8580; reviewed-allergen:Nuts (coconut)]
- `dravya.coconut-rice` / `900077` — Coconut rice: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Nuts (coconut)]
- `dravya.coconut-sugar` / `900078` — Coconut sugar: FC-1=`false` [no-match]; WE-8=`true` [category:sweetener; reviewed-allergen:Nuts (coconut)]
- `dravya.coconut-vinegar` / `900079` — Coconut vinegar: FC-1=`false` [no-match]; WE-8=`true` [category:regional; reviewed-allergen:Nuts (coconut)]
- `dravya.coconut-water` / `7561` — Coconut water: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; existing-usda:7561; reviewed-allergen:Nuts (coconut)]
- `dravya.desiccated-coconut` / `7557` — Desiccated coconut: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7557; reviewed-allergen:Nuts (coconut)]
- `dravya.dry-coconut` / `900096` — Dry coconut (copra): FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; reviewed-allergen:Nuts (coconut)]
- `dravya.hazelnut` / `7898` — Hazelnut: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7898; reviewed-allergen:Nuts (hazelnuts)]
- `dravya.panchmeva` / `900237` — Panchmeva (five dry fruits): FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; reviewed-allergen:Nuts]
- `dravya.pecan` / `7568` — Pecan: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7568; reviewed-allergen:Nuts (pecans)]
- `dravya.pine-nut` / `7907` — Pine nut: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7907; reviewed-allergen:Nuts (pine nuts)]
- `dravya.tender-coconut-flesh` / `900340` — Tender coconut flesh: FC-1=`false` [no-match]; WE-8=`true` [category:fruit; reviewed-allergen:Nuts (coconut)]
- `dravya.thandai` / `900343` — Thandai: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk; reviewed-allergen:Nuts]
- `dravya.walnut` / `7573` — Walnut: FC-1=`false` [no-match]; WE-8=`true` [category:dry-fruit-nut; existing-usda:7573; reviewed-allergen:Nuts (walnuts)]
- `recipe.ash-gourd-kootu` / `1000029` — Ash Gourd Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ash-gourd-poriyal` / `1000031` — Ash Gourd Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-black-bean-pumpkin-curry` / `1000033` — Black Bean Pumpkin Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-chickpea-cauliflower-curry` / `1000039` — Chickpea Cauliflower Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-chickpea-plantain-curry` / `1000040` — Chickpea Plantain Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-coconut-pumpkin-rice` / `1000041` — Coconut Pumpkin Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-green-pea-broccoli-curry` / `1000046` — Green Pea Broccoli Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-lentil-eggplant-curry` / `1000047` — Lentil Eggplant Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-mung-zucchini-curry` / `1000049` — Mung Zucchini Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-tempeh-sweet-potato-curry` / `1000070` — Tempeh Sweet Potato Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-tofu-mushroom-coconut-curry` / `1000077` — Tofu Mushroom Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-tofu-pumpkin-coconut-curry` / `1000079` — Tofu Pumpkin Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.asia-tofu-spinach-coconut-curry` / `1000080` — Tofu Spinach Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.avial` / `1000082` — Avial: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bagara-khichdi-bajra` / `1000083` — Millet-Curd Rice (Cooling): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.barley-kheer` / `1000091` — Barley Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beans-poriyal` / `1000098` — Beans Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beetroot-kootu` / `1000104` — Beetroot Coconut Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beetroot-poriyal` / `1000106` — Beetroot Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-coconut-cholar-dal` / `1000109` — Bengali Coconut Cholar Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.besan-laddu` / `1000118` — Besan Laddu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.besan-sheera-postpartum` / `1000120` — Besan Sheera: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-fennel-coconut-milk-tonic` / `1000137` — Fennel Coconut-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bottle-gourd-kootu` / `1000175` — Bottle Gourd Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-amaranth-date-porridge` / `1000228` — Amaranth Date Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-barley-apple-porridge` / `1000235` — Barley Apple Cinnamon Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-brown-rice-raisin-porridge` / `1000239` — Brown Rice Raisin Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-buckwheat-prune-porridge` / `1000242` — Buckwheat Prune Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-millet-peach-porridge` / `1000249` — Millet Peach Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apricot-granola` / `1000255` — Oat Apricot Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apricot-porridge` / `1000256` — Warm Apricot Oat Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-ragi-coconut-granola` / `1000267` — Ragi Coconut Granola Clusters: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cabbage-kootu` / `1000279` — Cabbage Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cabbage-thoran` / `1000283` — Cabbage Thoran: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-halwa-classic` / `1000288` — Gajar Halwa (Ghee-Milk): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-poriyal` / `1000292` — Carrot Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.coconut-coriander-water` / `1000302` — Coconut Coriander Water: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.coconut-ladoo` / `1000303` — Coconut Ladoo: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-coconut-mint-chutney-ii` / `1000317` — Coconut Mint Chutney II: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-peanut-fennel-dry-chutney` / `1000337` — Peanut Fennel Dry Chutney: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-sesame-coriander-dry-chutney` / `1000345` — Sesame Coriander Dry Chutney: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.curry-leaf-chutney` / `1000418` — Curry Leaf Chutney: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-apple-oat-crumble` / `1000433` — Warm Apple Oat Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-banana-oat-bake` / `1000436` — Warm Banana Oat Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-beet-pear-bake` / `1000437` — Beet Pear Dessert Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-blueberry-oat-crumble` / `1000439` — Warm Blueberry Oat Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-carrot-apple-bake` / `1000441` — Carrot Apple Dessert Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-coconut-date-truffles` / `1000444` — Coconut Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-coconut-fig-truffles` / `1000445` — Coconut Fig Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-date-apple-bake` / `1000446` — Warm Date Apple Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-grape-pear-bake` / `1000448` — Warm Grape Pear Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-mango-coconut-bake` / `1000449` — Warm Mango Coconut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-oat-date-truffles` / `1000452` — Oat Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pineapple-coconut-bake` / `1000459` — Warm Pineapple Coconut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-plum-oat-crisp` / `1000462` — Warm Plum Oat Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pumpkin-apple-crumble` / `1000464` — Pumpkin Apple Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-sesame-date-truffles` / `1000466` — Sesame Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-strawberry-apple-crisp` / `1000468` — Strawberry Apple Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-sweet-potato-pear-crumble` / `1000471` — Sweet Potato Pear Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-blueberry-cow-milk-smoothie` / `1000484` — Blueberry Cow-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-cucumber-mint-coconut-smoothie` / `1000491` — Cucumber Mint Coconut-Water Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-grape-fennel-coconut-smoothie` / `1000497` — Grape Fennel Coconut-Water Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-mango-banana-coconut-smoothie` / `1000499` — Mango Banana Coconut-Water Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-mango-coconut-water-smoothie` / `1000500` — Mango Coconut Water Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-peach-oat-smoothie` / `1000506` — Peach Oat-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-pineapple-coconut-water-smoothie` / `1000508` — Pineapple Coconut Water Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-pomegranate-beet-coconut-smoothie` / `1000513` — Pomegranate Beet Coconut-Water Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dry-fruit-ladoo` / `1000527` — Dry Fruit Ladoo (No Sugar): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-coconut-mint-rice` / `1000563` — Coconut Mint Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-coconut-rice-sevai` / `1000564` — Coconut Rice Sevai: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-plantain-chickpea-curry` / `1000593` — Green Plantain Chickpea Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-ragi-cardamom-breakfast` / `1000601` — Ragi Cardamom Breakfast Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.green-bean-kootu` / `1000650` — Green Bean Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.grishma-fennel-kitchari` / `1000659` — Grishma Fennel-Coconut Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.gujarati-surti-winter-undhiyu` / `1000677` — Gujarati Surti Winter Undhiyu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-coconut-chickpea-stew` / `1000728` — Coconut Chickpea Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-white-rice-green-bean-coconut-bowl` / `1000786` — Warm Rice Green Bean Coconut Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-beet-sesame-palya` / `1000820` — Karnataka Beet Sesame Palya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-cabbage-pea-palya` / `1000822` — Karnataka Cabbage Pea Palya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-chayote-majjige-huli` / `1000823` — Karnataka Chayote Majjige Huli: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-coconut-sesame-rice-bath` / `1000824` — Karnataka Coconut Sesame Rice Bath: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-green-bean-coconut-palya` / `1000826` — Karnataka Green Bean Coconut Palya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-ash-gourd-mung-olan` / `1000832` — Kerala Ash Gourd Mung Olan: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-beet-coconut-thoran` / `1000833` — Kerala Beet Coconut Thoran: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-cabbage-carrot-thoran` / `1000834` — Kerala Cabbage Carrot Thoran: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-chayote-coconut-stew` / `1000835` — Kerala Chayote Coconut Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-eggplant-theeyal` / `1000836` — Kerala Eggplant Theeyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-green-bean-thoran` / `1000837` — Kerala Green Bean Thoran: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-plantain-mung-erissery` / `1000838` — Kerala Green Plantain Erissery: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-pumpkin-mung-erissery` / `1000839` — Kerala Pumpkin Mung Erissery: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-pumpkin-pea-olan` / `1000840` — Kerala Pumpkin and Pea Olan: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-ridge-gourd-coconut-curry` / `1000841` — Kerala Ridge Gourd Coconut Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-root-vegetable-avial` / `1000842` — Kerala Root Vegetable Avial: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-spinach-mung-molagootal` / `1000843` — Kerala Spinach Mung Molagootal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-taro-pepper-curry` / `1000844` — Kerala Taro Pepper Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kootu` / `1000846` — Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.lauki-halwa` / `1000897` — Lauki Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.masala-doodh` / `1000957` — Masala Doodh: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mint-coconut-chutney` / `1001019` — Mint Coconut Chutney: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mint-rice` / `1001023` — Mint Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.modak-ukadiche` / `1001027` — Ukadiche Modak: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mung-panjiri` / `1001032` — Mung Panjiri: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.oats-cardamom-kheer` / `1001038` — Oats Cardamom Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.okra-coconut-poriyal` / `1001042` — Okra Coconut Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.olan` / `1001043` — Olan: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-broccoli-tofu-rice-bowl` / `1001063` — Pitta Broccoli Tofu Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-coconut-cilantro-rice-dal` / `1001068` — Pitta Coconut Cilantro Rice Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-coconut-tofu-rice-noodles` / `1001069` — Pitta Coconut Tofu Rice Noodles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-cooked-sprout-rice-bowl` / `1001070` — Pitta Cooked Sprout Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-green-bean-coconut-rice` / `1001078` — Pitta Green Bean Coconut Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-pumpkin-quinoa-mung-bowl` / `1001079` — Pitta Pumpkin Quinoa Mung Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-sweet-potato-mung-rice` / `1001081` — Pitta Sweet Potato Mung Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.plantain-curry-leaf-sabzi` / `1001084` — Green Plantain Curry-Leaf Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.plantain-poriyal` / `1001085` — Green Plantain Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-kootu` / `1001091` — Pumpkin Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-poriyal` / `1001095` — Pumpkin Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-seed-chutney` / `1001098` — Pumpkin Seed Chutney: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ragi-halwa` / `1001115` — Ragi Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ridge-gourd-kootu` / `1001138` — Ridge Gourd Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-cauliflower-herb-dip` / `1001182` — Cauliflower Herb Dip: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-coconut-date-bites` / `1001185` — Coconut Date Snack Bites: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-green-pea-mint-dip` / `1001195` — Green Pea Mint Snack Dip: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-oat-date-energy-balls` / `1001199` — Oat Date Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spinach-coconut-thoran` / `1001220` — Spinach Coconut Thoran: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spinach-kootu` / `1001221` — Spinach Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sweet-potato-halwa` / `1001281` — Sweet Potato Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-bottle-gourd-mung-kootu` / `1001288` — Tamil Bottle Gourd Mung Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-bottle-gourd-poricha-kuzhambu` / `1001289` — Tamil Bottle Gourd Poricha Kuzhambu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-chayote-chana-kootu` / `1001291` — Tamil Chayote Chana Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-coconut-cumin-rice` / `1001292` — Tamil Coconut Cumin Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-okra-mor-kuzhambu` / `1001297` — Tamil Okra Mor Kuzhambu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.undhiyu-light` / `1001337` — Light Undhiyu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-coconut-chana-rice-bowl` / `1001366` — Vata Coconut Chana Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-cardamom-kheer` / `1001394` — Vrat Amaranth Cardamom Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-apple-amaranth-bake` / `1001403` — Vrat Apple Amaranth Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-baked-yam-patties` / `1001406` — Vrat Baked Yam Patties: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-coconut-lemon-sabudana` / `1001428` — Vrat Coconut Lemon Sabudana: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-pumpkin-coconut-stew` / `1001435` — Vrat Pumpkin Coconut Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.whole-wheat-halwa` / `1001494` — Whole Wheat Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.whole-wheat-panjiri` / `1001495` — Whole Wheat Panjiri: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.zucchini-poriyal` / `1001500` — Zucchini Poriyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]

#### fish (4)

- `dravya.catla` / `900058` — Catla: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.hilsa` / `900146` — Hilsa: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.pomfret` / `900252` — Pomfret: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.rohu` / `900289` — Rohu (freshwater fish): FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]

#### shellfish (1)

- `dravya.oyster-mushroom` / `6110` — Oyster mushroom: FC-1=`true` [hierarchy:mollusc]; WE-8=`false` [category:vegetable; existing-usda:6110]

#### mollusc (1)

- `dravya.oyster-mushroom` / `6110` — Oyster mushroom: FC-1=`true` [name:oyster]; WE-8=`false` [category:vegetable; existing-usda:6110]

#### meat (65)

- `dravya.catla` / `900058` — Catla: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.crab` / `871` — Crab: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:871; reviewed-allergen:Crustaceans]
- `dravya.desi-egg` / `900091` — Country chicken egg: FC-1=`true` [hierarchy:chicken]; WE-8=`false` [category:animal; reviewed-allergen:Eggs]
- `dravya.dried-fish` / `12220` — Dried fish: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:12220; reviewed-allergen:Fish]
- `dravya.duck-egg` / `9240` — Duck egg: FC-1=`true` [hierarchy:duck]; WE-8=`false` [category:animal; existing-usda:9240; reviewed-allergen:Eggs]
- `dravya.goat-liver` / `900123` — Goat liver: FC-1=`false` [no-match]; WE-8=`true` [category:animal]
- `dravya.hilsa` / `900146` — Hilsa: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.mackerel` / `790` — Mackerel (bangda): FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:790; reviewed-allergen:Fish]
- `dravya.paya-soup` / `900242` — Trotters soup (paya): FC-1=`false` [no-match]; WE-8=`true` [category:animal]
- `dravya.pomfret` / `900252` — Pomfret: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.potato` / `7413` — Potato: FC-1=`true` [name:flesh]; WE-8=`false` [category:vegetable; existing-usda:7413]
- `dravya.prawn` / `11772` — Prawn: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:11772; reviewed-allergen:Crustaceans]
- `dravya.quail-egg` / `9242` — Quail egg: FC-1=`true` [hierarchy:game]; WE-8=`false` [category:animal; existing-usda:9242; reviewed-allergen:Eggs]
- `dravya.rohu` / `900289` — Rohu (freshwater fish): FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.salmon` / `811` — Salmon: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:811; reviewed-allergen:Fish]
- `dravya.sardine` / `11733` — Sardine: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:11733; reviewed-allergen:Fish]
- `dravya.seer-fish` / `900306` — Seer fish (surmai): FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.tender-coconut-flesh` / `900340` — Tender coconut flesh: FC-1=`true` [name:flesh]; WE-8=`false` [category:fruit; reviewed-allergen:Nuts (coconut)]
- `dravya.tuna` / `835` — Tuna: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:835; reviewed-allergen:Fish]
- `recipe.aloo-jeera` / `1000006` — Aloo Jeera: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.aloo-paratha-light` / `1000007` — Aloo Paratha: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.baked-vegetable-cutlet` / `1000089` — Baked Vegetable Cutlet: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-baked-dhokar-dalna` / `1000107` — Bengali Baked Dhokar Dalna: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-cabbage-chickpea-ghonto` / `1000108` — Bengali Cabbage Chickpea Ghonto: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-mung-shukto` / `1000111` — Bengali Mung Shukto: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-potato-poppy-seed` / `1000113` — Bengali Potato Poppy Seed Curry: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-pumpkin-bean-chorchori` / `1000114` — Bengali Pumpkin Bean Chorchori: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-bajra-potato-roti` / `1000181` — Bajra Potato Roti: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-buckwheat-potato-roti` / `1000197` — Buckwheat Potato Roti: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-corn-potato-makki-roti` / `1000204` — Corn Potato Makki Roti: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-jowar-potato-roti` / `1000209` — Jowar Potato Roti: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-artichoke-potato-bake` / `1000355` — Artichoke Potato Rosemary Bake: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-artichoke-potato-roast` / `1000356` — Artichoke Potato Tray Roast: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-potato-carrot-rosemary-roast` / `1000384` — Potato Carrot Rosemary Roast: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-potato-leek-cottage-gratin` / `1000385` — Potato Leek Cottage Cheese Gratin: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-buckwheat-potato-pancake` / `1000549` — Buckwheat Potato Pancake: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-chickpea-potato-curry` / `1000561` — Chickpea Potato Curry: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-okra-potato-curry` / `1000588` — Okra Potato Curry: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fasting-kuttu-roti` / `1000629` — Kuttu Roti (Fasting): FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.gujarati-eggplant-potato-shaak` / `1000670` — Gujarati Eggplant Potato Shaak: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-artichoke-leek-soup` / `1000694` — Artichoke Leek Soup: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-green-bean-potato-stew` / `1000732` — Green Bean Potato Stew: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-mushroom-thyme-soup` / `1000749` — Mushroom Thyme Soup: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-potato-leek-soup` / `1000753` — Potato Leek Soup: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-radish-spinach-soup` / `1000768` — Radish Spinach Soup: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-turnip-parsley-soup` / `1000783` — Turnip Parsley Soup: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.latin-corn-potato-pepper-stew` / `1000868` — Corn Potato Pepper Stew: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-artichoke-potato-bake` / `1000966` — Artichoke Potato Herb Bake: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-spinach-potato-cottage-bake` / `1001009` — Spinach Potato Cottage Cheese Bake: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.methi-aloo` / `1001013` — Methi Aloo: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.navratri-kuttu-thali` / `1001037` — Navratri Fasting Thali: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-cumin-aloo-gobi` / `1001103` — Punjabi Cumin Aloo Gobi: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-potato-onion-saag` / `1001128` — Rajasthani Potato Onion Saag: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-potato-flatbread` / `1001397` — Vrat Amaranth Potato Flatbread: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-potato-pilaf` / `1001398` — Vrat Amaranth Potato Pilaf: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-baked-sabudana-vada` / `1001405` — Vrat Baked Sabudana Vada: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-cumin-khichdi` / `1001409` — Vrat Buckwheat Cumin Khichdi: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-dumpling-kadhi` / `1001410` — Vrat Buckwheat Dumpling Kadhi: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-potato-roti` / `1001413` — Vrat Buckwheat Potato Roti: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-potato-cakes` / `1001423` — Vrat Chestnut Potato Cakes: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-potato-flatbread` / `1001424` — Vrat Chestnut Potato Flatbread: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-cumin-potato-curry` / `1001429` — Vrat Cumin Potato Curry: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-cumin-sabudana-khichdi` / `1001430` — Vrat Cumin Sabudana Khichdi: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-lotus-sabudana-khichdi` / `1001432` — Vrat Lotus Seed Sabudana Khichdi: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-sabudana-potato-thalipeeth` / `1001437` — Vrat Sabudana Potato Thalipeeth: FC-1=`true` [ingredient:7413]; WE-8=`false` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]

#### honey (831)

- `dravya.aged-cheese` / `259` — Cheese, aged (cheddar): FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:259; reviewed-allergen:Milk]
- `dravya.badam-milk` / `900022` — Badam milk: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk; reviewed-allergen:Nuts (almonds)]
- `dravya.basundi` / `900032` — Basundi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.besan-ladoo` / `900036` — Besan ladoo: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.broiler-chicken` / `8262` — Chicken (broiler): FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:8262]
- `dravya.buffalo-ghee` / `900050` — Buffalo ghee: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.buffalo-milk` / `8477` — Buffalo milk: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:8477; reviewed-allergen:Milk]
- `dravya.butter` / `10276` — Butter, unsalted: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:10276; reviewed-allergen:Milk]
- `dravya.buttermilk` / `10` — Buttermilk: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:10; reviewed-allergen:Milk]
- `dravya.camel-milk` / `900053` — Camel milk: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.catla` / `900058` — Catla: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.chhena` / `900067` — Chhena (fresh curd cheese): FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.chhurpi` / `900068` — Chhurpi (Himalayan hard cheese): FC-1=`false` [no-match]; WE-8=`true` [category:regional; reviewed-allergen:Milk]
- `dravya.chicken-egg` / `8484` — Chicken egg: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:8484; reviewed-allergen:Eggs]
- `dravya.chyawanprash` / `900073` — Chyawanprash: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; honey-min-age:12; reviewed-allergen:Milk]
- `dravya.colostrum-milk` / `900082` — Colostrum milk: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.condensed-milk` / `19` — Condensed milk, sweetened: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:19; reviewed-allergen:Milk]
- `dravya.cottage-cheese` / `9231` — Cottage cheese: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:9231; reviewed-allergen:Milk]
- `dravya.country-chicken` / `900084` — Country chicken (desi): FC-1=`false` [no-match]; WE-8=`true` [category:animal]
- `dravya.crab` / `871` — Crab: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:871; reviewed-allergen:Crustaceans]
- `dravya.cream` / `8093` — Cream, heavy: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:8093; reviewed-allergen:Milk]
- `dravya.curd-rice` / `900086` — Curd rice: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.desi-egg` / `900091` — Country chicken egg: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Eggs]
- `dravya.dried-fish` / `12220` — Dried fish: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:12220; reviewed-allergen:Fish]
- `dravya.duck-egg` / `9240` — Duck egg: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:9240; reviewed-allergen:Eggs]
- `dravya.duck-meat` / `9417` — Duck meat: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:9417]
- `dravya.egg-bhurji` / `900099` — Egg bhurji: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Eggs]
- `dravya.filter-coffee` / `900107` — South Indian filter coffee: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk]
- `dravya.full-cream-milk` / `900113` — Full-cream milk (packaged): FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.ghee` / `4558` — Ghee: FC-1=`false` [no-match]; WE-8=`true` [category:oil-fat; existing-usda:4558; reviewed-allergen:Milk]
- `dravya.ghee-cultured` / `900116` — Cultured ghee: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.ghee-spiced` / `900117` — Spiced ghee: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.goat-liver` / `900123` — Goat liver: FC-1=`false` [no-match]; WE-8=`true` [category:animal]
- `dravya.goat-meat` / `11874` — Goat meat (mutton): FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:11874]
- `dravya.goat-milk` / `8475` — Milk, goat: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:8475; reviewed-allergen:Milk]
- `dravya.golden-milk` / `900125` — Golden milk: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.halwa-carrot` / `900141` — Carrot halwa: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.hilsa` / `900146` — Hilsa: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.hung-curd` / `900150` — Hung curd (chakka): FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.kadhi` / `900166` — Kadhi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.keema` / `900174` — Minced mutton (keema): FC-1=`false` [no-match]; WE-8=`true` [category:animal]
- `dravya.kefir` / `11` — Kefir: FC-1=`false` [no-match]; WE-8=`true` [category:fermented; existing-usda:11; reviewed-allergen:Milk]
- `dravya.kharvas` / `900178` — Kharvas (colostrum pudding): FC-1=`false` [no-match]; WE-8=`true` [category:regional; reviewed-allergen:Milk]
- `dravya.kheer-rice` / `239` — Rice kheer: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; existing-usda:239; reviewed-allergen:Milk]
- `dravya.khoya` / `900180` — Khoya (mawa): FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.lamb` / `9619` — Lamb: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:9619]
- `dravya.lassi-digestive` / `900190` — Cumin lassi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.lassi-sweet` / `900191` — Sweet lassi: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.mackerel` / `790` — Mackerel (bangda): FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:790; reviewed-allergen:Fish]
- `dravya.mamsa-rasa` / `900203` — Meat broth (mamsa rasa): FC-1=`false` [no-match]; WE-8=`true` [category:animal]
- `dravya.masala-chai` / `900208` — Masala chai: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk]
- `dravya.milk-cow` / `2` — Milk, whole cow: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:2; reviewed-allergen:Milk]
- `dravya.milk-powder` / `10295` — Milk powder: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:10295; reviewed-allergen:Milk]
- `dravya.moong-dal-halwa` / `900214` — Moong dal halwa: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.panchamrita` / `900236` — Panchamrita: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; honey-min-age:12; reviewed-allergen:Milk]
- `dravya.paneer` / `276` — Paneer: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:276; reviewed-allergen:Milk]
- `dravya.paya-soup` / `900242` — Trotters soup (paya): FC-1=`false` [no-match]; WE-8=`true` [category:animal]
- `dravya.payasam-mung` / `900243` — Mung payasam: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.pomfret` / `900252` — Pomfret: FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.pongal-sweet` / `900253` — Sweet pongal: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.pongal-ven` / `900254` — Ven pongal: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.pork` / `393` — Pork: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:393]
- `dravya.prawn` / `11772` — Prawn: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:11772; reviewed-allergen:Crustaceans]
- `dravya.quail-egg` / `9242` — Quail egg: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:9242; reviewed-allergen:Eggs]
- `dravya.quail-meat` / `9426` — Quail meat: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:9426]
- `dravya.rabri` / `900262` — Rabri: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.rohu` / `900289` — Rohu (freshwater fish): FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.rose-milk` / `900291` — Rose milk: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk]
- `dravya.salmon` / `811` — Salmon: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:811; reviewed-allergen:Fish]
- `dravya.sardine` / `11733` — Sardine: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:11733; reviewed-allergen:Fish]
- `dravya.seer-fish` / `900306` — Seer fish (surmai): FC-1=`false` [no-match]; WE-8=`true` [category:animal; reviewed-allergen:Fish]
- `dravya.sheep-milk` / `8115` — Sheep milk: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:8115; reviewed-allergen:Milk]
- `dravya.shrikhand` / `900312` — Shrikhand: FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Milk]
- `dravya.skimmed-milk` / `900316` — Skimmed milk: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; reviewed-allergen:Milk]
- `dravya.sooji-halwa` / `900320` — Sooji halwa (sheera): FC-1=`false` [no-match]; WE-8=`true` [category:preparation; reviewed-allergen:Cereals containing gluten; reviewed-allergen:Milk]
- `dravya.takra` / `8107` — Spiced buttermilk (takra): FC-1=`false` [no-match]; WE-8=`true` [category:preparation; existing-usda:8107; reviewed-allergen:Milk]
- `dravya.thandai` / `900343` — Thandai: FC-1=`false` [no-match]; WE-8=`true` [category:beverage; reviewed-allergen:Milk; reviewed-allergen:Nuts]
- `dravya.tuna` / `835` — Tuna: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:835; reviewed-allergen:Fish]
- `dravya.turkey` / `8645` — Turkey: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:8645]
- `dravya.venison` / `10623` — Venison: FC-1=`false` [no-match]; WE-8=`true` [category:animal; existing-usda:10623]
- `dravya.whey` / `148` — Whey (mastu): FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:148; reviewed-allergen:Milk]
- `dravya.yak-butter` / `900381` — Yak butter: FC-1=`false` [no-match]; WE-8=`true` [category:regional; reviewed-allergen:Milk]
- `dravya.yak-milk` / `900382` — Yak milk: FC-1=`false` [no-match]; WE-8=`true` [category:regional; reviewed-allergen:Milk]
- `dravya.yogurt` / `8481` — Yogurt, plain whole milk: FC-1=`false` [no-match]; WE-8=`true` [category:dairy; existing-usda:8481; reviewed-allergen:Milk]
- `recipe.adai` / `1000001` — Adai (Mixed-Dal Dosa): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ajwain-takra` / `1000003` — Ajwain Takra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.akki-roti` / `1000004` — Akki Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.almond-sesame-laddu` / `1000005` — Almond Sesame Laddu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.aloo-jeera` / `1000006` — Aloo Jeera: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.aloo-paratha-light` / `1000007` — Aloo Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.amaranth-cardamom-porridge` / `1000008` — Amaranth Cardamom Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.amaranth-kheer` / `1000009` — Amaranth Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.amaranth-leaf-sabzi` / `1000010` — Amaranth Leaf Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.amaranth-mung-kitchari` / `1000011` — Amaranth Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.amaranth-panjiri` / `1000012` — Amaranth Panjiri: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.andhra-cucumber-mung-pappu` / `1000014` — Andhra Cucumber Mung Pappu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.andhra-purslane-toor-pappu` / `1000020` — Andhra Purslane Toor Pappu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.andhra-ridge-gourd-chana-dal` / `1000021` — Andhra Ridge Gourd Chana Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.andhra-spinach-masoor-pappu` / `1000023` — Andhra Spinach Masoor Pappu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.andhra-tomato-toor-pappu` / `1000024` — Andhra Tomato Toor Pappu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.apple-spice-avaleha` / `1000025` — Apple Spice Avaleha-Style Preserve: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ash-gourd-chana-dal` / `1000026` — Ash Gourd Chana Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ash-gourd-coriander-soup` / `1000027` — Ash Gourd Coriander Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ash-gourd-fennel-sabzi` / `1000028` — Ash Gourd Fennel Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.avial` / `1000082` — Avial: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bagara-khichdi-bajra` / `1000083` — Millet-Curd Rice (Cooling): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.baingan-bharta` / `1000084` — Baingan Bharta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bajra-khichdi` / `1000085` — Bajra Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bajra-roti-gud-ghee` / `1000086` — Bajra Roti with Gud-Ghee: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bajra-winter-porridge` / `1000087` — Bajra Winter Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.baked-sweet-potato-cinnamon` / `1000088` — Cinnamon Sweet Potato: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.baked-vegetable-cutlet` / `1000089` — Baked Vegetable Cutlet: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.barley-cinnamon-porridge` / `1000090` — Barley Cinnamon Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.barley-kheer` / `1000091` — Barley Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.barley-mung-kitchari` / `1000093` — Simple Barley Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.barley-vegetable-breakfast` / `1000095` — Barley Vegetable Breakfast Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.barley-vegetable-soup` / `1000096` — Barley Vegetable Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bathua-raita` / `1000097` — Bathua Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beet-halwa` / `1000099` — Beetroot Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beet-mung-kitchari` / `1000100` — Beetroot Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beetroot-cumin-sabzi` / `1000103` — Beetroot Cumin Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beetroot-mung-dal` / `1000105` — Beetroot Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-baked-dhokar-dalna` / `1000107` — Bengali Baked Dhokar Dalna: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-cabbage-chickpea-ghonto` / `1000108` — Bengali Cabbage Chickpea Ghonto: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-coconut-cholar-dal` / `1000109` — Bengali Coconut Cholar Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-mung-shukto` / `1000111` — Bengali Mung Shukto: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-roasted-mung-dal` / `1000115` — Bengali Roasted Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bengali-spinach-chana-dal` / `1000116` — Bengali Spinach Chana Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.besan-chilla` / `1000117` — Besan Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.besan-laddu` / `1000118` — Besan Laddu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.besan-panjiri` / `1000119` — Besan Panjiri: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.besan-sheera-postpartum` / `1000120` — Besan Sheera: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-cumin-oat-milk-tonic` / `1000134` — Cumin Oat-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-golden-oat-milk-tonic-ii` / `1000141` — Golden Oat-Milk Tonic II: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.beverage-turmeric-soy-milk-tonic` / `1000167` — Turmeric Soy-Milk Tonic: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bhindi-sabzi` / `1000171` — Bhindi Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bisi-bele-bath` / `1000172` — Bisi Bele Bath: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.black-salt-takra` / `1000173` — Black Salt Cumin Takra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.boondi-raita-light` / `1000174` — Boondi Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bottle-gourd-sambar` / `1000176` — Bottle Gourd Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-ajwain-whole-wheat-roti` / `1000177` — Ajwain Whole-Wheat Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-amaranth-pumpkin-roti` / `1000178` — Amaranth Pumpkin Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-amaranth-sweet-potato-roti` / `1000179` — Amaranth Sweet Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-bajra-potato-roti` / `1000181` — Bajra Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-bajra-pumpkin-roti` / `1000182` — Bajra Pumpkin Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-barley-wheat-roti` / `1000183` — Barley Wheat Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-beet-stuffed-wheat-flatbread` / `1000185` — Beet-Stuffed Wheat Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-beet-chilla` / `1000186` — Besan Beet Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-cabbage-chilla` / `1000187` — Besan Cabbage Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-carrot-chilla` / `1000188` — Coriander Carrot Besan Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-cumin-chilla` / `1000189` — Besan Cumin Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-fennel-chilla` / `1000190` — Besan Fennel Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-methi-chilla` / `1000191` — Besan Methi Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-paneer-chilla` / `1000192` — Besan Paneer Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-pumpkin-chilla` / `1000193` — Besan Pumpkin Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-spinach-chilla` / `1000194` — Besan Spinach Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-wheat-missi-roti` / `1000195` — Besan Wheat Missi Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-besan-zucchini-chilla` / `1000196` — Besan Zucchini Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-buckwheat-potato-roti` / `1000197` — Buckwheat Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-cabbage-stuffed-flatbread` / `1000199` — Cabbage-Stuffed Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-carrot-stuffed-wheat-flatbread` / `1000200` — Carrot-Stuffed Wheat Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-cauliflower-stuffed-flatbread` / `1000201` — Cauliflower-Stuffed Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-coriander-whole-wheat-roti` / `1000203` — Coriander Whole-Wheat Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-corn-potato-makki-roti` / `1000204` — Corn Potato Makki Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-cumin-whole-wheat-roti` / `1000206` — Cumin Whole-Wheat Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-fennel-whole-wheat-roti` / `1000207` — Fennel Whole-Wheat Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-jowar-potato-roti` / `1000209` — Jowar Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-jowar-sweet-potato-roti` / `1000210` — Jowar Sweet Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-methi-stuffed-flatbread` / `1000211` — Methi Stuffed Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-oat-wheat-soft-roti` / `1000213` — Oat Wheat Soft Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-paneer-fennel-stuffed-flatbread` / `1000215` — Paneer Fennel Stuffed Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-pea-cumin-stuffed-flatbread` / `1000216` — Pea Cumin Stuffed Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-pumpkin-stuffed-wheat-flatbread` / `1000217` — Pumpkin-Stuffed Wheat Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-ragi-pumpkin-roti` / `1000219` — Ragi Pumpkin Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-ragi-sweet-potato-roti` / `1000220` — Ragi Sweet Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-ragi-wheat-roti` / `1000221` — Ragi Wheat Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-sesame-whole-wheat-roti` / `1000223` — Sesame Whole-Wheat Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-spinach-stuffed-wheat-flatbread` / `1000224` — Spinach-Stuffed Wheat Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-sweet-potato-stuffed-flatbread` / `1000225` — Sweet-Potato-Stuffed Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.bread-yogurt-whole-wheat-flatbread` / `1000226` — Yogurt Whole-Wheat Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-amaranth-blueberry-pancakes` / `1000227` — Amaranth Blueberry Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-amaranth-pistachio-granola` / `1000230` — Amaranth Pistachio Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-banana-dairy-oat-porridge` / `1000231` — Banana Dairy Oat Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-banana-dairy-wheat-pancakes` / `1000232` — Banana Dairy Wheat Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-barley-almond-granola` / `1000233` — Barley Almond Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-barley-apple-pancakes` / `1000234` — Barley Apple Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-besan-pear-pancakes` / `1000237` — Chickpea Pear Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-blueberry-dairy-buckwheat-pancakes` / `1000238` — Blueberry Dairy Buckwheat Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-buckwheat-pear-pancakes` / `1000241` — Buckwheat Pear Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-buckwheat-walnut-granola` / `1000243` — Buckwheat Walnut Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-corn-blueberry-pancakes` / `1000245` — Corn Blueberry Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-mango-dairy-millet-porridge` / `1000246` — Mango Dairy Millet Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-mango-dairy-ragi-pancakes` / `1000247` — Mango Dairy Ragi Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-millet-peanut-granola` / `1000250` — Millet Peanut Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-millet-pumpkin-pancakes` / `1000251` — Millet Pumpkin Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-almond-raisin-granola` / `1000252` — Oat Almond Raisin Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apple-pancakes` / `1000254` — Oat Apple Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-apricot-granola` / `1000255` — Oat Apricot Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-pumpkin-seed-granola` / `1000259` — Oat Pumpkin Seed Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-strawberry-pancakes` / `1000260` — Oat Strawberry Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-oat-walnut-date-granola` / `1000261` — Oat Walnut Date Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-quinoa-peach-pancakes` / `1000263` — Quinoa Peach Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-quinoa-seed-granola` / `1000265` — Quinoa Seed Granola: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-ragi-banana-pancakes` / `1000266` — Ragi Banana Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-ragi-coconut-granola` / `1000267` — Ragi Coconut Granola Clusters: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-rice-banana-pancakes` / `1000269` — Rice Banana Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-strawberry-dairy-rice-porridge` / `1000275` — Strawberry Dairy Rice Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.breakfast-whole-wheat-carrot-pancakes` / `1000276` — Whole-Wheat Carrot Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.brown-lentil-warming-soup` / `1000277` — Warming Brown Lentil Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.brown-rice-mung-kitchari` / `1000278` — Brown Rice Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cabbage-mung-dal` / `1000280` — Cabbage Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cabbage-peas-sabzi` / `1000281` — Cabbage and Peas Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cabbage-sambar` / `1000282` — Cabbage Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-fennel-sabzi` / `1000287` — Carrot Fennel Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-halwa-classic` / `1000288` — Gajar Halwa (Ghee-Milk): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-mung-dal` / `1000289` — Carrot Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-mung-kitchari` / `1000290` — Carrot Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-mung-soup` / `1000291` — Carrot Mung Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-rasam` / `1000293` — Carrot Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-rava-idli` / `1000294` — Carrot Rava Idli: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.carrot-upma` / `1000295` — Carrot Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cauliflower-cumin-sabzi` / `1000296` — Cauliflower Cumin Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.chana-dal-lauki` / `1000297` — Chana Dal with Bottle Gourd: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.chana-dal-rice-kitchari` / `1000298` — Chana Dal Rice Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.classic-mung-kitchari` / `1000300` — Classic Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.classic-vegetable-sambar` / `1000301` — Classic Mixed Vegetable Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.coconut-ladoo` / `1000303` — Coconut Ladoo: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-beet-dill-raita` / `1000307` — Beet Dill Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-bottle-gourd-cumin-raita` / `1000308` — Bottle Gourd Cumin Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-carrot-coriander-raita` / `1000312` — Carrot Coriander Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-cucumber-fennel-raita` / `1000320` — Cucumber Fennel Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-fennel-bulb-raita` / `1000325` — Fennel Bulb Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-mint-cilantro-raita` / `1000334` — Mint Cilantro Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-pumpkin-fennel-raita` / `1000340` — Pumpkin Fennel Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-radish-cumin-raita` / `1000344` — Cooked Radish Cumin Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-spinach-coriander-raita` / `1000347` — Spinach Coriander Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.condiment-zucchini-dill-raita` / `1000353` — Zucchini Dill Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-broccoli-cottage-gratin` / `1000364` — Broccoli Cottage Cheese Gratin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-broccoli-paneer-pasta` / `1000365` — Broccoli Paneer Pasta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-cauliflower-aged-cheese-gratin` / `1000372` — Cauliflower Aged Cheese Gratin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-cauliflower-tomato-cottage-bake` / `1000375` — Cauliflower Tomato Cottage Cheese Gratin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-eggplant-tomato-cheese-gratin` / `1000377` — Eggplant Tomato Cheese Gratin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-mushroom-aged-cheese-pasta` / `1000381` — Mushroom Aged Cheese Pasta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-mushroom-spinach-cheese-bake` / `1000382` — Mushroom Spinach Cheese Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-potato-leek-cottage-gratin` / `1000385` — Potato Leek Cottage Cheese Gratin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-spinach-cottage-cheese-pasta` / `1000391` — Spinach Cottage Cheese Pasta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-sweet-potato-spinach-paneer-gratin` / `1000395` — Sweet Potato Spinach Paneer Gratin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-tomato-aged-cheese-pasta` / `1000396` — Tomato Aged Cheese Pasta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-tomato-cottage-cheese-pasta` / `1000397` — Tomato Cottage Cheese Pasta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-tomato-paneer-basil-pasta` / `1000398` — Tomato Paneer Basil Pasta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-tomato-pepper-paneer-bake` / `1000399` — Tomato Pepper Paneer Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.continental-zucchini-tomato-cheese-gratin` / `1000403` — Zucchini Tomato Cheese Gratin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.coriander-leaf-rasam` / `1000406` — Coriander Leaf Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.coriander-mung-dal` / `1000407` — Coriander Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.coriander-takra` / `1000409` — Coriander Takra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.corn-chaat-warm` / `1000410` — Warm Corn Chaat: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cucumber-raita` / `1000411` — Cucumber Raita: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cumin-coriander-rasam` / `1000413` — Cumin-Coriander Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cumin-masoor-dal` / `1000415` — Cumin Masoor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.cumin-vilepi` / `1000416` — Cumin Rice Vilepi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.curd-oats-bowl` / `1000417` — Curd Oats Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.curry-leaf-takra` / `1000419` — Curry Leaf Takra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dalia-porridge` / `1000420` — Dalia (Broken Wheat) Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.daliya-khichdi` / `1000421` — Daliya Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.date-milk` / `1000422` — Date Milk: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.date-raisin-avaleha` / `1000423` — Date-Raisin Avaleha-Style Preserve: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-almond-apricot-truffles` / `1000424` — Almond Apricot Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-almond-date-truffles` / `1000427` — Almond Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-amaranth-jaggery-squares` / `1000431` — Amaranth Jaggery Dessert Squares: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-apple-dairy-rice-pudding` / `1000432` — Apple Dairy Rice Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-apple-oat-crumble` / `1000433` — Warm Apple Oat Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-apricot-pistachio-crisp` / `1000434` — Warm Apricot Pistachio Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-banana-dairy-oat-pudding` / `1000435` — Banana Dairy Oat Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-banana-oat-bake` / `1000436` — Warm Banana Oat Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-beet-pear-bake` / `1000437` — Beet Pear Dessert Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-blueberry-dairy-quinoa-pudding` / `1000438` — Blueberry Dairy Quinoa Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-blueberry-oat-crumble` / `1000439` — Warm Blueberry Oat Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-blueberry-peach-crisp` / `1000440` — Blueberry Peach Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-carrot-apple-bake` / `1000441` — Carrot Apple Dessert Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-cashew-fig-truffles` / `1000442` — Cashew Fig Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-cherry-almond-crisp` / `1000443` — Warm Cherry Almond Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-coconut-date-truffles` / `1000444` — Coconut Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-coconut-fig-truffles` / `1000445` — Coconut Fig Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-date-apple-bake` / `1000446` — Warm Date Apple Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-fig-walnut-bake` / `1000447` — Warm Fig Walnut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-grape-pear-bake` / `1000448` — Warm Grape Pear Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-mango-coconut-bake` / `1000449` — Warm Mango Coconut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-mango-dairy-millet-pudding` / `1000450` — Mango Dairy Millet Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-oat-date-truffles` / `1000452` — Oat Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-peach-almond-crisp` / `1000455` — Warm Peach Almond Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-peach-dairy-millet-pudding` / `1000456` — Peach Dairy Millet Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-peanut-raisin-truffles` / `1000457` — Peanut Raisin Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pear-walnut-crumble` / `1000458` — Warm Pear Walnut Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pineapple-coconut-bake` / `1000459` — Warm Pineapple Coconut Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pineapple-dairy-rice-pudding` / `1000460` — Pineapple Dairy Rice Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pistachio-apricot-truffles` / `1000461` — Pistachio Apricot Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-plum-oat-crisp` / `1000462` — Warm Plum Oat Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pomegranate-pear-bake` / `1000463` — Warm Pomegranate Pear Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pumpkin-apple-crumble` / `1000464` — Pumpkin Apple Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-pumpkin-seed-date-truffles` / `1000465` — Pumpkin Seed Date Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-sesame-date-truffles` / `1000466` — Sesame Date Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-sesame-prune-truffles` / `1000467` — Sesame Prune Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-strawberry-apple-crisp` / `1000468` — Strawberry Apple Crisp: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-strawberry-dairy-tapioca-pudding` / `1000469` — Strawberry Dairy Tapioca Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-sunflower-apricot-truffles` / `1000470` — Sunflower Apricot Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-sweet-potato-pear-crumble` / `1000471` — Sweet Potato Pear Crumble: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-walnut-fig-truffles` / `1000472` — Walnut Fig Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dessert-walnut-prune-truffles` / `1000473` — Walnut Prune Dessert Truffles: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-banana-cow-milk-smoothie` / `1000480` — Banana Cow-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-blueberry-cow-milk-smoothie` / `1000484` — Blueberry Cow-Milk Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-mango-yogurt-smoothie` / `1000501` — Mango Yogurt Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-pineapple-yogurt-smoothie` / `1000509` — Pineapple Yogurt Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drink-strawberry-yogurt-smoothie` / `1000521` — Strawberry Yogurt Smoothie: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drumstick-curry` / `1000524` — Drumstick Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drumstick-sambar` / `1000525` — Drumstick Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.drumstick-toor-dal` / `1000526` — Drumstick Toor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dry-fruit-ladoo` / `1000527` — Dry Fruit Ladoo (No Sugar): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.dry-fruit-shake` / `1000528` — Panchmeva Milk Shake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-adzuki-pumpkin-curry` / `1000529` — Adzuki Pumpkin Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-amaranth-fennel-breakfast` / `1000530` — Amaranth Fennel Breakfast Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-amaranth-fennel-pancake` / `1000531` — Amaranth Fennel Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-amaranth-leaf-paratha` / `1000532` — Amaranth Leaf Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-amaranth-vegetable-pot` / `1000533` — Amaranth Vegetable Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-bajra-cumin-flatbread` / `1000534` — Bajra Cumin Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-bajra-spinach-pot` / `1000535` — Bajra Spinach Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-barley-cumin-pancake` / `1000536` — Barley Cumin Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-barley-mung-pongal` / `1000537` — Barley Mung Breakfast Pongal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-barley-vegetable-pilaf` / `1000538` — Barley Vegetable Pilaf: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-beetroot-paratha` / `1000539` — Beetroot Fennel Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-beetroot-pulao` / `1000540` — Everyday Beetroot Pulao: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-beetroot-uttapam` / `1000541` — Beetroot Fennel Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-besan-carrot-chilla` / `1000542` — Besan Carrot Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-besan-wheat-flatbread` / `1000543` — Besan Wheat Breakfast Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-black-bean-sweet-potato-masala` / `1000544` — Black Bean Sweet Potato Masala: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-brown-lentil-carrot-dal` / `1000545` — Brown Lentil Carrot-Celery Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-brown-rice-breakfast-pot` / `1000546` — Brown Rice Breakfast Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-brown-rice-green-bean-pilaf` / `1000547` — Brown Rice Green Bean Pilaf: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-brown-rice-masoor-pot` / `1000548` — Brown Rice Masoor Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-buckwheat-potato-pancake` / `1000549` — Buckwheat Potato Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-cabbage-carrot-pea-curry` / `1000550` — Cabbage Carrot Pea Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-cabbage-uttapam` / `1000551` — Cabbage Cumin Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-carrot-paratha` / `1000552` — Carrot Cumin Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-carrot-pea-pulao` / `1000553` — Everyday Carrot Pea Pulao: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-carrot-uttapam` / `1000554` — Carrot Cilantro Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-cauliflower-paratha` / `1000555` — Cauliflower Coriander Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-cauliflower-pea-curry` / `1000556` — Cauliflower Pea Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-chana-cauliflower-dal` / `1000557` — Chana Dal with Cauliflower: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-chana-ridge-gourd-dal` / `1000558` — Chana Dal with Ridge Gourd: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-chana-spinach-dal` / `1000559` — Chana Dal with Spinach: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-chana-sweet-potato-dal` / `1000560` — Chana Dal with Sweet Potato: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-chickpea-potato-curry` / `1000561` — Chickpea Potato Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-chickpea-rice-pot` / `1000562` — Chickpea Rice Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-coconut-rice-sevai` / `1000564` — Coconut Rice Sevai: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-corn-cilantro-pancake` / `1000565` — Corn Cilantro Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-dill-paratha` / `1000566` — Dill Seeded Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-eggplant-chickpea-curry` / `1000567` — Eggplant Chickpea Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-green-pea-paratha` / `1000568` — Green Pea Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-green-pea-uttapam` / `1000569` — Green Pea Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-jowar-methi-flatbread` / `1000570` — Jowar Methi Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-jowar-spinach-dosa` / `1000571` — Jowar Spinach Dosa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-jowar-vegetable-pot` / `1000572` — Jowar Vegetable Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-masoor-beet-dal` / `1000573` — Masoor Beetroot Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-masoor-carrot-dal` / `1000574` — Masoor Carrot Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-masoor-eggplant-dal` / `1000575` — Masoor Dal with Eggplant: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-masoor-green-bean-dal` / `1000576` — Masoor Dal with Green Beans: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-masoor-spinach-chilla` / `1000577` — Masoor Spinach Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-millet-carrot-pongal` / `1000578` — Millet Carrot Pongal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mung-amaranth-leaf-dal` / `1000579` — Mung Dal with Amaranth Leaves: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mung-beet-chilla` / `1000580` — Mung Beetroot Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mung-lauki-dal` / `1000581` — Everyday Mung and Lauki Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mung-methi-dal` / `1000582` — Mung Dal with Fresh Methi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mung-okra-dal` / `1000583` — Mung Dal with Okra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mung-zucchini-dal` / `1000584` — Mung Dal with Zucchini: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mushroom-pea-curry` / `1000585` — Mushroom Pea Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-mushroom-uttapam` / `1000586` — Mushroom Coriander Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-oat-zucchini-chilla` / `1000587` — Oat Zucchini Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-okra-potato-curry` / `1000588` — Okra Potato Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-paneer-tomato-curry` / `1000589` — Paneer Tomato Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-paneer-tomato-uttapam` / `1000590` — Paneer Tomato Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-paneer-zucchini-curry` / `1000591` — Paneer Zucchini Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-pea-besan-chilla` / `1000592` — Green Pea Besan Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-pumpkin-paratha` / `1000594` — Pumpkin Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-pumpkin-rice-pot` / `1000595` — Pumpkin Rice Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-pumpkin-semolina-pancake` / `1000596` — Pumpkin Semolina Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-quinoa-cilantro-pancake` / `1000597` — Quinoa Cilantro Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-quinoa-masala-pot` / `1000598` — Everyday Quinoa Masala Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-quinoa-vegetable-tiffin` / `1000599` — Quinoa Vegetable Tiffin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-radish-paratha` / `1000600` — Radish Ajwain Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-ragi-cardamom-breakfast` / `1000601` — Ragi Cardamom Breakfast Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-ragi-carrot-dosa` / `1000602` — Ragi Carrot Dosa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-rajma-pumpkin-dal` / `1000603` — Rajma Pumpkin Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-rajma-spinach-curry` / `1000604` — Rajma Spinach Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-rice-lentil-dosa` / `1000605` — Rice Lentil Tiffin Dosa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-savory-barley-tiffin` / `1000606` — Savory Barley Tiffin Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-savory-oat-tiffin` / `1000607` — Savory Oat Tiffin Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-semolina-pea-upma` / `1000608` — Semolina Pea Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-sesame-paratha` / `1000609` — Sesame Whole-Wheat Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-spinach-paratha` / `1000610` — Spinach Coriander Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-spinach-rice` / `1000611` — Everyday Spinach Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-spinach-uttapam` / `1000612` — Spinach Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-sweet-corn-uttapam` / `1000613` — Sweet Corn Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-sweet-potato-millet-pot` / `1000614` — Sweet Potato Millet Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-sweet-potato-paratha` / `1000615` — Sweet Potato Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-taro-spinach-curry` / `1000616` — Taro Spinach Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-tofu-pea-rice` / `1000617` — Tofu Pea Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-tofu-rice-pancake` / `1000618` — Tofu Rice Breakfast Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-tofu-spinach-curry` / `1000619` — Tofu Spinach Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-tomato-onion-uttapam` / `1000620` — Tomato Onion Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-toor-ash-gourd-dal` / `1000621` — Toor Dal with Ash Gourd: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-toor-drumstick-dal` / `1000622` — Toor Dal with Drumstick: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-toor-pumpkin-dal` / `1000623` — Toor Dal with Pumpkin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-toor-spinach-dal` / `1000624` — Toor Dal with Spinach: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-urad-cabbage-dal` / `1000625` — Urad Dal with Cabbage: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-yam-green-bean-curry` / `1000626` — Yam Green Bean Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-zucchini-paratha` / `1000627` — Zucchini Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.everyday-zucchini-uttapam` / `1000628` — Zucchini Dill Uttapam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fasting-kuttu-roti` / `1000629` — Kuttu Roti (Fasting): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fennel-masoor-dal` / `1000632` — Fennel Masoor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fennel-takra` / `1000633` — Fennel Takra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fenugreek-rasam` / `1000636` — Fenugreek Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fig-cardamom-avaleha` / `1000637` — Fig Cardamom Avaleha-Style Preserve: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fig-milk` / `1000638` — Fig Milk: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.fruit-custard-light` / `1000639` — Stewed Fruit Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.garlic-pepper-rasam` / `1000640` — Garlic Pepper Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ginger-rasam` / `1000645` — Fresh Ginger Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ginger-takra` / `1000646` — Ginger Takra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.golden-milk` / `1000647` — Golden Milk: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.green-bean-carrot-sambar` / `1000649` — Green Bean Carrot Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.green-bean-mung-dal` / `1000651` — Green Bean Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.green-bean-mung-kitchari` / `1000652` — Green Bean Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.green-bean-toor-dal` / `1000653` — Green Bean Toor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.green-pea-upma` / `1000655` — Green Pea Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.grishma-cooling-plate` / `1000658` — Grishma Cooling Plate: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.grishma-millet-bottle-gourd` / `1000660` — Grishma Millet Bottle Gourd Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.grishma-rice-asparagus-mung` / `1000663` — Grishma Asparagus Mung Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.grishma-rice-chayote-pea` / `1000664` — Grishma Chayote Pea Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.grishma-rice-cucumber-mung` / `1000665` — Grishma Cooked Cucumber Rice Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.grishma-rice-zucchini-masoor` / `1000666` — Grishma Zucchini Masoor Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.gujarati-cumin-yogurt-kadhi` / `1000668` — Gujarati Cumin Yogurt Kadhi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.gujarati-dudhi-chana-dal` / `1000669` — Gujarati Dudhi Chana Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.gujarati-mung-brown-rice-khichdi` / `1000672` — Gujarati Mung Brown Rice Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.gujarati-spinach-mung-shaak` / `1000675` — Gujarati Spinach Mung Shaak: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.gujarati-sweet-sour-toor-dal` / `1000678` — Gujarati Sweet-Sour Toor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-amaranth-squash-mung` / `1000680` — Hemanta Amaranth Squash Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-bajra-urad-pumpkin` / `1000681` — Hemanta Bajra Urad Pumpkin Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-brown-rice-rajma-squash` / `1000683` — Hemanta Brown Rice Rajma Squash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-jowar-yam-mung` / `1000684` — Hemanta Jowar Yam Mung Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-oat-sweet-potato-dal` / `1000685` — Hemanta Oat Sweet Potato Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-rice-chana-carrot` / `1000687` — Hemanta Rice Chana Carrot Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-strength-bowl` / `1000688` — Hemanta Strength Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.hemanta-urad-rice-kitchari` / `1000689` — Hemanta Urad-Rice Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.intl-tomato-cottage-cheese-soup` / `1000780` — Tomato Cottage Cheese Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.jeera-rice` / `1000790` — Jeera Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.jowar-dosa` / `1000791` — Jowar Dosa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.jowar-khichdi` / `1000792` — Jowar Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kapha-brown-rice-mung-mustard-greens` / `1000803` — Kapha Brown Rice Mustard Greens Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kapha-brown-rice-toor-broccoli` / `1000804` — Kapha Brown Rice Toor Broccoli Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kapha-jowar-chana-broccoli-pot` / `1000809` — Kapha Jowar Chana Broccoli Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kapha-light-barley-kitchari` / `1000811` — Kapha-Light Barley Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kapha-millet-chana-mustard-greens` / `1000812` — Kapha Millet Chana Mustard Greens: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karela-sabzi` / `1000819` — Karela Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-brown-rice-bisi-bele` / `1000821` — Karnataka Brown Rice Bisi Bele: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-chayote-majjige-huli` / `1000823` — Karnataka Chayote Majjige Huli: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-coconut-sesame-rice-bath` / `1000824` — Karnataka Coconut Sesame Rice Bath: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-dill-lentil-saaru` / `1000825` — Karnataka Dill Lentil Saaru: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-methi-brown-rice-bath` / `1000828` — Karnataka Methi Brown Rice Bath: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-ridge-gourd-toor-tovve` / `1000830` — Karnataka Ridge Gourd Toor Tovve: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.karnataka-spinach-mung-bassaru` / `1000831` — Karnataka Spinach Mung Bassaru: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kerala-root-vegetable-avial` / `1000842` — Kerala Root Vegetable Avial: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.kesar-shrikhand-light` / `1000845` — Kesar Shrikhand (Light): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.latin-black-bean-tomato-cheese-bake` / `1000862` — Black Bean Tomato Cheese Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.latin-corn-tomato-paneer-casserole` / `1000869` — Corn Tomato Paneer Casserole: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.latin-zucchini-tomato-cottage-bake` / `1000896` — Zucchini Tomato Cottage Cheese Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.lauki-halwa` / `1000897` — Lauki Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.lauki-mung-dal` / `1000898` — Bottle Gourd Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.lauki-mung-kitchari` / `1000899` — Bottle Gourd Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.lauki-sabzi` / `1000900` — Lauki Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.lauki-soup` / `1000901` — Bottle Gourd Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.lemon-rasam` / `1000903` — Lemon Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-amaranth-chayote-peya` / `1000905` — Amaranth Chayote Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-barley-carrot-peya` / `1000906` — Barley Carrot Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-barley-manda` / `1000907` — Soft Barley Manda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-bottle-gourd-mung-mash` / `1000908` — Bottle Gourd Mung Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-bottle-gourd-mung-yusha` / `1000909` — Bottle Gourd Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-bottle-gourd-rice-peya` / `1000910` — Bottle Gourd Rice Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-bottle-gourd-rice-rest-bowl` / `1000911` — Bottle Gourd Rice Rest-Day Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-carrot-mung-peya` / `1000912` — Carrot Mung Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-carrot-mung-yusha` / `1000913` — Carrot Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-carrot-potato-mash` / `1000914` — Carrot Potato Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-carrot-quinoa-mash` / `1000915` — Carrot Quinoa Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-carrot-rice-peya` / `1000916` — Carrot Rice Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-carrot-rice-rest-bowl` / `1000917` — Carrot Rice Rest-Day Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-chayote-mung-yusha` / `1000918` — Chayote Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-chayote-rice-mash` / `1000919` — Chayote Rice Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-chayote-rice-peya` / `1000920` — Chayote Rice Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-coriander-rice-manda` / `1000921` — Coriander Rice Manda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-cumin-rice-manda` / `1000922` — Cumin Rice Manda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-fennel-barley-broth` / `1000923` — Fennel Barley Rest-Day Broth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-fennel-mung-peya` / `1000924` — Fennel Mung Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-fennel-mung-yusha` / `1000925` — Fennel Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-fennel-rice-manda` / `1000926` — Fennel Rice Manda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-ginger-rice-manda` / `1000927` — Ginger Rice Manda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-masoor-carrot-broth` / `1000928` — Masoor Carrot Soft Broth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-masoor-pumpkin-broth` / `1000929` — Masoor Pumpkin Soft Broth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-millet-bottle-gourd-peya` / `1000930` — Millet Bottle Gourd Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-mung-rice-peya` / `1000931` — Mung Rice Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-oat-fennel-peya` / `1000932` — Oat Fennel Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-oat-pumpkin-peya` / `1000933` — Oat Pumpkin Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-plain-mung-yusha` / `1000934` — Plain Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-plain-rice-manda` / `1000935` — Plain Rice Manda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-pumpkin-millet-mash` / `1000936` — Pumpkin Millet Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-pumpkin-mung-mash` / `1000937` — Pumpkin Mung Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-pumpkin-mung-peya` / `1000938` — Pumpkin Mung Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-pumpkin-mung-rest-bowl` / `1000939` — Pumpkin Mung Rest-Day Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-pumpkin-mung-yusha` / `1000940` — Pumpkin Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-pumpkin-rice-peya` / `1000941` — Pumpkin Rice Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-quinoa-zucchini-peya` / `1000942` — Quinoa Zucchini Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-ragi-carrot-gruel` / `1000943` — Ragi Carrot Gruel: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-ragi-fennel-gruel` / `1000944` — Ragi Fennel Gruel: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-spinach-mung-peya` / `1000945` — Spinach Mung Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-spinach-mung-yusha` / `1000946` — Spinach Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-spinach-rice-mash` / `1000947` — Spinach Rice Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-sweet-potato-mung-peya` / `1000948` — Sweet Potato Mung Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-sweet-potato-mung-yusha` / `1000949` — Sweet Potato Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-toor-bottle-gourd-broth` / `1000950` — Toor Bottle Gourd Soft Broth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-toor-chayote-broth` / `1000951` — Toor Chayote Soft Broth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-zucchini-mung-yusha` / `1000952` — Zucchini Mung Yusha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-zucchini-oat-mash` / `1000953` — Zucchini Oat Soft Mash: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.light-zucchini-rice-peya` / `1000954` — Zucchini Rice Peya: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.makhana-kheer` / `1000955` — Makhana Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.masala-doodh` / `1000957` — Masala Doodh: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.masala-khichdi` / `1000958` — Masala Vegetable Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.masoor-chilla` / `1000959` — Masoor Dal Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.masoor-dal-tadka` / `1000960` — Masoor Dal Tadka: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.masoor-rice-kitchari` / `1000961` — Masoor Rice Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-cauliflower-tomato-cottage-bake` / `1000978` — Cauliflower Tomato Cottage Cheese Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-eggplant-tomato-cheese-bake` / `1000989` — Eggplant Tomato Cheese Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-pepper-tomato-paneer-bake` / `1001000` — Pepper Tomato Paneer Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-spinach-potato-cottage-bake` / `1001009` — Spinach Potato Cottage Cheese Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.med-tomato-zucchini-cheese-bake` / `1001010` — Tomato Zucchini Cheese Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.methi-aloo` / `1001013` — Methi Aloo: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.methi-mung-dal` / `1001014` — Fresh Methi Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.methi-mung-kitchari` / `1001015` — Fresh Methi Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.methi-paratha` / `1001016` — Methi Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.millet-pongal` / `1001017` — Millet Pongal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.millet-upma` / `1001018` — Proso Millet Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mint-rasam` / `1001022` — Mint Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mint-takra` / `1001024` — Mint Takra: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.missi-roti` / `1001025` — Missi Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mixed-veg-korma-light` / `1001026` — Light Vegetable Korma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.modak-ukadiche` / `1001027` — Ukadiche Modak: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.moon-milk` / `1001028` — Nutmeg Moon Milk: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.moong-chilla` / `1001029` — Moong Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mung-dal-halwa` / `1001030` — Mung Dal Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mung-laddu` / `1001031` — Mung Dal Laddu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mung-panjiri` / `1001032` — Mung Panjiri: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.murmura-chikki` / `1001035` — Murmura Chikki: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.mustard-greens-mung-sabzi` / `1001036` — Mustard Greens with Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.navratri-kuttu-thali` / `1001037` — Navratri Fasting Thali: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.oats-cardamom-kheer` / `1001038` — Oats Cardamom Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.oats-spiced-porridge` / `1001039` — Spiced Oats Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.odia-cumin-vegetable-santula` / `1001040` — Odia Cumin Vegetable Santula: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.odia-pumpkin-vegetable-dalma` / `1001041` — Odia Pumpkin Vegetable Dalma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.paal-payasam` / `1001044` — Paal Payasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.palak-mung-dal` / `1001045` — Palak Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.palak-paneer-light` / `1001046` — Light Palak Paneer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.panchmel-dal` / `1001048` — Panchmel Dal (Five-Lentil): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.panchmel-rice-khichdi` / `1001049` — Panchmel Rice Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.peanut-jaggery-laddu` / `1001050` — Peanut Jaggery Laddu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.peas-pulao` / `1001052` — Peas Pulao: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pepper-rasam` / `1001053` — Pepper Rasam (Milagu): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pesarattu` / `1001054` — Pesarattu (Mung Dosa): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pistachio-makhana-kheer` / `1001056` — Pistachio Makhana Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-amaranth-chayote-meal` / `1001057` — Pitta Amaranth Chayote Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-cabbage-pea-rice-pot` / `1001064` — Pitta Cabbage Pea Rice Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-cauliflower-mung-bowl` / `1001065` — Pitta Cauliflower Mung Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-chayote-paneer-rice` / `1001067` — Pitta Chayote Paneer Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-coconut-cilantro-rice-dal` / `1001068` — Pitta Coconut Cilantro Rice Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-cooling-kitchari` / `1001071` — Pitta-Cooling Coriander Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-coriander-pumpkin-khichdi` / `1001072` — Pitta Coriander Pumpkin Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-cucumber-mung-rice-bowl` / `1001073` — Pitta Cucumber Mung Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-fennel-masoor-rice-bowl` / `1001076` — Pitta Fennel Masoor Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-fennel-paneer-quinoa` / `1001077` — Pitta Fennel Paneer Quinoa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-spinach-mung-rice-pot` / `1001080` — Pitta Spinach Mung Rice Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pitta-zucchini-mung-millet` / `1001082` — Pitta Zucchini Mung Millet: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.plain-semolina-upma` / `1001083` — Plain Semolina Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.poha-lemon` / `1001086` — Lemon Poha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.puffed-rice-morning-chivda` / `1001088` — Warm Puffed Rice Morning Chivda: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-chana-dal` / `1001089` — Pumpkin Chana Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-halwa` / `1001090` — Pumpkin Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-mung-dal` / `1001092` — Pumpkin Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-mung-kitchari` / `1001093` — Pumpkin Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-mung-soup` / `1001094` — Pumpkin Mung Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-sabzi-sweet` / `1001096` — Sweet Pumpkin Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.pumpkin-sambar` / `1001097` — Pumpkin Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-amritsari-fennel-chole` / `1001099` — Punjabi Amritsari Fennel Chole: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-baked-pakora-kadhi` / `1001100` — Punjabi Baked Pakora Kadhi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-bottle-gourd-besan-kofta` / `1001101` — Punjabi Bottle Gourd Besan Kofta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-chana-palak` / `1001102` — Punjabi Chana Palak: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-cumin-aloo-gobi` / `1001103` — Punjabi Cumin Aloo Gobi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-cumin-pea-brown-rice` / `1001104` — Punjabi Cumin Pea Brown Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-fennel-palak-paneer` / `1001105` — Punjabi Fennel Palak Paneer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-methi-matar-fennel` / `1001106` — Punjabi Methi Matar Fennel: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-mustard-spinach-saag` / `1001107` — Punjabi Mustard Spinach Saag: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-pea-paneer-fennel-gravy` / `1001108` — Punjabi Pea Paneer Fennel Gravy: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-slow-cooked-rajma` / `1001109` — Punjabi Slow-Cooked Rajma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-smoky-eggplant-bharta` / `1001110` — Punjabi Smoky Eggplant Bharta: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.punjabi-urad-rajma-makhani` / `1001111` — Punjabi Urad Rajma Makhani: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.radish-sambar` / `1001112` — Radish Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.radish-spinach-sabzi` / `1001113` — Radish Spinach Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ragi-dosa` / `1001114` — Ragi Dosa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ragi-halwa` / `1001115` — Ragi Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ragi-kheer` / `1001116` — Ragi Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ragi-porridge` / `1001117` — Ragi Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ragi-roti` / `1001118` — Ragi Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-ajwain-gatte-curry` / `1001119` — Rajasthani Ajwain Gatte Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-bajra-methi-pilaf` / `1001120` — Rajasthani Bajra Methi Pilaf: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-bajra-mung-khichdi` / `1001121` — Rajasthani Bajra Mung Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-besan-dumpling-pulao` / `1001122` — Rajasthani Besan Dumpling Pulao: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-bottle-gourd-chana` / `1001123` — Rajasthani Bottle Gourd Chana: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-carrot-pea-sabzi` / `1001124` — Rajasthani Carrot Pea Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-fenugreek-lentil-stew` / `1001125` — Rajasthani Fenugreek Lentil Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-five-lentil-panchmel` / `1001126` — Rajasthani Five-Lentil Panchmel: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-jaisalmer-chana-yogurt` / `1001127` — Rajasthani Jaisalmer Chana Yogurt Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajasthani-spinach-chickpea-curry` / `1001130` — Rajasthani Spinach Chickpea Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rajgira-ladoo` / `1001131` — Rajgira Ladoo: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rava-idli` / `1001132` — Rava Idli: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rice-flour-dosa` / `1001135` — Rice Flour Dosa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.rice-mung-idli` / `1001136` — Rice-Mung Steamed Idli: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ridge-gourd-cumin-sabzi` / `1001137` — Ridge Gourd Cumin Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.roasted-chana-jor` / `1001139` — Roasted Chana Snack: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.roasted-makhana` / `1001140` — Ghee-Roasted Makhana: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sabudana-kheer-fasting` / `1001141` — Sabudana Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.saffron-milk` / `1001143` — Saffron Milk: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sarson-ka-saag` / `1001144` — Sarson Ka Saag: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sesame-almond-panjiri` / `1001145` — Sesame Almond Panjiri: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sesame-jaggery-bar` / `1001147` — Til-Gud Bar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sharad-amaranth-pumpkin-mung` / `1001149` — Sharad Amaranth Pumpkin Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sharad-coriander-kitchari` / `1001151` — Sharad Coriander Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sharad-fennel-rice-mung` / `1001152` — Sharad Fennel Rice Mung Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sharad-pitta-soother` / `1001154` — Sharad Pitta-Soothing Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sharad-rice-bottle-gourd-mung` / `1001157` — Sharad Bottle Gourd Rice Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sharad-rice-cucumber-toor` / `1001158` — Sharad Cooked Cucumber Toor Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-amaranth-carrot-toor` / `1001159` — Shishira Amaranth Carrot Toor: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-bajra-sweet-potato-mung` / `1001160` — Shishira Bajra Sweet Potato Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-brown-rice-turnip-toor` / `1001162` — Shishira Brown Rice Turnip Toor: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-jowar-carrot-mung` / `1001163` — Shishira Jowar Carrot Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-oat-pumpkin-masoor` / `1001164` — Shishira Oat Pumpkin Masoor: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-rice-yam-chana` / `1001166` — Shishira Rice Yam Chana Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.shishira-sesame-kitchari` / `1001167` — Shishira Sesame Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.simple-mung-dal` / `1001168` — Simple Yellow Mung Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-amaranth-jaggery-bites` / `1001171` — Amaranth Jaggery Snack Bites: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-apricot-pistachio-energy-balls` / `1001172` — Apricot Pistachio Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-coconut-date-bites` / `1001185` — Coconut Date Snack Bites: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-date-almond-energy-balls` / `1001191` — Date Almond Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-fig-walnut-energy-balls` / `1001193` — Fig Walnut Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-oat-date-energy-balls` / `1001199` — Oat Date Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-prune-sesame-energy-balls` / `1001202` — Prune Sesame Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-pumpkin-seed-date-bites` / `1001203` — Pumpkin Seed Date Bites: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-raisin-peanut-energy-balls` / `1001207` — Raisin Peanut Energy Balls: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-rosemary-roasted-makhana` / `1001209` — Rosemary Roasted Makhana: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.snack-sunflower-raisin-bites` / `1001211` — Sunflower Raisin Snack Bites: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spiced-takra` / `1001219` — Spiced Takra (Digestive Buttermilk): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spinach-masoor-dal` / `1001222` — Spinach Masoor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spinach-mung-chilla` / `1001223` — Spinach Mung Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spinach-mung-kitchari` / `1001224` — Spinach Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spinach-sambar` / `1001225` — Spinach Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.spinach-sesame-sabzi` / `1001226` — Spinach Sesame Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sprout-salad-steamed` / `1001227` — Warm Sprout Salad: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.stuffed-lauki-paratha` / `1001228` — Lauki Paratha: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.suji-halwa` / `1001229` — Suji Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.summer-beet-fennel-cold-soup` / `1001241` — Summer Beet Fennel Cold Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.summer-carrot-cucumber-cold-soup` / `1001245` — Summer Carrot Cucumber Cold Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.summer-cucumber-dill-cold-soup` / `1001248` — Summer Cucumber Dill Cold Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.summer-cucumber-mint-cold-soup` / `1001250` — Summer Cucumber Mint Cold Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.summer-zucchini-fennel-cold-soup` / `1001279` — Summer Zucchini Fennel Cold Soup: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.suran-sabzi` / `1001280` — Suran (Yam) Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sweet-potato-halwa` / `1001281` — Sweet Potato Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sweet-potato-sambar` / `1001282` — Sweet Potato Sambar: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.sweet-potato-sesame-sabzi` / `1001283` — Sweet Potato Sesame Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamarind-toor-dal` / `1001286` — Tamarind Toor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-black-pepper-sesame-rice` / `1001287` — Tamil Black Pepper Sesame Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-bottle-gourd-mung-kootu` / `1001288` — Tamil Bottle Gourd Mung Kootu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-okra-mor-kuzhambu` / `1001297` — Tamil Okra Mor Kuzhambu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tamil-spinach-garlic-masiyal` / `1001298` — Tamil Spinach Garlic Masiyal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.taro-ajwain-sabzi` / `1001300` — Taro Ajwain Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.thalipeeth` / `1001301` — Thalipeeth (Multigrain): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.til-laddu-sankranti` / `1001302` — Sankranti Til Laddu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tomato-masoor-dal` / `1001304` — Tomato Masoor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tomato-rasam-light` / `1001305` — Light Tomato Rasam: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tomato-toor-dal` / `1001306` — Tomato Toor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.toor-dal-lemon` / `1001307` — Lemon Toor Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.toor-rice-kitchari` / `1001308` — Toor Dal Rice Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-amaranth-mung-carrot` / `1001309` — Tridoshic Amaranth Mung Carrot Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-amaranth-mung-fennel` / `1001310` — Tridoshic Amaranth Mung Fennel: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-amaranth-mung-pumpkin` / `1001311` — Tridoshic Amaranth Mung Pumpkin: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-barley-mung-chayote` / `1001312` — Tridoshic Barley Mung Chayote Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-brown-rice-mung-beet` / `1001315` — Tridoshic Brown Rice Mung Beet Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-brown-rice-mung-pumpkin` / `1001316` — Tridoshic Brown Rice Mung Pumpkin Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-millet-mung-bottle-gourd` / `1001318` — Tridoshic Millet Mung Bottle Gourd: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-millet-mung-green-bean` / `1001319` — Tridoshic Millet Mung Green Bean Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-oat-masoor-carrot` / `1001321` — Tridoshic Oat Masoor Carrot Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-oat-mung-pumpkin-bowl` / `1001322` — Tridoshic Oat Mung Pumpkin Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-rice-chana-pumpkin` / `1001327` — Tridoshic Rice Chana Pumpkin Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-rice-masoor-zucchini` / `1001328` — Tridoshic Rice Masoor Zucchini Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-rice-mung-carrot-spinach` / `1001329` — Tridoshic Rice Mung Carrot Spinach: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-rice-mung-chayote-meal` / `1001330` — Tridoshic Rice Mung Chayote Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-rice-paneer-chayote` / `1001331` — Tridoshic Rice Paneer Chayote: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-rice-pea-fennel-pot` / `1001332` — Tridoshic Rice Pea Fennel Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.tridoshic-rice-toor-bottle-gourd` / `1001333` — Tridoshic Rice Toor Bottle Gourd: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.turnip-ginger-sabzi` / `1001336` — Turnip Ginger Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.urad-dal-makhani-light` / `1001338` — Light Urad Dal (No Cream): FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.urad-rice-kitchari` / `1001339` — Urad Rice Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-amaranth-sweet-potato-mung` / `1001340` — Varsha Amaranth Sweet Potato Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-bajra-pumpkin-dal` / `1001341` — Varsha Bajra Pumpkin Dal Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-brown-rice-squash-mung` / `1001342` — Varsha Squash Brown Rice Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-dry-ginger-kitchari` / `1001343` — Varsha Dry-Ginger Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-ginger-rice-mung-khichdi` / `1001344` — Varsha Ginger Rice Mung Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-jowar-turnip-mung` / `1001345` — Varsha Jowar Turnip Mung Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-light-khichdi` / `1001346` — Varsha Light Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-millet-beet-masoor` / `1001347` — Varsha Millet Beet Masoor: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-oat-carrot-masoor` / `1001348` — Varsha Oat Carrot Masoor Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.varsha-rice-yam-toor` / `1001349` — Varsha Yam Toor Rice Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vasanta-barley-mung-kitchari` / `1001353` — Vasanta Barley-Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vasanta-jowar-broccoli-mung` / `1001355` — Vasanta Jowar Broccoli Mung Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vasanta-millet-radish-dal` / `1001357` — Vasanta Millet Radish Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vasanta-quinoa-cauliflower-mung` / `1001359` — Vasanta Quinoa Cauliflower Mung: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-amaranth-root-one-pot` / `1001361` — Vata Amaranth Root One-Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-beet-mung-rice-bowl` / `1001362` — Vata Beet Mung Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-bottle-gourd-chana-rice-bowl` / `1001363` — Vata Bottle Gourd Chana Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-carrot-cashew-rice-dal` / `1001364` — Vata Carrot Cashew Rice Dal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-carrot-masoor-rice-stew` / `1001365` — Vata Carrot Masoor Rice Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-coconut-chana-rice-bowl` / `1001366` — Vata Coconut Chana Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-corn-mung-pumpkin-bowl` / `1001367` — Vata Corn Mung Pumpkin Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-fennel-paneer-millet-pot` / `1001368` — Vata Fennel Paneer Millet Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-gentle-kadhi-rice-meal` / `1001369` — Vata Gentle Kadhi Rice Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-oat-sweet-potato-dal-bowl` / `1001370` — Vata Oat Sweet Potato Dal Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-pea-paneer-rice-meal` / `1001371` — Vata Pea Paneer Rice Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-pumpkin-rajma-rice-bowl` / `1001372` — Vata Pumpkin Rajma Rice Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-pumpkin-urad-rice-pot` / `1001373` — Vata Pumpkin Urad Rice Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-quinoa-squash-complete-bowl` / `1001374` — Vata Quinoa Squash Complete Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-sesame-pumpkin-khichdi` / `1001376` — Vata Sesame Pumpkin Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-soft-chickpea-barley-stew` / `1001377` — Vata Soft Chickpea Barley Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-soft-rice-root-mung-bowl` / `1001378` — Vata Soft Rice Root Mung Bowl: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-soothing-kitchari` / `1001379` — Vata-Soothing Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-spinach-paneer-rice-pot` / `1001380` — Vata Spinach Paneer Rice Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-taro-red-lentil-pot` / `1001383` — Vata Taro Red Lentil Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-urad-rice-porridge-meal` / `1001384` — Vata Urad Rice Porridge Meal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vata-yam-mung-stew` / `1001385` — Vata Yam Mung Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vegetable-upma` / `1001387` — Vegetable Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.ven-pongal-ghee` / `1001389` — Ghee Ven Pongal: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vermicelli-kheer` / `1001390` — Seviyan Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vermicelli-upma` / `1001391` — Vermicelli Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-cardamom-kheer` / `1001394` — Vrat Amaranth Cardamom Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-chayote-pot` / `1001395` — Vrat Amaranth Chayote Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-potato-flatbread` / `1001397` — Vrat Amaranth Potato Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-potato-pilaf` / `1001398` — Vrat Amaranth Potato Pilaf: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-pumpkin-khichdi` / `1001399` — Vrat Amaranth Pumpkin Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-pumpkin-pancake` / `1001400` — Vrat Amaranth Pumpkin Pancake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-sesame-brittle` / `1001401` — Vrat Amaranth Sesame Brittle: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-amaranth-sesame-laddoo` / `1001402` — Vrat Amaranth Sesame Laddoo: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-apple-amaranth-bake` / `1001403` — Vrat Apple Amaranth Bake: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-baked-plantain-cutlets` / `1001404` — Vrat Baked Green Plantain Cutlets: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-baked-sabudana-vada` / `1001405` — Vrat Baked Sabudana Vada: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-baked-yam-patties` / `1001406` — Vrat Baked Yam Patties: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-chayote-pilaf` / `1001408` — Vrat Buckwheat Chayote Pilaf: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-cumin-khichdi` / `1001409` — Vrat Buckwheat Cumin Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-dumpling-kadhi` / `1001410` — Vrat Buckwheat Dumpling Kadhi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-fennel-dosa` / `1001411` — Vrat Buckwheat Fennel Dosa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-jaggery-halwa` / `1001412` — Vrat Buckwheat Jaggery Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-potato-roti` / `1001413` — Vrat Buckwheat Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-pumpkin-chilla` / `1001414` — Vrat Buckwheat Pumpkin Chilla: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-pumpkin-stew` / `1001415` — Vrat Buckwheat Pumpkin Stew: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-buckwheat-sweet-potato-cakes` / `1001416` — Vrat Buckwheat Sweet Potato Cakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-cardamom-sabudana-kheer` / `1001417` — Vrat Cardamom Sabudana Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chayote-sabudana-upma` / `1001418` — Vrat Chayote Sabudana Upma: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-cardamom-halwa` / `1001419` — Vrat Chestnut Cardamom Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-fennel-crepes` / `1001420` — Vrat Chestnut Fennel Crepes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-milk-pudding` / `1001421` — Vrat Chestnut Milk Pudding: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-potato-cakes` / `1001423` — Vrat Chestnut Potato Cakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-potato-flatbread` / `1001424` — Vrat Chestnut Potato Flatbread: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-pumpkin-dumplings` / `1001425` — Vrat Chestnut Pumpkin Dumplings: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-pumpkin-pancakes` / `1001426` — Vrat Chestnut Pumpkin Pancakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-chestnut-sweet-potato-roti` / `1001427` — Vrat Chestnut Sweet Potato Roti: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-cumin-potato-curry` / `1001429` — Vrat Cumin Potato Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-cumin-sabudana-khichdi` / `1001430` — Vrat Cumin Sabudana Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-fennel-lotus-seed-curry` / `1001431` — Vrat Fennel Lotus Seed Curry: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-lotus-sabudana-khichdi` / `1001432` — Vrat Lotus Seed Sabudana Khichdi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-lotus-seed-saffron-kheer` / `1001433` — Vrat Lotus Seed Saffron Kheer: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-pepper-roasted-lotus-seeds` / `1001434` — Vrat Pepper Roasted Lotus Seeds: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-pumpkin-sabudana-pot` / `1001436` — Vrat Pumpkin Sabudana Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-sabudana-potato-thalipeeth` / `1001437` — Vrat Sabudana Potato Thalipeeth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-soft-sabudana-porridge` / `1001438` — Vrat Soft Savory Sabudana Porridge: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-steamed-chestnut-cakes` / `1001439` — Vrat Steamed Chestnut Cakes: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-sweet-potato-sabudana-pilaf` / `1001440` — Vrat Sweet Potato Sabudana Pilaf: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.vrat-taro-lotus-seed-pot` / `1001441` — Vrat Taro Lotus Seed Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.walnut-date-laddu` / `1001443` — Walnut Date Laddu: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-bottle-gourd-mung-rice` / `1001446` — Weeknight Bottle Gourd Mung Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-bottle-gourd-mung-semolina` / `1001447` — Weeknight Bottle Gourd Mung Semolina: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-cabbage-masoor-rice` / `1001450` — Weeknight Cabbage Masoor Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-carrot-masoor-oats` / `1001451` — Weeknight Carrot Masoor Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-carrot-mung-amaranth` / `1001452` — Weeknight Carrot Mung Amaranth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-carrot-mung-rice` / `1001453` — Weeknight Carrot Mung Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-carrot-mung-semolina` / `1001454` — Weeknight Carrot Mung Semolina: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-cauliflower-mung-millet` / `1001456` — Weeknight Cauliflower Mung Millet: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-cauliflower-pea-rice` / `1001457` — Weeknight Cauliflower Pea Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-chayote-pea-rice` / `1001461` — Weeknight Chayote Pea Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-fennel-pea-rice` / `1001462` — Weeknight Fennel Pea Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-green-bean-masoor-rice` / `1001464` — Weeknight Green Bean Masoor Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-green-bean-paneer-rice` / `1001465` — Weeknight Green Bean Paneer Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-paneer-chayote-rice` / `1001466` — Weeknight Paneer Chayote Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-paneer-fennel-rice` / `1001467` — Weeknight Paneer Fennel Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-paneer-pumpkin-millet` / `1001468` — Weeknight Paneer Pumpkin Millet: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-paneer-spinach-quinoa` / `1001469` — Weeknight Paneer Spinach Quinoa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-pumpkin-masoor-amaranth` / `1001470` — Weeknight Pumpkin Masoor Amaranth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-pumpkin-masoor-rice` / `1001471` — Weeknight Pumpkin Masoor Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-pumpkin-masoor-semolina` / `1001472` — Weeknight Pumpkin Masoor Semolina: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-pumpkin-mung-oats` / `1001473` — Weeknight Pumpkin Mung Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-pumpkin-pea-rice` / `1001474` — Weeknight Pumpkin Pea Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-spinach-masoor-semolina` / `1001475` — Weeknight Spinach Masoor Semolina: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-spinach-mung-amaranth` / `1001476` — Weeknight Spinach Mung Amaranth: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-spinach-mung-oats` / `1001477` — Weeknight Spinach Mung Oat Pot: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-spinach-mung-rice` / `1001478` — Weeknight Spinach Mung Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-spinach-paneer-rice` / `1001479` — Weeknight Spinach Paneer Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-tomato-masoor-rice` / `1001485` — Weeknight Tomato Masoor Rice: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.weeknight-tomato-pea-millet` / `1001487` — Weeknight Tomato Pea Millet: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.whole-wheat-halwa` / `1001494` — Whole Wheat Halwa: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.whole-wheat-panjiri` / `1001495` — Whole Wheat Panjiri: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.yam-fenugreek-sabzi` / `1001496` — Yam Fenugreek Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.zucchini-dill-sabzi` / `1001498` — Zucchini Dill Sabzi: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]
- `recipe.zucchini-mung-kitchari` / `1001499` — Zucchini Mung Kitchari: FC-1=`false` [no-match]; WE-8=`true` [ingredient-intersection:diets; ingredient-maximum:minAgeMonths; ingredient-union:allergens]

## FC1-G13 alias coverage

| MP-3c unresolved form | Ontology canonical alias | Covered |
|---|---|---|
| `rajma` | `kidney beans` | yes |
| `dahi` | `yogurt, plain` | yes |
| `sooji` | `semolina` | yes |
| `saunf` | `fennel seed` | yes |
| `dalchini` | `cinnamon` | yes |
| `chicken stock` | `chicken broth` | yes |
| `nutritional yeast` | `yeast, nutritional` | yes |
| `steamed broccoli` | — | no |

Seven of eight held-out misses have an authored ontology alias: rajma, dahi, sooji, saunf, dalchini, chicken stock, and nutritional yeast. `steamed broccoli` has no alias and remains a form/catalogue-resolution gap. Per scope, none were wired into MP-3 resolution.

## Director-artifact contradictions and corpus findings

1. `tree_nuts.phrases` explicitly includes `chestnut`, but a contested golden requires chestnut not to be excluded. The ontology note also says chestnut is included but contested. The implementation cannot satisfy both authorities without a director ruling.
2. `tree_nuts.negativePhrases` has singular `peanut`; the corpus rows use plural `peanuts` and also match positive `mixed nuts`. Token-boundary matching correctly does not stem singular to plural. Moreover, “mixed nuts, with peanuts” is genuinely a tree-nut mixture, while “mixed nuts, without peanuts” is also a tree-nut mixture, so the pattern-level must-not case is semantically broader than its stated intent.
3. The golden corpus references `corn` and `grape`, but neither is one of the 25 ontology concept IDs. Those rows cannot be evaluated as concept-membership gates without an authored concept.
4. The ontology authority text says every concept and alias carries `qualityState`; all 25 concepts do, but all 75 alias records omit `qualityState` (they do carry provenance). The executor did not invent values.
5. The viaIngredient note says all 13 cases cannot pass by name. `palak paneer` directly matches `paneer`, and `lassi` collides with the substring in “classic”. Six patterns exist only as plain USDA rows and three do not exist in this catalogue, so 13/13 cannot be demonstrated by the current fixtures.

## Stop disposition and required founder/director decisions

The stopped implementation candidate and evidence are committed to `fc-1-food-concepts` for inspection, but **nothing was pushed**. The report does not update `PROGRESS.md` or the handbook because FC-1 did not complete its blocking safety gate.

To resume FC-1 without executor tuning, the authored inputs need a ruling on:

- whether the contested chestnut case or the positive chestnut ontology phrase is authoritative;
- whether the `peanut` must-not case is meant to test pure peanut foods, mixed-nut foods without peanuts, or all names containing the token;
- concrete recipe fixtures/foodIds for the 13 viaIngredient proofs, avoiding raw-substring collisions and plain-USDA-only matches;
- whether absent/unknown concepts (`corn`, `grape`) remain report-only cases or receive separately authored ontology entries.

No cold-launch number, artifact-size launch delta, final build result, final search result, or fresh-install result is claimed after the stop.
