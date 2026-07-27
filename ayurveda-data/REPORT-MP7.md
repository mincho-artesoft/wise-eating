# MP-7 — Culinary plausibility

Date: 2026-07-27

Branch: `ayurveda-app`

Status: **STOPPED at MP7-G7 — real-catalogue seven-day solve exceeds 150 ms**

## Outcome

Rev9 fixes the concentrated-milk eligibility defect found by the rev8 forward
census. The build-time resolver now applies the director-authored contiguous
phrases and prepared/negated evaluation, the runtime cache is version 9, and
the shipped role artifact is deterministic.

The founder-authorized G4 harness repair adds `.ingredientOnly` with the same
ineligible zero-portion shape as `.nonFood`. A new conformance test compares
all 15 harness roles and every required field against the shipped role
definitions, preventing another silent drift.

G4 is green at 150/150. G5 produces plans for all 30 real-catalogue
profile/horizon combinations, and G6 records a +1.5507 mean dosha-pacification
delta. G7 fails its first absolute arm: optimized seven-day solves over the
real 13,993-candidate input take 1.138–3.998 seconds, exceeding the 150 ms
ceiling. Work stopped without narrowing the pool or changing solver behavior.

| Gate | Actual | State |
|---|---:|---|
| G0 known-bad meals detected | **21/21** | pass |
| Role training fixtures | **71/71** | pass |
| G1 `other` coverage | **8/589 (1.358%)** | pass |
| G1b unmapped category rows | **0/12,601** | pass |
| G2c forward | **0/543 wrong** | pass |
| G2c reverse | **0/303 wrong** | pass |
| G2b authored-recipe sample | **39/40 (97.5%)** | retained; recipe mapping unchanged |
| G2 random holdout | seed 2026072704 is burned | no fourth sample drawn |
| G3 accepted independent cross-derivation | **4/4 reference populations exact** | retained |
| G4 full regression | **150/150** | pass |
| G5 real-catalogue feasibility | **30/30 plans** | pass |
| G6 Y1 mean delta | **+1.5507** | pass |
| G7 seven-day solve | **3,998.172 ms max** | **STOP — ceiling 150 ms** |
| G7 role/launch/memory arms | not run | stopped after first arm |
| G8 tracked-file gate | not run | stopped before gate |

## Commit and push ledger

| Work | Commit | State |
|---|---|---|
| Rev9 director rule, unmodified | `42281ac` | pushed |
| Rev9 projection, prepared-aware matching, tests, and deterministic cache | `a7e67b4` | pushed |
| G4 harness repair and shipped-role conformance test | `e98caf6` | pushed |
| Real-catalogue G5–G7 measurement harness | `d0c27fa` | pushed |
| This stop report | report commit | committed and pushed after stop |

Artifact SHA-256:

- `food-roles.json`: `0a9c19b1ed90bcf1a9cdc126b336afc7a6be6c958b1f8e72dab503973f987cac`
- `food-role-goldens.json`: `5dae3f4ff44ee904b38dbb207c6a2affa3fbfaaa6ea8b02f62b4765915b337f2`
- `food_roles.json.gz`: `ae131af1425b5ef8815dfe1b2398a7e3e0f57a270d66789e5fd170af5f2cce82`

## Rev9 implementation

`X-CONCENTRATED-MILK` no longer has positive `tokenGroups`. It uses contiguous
phrases plus the same prepared-indicator shape used by `X-DRY-MIX`:

1. a contiguous positive phrase must match;
2. `not reconstituted` preserves the positive result; and
3. any other prepared indicator suppresses the result.

The build-time matcher previously applied step 3 only when a token group
matched. It now applies the prepared/negated evaluation when either a
contiguous phrase or a legacy group matches. No other matching weight,
priority, scope, or role assignment changed.

The plain catalogue matches every rev9 reference:

| Metric | Actual |
|---|---:|
| `X-CONCENTRATED-MILK` fires | **17** |
| `other` | **108/12,601 (0.86%)** |
| ineligible | **543** |
| `infantProduct` | **322** |
| `ingredientOnly` | **171** |
| `nonFood` | **30** |
| `supplement` | **20** |
| `notReadyToEat` | **304 (2.41%)** |

Recipe references remain exact:

| Metric | Actual |
|---|---:|
| Recipes on an anchor role | **1,039/1,500** |
| Recipes in a prohibited role | **0/1,500** |

The focused MP-7 rerun is **22/22 green**: 16 role tests plus six C1–C10
validity tests. It includes deterministic artifact equality, all 71 role
fixtures, the five must-remain-eligible controls, the four must-be-ineligible
controls, and the retained rev8 corn/nut/egg-roll corrections.

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

All **71/71** director cases match with zero deviations. They remain a
training/self-consistency corpus and are not reported as a held-out score.

### G1 and G1b

G1 seed: **20260727**.

The proportional 500-row sample contains 13 classical, 78 derived, and 409
estimated rows. Unioning it with all 91 distinct food IDs selected by the
accepted MP-6b plan produces 589 unique rows.

| Metric | Actual | Gate |
|---|---:|---:|
| Rows resolving `other` | **8/589 (1.358%)** | ≤10% |
| Live category values mapped | **187/187** | — |
| Unmapped category rows | **0/12,601** | ≤2% |

The eight `other` rows are IDs 5222, 5240, 5577, 5580, 6463, 6469, 7202, and
12052.

### G2c forward — 0/543 wrong

The 543-row population is:

| Role | Rows |
|---|---:|
| `infantProduct` | **322** |
| `ingredientOnly` | **171** |
| `nonFood` | **30** |
| `supplement` | **20** |
| **Total** | **543** |

The accepted 526-row rev7 population is an exact subset of rev9. Rev9 adds 17
rows and removes none. All 17 additions are genuine concentrated, dried, or
dehydrated ingredients:

| Food ID | Catalogue name |
|---:|---|
| 15 | Milk, evaporated, NS as to fat content |
| 16 | Milk, evaporated, whole |
| 17 | Milk, evaporated, reduced fat (2%) |
| 18 | Milk, evaporated, fat free (skim) |
| 19 | Milk, condensed, sweetened |
| 147 | Milk, dry, not reconstituted |
| 7426 | Potatoes, mashed, dehydrated, granules without milk, dry form |
| 7428 | Potatoes, mashed, dehydrated, granules with milk, dry form |
| 7762 | Potatoes, mashed, dehydrated, flakes without milk, dry form |
| 8109 | Milk, dry, whole, with added vitamin D |
| 8110 | Milk, dry, nonfat, regular, without added vitamin A and vitamin D |
| 8469 | Milk, dry, nonfat, instant, with added vitamin A and vitamin D |
| 8470 | Milk, dry, nonfat, calcium reduced |
| 8494 | Milk, evaporated, 2% fat, with added vitamin A and vitamin D |
| 9246 | Milk, dry, nonfat, regular, with added vitamin A and vitamin D |
| 9247 | Milk, dry, nonfat, instant, without added vitamin A and vitamin D |
| 10295 | Milk, dry, whole, without added vitamin D |

Forward-set fingerprint:
`aa9aaf7e693ba95b2d99003b1be2592a20ca0f20cab0605ba9f61595f9e17ea7`.

### G2c reverse — 0/303 wrong

The marker-bearing, role-eligible, ready population is the exact same 303-row
set reviewed under rev7: no additions and no removals. Its accepted
adjudication therefore remains **0/303 wrong**.

Reverse-set fingerprint:
`9a031678b409fe629757f7b93865c2450533694784523f917e8ac43ab2c70137`.

The five must-remain-eligible rev9 controls all pass:

1. Puddings, vanilla, dry mix, instant, prepared with whole milk.
2. Hot chocolate / cocoa, dry mix, made with whole or reduced fat (2%) milk.
3. Bread, white, prepared from recipe, made with nonfat dry milk.
4. Milk, dry, reconstituted, whole.
5. Potatoes, au gratin, dry mix, prepared with water, whole milk and butter.

The four must-be-ineligible controls also pass:

1. Milk, evaporated, 2% fat, with added vitamin A and vitamin D.
2. Milk, condensed, sweetened.
3. Milk, dry, whole, with added vitamin D.
4. Milk, dry, not reconstituted.

### G2b, G2, and G3

Rev9 does not alter recipe post-pass mapping. The frozen G2b result remains
**39/40 (97.5%)**, with 1,039 anchor recipes and zero prohibited recipes.

The seed-2026072704 random sample is burned by rev8 and was not rescored or
quoted as a holdout. Per director instruction, no fourth random sample was
drawn.

The director-accepted G3 cross-derivation remains exact on all four reference
populations: catalogue `other`, recipe anchors, prohibited recipe roles, and
the 71 training fixtures.

## G4 — full regression

Command:

```text
python3 -m unittest discover -s ayurveda-data/tests -p 'test_*.py' -v
```

Result:

```text
Ran 150 tests in 345.081s
OK
```

The original G4 compilation error was corrected exactly as authorized:

- `.ingredientOnly` is non-anchor, `maxPerMeal = 0`,
  `eligibleAsComponent = false`, and has a `0...0 g` range;
- the harness exports its entire role table;
- the Python conformance test loads `food_roles.json.gz`;
- all 15 role IDs must be present in both sources; and
- `anchor`, `maxPerMeal`, `eligibleAsComponent`, and portion minimum/maximum
  must match for every role.

G4 evidence:

| Regression arm | Actual |
|---|---:|
| Full Python suite | **150/150** |
| MP-5 hard properties | **30/30** |
| MP-5 soft properties measured | **16/16** |
| MP-7 C1–C10 fixture gate | **21/21 known-bad detected** |
| Role table conformance | **15/15 roles exact** |
| Resolution training / holdout | **59/59 · 44/48** |
| Search goldens | **25/25 legacy + 2/2 safety** |
| Exclusion corpus | **117 cases intact; zero blocking negative-boundary failures** |
| Narration determinism | **100/100 byte-identical** |
| End-to-end model calls | **2** |
| Fresh install | **zero insert / no rebuild tests green** |

## G5 — real-catalogue feasibility

Measurement input:

- 13,993 nutrient-usable real catalogue candidates;
- 13,460 marked role-eligible;
- 533 marked role-ineligible within this nutrient-usable subset;
- 332 marked `notReadyToEat` within this subset;
- all ten director profiles;
- horizons 1, 3, and 7 days; and
- deterministic seed `0x4D503700`.

All **30/30** combinations produce a complete plan. No constraint was relaxed
and no binding failure occurred.

| Profile | 1-day | 3-day | 7-day | Daily kcal |
|---|---:|---:|---:|---:|
| P1 | 1,152.053 ms | 2,110.370 ms | 3,919.314 ms | **2,000 exact** |
| P2 | 416.504 ms | 707.613 ms | 1,341.298 ms | **2,000 exact** |
| P3 | 782.523 ms | 1,337.488 ms | 2,644.832 ms | **2,200 exact** |
| P4 | 1,359.626 ms | 2,214.462 ms | 3,968.620 ms | **2,400 exact** |
| P5 | 777.706 ms | 1,281.276 ms | 2,410.192 ms | **1,700 exact** |
| P6 | 686.405 ms | 1,221.064 ms | 2,298.829 ms | **2,000 exact** |
| P7 | 1,065.785 ms | 2,010.636 ms | 3,850.896 ms | **1,200 exact** |
| P8 | 1,201.127 ms | 2,104.097 ms | 3,998.172 ms | **3,600 exact** |
| P9 | 756.098 ms | 1,272.910 ms | 2,392.834 ms | **1,900 exact** |
| P10 | 336.513 ms | 602.122 ms | 1,138.039 ms | **2,000 exact** |

P7 and P8 remain reachable at all three horizons despite anchor requirements,
per-role clamps, 543 ineligible catalogue rows, and 304 catalogue
`notReadyToEat` rows.

## G6 — Y1 survives

TASK-MP7 §6 was reread before evaluating this result. The C3 seasoning cap was
not changed.

The production-sized seven-day comparison uses the same candidates, seed, and
profile in each pair; only Ayurvedic scoring is disabled in the cleared arm.

| Profile | Imbalanced scoring | Cleared scoring | Pacification delta |
|---|---:|---:|---:|
| P3 — Vata | −1.650794 | −0.017391 | **+1.633402** |
| P4 — Pitta | −1.352381 | +0.288136 | **+1.640517** |
| P5 — Kapha | −1.495868 | −0.117647 | **+1.378221** |
| **Mean** | **−1.499681** | **+0.051032** | **+1.550713** |

The +1.5507 mean is above the +0.30 gate and does not show the spice-cap
collapse described in §6. It is reported as measured; no parameter was tuned
to protect it.

## G7 — blocking real-catalogue solve latency

Method:

- `swiftc -O`;
- production `DeterministicMealPlanSolver`;
- one decoded 13,993-candidate input;
- one reused solver instance;
- ten seven-day runs, one per director profile;
- `localSearchIterations = 96`; and
- monotonic time around `solve`.

| N | Median | Min | Max | Ceiling |
|---:|---:|---:|---:|---:|
| 10 | **2,527.512 ms** | 1,138.039 ms | **3,998.172 ms** | **150 ms** |

Every measured seven-day solve exceeds the ceiling. The maximum is 26.65× the
budget. This is not startup compilation or candidate decoding: timing starts
immediately before the already-constructed solver's `solve` call, and the
solver instance is reused across all 30 G5 runs.

Per the standing stop rule, no solver optimization, pool reduction, iteration
reduction, cache, or constraint relaxation was attempted.

The remaining G7 arms were not run:

- full-catalogue role resolution cold/cached;
- device cold-launch ABAB; and
- device peak-memory ABAB.

No simulator number was substituted for the required device launch/memory
measurements. G8 was not run after the G7 stop.

The handbook and progress milestone are not advanced while MP-7 is stopped.

## Burned regression fixtures

The three general role samples remain regression fixtures only:

- seed 20260727 — 60 rows;
- seed 2026072702 — 100 rows;
- seed 2026072704 — 100 rows, burned by rev8.

None is quoted as a fresh held-out score.

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

The founder recorded a separate IMG-workstream issue: `foods.json` and
`frame_map.json` each contain 12,601 entries, but only 11,578 names match after
sanitizing `/` and `%` to `_`, leaving about 1,023 archived images unreachable
by the app lookup. MP-7 did not inspect, modify, or attempt to fix the imagery
pipeline.
