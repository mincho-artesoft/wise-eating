# REPORT-NUT5A — dravya nutrition and batch 1

Date: 2026-08-04

Baseline: `12e7b7993d4df9a2d24a8876444abc2ec3b07f28`

Branch: `ayurveda-app`

## Outcome

Dravya nutrition now reaches placeholder `FoodItem` rows in the shipped store. The packet
adds 17 director-reviewed IFCT matches and 34 authored compositions without changing the
catalogue, seed version, or food video archive.

Final source/seed state:

- 704 dravyas, 1,511 recipes, 14,487 foods, 2,215 profiles, 2,336 Ayurveda links
- 375 placeholders, seed version 8
- 124 dravya nutrition panels: 84 measured and 40 derived
- 251 placeholders remain all-null for nutrition
- `_review.status == "unsourced — no IFCT row, no published composition found"`: 267 → 216

## Phase 0 — reproduced defect

The baseline preseed returned:

```text
900005|Agathi leaf|1|1|1
all-null placeholders: 375
```

The source panel existed, but none of its macronutrients, vitamins, or minerals reached the
store.

## Phase 1 — panel emission and app ingest

`build_seed.py` now emits each sourced dravya panel on its placeholder seed entry.
`AyurvedaSeeder` writes the same 39-nutrient catalogue used by recipe panels and records
`RunResult.nutritionAppliedFoods`. Values remain per 100 g: no scaling and no invented
`other.weightG`.

The catalogue drift test now proves that:

1. the Python catalogue and Swift key list agree;
2. the dravya and recipe panel paths draw from that same catalogue; and
3. the raw dravya source template agrees on every shipped key and unit.

The comment above `SOURCE_ONLY_NUTRIENT_CATALOG` was corrected: 65 new structural fields are
validated at ingest but excluded from shipped artifacts. `vitamins.vitaminD` appears there
only for ingest-unit validation because it is already a shipped `NUTRIENT_CATALOG` field.

Manufacturing launch gate:

```text
nutritionAppliedFoods: 73
Agathi leaf: macronutrients/vitamins/minerals non-null, 33 nutrients
all-null placeholders: 302
```

Agathi's six absent shipped nutrients remain absent. Its vitamin D value, 4.02 µg/100 g, is
present. Its four zeroes (`retinol`, `caroteneAlpha`, `cryptoxanthinBeta`, `lycopene`) are
literal IFCT measurements; no source null became zero.

## Phase 2 — 17 reviewed IFCT matches

All accepted rows carry the review decision's `why` text in `_review.source`; the three
qualified accepts also carry their review note. `dravya.pomegranate-sour` is unchanged.

| dravya | IFCT | full-schema fields |
|---|---:|---:|
| `dravya.bathua` | C008 | 160 |
| `dravya.colocasia-stem` | D041 | 160 |
| `dravya.colocasia-leaf` | C018 | 160 |
| `dravya.jackfruit-seed` | D052 | 160 |
| `dravya.ponnanganni` | C029 | 160 |
| `dravya.rice-bean` | B023 | 160 |
| `dravya.vermicelli` | A023 | 160 |
| `dravya.tender-tamarind-leaf` | C034 | 160 |
| `dravya.red-amaranth-greens` | C003 | 160 |
| `dravya.radish-greens` | C031 | 160 |
| `dravya.dry-coconut` | H006 | 160 |
| `dravya.white-peas` | B017 | 160 |
| `dravya.ash-plantain` | D063 | 160 |
| `dravya.tender-bamboo-pickled` | D002 | 160 |
| `dravya.long-brinjal` | D031 | 160 |
| `dravya.pomegranate-sweet` | E055 | 160 |
| `dravya.snake-gourd` | D070 | 160 |

Zero reconciliation:

- 848 literal IFCT zeroes were written across the full 160-field source schema.
- 84 of those zeroes are within the 39 shipped nutrients.
- Every written zero maps to a literal zero in the corresponding IFCT source cell; no null
  or non-zero source value became zero.
- The earlier count of 849 was caused by rounding the positive value `0.00002` to four
  decimal places. The importer now retains sufficient precision, so the value remains
  positive and the correct literal-zero count is 848.

## Phase 3 — 34 authored compositions

All 34 composition slugs resolve to existing placeholder dravyas. Every ingredient has a
panel, so every composition produced a complete result; no partial panel was written.
`yieldG` is the divisor, while optional `waterG` documents mass and contributes no nutrient.

| dravya | ingredients | shipped nutrients |
|---|---:|---:|
| `dravya.aam-panna` | 5 | 34 |
| `dravya.kitchari-mung-rice` | 6 | 38 |
| `dravya.kitchari-tridoshic` | 8 | 38 |
| `dravya.khichadi-vegetable` | 8 | 39 |
| `dravya.curd-rice` | 7 | 35 |
| `dravya.coconut-rice` | 7 | 38 |
| `dravya.lemon-rice` | 9 | 37 |
| `dravya.tamarind-rice` | 8 | 34 |
| `dravya.veg-pulao` | 8 | 38 |
| `dravya.dal-tadka-mung` | 7 | 37 |
| `dravya.dal-fry-toor` | 7 | 33 |
| `dravya.kadhi` | 9 | 34 |
| `dravya.rasam` | 9 | 35 |
| `dravya.rice-gruel` | 2 | 28 |
| `dravya.pakhala` | 2 | 28 |
| `dravya.ambali` | 3 | 37 |
| `dravya.ragi-malt` | 3 | 35 |
| `dravya.sattu-drink` | 3 | 32 |
| `dravya.lassi-digestive` | 3 | 33 |
| `dravya.lassi-sweet` | 2 | 30 |
| `dravya.shrikhand` | 4 | 31 |
| `dravya.basundi` | 3 | 29 |
| `dravya.rabri` | 3 | 29 |
| `dravya.badam-milk` | 5 | 33 |
| `dravya.rose-milk` | 2 | 27 |
| `dravya.masala-chai` | 2 | 27 |
| `dravya.thandai` | 7 | 38 |
| `dravya.halwa-carrot` | 6 | 37 |
| `dravya.sooji-halwa` | 4 | 32 |
| `dravya.payasam-mung` | 6 | 37 |
| `dravya.pongal-sweet` | 7 | 38 |
| `dravya.til-ladoo` | 2 | 27 |
| `dravya.peanut-chikki` | 2 | 24 |
| `dravya.jowar-bhakri` | 2 | 25 |

### Inherited per-nutrient observation behaviour

The existing recipe calculator emits a nutrient when at least one ingredient observes it;
ingredients missing that individual nutrient contribute nothing. The composition path
deliberately inherits this behaviour so dravya and recipe panels remain consistent. It can
understate a nutrient when one ingredient has a measured value and another lacks that
measurement. This affects derived dravyas and all 1,511 existing recipes. Changing it is a
candidate for a separate packet that updates and gates both paths together.

For zeroes specifically, 28 outputs on 10 rows use this inherited rule: one ingredient has
a literal measured zero and the remaining ingredients do not carry that nutrient. Each of
the 10 rows records the exact nutrient names in `_review.inheritedPartialObservationZeroes`.
The complete trace is:

```text
dravya.kitchari-mung-rice | caroteneAlpha | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.ghee, dravya.cumin, dravya.turmeric, dravya.rock-salt
dravya.kitchari-mung-rice | cryptoxanthinBeta | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.ghee, dravya.cumin, dravya.turmeric, dravya.rock-salt
dravya.kitchari-mung-rice | lycopene | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.ghee, dravya.cumin, dravya.turmeric, dravya.rock-salt
dravya.kitchari-tridoshic | caroteneAlpha | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.ghee, dravya.cumin, dravya.coriander-seed, dravya.fennel-seed, dravya.turmeric, dravya.rock-salt
dravya.kitchari-tridoshic | cryptoxanthinBeta | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.ghee, dravya.cumin, dravya.coriander-seed, dravya.fennel-seed, dravya.turmeric, dravya.rock-salt
dravya.kitchari-tridoshic | lycopene | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.ghee, dravya.cumin, dravya.coriander-seed, dravya.fennel-seed, dravya.turmeric, dravya.rock-salt
dravya.khichadi-vegetable | cryptoxanthinBeta | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.carrot, dravya.green-peas, dravya.ghee, dravya.cumin, dravya.turmeric, dravya.rock-salt
dravya.coconut-rice | caroteneAlpha | zero: dravya.urad-dal | absent: dravya.white-rice, dravya.coconut-fresh, dravya.ghee, dravya.mustard-seed, dravya.curry-leaf, dravya.rock-salt
dravya.coconut-rice | cryptoxanthinBeta | zero: dravya.urad-dal | absent: dravya.white-rice, dravya.coconut-fresh, dravya.ghee, dravya.mustard-seed, dravya.curry-leaf, dravya.rock-salt
dravya.coconut-rice | lycopene | zero: dravya.urad-dal | absent: dravya.white-rice, dravya.coconut-fresh, dravya.ghee, dravya.mustard-seed, dravya.curry-leaf, dravya.rock-salt
dravya.lemon-rice | retinol | zero: dravya.urad-dal | absent: dravya.white-rice, dravya.sesame-oil, dravya.chana-dal, dravya.mustard-seed, dravya.turmeric, dravya.lemon, dravya.curry-leaf, dravya.rock-salt
dravya.lemon-rice | lycopene | zero: dravya.urad-dal | absent: dravya.white-rice, dravya.sesame-oil, dravya.chana-dal, dravya.mustard-seed, dravya.turmeric, dravya.lemon, dravya.curry-leaf, dravya.rock-salt
dravya.dal-tadka-mung | caroteneAlpha | zero: dravya.mung-dal-split | absent: dravya.ghee, dravya.cumin, dravya.asafoetida, dravya.ginger-fresh, dravya.turmeric, dravya.rock-salt
dravya.dal-tadka-mung | cryptoxanthinBeta | zero: dravya.mung-dal-split | absent: dravya.ghee, dravya.cumin, dravya.asafoetida, dravya.ginger-fresh, dravya.turmeric, dravya.rock-salt
dravya.dal-tadka-mung | lycopene | zero: dravya.mung-dal-split | absent: dravya.ghee, dravya.cumin, dravya.asafoetida, dravya.ginger-fresh, dravya.turmeric, dravya.rock-salt
dravya.ambali | caroteneAlpha | zero: dravya.ragi | absent: dravya.buttermilk, dravya.rock-salt
dravya.ambali | cryptoxanthinBeta | zero: dravya.ragi | absent: dravya.buttermilk, dravya.rock-salt
dravya.ambali | lycopene | zero: dravya.ragi | absent: dravya.buttermilk, dravya.rock-salt
dravya.ragi-malt | caroteneAlpha | zero: dravya.ragi | absent: dravya.milk-cow, dravya.jaggery
dravya.ragi-malt | cryptoxanthinBeta | zero: dravya.ragi | absent: dravya.milk-cow, dravya.jaggery
dravya.ragi-malt | lycopene | zero: dravya.ragi | absent: dravya.milk-cow, dravya.jaggery
dravya.ragi-malt | vitaminC | zero: dravya.ragi | absent: dravya.milk-cow, dravya.jaggery
dravya.payasam-mung | caroteneAlpha | zero: dravya.mung-dal-split | absent: dravya.jaggery, dravya.coconut-fresh, dravya.ghee, dravya.cashew, dravya.cardamom
dravya.payasam-mung | cryptoxanthinBeta | zero: dravya.mung-dal-split | absent: dravya.jaggery, dravya.coconut-fresh, dravya.ghee, dravya.cashew, dravya.cardamom
dravya.payasam-mung | lycopene | zero: dravya.mung-dal-split | absent: dravya.jaggery, dravya.coconut-fresh, dravya.ghee, dravya.cashew, dravya.cardamom
dravya.pongal-sweet | caroteneAlpha | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.milk-cow, dravya.jaggery, dravya.ghee, dravya.cashew, dravya.cardamom
dravya.pongal-sweet | cryptoxanthinBeta | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.milk-cow, dravya.jaggery, dravya.ghee, dravya.cashew, dravya.cardamom
dravya.pongal-sweet | lycopene | zero: dravya.mung-dal-split | absent: dravya.white-rice, dravya.milk-cow, dravya.jaggery, dravya.ghee, dravya.cashew, dravya.cardamom
```

## Phase 4 — shipped artifact and verification

Two independent builds were byte-identical:

| artifact | SHA-256 |
|---|---|
| `Ayura/ayurveda_seed.json.gz` | `b7d8138d1b2749d5f21ec3cde23878283eaaac8f44d0654b8fafc6a83def8ebf` |
| `Ayura/ayurveda_rules.json` | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` |
| `Ayura/food_concepts.json.gz` | `8ed4dcf7b38606247a739e1fa9ee98b667af07a3dd4b67a531a5fd9f2313a90d` |
| `Ayura/food_roles.json.gz` | `b5b858ac9bb94ead6b9a2cf57f0db92e2b8b335b0a66b2b8f92801149981ffab` |
| reconstructed preseed store | `78f2ae49ad7576eb4a234350a382310e2c3b26f6018936a8ce2643b00963b861` |

Preseed parts:

| part | bytes | SHA-256 |
|---|---:|---|
| `preseeded_db.store.gz.part-aa` | 73,400,320 | `445da9297e32b676f46fe149a32c7200e97b52161e8d0f90311076f9fabefeda` |
| `preseeded_db.store.gz.part-ab` | 21,285,651 | `178f91fe9be1c13bfcd0640c49dba0004e2e7289aabdb186c5436414f1fc3137` |

`validate.py --store` passed, including the 900001–900375 placeholder band and its pinned
mapping hash. SQLite integrity is `ok`. Runtime/export spot checks:

```text
900001|Aam panna|macros=1|vitamins=1|minerals=1|other=1
900005|Agathi leaf|macros=1|vitamins=1|minerals=1|other=1
900183|Mung and rice kitchari|macros=1|vitamins=1|minerals=1|other=1
```

The final installed Debug app opened the completed store, skipped seed mutation, loaded
nutrition display data for all 1,511 recipes, and reported search index version 9 complete
for 14,487 foods.

Verification results:

- full Python suite: 182 tests, 0 failures
- Debug simulator build: succeeded, required assets 8/8
- Release simulator build: succeeded, required assets 8/8
- tracked files over 80,000,000 bytes: only
  `Ayura/Food/food_archive_480.mp4`, 85,697,754 bytes
- no tracked file reaches 90,000,000 bytes
- no archive file or frame map changed

Seed version remains 8. This packet adds content to existing nutrition fields; it does not
add or migrate schema, and the regenerated preseed already carries the panels.
