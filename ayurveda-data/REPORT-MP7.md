# MP-7 — Culinary plausibility

Date: 2026-07-27

Branch: `ayurveda-app`

Status: **STOPPED at MP7-G2: 9 MAJOR errors; gate is at most 8**

## Outcome

Rev7 fixes the final G2c readiness leak without changing role classification.
The build-time projection, immutable runtime cache, solver eligibility check,
narration adapter, solver harness, and C1–C10 checker all consume
`notReadyToEat`. The obsolete `concentrateGroups` path has been deleted.

The ordered gates are green through G2b:

| Gate | Actual | State |
|---|---:|---|
| G0 known-bad meals detected | **21/21** | pass |
| Role training fixtures | **71/71** | pass |
| G1 `other` coverage | **7/589 (1.188%)** | pass |
| G1b unmapped category rows | **0/12,601** | pass |
| G2c forward | **0/526 wrong** | pass |
| G2c reverse | **0/303 wrong** | pass |
| G2b authored recipes | **39/40 (97.5%)** | pass |
| G2 exact | **85/100** | pass |
| G2 unresolved | **0/100** | pass |
| G2 MAJOR | **9/100** | **STOP** |

No resolver rule, source label, threshold, or fixture was changed after the
G2 result. G4–G8 were not run.

## Commit and push ledger

| Work | Commit | State |
|---|---|---|
| Rev7 director rule, unmodified | `687e719` | pushed |
| Rev7 projection and deterministic cache | `a1483a8` | pushed |
| G2b labels frozen before scoring | `d11923b` | pushed |
| G2 labels frozen before scoring | `b0f683b` | pushed |
| This stop report | report commit | committed and pushed after stop |

Artifact SHA-256:

- `food-roles.json`: `0bf542cf312ba5584d4fc8188ad013499e2aab4907f6ba903106ab908940e603`
- `food_roles.json.gz`: `2fd30464da8c403cd5cf962b8201148d2d6c34ea8ab828b87845a6b33bda201d`
- G2b frozen fixture: `768035e0c7fee3db4267a5896ab64a0d59547d62c27db1233ebe1c23aaae6bdc`
- G2 frozen fixture: `614831c18d39f29696187bf286dca1ece649dc8ad10d492c741bd6549a6fba58`

## Rev7 implementation

The concentrate rule is exactly the director-authored token rule:

```text
trigger: concentrate
veto: from concentrate | includes from concentrate
```

The token is evaluated after explicit-unready markers and prepared indicators,
and before the other structural triggers. The former
`concentrateGroups` implementation is absent from source.

| `notReadyToEat` trigger | Plain rows |
|---|---:|
| unprepared | **87** |
| dry-pulse-or-grain | **89** |
| commodity-flour | **58** |
| unreconstituted | **26** |
| uncooked | **12** |
| dough | **11** |
| ready-to-bake | **10** |
| concentrate | **11** |
| **Total** | **304 (2.41%)** |

The three distinguishing rows match the reference:

| Row | Role | Readiness result |
|---|---|---|
| Raspberry juice concentrate | beverage | `concentrate` |
| Lemon juice from concentrate, canned | condiment | ready |
| Orange juice, chilled, includes from concentrate | beverage | ready |

Focused MP-7 tests: **20/20 green**, including deterministic artifact equality,
all G0 assertions, all 71 role fixtures, the exact 304-row trigger partition,
and the three concentrate cases.

The legacy rev2 fixture key remains named `requiresCookingCases`. Its only
intentional semantic migration is “Chickpea flour (besan),” which is false
under the narrow historical flag and true under generalized
`notReadyToEat`. It is not counted in the 71 role-fixture result.

## Ordered gate evidence

### G0 — known-bad MP-6b plan

| Required finding | Actual |
|---|---:|
| Meals failing at least one hard plausibility property | **21/21** |
| Named infant-formula meals fail C1 | **3/3** |
| Four-chocolate-drink breakfast fails C6 | **yes** |
| Six-herb dinner fails C2 and C3 | **yes / yes** |
| Named raw mung/lentil meals fail C5 | **3/3** |

### Role fixtures

All **71/71** director cases match with zero deviations. This is
training/self-consistency evidence, not a score.

### G1 and G1b

G1 seed: **20260727**.

The proportional 500-row sample contains 13 classical, 78 derived, and 409
estimated rows. Unioning it with the 91 distinct IDs in the real MP-6b sample
produces 589 unique rows.

| Metric | Actual | Gate |
|---|---:|---:|
| Rows resolving `other` | **7/589 (1.188%)** | ≤10% |
| Live category values mapped | **187/187** | — |
| Unmapped category rows | **0/12,601** | ≤2% |

### G2c — exhaustive eligibility census

Rev7 retains the 526-row forward population:

| Role | Rows |
|---|---:|
| infantProduct | 322 |
| ingredientOnly | 154 |
| nonFood | 30 |
| supplement | 20 |
| **Total** | **526** |

No new ineligible ID was added relative to the previously reviewed rev5
population. The remaining 526 retain their genuine-ineligible adjudications:
**0/526 wrong**.

The reverse gate rechecks the frozen 303-row rev6 eligible-and-ready cohort.
Raspberry juice concentrate is now blocked by C5, and the other 302 rows retain
their prepared-food adjudications: **0/303 wrong**. The live residual
marker-bearing, role-eligible, ready population is therefore 302.

### G2b — authored recipes

The labels were committed before any resolver lookup.

- Seed: **2026072703**
- Population: 1,500 authored recipes
- Sample: 40
- Exact: **39/40 (97.5%)**
- Recipes in prohibited roles across the corpus: **0/1,500**
- Recipes on an anchor role: **1,039/1,500**

One disagreement:

| Food ID | Name | Expected | Actual | Rule |
|---:|---|---|---|---|
| 1000676 | Gujarati Stuffed Bitter Gourd | side | main | recipePostPass-default |

The frozen label was not changed after scoring.

### G2 — third random holdout

The 100 labels were committed in `b0f683b` before the role artifact was queried.

- Seed: **2026072704**
- Population: 14,484 canonical rows sorted by food ID
- Sample: 100

| Class | Actual | Gate |
|---|---:|---:|
| exact | **85** | ≥85 — pass |
| unresolved | **0** | ≤8 — pass |
| minor | **5** | report |
| MAJOR | **9** | ≤8 — **STOP** |
| eligibility-crossing | **1** | report loudly; G2c is the eligibility gate |

#### MAJOR — 9

| Food ID | Name | Expected | Actual | Rule |
|---:|---|---|---|---|
| 1001103 | Punjabi Cumin Aloo Gobi | side | main | recipePostPass-default |
| 3366 | Macaroni or pasta salad, made with any type of fat free dressing | side | main | U-CATEGORY-FINE |
| 6866 | Nuts, formulated, wheat-based, all flavors except macadamia, without salt | side | staple | G-STAPLE |
| 3909 | Potato skins, with cheese | side | staple | U-CATEGORY-FINE |
| 3129 | Egg roll, meatless | side | main | S-EGG |
| 7505 | Potatoes, french fried, all types, salt not added in processing, frozen, oven-heated | side | staple | G-STAPLE |
| 2327 | Muffin, chocolate chip | sweet | staple | U-CATEGORY-FINE |
| 9036 | Water, with corn syrup and/or sugar and low calorie sweetener, fruit flavored | beverage | staple | G-STAPLE |
| 7385 | Corn, sweet, yellow, raw | side | staple | G-STAPLE |

#### Minor — 5

| Food ID | Name | Expected | Actual |
|---:|---|---|---|
| 1000956 | Manda (Thin Rice Water) | staple | main |
| 4469 | Kimchi | condiment | side |
| 4375 | Sauerkraut | condiment | side |
| 3528 | Rice, brown, with cheese and/or cream based sauce, no added fat | staple | main |
| 5670 | Frozen novelty, ice cream type, covered, with nuts | sweet | side |

#### Eligibility-crossing — 1

| Food ID | Name | Expected | Actual | Rule |
|---:|---|---|---|---|
| 8494 | Milk, evaporated, 2% fat, with added vitamins A and D | ingredientOnly | side | U-CATEGORY-COARSE |

This row is a real new finding: the frozen label treats evaporated milk as a
cooking ingredient rather than a directly served component. Per §9, G2c—not
the random sample—remains the eligibility gate, so this is reported separately
and was not counted among the nine MAJOR errors. No rule was added after seeing
it.

The measured third holdout is valid for rev7. Any rule revision authored after
these results must mark it burned and retain it only as a regression fixture.

## Gates not run after stop

| Gate | State |
|---|---|
| G3 100-row disagreement review | Prior exact cross-derivation reference retained; no new review started |
| G4 full regression | **NOT RUN** |
| G5 30-solve feasibility | **NOT RUN** |
| G6 Y1 before/after | **NOT RUN** |
| G7 solve/role/launch/memory | **NOT RUN** |
| G8 tracked-file size | **NOT RUN** |

The handbook and progress milestone are not advanced while MP-7 is stopped.

## Burned regression fixtures

The two earlier samples remain committed and explicitly labelled in-file as
training fixtures:

- seed 20260727 — 60 rows;
- seed 2026072702 — 100 rows.

Neither is quoted as a held-out score.

## Contested — printed, not acted on

Role cases:

1. Kheer (rice pudding): sweet / staple.
2. Buttermilk / chaas: beverage / side.
3. Ghee: fat / condiment.
4. Hummus: side / condiment.
5. Chyawanprash: medicinalHerb / sweet.
6. Coconut, raw: side / fat.

Exclusion cases:

1. pork / salami;
2. pork / pepperoni;
3. fish / caesar;
4. shellfish / scallop;
5. alcohol / vanilla extract;
6. fish / vegetarian fishcake;
7. poultry / chicken of the woods.

No contested case entered a blocking calculation.

## Out of scope — imagery lookup

The founder reported a separate IMG-workstream issue: `foods.json` and
`frame_map.json` each contain 12,601 entries, but only 11,578 names match after
sanitizing `/` and `%` to `_`, leaving about 1,023 archived images unreachable
by the app lookup. MP-7 did not inspect, modify, or attempt to fix the imagery
pipeline.
