# REPORT WE-2 — recipe nutrition and build-time seed/index

Date: 2026-07-24
Branch: `ayurveda-app`
Status: **COMPLETE — all local gates green**

## Summary

WE-2 ships two founder requirements:

1. Every canonical recipe now has component-aware per-serving and per-100g
   nutrition derived from its USDA-bound ingredients. The panel covers energy,
   macros, fiber, sugars, all vitamins, and all minerals available in
   WiseEating's nutrient source.
2. The app now ships the final 14,484-row Ayurveda projection and a matching
   14,484-row search cache in the preseed artifact. A fresh install performs no
   Ayurveda inserts and no search rebuild.

T1 was accepted as commit `1e54ca4`. T2 contains the preseed artifact, runtime
no-op/delta behavior, tests, build tooling, and this close-out documentation.

The superseded untracked `docs/PORT-1-REPORT.md` was deleted before work began,
as explicitly directed. It was not archived or committed.

## T1 — component-aware recipe nutrition

`ayurveda-data/build_seed.py` selects each dravya's best ordered USDA binding
(`exact` before `near`, then authored order), multiplies each per-100g nutrient
by ingredient grams/100, and sums the components. Whole-recipe totals are
divided by servings and by total ingredient weight for the two display bases.

The catalog contains 39 fields:

- energy;
- carbohydrates, protein, fat, fiber, and total sugars;
- 22 vitamin fields;
- 11 mineral fields.

A source nutrient recorded as unavailable remains absent and is displayed as
`—`; it is never fabricated as zero. An ingredient without a resolvable
nutrition row marks the panel `estimated` and records the missing slug. A recipe
with no resolvable ingredient nutrition is marked `none`.

### Coverage

| Status | Recipes | Share |
|---|---:|---:|
| Full ingredient coverage | 1,500 | 100% |
| Estimated, with missing slugs | 0 | 0% |
| None | 0 | 0% |
| **Total** | **1,500** | **100%** |

The `none` share is 0%, below the 25% stop threshold.

### Classic Mung Kitchari hand check

Recipe: `recipe.classic-mung-kitchari`
Servings: 4
Total ingredient weight: 1,852 g

| Ingredient | USDA-bound kcal/100g | Recipe grams | Whole-recipe kcal |
|---|---:|---:|---:|
| White basmati rice (`6372`) | 365 | 180 | 657.00 |
| Split yellow mung dal (`10962`) | 347 | 180 | 624.60 |
| Ghee (`4558`) | 876 | 24 | 210.24 |
| Cumin seeds (`8148`) | 375 | 4 | 15.00 |
| Turmeric (`9277`) | 312 | 2 | 6.24 |
| Fresh ginger (`6687`) | 80 | 7 | 5.60 |
| Rock salt (`11888`) | unavailable | 5 | no energy value added |
| Water (`10444`) | unavailable | 1,450 | no energy value added |
| **Total** |  |  | **1,518.68** |

`1,518.68 / 4 = 379.67 kcal per serving`.

The pipeline result is **379.67 kcal per serving**, an absolute difference of
0.00 kcal from the independent arithmetic and within the 0.5 kcal gate.
Per 100 g, the result is `1,518.68 / 1,852 × 100 =
82.002159827214 kcal`.

### Recipe detail UI

Canonical recipe detail views use the existing glass-card, segmented-picker,
flow-layout, typography, and tint language. The panel switches between
per-serving and per-100g values, displays all 39 catalog entries, labels
coverage, and surfaces missing slugs when present.

## T2 — build-time projection and search cache

### Duplicate and ownership audit

The already runtime-seeded baseline store was audited before any dedupe
decision:

| Audit item | Result |
|---|---:|
| FoodItem rows | 14,484 |
| AyurvedaProfile rows | 2,214 |
| AyurvedaLink rows | 2,305 |
| Duplicate FoodItem IDs | 0 |
| Duplicate canonical profile slugs | 0 |
| Duplicate `(foodId, kind)` profiles | 0 |
| Duplicate AyurvedaLink `fdcId` values | 0 |

No duplicates exist, so **no dedupe path was added**.

Canonical ownership uses the unique profile slug (`dravya.*` or `recipe.*`)
mapped to a stable `foodId`. USDA and user-created FoodItems do not receive
those canonical slugs or Ayurveda fields. The delta path refuses any
reserved-band or canonical-slug ownership ambiguity instead of deleting or
overwriting possible user data.

### Shipped artifact

`ayurveda-data/build_preseeded_store.py` checkpoints and compacts a completed
build store, audits every invariant, emits deterministic gzip bytes, and writes
the two existing bundle parts. The shipped artifact contains:

| Invariant | Value |
|---|---:|
| FoodItem rows | 14,484 |
| Canonical profiles | 2,214 |
| Dravya / recipe profiles | 714 / 1,500 |
| Links | 2,305 |
| Recipe profiles with full nutrition | 1,500 |
| Profile seed version | 3 |
| Search cache version | 3 |
| Search cache `foodsCount` | 14,484 |
| Search payload compact foods | 14,484 |
| Search payload bytes | 27,436,229 |
| Part `aa` | 73,400,320 bytes |
| Part `ab` | 18,547,123 bytes |

The artifact audit rejects count drift, duplicate IDs/slugs/links, non-aiDraft
canonical content, missing nutrition panels, stale seed versions, cache-count
drift, an invalid payload, or duplicate compact search IDs.

### Runtime behavior

On a fresh store, `AyurvedaSeeder` verifies the version-3 profile stamps and
canonical ownership, returns without mutations, and records version 3 in
UserDefaults. `SearchIndexStore` now requires exact cache/DB count equality
before skipping a rebuild.

Fresh-install log evidence:

```text
✅ Ayurveda v3 preseed stamp verified; no inserts or updates.
✅ SearchIndexStore: Index is up-to-date (version: 3, DB: 14484). Skipping rebuild.
🔎 SearchIndexStore: Loaded from cached index (version: 3, 14484 foods).
```

The second/cold launch logged:

```text
Ayurveda seed version already applied, skipping.
✅ SearchIndexStore: Index is up-to-date (version: 3, DB: 14484). Skipping rebuild.
🔎 SearchIndexStore: Loaded from cached index (version: 3, 14484 foods).
```

Counts after both launches remained 14,484 foods / 2,214 profiles / 2,305
links, with one 14,484-row cache.

### Existing-store upgrade path

The original fully runtime-seeded baseline simulator was upgraded from seed v2
to v3 using the shipped T2 build. The log was:

```text
✅ Ayurveda v3 slug-keyed delta: inserted 0 rows (0 foods, 0 profiles, 0 links); updated 2214 profiles, 0 links, 0 recipe foods; replaced 0 ingredient sets.
✅ SearchIndexStore: Index is up-to-date (version: 3, DB: 14484). Skipping rebuild.
```

Post-upgrade counts were unchanged at 14,484 / 2,214 / 2,305; all 1,500 recipe
profiles had full nutrition; duplicate food IDs, profile slugs, and link
`fdcId` values were all zero.

For future content versions, the runtime delta:

- upserts profiles by canonical slug and links by `fdcId`;
- inserts only missing canonical rows;
- changes a canonical recipe FoodItem only after its slug proves ownership;
- replaces ingredient links only when their stable food/grams multiset differs;
- forces search rebuild only when searchable FoodItems changed;
- aborts on any ambiguous reserved-ID or canonical-slug ownership.

## Timing

Simulator: iOS 26.2, debug build, `-uiTestNoAds`. Times are wall-clock deltas
from the timestamp immediately before `simctl launch`.

| Measurement | Before | After | Delta |
|---|---:|---:|---:|
| Fresh launch to seed/index consistency check complete | 499.74 s | 13.09 s | **−486.65 s (−97.4%)** |
| Fresh launch to cached index loaded in memory | 499.74 s | 15.65 s | **−484.09 s (−96.9%)** |
| Cold launch to seeding complete | 1.48 s | 2.34 s | +0.86 s |
| Cold launch to cached index loaded | 3.00 s | 4.34 s | +1.34 s |

The first-launch regression stop condition did not trigger: first-launch
index readiness improved by 96.9%. The cold-launch increase is recorded
honestly; no rebuild or insertion occurred during that measurement.

## WE-2-FIX boundary correction

The first close-out attempt stopped when the validator passed a `str` to the
new preseed audit, whose implementation called `Path.is_file()`. The authorized
fix normalizes the argument at the audit function boundary:

```python
path = Path(path)
```

This is a one-line type-boundary correction. No deeper design issue was found
and no other production code was changed during WE-2-FIX.

## Full local gate rerun

Nothing was grandfathered from the stopped run.

| Gate | Result |
|---|---|
| Final artifact validator + D34 resolver simulation | PASS — 714 dravyas / 1,500 recipes; 12,601/12,601 USDA foods resolved |
| Nutrition and preseed tests | PASS — 8/8 |
| Coverage floor | PASS — 1,500 full / 0 estimated / 0 none |
| Kitchari independent arithmetic | PASS — 379.67 kcal/serving; difference 0.00 kcal |
| Two-build seed determinism | PASS — both seed files SHA-256 `1830a19134b7aabb044023140dea319424789cc7cfdfdde331230e357ef509b6` |
| Rules determinism | PASS — both rules files SHA-256 `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` |
| Fresh-install zero inserts/updates | PASS — explicit runtime log |
| Fresh-install no search rebuild | PASS — explicit runtime log |
| Second launch idempotence | PASS — zero new rows; counts unchanged |
| Existing-store slug-keyed upgrade | PASS — zero inserted rows and zero duplicates |
| Clean-derived-data iOS simulator build | PASS — `** BUILD SUCCEEDED **` |
| Lifecycle | PASS — 714 dravyas, 1,500 recipes, and all 2,214 artifact profiles remain `aiDraft` |
| Claims boundary | PASS — `ZFOODITEM` has no Ayurveda claim columns; no new medical-language terms |
| Diff hygiene | PASS — T1 untouched; WE-2-FIX production change is the one-line boundary normalization |

The Xcode project has no test target; the complete repository test suite for
WE-2 is the eight-test Python suite plus the clean simulator build and runtime
launch gates above.

## Follow-up candidates

These are candidates only; none was started:

1. Profile cold-start loading to explain the measured 1.34-second cold index
   increase without changing the now-green first-launch path.
2. VoiceOver and dark-mode smoke for the long-form recipe nutrition panel.
3. Expert review of the existing `aiDraft` Ayurveda content; nutrition values
   remain mechanically USDA-derived and do not alter that lifecycle.
