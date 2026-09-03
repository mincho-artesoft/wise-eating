# REPORT WE-8b — Age-Floor Source Audit

Date: 2026-07-25
Branch: `ayurveda-app`
Audit baseline: `6bb8740881e778ed00b7815ede9b632a9ab65843`
Status: **AUDIT COMPLETE — no behavior, source-data, seed, or artifact change**

## Scope and method

This task audited the input values consumed by WE-8. The approved propagation
rule itself was not changed.

The audit:

1. decoded the shipped `ayurveda_seed.json.gz`;
2. independently re-derived every recipe floor from the 30 dravya and 30 recipe
   batches plus `WiseEating/Legacy/foods.json`;
3. counted every tied ingredient whose age equals its recipe's derived maximum;
4. inspected the pre-WE-8 (`731c811`) preseed store read-only;
5. traced the implicated source rows through repository history; and
6. simulated the B options entirely in memory without writing a seed or store.

“Above” always means strict `>`. Driver counts include ties: when two
ingredients share the recipe maximum, both genuinely set that floor and both
receive one count. Consequently, driver counts are not expected to sum to
1,500.

Baseline artifact SHA-256 values:

| Artifact | SHA-256 at `0e8a028` |
|---|---|
| `WiseEating/ayurveda_seed.json.gz` | `e4bfcd638ce10d2815238a0c7da2dff00114f041bbd620425b7db92ac2d55156` |
| `WiseEating/preseeded_db.store.gz.part-aa` | `fb44696a82f9ad53bd8e98a65164865a2a160fb4e285a73173847226bc7fb0b8` |
| `WiseEating/preseeded_db.store.gz.part-ab` | `c2a569744291bcb89cfa509810a08aa991477c0d7e54e8a2be8c9a3db7d73bb2` |

## Phase A — audit findings

### A1. Full recipe histogram

| `minAgeMonths` | Recipes |
|---:|---:|
| 6 | 1 |
| 24 | 1,201 |
| 48 | 226 |
| 60 | 70 |
| 192 | 2 |
| **Total** | **1,500** |

| Threshold | Recipes strictly above |
|---:|---:|
| 12 months | 1,499 |
| 24 months | 298 |
| 36 months | 298 |
| 72 months | 2 |
| 144 months | 2 |

The distribution exactly matches the WE-8 report. The input population is
broader than three anomalous rows: the recipes use 190 distinct ingredient
references, of which 182 carry a positive age and 159 carry an age above 12.
Their distinct-reference histogram is:

| Ingredient reference age | Distinct references |
|---:|---:|
| 0 | 8 |
| 6 | 16 |
| 8 | 2 |
| 12 | 5 |
| 24 | 145 |
| 48 | 11 |
| 60 | 1 |
| 192 | 2 |

### A2–A3. Top 15 drivers and exact provenance

All 15 values are inherited from the exact USDA-backed `FoodItem` source row
selected by the dravya's exact FDC binding. None is authored in a dravya batch,
defaulted, or set by a WE-8 age rule. The batch supplies the binding only;
`build_seed.py:579-589` reads the age from the bound source row.

| Rank | Ingredient | Stored age | Recipes whose floor it sets | Exact source |
|---:|---|---:|---:|---|
| 1 | Cumin seed (`dravya.cumin`) | 24 | 607 | `batch-01.json` exact binding → `foods.json` ID 8148, “Spices, cumin seed,” `minAgeMonths: 24` |
| 2 | Olive oil (`dravya.olive-oil`) | 24 | 373 | `batch-08.json` exact binding → ID 8581, “Oil, olive, salad or cooking,” age 24 |
| 3 | Coriander seed (`dravya.coriander-seed`) | 24 | 280 | `batch-01.json` exact binding → ID 8147, “Spices, coriander seed,” age 24 |
| 4 | Ginger, fresh (`dravya.ginger-fresh`) | 24 | 259 | `batch-01.json` exact binding → ID 6687, “Ginger root, raw,” age 24 |
| 5 | Fennel seed (`dravya.fennel-seed`) | 24 | 257 | `batch-01.json` exact binding → ID 8509, “Spices, fennel seed,” age 24 |
| 6 | Turmeric (`dravya.turmeric`) | 24 | 196 | `batch-01.json` exact binding → ID 9277, “Spices, turmeric, ground,” age 24 |
| 7 | Mung bean (`dravya.mung-bean`) | 24 | 176 | `batch-01.json` exact binding → ID 10962, “Mung beans, mature seeds, raw,” age 24 |
| 8 | White rice (`dravya.white-rice`) | 24 | 158 | `batch-01.json` exact binding → ID 6372, “Rice, white, long-grain, regular, raw, enriched,” age 24 |
| 9 | Carrot (`dravya.carrot`) | 24 | 142 | `batch-04.json` exact binding → ID 7710, “Carrots, raw,” age 24 |
| 10 | Lemon (`dravya.lemon`) | 24 | 127 | `batch-01.json` exact binding → ID 5344, “Lemons, raw, without peel,” age 24 |
| 11 | Cilantro (`dravya.cilantro`) | 24 | 109 | `batch-02.json` exact binding → ID 7384, “Coriander (cilantro) leaves, raw,” age 24 |
| 12 | Cardamom, green (`dravya.cardamom`) | 24 | 92 | `batch-01.json` exact binding → ID 8144, “Spices, cardamom,” age 24 |
| 13 | Pumpkin (`dravya.pumpkin`) | 24 | 79 | `batch-04.json` exact binding → ID 5978, “Pumpkin, raw,” age 24 |
| 14 | Coconut, fresh (`dravya.coconut-fresh`) | 48 | 76 | `batch-05.json` exact binding → ID 7556, “Nuts, coconut meat, raw,” age 48 |
| 15 | Tomato (`dravya.tomato`) | 24 | 76 | `batch-04.json` exact binding → ID 7774, “Tomatoes, red, ripe, raw, year round average,” age 24 |

Repository history traces all these raw values, plus oats and both tea rows, to
the original `foods.json` import in commit `a6f5cf8` (then moved without content
change in `3295075`). Each remained byte-for-byte the same through `731c811`
and `0e8a028`.

The upstream authority or clinical derivation used to author the imported
`minAgeMonths` values is **untraced**. `foods.json` is USDA-backed nutritional
data, but `minAgeMonths` is application metadata, not a USDA nutrient field.
The repository contains no citation or generator that explains why cumin,
olive oil, rice, carrots, and many other rows received 24 months. No clinical
rationale is inferred here.

### A4. The 192-month rows

| Ingredient | Stored value | Exact source | Recipe inheriting it |
|---|---:|---|---|
| Chamomile tea (`dravya.chamomile-tea`) | 192 months | `batch-09.json` exact binding → `foods.json` ID 4889, “Tea, hot, chamomile,” raw age 192 | `recipe.beverage-chamomile-fennel-tea` (12 g chamomile) |
| Hibiscus tea (`dravya.hibiscus-tea`) | 192 months | `batch-09.json` exact binding → `foods.json` ID 4887, “Tea, hot, hibiscus,” raw age 192 | `recipe.beverage-hibiscus-fennel-tea` (10 g hibiscus) |

Each row gates one recipe, for two recipes total. Neither value comes from a
dravya batch or WE-8 rule. Both were already 192 months in the original
`a6f5cf8` import; their upstream rationale is untraced.

### A5. Oats

`dravya.oats` is exactly bound in `batch-03.json` to `foods.json` ID 2918,
“Oats, raw.” That source row stores **60 months**, and 70 recipes inherit 60 as
their floor. It is plainly above 12 months: the stored floor is five years.
WE-8 did not create or raise it; the same value is present in the original
`a6f5cf8` import and the pre-WE-8 store. Its upstream rationale is untraced.

### A6. Pre-WE-8 comparison

The read-only `731c811` store query found:

- all 15 top-driver FoodItems at the exact ages shown above;
- oats at 60 months;
- chamomile and hibiscus tea at 192 months; and
- all 1,500 recipe FoodItems at 0 months.

There is no `731c811..0e8a028` diff to `WiseEating/Legacy/foods.json` or any
dravya/recipe batch. For the 15 drivers, oats, and the two teas, WE-8 changed no
ingredient-level age; it propagated existing values onto recipe rows.

Across the complete ingredient set there is one deliberate exception: WE-8's
explicit honey rule raised three placeholder dravyas from 0 to 12 months:
`dravya.chyawanprash`, `dravya.honey-aged`, and `dravya.panchamrita`. Raw honey
was already 12 in source row 7075. This is the approved infant-botulism floor,
not part of the anomalous driver population.

### A7. Filter behavior and visible recipe counts

The age filter **hides** non-matching results; it does not badge or downrank
them:

- `SmartFoodSearchEngine.swift:985` executes `continue` when a profile
  constraint age is below `item.minAgeMonths`.
- `SmartFoodSearchEngine.swift:1076` executes the same hard exclusion for a
  parsed or quick-filter `targetConsumerAge`.
- `Tokenizer.swift:193-218` parses numeric age speech into that target.
- `FoodSearchView.swift:441-452` draws the age badge only for rows that survived
  filtering; it is not an alternative to the exclusion.

With the shipped 1,500-recipe histogram:

| Profile age | Visible recipes | Hidden recipes | Visible share |
|---:|---:|---:|---:|
| 9 months | 1 | 1,499 | 0.07% |
| 24 months | 1,202 | 298 | 80.13% |
| 60 months | 1,498 | 2 | 99.87% |

## Phase B — options costed, not applied

No option below was implemented. B2 and B3 are counterfactual in-memory
simulations; B1 deliberately has no fabricated replacement values.

### B1. Correct source values and re-derive — preferred

This addresses the defect at its source while preserving the approved maximum
propagation rule. It requires an expert-approved correction map for the
implicated `foods.json` rows, followed by the normal seed/store regeneration,
upgrade test, search-cache verification, and the full safety/golden suite.

The source review is not limited to three rows: 159 of the 190 distinct recipe
ingredient references currently exceed 12 months, including 145 at 24 months.

**Resulting histogram: unavailable without an approved correction map.**
**Visible counts at 9/24/60 months: unavailable for the same reason.** Producing
numbers would require guessing clinical source values, which this audit is
explicitly forbidden to do. Once the map exists, the unchanged max rule makes
both outputs deterministic.

### B2. Cap propagated floors at 36 months

Costing assumption: `min(ingredientMaximum, 36)`, except any explicit age rule
could set a higher value; the honey floor remains an absolute minimum of 12.
There is currently no explicit rule above 36.

| Resulting `minAgeMonths` | Recipes |
|---:|---:|
| 6 | 1 |
| 24 | 1,201 |
| 36 | 298 |

| Profile age | Visible recipes |
|---:|---:|
| 9 months | 1 |
| 24 months | 1,202 |
| 60 months | 1,500 |

This is mechanically small but changes the approved propagation rule and
conceals bad source inputs rather than correcting them. It requires founder and
expert justification plus seed, upgrade, artifact, and filter regression work.

### B3. Separate trace ingredients

Because no trace threshold is approved, this costing uses one explicit
illustrative rule only: ingredients of **2 g or less** do not participate in
the maximum; honey still imposes 12 months; if a recipe had no ingredient above
2 g it would retain the original maximum. No recipe in this corpus needs that
fallback.

| Resulting `minAgeMonths` | Recipes |
|---:|---:|
| 6 | 2 |
| 12 | 11 |
| 24 | 1,189 |
| 48 | 226 |
| 60 | 70 |
| 192 | 2 |

| Profile age | Visible recipes |
|---:|---:|
| 9 months | 2 |
| 24 months | 1,202 |
| 60 months | 1,498 |

Only 12 recipes change under this particular threshold. It does not address
oats or the two teas because those ingredients exceed 2 g. This is a genuine
modeling change: grams versus percentage, prepared weight, concentrated
ingredients, and rule-bearing trace ingredients all need expert decisions.

### B4. Accept as-is

| Resulting `minAgeMonths` | Recipes |
|---:|---:|
| 6 | 1 |
| 24 | 1,201 |
| 48 | 226 |
| 60 | 70 |
| 192 | 2 |

| Profile age | Visible recipes |
|---:|---:|
| 9 months | 1 |
| 24 months | 1,202 |
| 60 months | 1,498 |

This has no implementation cost, but records the present hard-exclusion
behavior as intentional: a 9-month profile sees 0.07% of recipes, and a
24-month profile loses 298. Given the untraced source rationale, this option
would need an explicit founder/expert ruling.

## Phase C — registry corrections applied

Only the two authorized handbook changes were made:

1. §5 now makes **1.592s** the post-WE-8 cold-launch baseline, explicitly
   recording the +5.9% change from WE-7's 1.504s as a deliberate safety-metadata
   trade associated with 478,317 bytes of preseed growth.
2. §3 now fixes the decision that unresolved safety metadata fails the build
   rather than defaulting permissively.

## Gates

| Gate | Result |
|---|---|
| G1 audit-only scope | PASS — only this report and the two authorized handbook edits |
| Seed rebuild | **Not run** |
| Seed SHA unchanged | PASS — `e4bfcd63…5156` |
| Preseed part-aa SHA unchanged | PASS — `fb44696a…0b8` |
| Preseed part-ab SHA unchanged | PASS — `c2a56974…3bb2` |
| G2 seven A questions | PASS — A1 through A7 answered |
| G3 provenance honesty | PASS — repository source traced exactly; missing upstream rationale marked **untraced** |
| Behavior/code/source-data changes | None |

## Finding

The WE-8 maximum propagation behaves exactly as designed. The restrictive
recipe distribution originates in pre-existing application metadata on the
USDA-backed food rows, not in the propagation math. Those values are old and
stable in repository history, but their upstream clinical derivation is
untraced. B1 is therefore the cleanest next decision path once an expert
supplies a reviewed source-value map.
