# D34 Execution Report

## Summary

D34 is complete on `ayurveda-app`. The deterministic D3 crosswalk adds 1,969 derived USDA links, the v2 seed contains 2,305 total links, and the D4 rules cover every remaining store food through the estimated tier. The Python resolver mirror classifies all 12,601 foods and reproduces the director's tier totals, modifier histogram, and nine spot values.

The four implementation groups before this report were committed as `0c3d9ee`, `a71ae2e`, `51e8d13`, and `a588c91`. Every commit uses `mincho.milev@gmail.com`. Nothing was pushed.

## match_crosswalk output block

```text
match_crosswalk output
rows: 1969
contested: 67
M2: 112
F: 0
distinct dravyas: 166
v1 overlap: 0
denied present: 0
top derived targets: pork 347 · lamb 296 · broiler-chicken 233 · turkey 140 · corn 67 · chicken-egg 56
wrote: ayurveda-data/crosswalk/crosswalk.csv
wrote: ayurveda-data/crosswalk/REVIEW-D3.md
```

## Gate results

### G1 — crosswalk: PASS

- Normative constants copied into `match_crosswalk.py`: 21 group prefixes, 89 eligible categories, 132 descriptor stopwords.
- Normalized distinct dravya keys: 1,608.
- Rows: 1,969; contested: 67; M2: 112; F: 0; distinct dravyas: 166.
- v1-bound overlap: 0 of 336; denied fdcIds 8244 and 12546 present: 0.
- Both generated files were byte-identical across two consecutive runs.

| Artifact | Run 1 SHA-256 | Run 2 SHA-256 | Result |
|---|---|---|---|
| `crosswalk.csv` | `b6458bdd12e5459648187d53612b523740ccc5d13b05962e3fb35e72f8e5606f` | `b6458bdd12e5459648187d53612b523740ccc5d13b05962e3fb35e72f8e5606f` | PASS |
| `REVIEW-D3.md` | `4d097037e66ce5a02753f04d19fcce09579003f072789fe62ef5b9f39812d138` | `4d097037e66ce5a02753f04d19fcce09579003f072789fe62ef5b9f39812d138` | PASS |

### G2 — seed v2 and rules bundle: PASS

```text
dravyas: 714
recipes: 1500
links: 2305 (336 v1 + 1969 derived)
placeholders: 383
primaries: 331
categoryRules: 187
modifiers: 14
unresolved ingredients: 0
engineExcluded: 2
```

- `seedVersion`: 2.
- The v1 `generatedAt`, dravyas, recipes, and first 336 links compare equal to the committed v1 payload.
- `ayurveda_rules.json` compares structurally equal to the verbatim authored category/default/modifier payload.
- Both generated files were byte-identical across two consecutive runs.

| Artifact | Run 1 SHA-256 | Run 2 SHA-256 | Result |
|---|---|---|---|
| `ayurveda_seed.json.gz` | `b20f45715c2b000f1d06dacb59377e5c799c84a45e0593779528f5872c8990b3` | `b20f45715c2b000f1d06dacb59377e5c799c84a45e0593779528f5872c8990b3` | PASS |
| `ayurveda_rules.json` | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` | PASS |

### G3 — validator and resolver simulation: PASS

Command: `python3 ayurveda-data/validate.py --store /tmp/pre`

```text
D34 resolver simulation
tiers: classical 336 · derived 1969 · estimated 10296
resolved foods: 12601/12601
foods firing modifiers: 6357/12265
Checked 714 dravyas, 1500 recipes
All checks passed.
```

- Crosswalk: 1,969 unique store fdcIds, no v1 overlap, no denied IDs, valid rules and resolvable dravyas.
- Category rules: 187 store categories / 187 rules / 0 dead / 0 uncovered.
- Modifiers: 14 unique IDs; all vectors, virya values, and gunas pass their enums/ranges.
- Seed: version 2, 2,305 unique links, 336 classical plus 1,969 derived.
- Resolver: all 12,601 store foods resolve; no default category fallback was needed for the current store.

### G4 — director spot values: PASS

| fdcId | Expected result | Result |
|---:|---|:---:|
| 8641 | derived `dravya.broiler-chicken`, base `[-1,0,1]`, fried → `[-1,1,2]` | PASS |
| 6556 | derived `dravya.orange-juice` over `dravya.orange` (R2) | PASS |
| 4106 | derived `dravya.sweet-potato` over `dravya.potato` (R1) | PASS |
| 11971 | derived `dravya.garlic` over `dravya.garlic-fresh-bulb` (R3) | PASS |
| 3623 | derived `dravya.apricot`, dried → `[0,1,-1]` | PASS |
| 3923 | estimated, processed → `[1,0,1]` | PASS |
| 68 | estimated, frozen → `[2,-1,2]` | PASS |
| 6148 | estimated, dry-heat → `[0,2,0]` | PASS |
| 2655 | estimated, no modifiers → `[2,0,-1]` | PASS |

## Contested sample

| fdcId | Food | Winner | Deciding rule | Losers |
|---:|---|---|:---:|---|
| 24 | Almond milk, sweetened | `dravya.almond-milk` | R3 | `dravya.badam-milk` |
| 25 | Almond milk, chocolate | `dravya.almond-milk` | R3 | `dravya.badam-milk` |
| 26 | Almond milk, unsweetened | `dravya.almond-milk` | R3 | `dravya.badam-milk` |
| 2086 | Pumpkin seeds, NFS | `dravya.pumpkin-seed` | R1 | `dravya.pumpkin` |
| 2087 | Pumpkin seeds, salted | `dravya.pumpkin-seed` | R1 | `dravya.pumpkin` |
| 2088 | Pumpkin seeds, unsalted | `dravya.pumpkin-seed` | R1 | `dravya.pumpkin` |
| 3613 | Orange juice, 100%, freshly squeezed | `dravya.orange-juice` | R1 | `dravya.orange` |
| 3614 | Orange juice, 100%, canned/bottled/carton | `dravya.orange-juice` | R1 | `dravya.orange` |
| 3615 | Orange juice, calcium added, canned/bottled/carton | `dravya.orange-juice` | R1 | `dravya.orange` |
| 3616 | Orange juice, frozen, reconstituted | `dravya.orange-juice` | R1 | `dravya.orange` |

## Modifier histogram

| Modifier | Foods |
|---|---:|
| raw | 1,356 |
| dry-heat | 1,031 |
| moist-heat | 771 |
| sweetened | 643 |
| canned | 640 |
| rich | 565 |
| frozen | 548 |
| processed | 424 |
| lowfat | 344 |
| fried | 329 |
| cured | 212 |
| dried | 206 |
| fermented-sour | 63 |
| pungent | 26 |

At least one modifier fired on 6,357 of the 12,265 non-classical foods.

## Files changed

`git diff --stat dac34aa --cached` was used so the unrelated, pre-existing unstaged `.DS_Store` modification is excluded from the D34 scope proof. The final committed range contains exactly the 12 authorized deliverables:

```text
 WiseEating/Ayurveda/AyurvedaResolver.swift  |   49 +-
 WiseEating/Ayurveda/AyurvedaRules.swift     |  233 ++++
 WiseEating/Main/DBSeed/AyurvedaSeeder.swift |   40 +-
 WiseEating/Main/DBSeed/SeedManager.swift    |    5 -
 WiseEating/ayurveda_rules.json              |    1 +
 WiseEating/ayurveda_seed.json.gz            |  Bin 450200 -> 458845 bytes
 ayurveda-data/REPORT-D34.md                 |  163 +++
 ayurveda-data/build_seed.py                 |  145 +-
 ayurveda-data/crosswalk/REVIEW-D3.md        |  199 +++
 ayurveda-data/crosswalk/crosswalk.csv       | 1970 +++++++++++++++++++++++++++
 ayurveda-data/match_crosswalk.py            |  594 ++++++++
 ayurveda-data/validate.py                   |  380 +++++-
 12 files changed, 3755 insertions(+), 24 deletions(-)
```

No director-authored input, dravya batch, recipe batch, model schema, or other source file was changed. The unrelated `.DS_Store` worktree modification remains unstaged and untouched.

## Open items for founder gate

No Xcode build or simulator execution is claimed in this packet. The founder should verify:

1. Build the app target in Xcode with `AyurvedaRules.swift`, `ayurveda_rules.json`, and the v2 seed included in the synchronized target.
2. Fresh install: confirm full Ayurveda seeding succeeds with 714 dravya profiles, 1,500 recipe profiles, and 2,305 links.
3. v1→v2 upgrade: start from a v1-seeded store with 336 links; confirm the top-up inserts exactly 1,969 missing links and touches no profiles, recipes, placeholders, or foods.
4. Relaunch after the upgrade: confirm the version-key guard skips; if the key is deliberately cleared, confirm the idempotent top-up inserts 0 links.
5. Smoke-test existing food, recipe, nutrition, search, and user-data flows for regressions.
