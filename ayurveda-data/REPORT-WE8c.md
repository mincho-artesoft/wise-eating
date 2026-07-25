# WE-8c — Provenance-Gated Age Enforcement

Date: 2026-07-26
Branch: `ayurveda-app`
Starting tip: `8b54f87` (one commit ahead of `origin/ayurveda-app`)
Status: **BLOCKED — G7 cold-launch gate is red; not pushed**

## Outcome

The B5 enforcement split is implemented and all correctness, safety,
determinism, search, fresh-install, and build gates are green. The candidate
does not ship because the final controlled cold-process median is **1.650s**,
which is **+3.62%** over the recorded 1.592s baseline and exceeds the authorized
**+2% / 1.624s** limit.

No FoodSearch ranking, ingredient-level age, propagation rule, UI copy, schema,
or authored content value changed. The implementation and regenerated artifacts
remain in local commits for founder review; nothing was pushed.

## Implementation

Each canonical seed safety block now stores:

- `minAgeMonths`: display floor, still the maximum over all ingredient floors;
- `enforcedMinAgeMonths`: maximum over `authored` ingredient floors only;
- `ageProvenance`: `authored` or `legacyImport`;
- `ageContributors`: one entry per contributing ingredient, including its
  display floor, enforced floor, provenance, ingredient ID, and grams.

`authored` currently means exactly the deliberate 12-month honey/infant-
botulism rule. Values inherited from `WiseEating/Legacy/foods.json` are
`legacyImport`. The v5 compact index persists both floors. Existing age badges
continue reading `CompactFoodItem.minAgeMonths`
(`FoodSearchView.swift:441–444`); both age-filter paths now read
`enforcedMinAgeMonths` (`SmartFoodSearchEngine.swift:985` and `:1076–1077`).
Noncanonical USDA/user rows retain their prior behavior by persisting their
existing `minAgeMonths` as both display and enforced values.

The cache and seed versions are both 5. This is a representation/version bump,
not a SwiftData schema change.

## Provenance breakdown

| Scope | Total | `authored` | `legacyImport` |
|---|---:|---:|---:|
| Dravya safety blocks | 714 | 4 | 710 |
| Recipe safety blocks | 1,500 | 4 | 1,496 |
| Recipe ingredient contributors | 10,571 | 4 | 10,567 |

All four authored dravyas have an enforced 12-month floor:
`dravya.chyawanprash`, `dravya.honey`, `dravya.honey-aged`, and
`dravya.panchamrita`. Three are placeholder dravyas; `dravya.honey` is the
USDA-bound canonical honey row. The four authored recipes are:
`recipe.drink-ginger-oat-warmer`, `recipe.ginger-lemon-honey-tea`,
`recipe.panchamrit-classic`, and `recipe.vasanta-kapha-clearer`.

Among legacy-import dravyas, 330 carry a positive display floor and 380 carry
zero. All 1,496 legacy-import recipes carry a positive display floor. Their
enforced floor is zero because no cited authored age rule contributes.

## G1 — honey protection

**PASS.** All four honey recipes and all three honey placeholder dravyas remain
hidden below 12 months. The USDA-bound canonical honey dravya also remains
hidden. At 12 months and above all eight are eligible.

Permanent derivation and persisted-artifact tests check these exact sets and
floors.

## G2 — recipe visibility

**PASS; actuals equal the founder simulation.**

| Profile age | Visible recipes | Hidden recipes |
|---:|---:|---:|
| 9 months | **1,496** | 4 honey recipes |
| 24 months | **1,500** | 0 |
| 60 months | **1,500** | 0 |

## G3 — display floors

**PASS; byte-for-byte values are unchanged from WE-8.**

| Display `minAgeMonths` | Recipe count |
|---:|---:|
| 6 | 1 |
| 24 | 1,201 |
| 48 | 226 |
| 60 | 70 |
| 192 | 2 |
| **Total** | **1,500** |

The enforced recipe histogram is `0: 1,496; 12: 4`.

## G4 — dravya visibility delta

The same provenance rule is applied to dravyas; no grandfathering preserves
the untraced legacy hard gate.

| Profile age | Visible before (display floor enforced) | Visible with B5 | Delta |
|---:|---:|---:|---:|
| 9 months | 457 | 710 | **+253** |
| 24 months | 684 | 714 | **+30** |
| 60 months | 706 | 714 | **+8** |

Ten-row sample:

| Dravya | Display | Enforced | Newly visible at |
|---|---:|---:|---|
| `dravya.chamomile-tea` | 192 | 0 | 9, 24, 60 months |
| `dravya.hibiscus-tea` | 192 | 0 | 9, 24, 60 months |
| `dravya.oats` | 60 | 0 | 9, 24 months |
| `dravya.carrot` | 24 | 0 | 9 months |
| `dravya.white-rice` | 24 | 0 | 9 months |
| `dravya.mung-bean` | 24 | 0 | 9 months |
| `dravya.olive-oil` | 24 | 0 | 9 months |
| `dravya.pumpkin` | 24 | 0 | 9 months |
| `dravya.lemon` | 24 | 0 | 9 months |
| `dravya.cumin` | 24 | 0 | 9 months |

The dravya display histogram remains:
`0:380, 6:64, 8:12, 9:1, 12:17, 24:210, 48:19, 60:3, 192:8`.
The enforced histogram is `0:710, 12:4`.

## G5 — production goldens

**PASS.** A temporary production-engine probe (removed after capture) called
`SmartFoodSearch3.searchCompact` against the final v5 cache:

- legacy goldens: **25/25 exact**;
- `without dairy`: Amaranth Kheer absent;
- `no allergens`: **0** allergen-bearing seeded recipe violations.

No baseline was edited and no age-sensitive golden moved.

## G6 — complete local gates

| Gate | Result |
|---|---|
| Validator + D34 resolver | PASS — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA rows |
| Complete repository suite | PASS — **62/62** |
| WE-8c methods | PASS — 9/9 derivation/artifact checks |
| Deterministic seed | PASS — two builds and shipped file SHA `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| Deterministic compact store | PASS — two builds byte-identical |
| Artifact audit | PASS — 14,484 foods/cache rows, cache v5, 2,214 profiles, 2,305 links, 10,571 IngredientLinks |
| Fresh install | PASS — `Ayurveda v5 preseed stamp verified; no inserts or updates` |
| Fresh search index | PASS — v5 / DB 14,484, `Skipping rebuild` |
| Second seed run | PASS — version-stamped no-op |
| Production goldens | PASS — 25/25 legacy + 2/2 safety |
| Debug arm64 simulator build | PASS |
| Clean Release arm64 simulator build | PASS |
| Lifecycle | PASS — 2,214/2,214 profiles remain `aiDraft` |
| Claims boundary | PASS — exactly 2,214 canonical rows have Ayurveda facets; plain USDA rows receive none |

Artifact hashes:

| Artifact | SHA-256 |
|---|---|
| `ayurveda_seed.json.gz` | `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| `preseeded_db.store.gz.part-aa` | `9509d74422f90a2a178955cede10729077fe328fda871fee477a47d08bfe4896` |
| `preseeded_db.store.gz.part-ab` | `0e7b8a44ad9c9a5bd934ed5308e36c04d96d5d3c39df52cb2ae6dd5b17bb41ee` |

The seed grew 88,323 bytes. The two preseed parts grew 27,211 bytes combined;
total bundled seed-plus-store growth is 115,534 bytes.

## G7 — cold launch

**FAIL — shipment blocker.**

Method: final uninstrumented Debug app, `-uiTestNoAds -we6LaunchProfile`,
process terminated before each run, Calendar permission resolved, simulator
left booted, and host monotonic launch time compared with the
`first-interactive-frame` marker. The final series used the exact retained
baseline device, `WiseEating-WE2-Baseline`
(`AF937668-3BFE-45E8-B42A-A76B914038DD`), with the other simulator shut down.

Fresh install completed in 5.181s and separately proved no insert/no rebuild.
Final cold-process samples:

| Sample | Total |
|---:|---:|
| 1 | 1.653s |
| 2 | 1.634s |
| 3 | 1.674s |
| 4 | 1.649s |
| 5 | 1.649s |
| 6 | 1.654s |
| 7 | 1.650s |
| **Median** | **1.650s** |

Recorded baseline: 1.592s. Authorized ceiling: 1.62384s (reported as 1.624s).
Actual delta: **+0.058s / +3.62%**. The best sample (1.634s) also exceeds the
ceiling. No launch behavior was changed to chase the gate.

For completeness, an initial series on a different iPhone 17 Pro simulator
measured 1.663s median, and the correct baseline device while both simulators
were booted measured 1.672s. Those noncomparable/control-contaminated series
were not used as the final gate result.

## Additional audit — plain USDA rows on `main`

**Yes.** This is a pre-existing `main` behavior independent of Ayurveda.
At pristine-main tip `9a5429d`,
`WiseEating/FoodSearch/VM/SmartFoodSearch 3.swift:834` applies
`item.minAgeMonths` to profile constraints and line 925 applies it to parsed
age intent. Both paths `continue`, so nonmatching rows are hard-hidden rather
than badged or downranked. `SearchIndexStore.swift:403` copies the legacy value
into every compact row.

The shipping `WiseEating/Legacy/foods.json` has exactly 12,601 plain USDA rows.
Its impact is:

| Profile age | Visible plain USDA | Hidden plain USDA |
|---:|---:|---:|
| 9 months | 4,353 | 8,248 |
| 24 months | 11,807 | 794 |
| 60 months | 12,243 | 358 |

WE-8c deliberately does not fix that production-main issue. Noncanonical rows
on `ayurveda-app` likewise preserve the pre-existing enforcement behavior.

## Commit and push disposition

Local commits created:

1. `bf2624b` — provenance-gated enforcement and tests;
2. `4d61667` — deterministic v5 seed and prebuilt cache artifacts;
3. `6e14f5b` — corrected the stale fresh-cache test version literal.

Because G7 is red, the report/update phase is recorded locally and **no push is
authorized or attempted**. Founder direction is required before this candidate
can ship.
