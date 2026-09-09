# MP-7 — Culinary plausibility

Date: 2026-07-27

Branch: `ayurveda-app`

Status: **COMPLETE — real-catalogue solver profiled and optimized without output change**

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
delta.

The original G7 stop captured the first honest real-catalogue timing:
1.138–3.998 seconds. The founder withdrew the synthetic-harness 150 ms ceiling
and authorized profile-first, behavior-preserving work only. The profile
disproves the proposed 28-million-evaluation shape: eligibility already ran
once and the 96-iteration local search scanned 1.266 million rows. Repeated
greedy scoring and four full sorts of value-heavy candidates were dominant.

Compact ranking records, role buckets, precomputed immutable lookup state, and
per-iteration viruddha context reduce the final seven-day median to
**641.588 ms** and maximum to **959.744 ms**. All 30 canonical plan hashes are
identical to the frozen pre-change capture, P7/P8 remain exact at 1,200/3,600
kcal, Y1 remains +1.5507, and narration remains byte-identical over 100 runs.
No iteration count, pool size, candidate set, constraint, weight, random draw,
or comparator changed.

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
| G7 profiled seven-day solve | P8 **4,055.677 ms** before | finding |
| G7 optimized seven-day solve | median **641.588 ms**, max **959.744 ms** | measured; new ceiling pending founder ruling |
| G7 full role resolution | **44.735 ms cold / 1.086 ms cached** | pass |
| G7 device cold launch | **1.090 s median**, N=10 | pass |
| G7 device peak memory | **402.6 MiB median**, +10.3 MiB paired vs rev1 | pass |
| G8 largest tracked file | **82,726,160 bytes** | pass |

## Commit and push ledger

| Work | Commit | State |
|---|---|---|
| Rev9 director rule, unmodified | `bc6e346` | pushed |
| Rev9 projection, prepared-aware matching, tests, and deterministic cache | `c046559` | pushed |
| G4 harness repair and shipped-role conformance test | `6a12a9a` | pushed |
| Real-catalogue G5–G7 measurement harness | `b0d3245` | pushed |
| Initial real-catalogue G7 stop report | `0e9c502` | pushed |
| Behavior-preserving G7 optimization and measurement harnesses | `9330cac` | pushed |
| Final report and registries | report commit | committed and pushed after all gates |

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

Final post-optimization result:

```text
Ran 150 tests in 209.925s
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
| P1 | 283.749 ms | 510.009 ms | 949.959 ms | **2,000 exact** |
| P2 | 99.221 ms | 180.883 ms | 350.194 ms | **2,000 exact** |
| P3 | 186.745 ms | 328.005 ms | 664.789 ms | **2,200 exact** |
| P4 | 284.802 ms | 501.065 ms | 958.718 ms | **2,400 exact** |
| P5 | 184.135 ms | 332.293 ms | 618.388 ms | **1,700 exact** |
| P6 | 163.478 ms | 287.134 ms | 547.340 ms | **2,000 exact** |
| P7 | 286.638 ms | 502.006 ms | 927.294 ms | **1,200 exact** |
| P8 | 287.326 ms | 496.204 ms | 959.744 ms | **3,600 exact** |
| P9 | 180.829 ms | 328.503 ms | 614.552 ms | **1,900 exact** |
| P10 | 79.076 ms | 145.720 ms | 314.421 ms | **2,000 exact** |

P7 and P8 remain reachable at all three horizons despite anchor requirements,
per-role clamps, 543 ineligible catalogue rows, and 304 catalogue
`notReadyToEat` rows.

The ordered 30-plan canonical-hash ledger is identical before and after the
G7 optimization. Its SHA-256 is
`542c8524e27fddd3322cf694ebc0cb08a4194bfb6cf9fe3b291718b355282de0`.
The P8 seven-day plan remains
`e9e623f8944d368ea5ec0bb50e9cc47ebf5f76795886e765f6b259f23bca5aea`.

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

## G7 — real-catalogue profile and behavior-preserving optimization

### Method and frozen behavior

- `swiftc -O`;
- production `DeterministicMealPlanSolver`;
- 13,993 nutrient-usable candidates from shipped `foods.json`,
  `ayurveda_seed.json.gz`, `food_concepts.json.gz`, and
  `food_roles.json.gz`;
- one decoded input and one reused solver instance;
- deterministic seed `0x4D503700`;
- `localSearchIterations = 96` before and after; and
- monotonic time immediately around `solve`, excluding candidate decoding and
  compilation.

Before modifying the solver, the harness captured all 30 canonical plan
hashes. The optimization was accepted only after every hash matched. It does
not reduce local-search iterations, cap or sample candidates, relax a
constraint, alter any score/weight, or change RNG consumption.

### Before profile — P8 seven-day real catalogue

The profile accounts for the complete **4,055.677 ms** solve. Child rows are
subphases and therefore are not added again to their parent.

| Phase | Time | Calls / rows | Finding |
|---|---:|---:|---|
| Eligibility filter | **1.013 ms** | 13,993 scans | once per solve; 13,185 allowed |
| Per-meal recent/required pool filter | **15.831 ms** | 276,885 scans | 21 × 13,185; not safety eligibility |
| Greedy construction | **3,300.025 ms** | 21 slots | dominant |
| ↳ selection/dosha score | 1,207.664 ms | 1,381,972 calls | about 0.874 µs/call |
| ↳ four full candidate sorts | 1,713.661 ms | 5,524,360 input rows | copied/sorted value-heavy candidates |
| ↳ mode selection | 256.855 ms | — | repeated global traversal |
| Local search | **754.316 ms** | 96 iterations total | not 96 × 21 slots |
| ↳ replacement filtering | 704.698 ms | 1,265,760 scans | exactly 96 × 13,185 |
| ↳ role checks | 0.509 ms | 96 | metadata already on candidate |
| ↳ hard validation | 14.665 ms | 79 | complete-plan validation |
| ↳ objective | 6.392 ms | 79 | includes dosha objective |
| Portion fitting/clamping | 0.403 ms | 100 | about 4.03 µs/call |
| Near-duplicate test | 0.979 ms | 231 | about 4.24 µs/call |
| Final hard validation | 0.196 ms | 1 | — |

The proposed `21 × 96 × 13,993 ≈ 28M` explanation is **false for the
implemented algorithm**. Local search performs 96 iterations for the whole
plan, chooses one meal component per iteration, and scans 1.266 million
candidates. The seconds were instead dominated by greedy scoring and repeated
full sorting.

Role, `notReadyToEat`, and headword resolution were already build-time
metadata. `DeterministicMealPlanSolver+WiseEating` copies them into
`MP5Candidate` once; the inner loops do not call `FoodRoleResolver`.
Eligibility was already filtered once per solve. No repeated runtime role
derivation was found.

### Behavior-preserving changes

1. Precompute immutable near-duplicate keys and per-role maximums once in the
   solver.
2. Rank compact index/ID/role/number records instead of copying and sorting
   `MP5Candidate` values containing names and sets.
3. Reuse each candidate's density and base score across the four ordering
   modes for a given meal/count.
4. Bucket compact rankings by role. Anchor selection opens only anchor buckets;
   other selection performs a k-way comparison of the current head from each
   role bucket, preserving the exact former global comparator order.
5. Build the local-search “meal except the replaced component” and viruddha
   context once per iteration rather than inside every candidate predicate.

The compact role buckets do not restrict the candidate universe. They avoid
sorting and traversing irrelevant roles while preserving which candidate wins.

### After profile — same P8 plan

| Phase | Time | Calls / rows | Delta / finding |
|---|---:|---:|---|
| Complete solve | **928.726 ms** | — | **−77.1%; 4.37× faster** |
| Eligibility filter | 0.957 ms | 13,993 scans | still once |
| Per-meal pool filter | 15.063 ms | 276,885 scans | unchanged shape |
| Greedy construction | **727.788 ms** | 21 slots | −78.0% |
| ↳ selection/dosha score | 203.444 ms | 1,381,972 calls | same call count |
| ↳ compact role-bucket sorts | 422.238 ms | 5,524,360 input rows | rank 100.615; density 107.343; kcal ↓ 106.373; kcal ↑ 107.906 |
| ↳ actual candidate evaluations | — | 15,036 | 15,456 bucket-head scans |
| Local search | **199.627 ms** | 96 iterations | same iteration count |
| ↳ replacement filtering | 152.884 ms | 1,265,760 scans | same scan count |
| ↳ role checks | 0.486 ms | 96 | — |
| ↳ hard validation | 17.033 ms | 79 | — |
| ↳ objective | 6.181 ms | 79 | — |
| Portion fitting/clamping | 0.305 ms | 100 | same calls |
| Near-duplicate test | 0.859 ms | 231 | same calls |
| Final hard validation | 0.245 ms | 1 | — |

Across the ten final seven-day solves:

| N | Median | Min | Max |
|---:|---:|---:|---:|
| 10 | **641.588 ms** | **314.421 ms** | **959.744 ms** |

The withdrawn 150 ms number is not reused as a gate. This is the measured
real-catalogue baseline from which the founder can set the product ceiling.

### Role resolver, cold and cached

The performance harness loads the shipped gzip, decodes all 14,484 immutable
entries, resolves every food ID, then immediately repeats the same 14,484
lookups on the constructed cache.

| Catalogue rows | Cold load + full resolution | Cached full pass | Checksum |
|---:|---:|---:|---:|
| 14,484 | **44.735 ms** | **1.086 ms** | 3,850,755,146 |

This is below the 400 ms role-resolution ceiling and proves role/flag/headword
lookups are cached rather than recomputed during solver evaluation.

### Physical-device launch and peak memory

Device: iPhone 16 Pro, iOS 26.5. A = MP-6b/rev1 `6468169`; B = final optimized
working tree. Both are signed Release iPhoneOS builds. The same physical device,
bundle container, cable, and host session were used in strict ABAB order with a
discarded A warm-up.

The host was quiesced before the counted series: Xcode and Simulator were
closed; no Maestro, CI, `xcodebuild`, test runner, or active Spotlight indexing
workload was running. Codex desktop, a low-CPU Claude background process,
Finder, and normal system services remained. Each trace launched a new app
process with `-uiTestNoAds -we6LaunchProfile`. Launch is process start to the
app's `first-interactive-frame` signpost. Peak memory is the maximum physical
footprint sampled by Instruments Activity Monitor during the same five-second
trace. No simulator number is substituted.

| Pair | Rev1 launch ms | Optimized launch ms | Rev1 peak MiB | Optimized peak MiB |
|---:|---:|---:|---:|---:|
| 1 | 1,339.752 | 1,098.163 | 363.6 | 395.9 |
| 2 | 1,091.184 | 1,084.989 | 397.4 | 393.0 |
| 3 | 1,132.496 | 1,097.352 | 374.1 | 393.7 |
| 4 | 1,086.862 | 1,098.710 | 396.7 | 401.5 |
| 5 | 1,123.000 | 1,093.793 | 390.7 | 439.8 |
| 6 | 1,107.736 | 1,083.681 | 393.2 | 405.1 |
| 7 | 1,091.923 | 1,095.117 | 399.0 | 407.7 |
| 8 | 1,081.970 | 1,082.933 | 406.0 | 403.6 |
| 9 | 1,105.524 | 1,083.226 | 392.1 | 394.0 |
| 10 | 1,089.966 | 1,085.295 | 399.8 | 421.4 |

| Metric | Rev1 A | Optimized B | Paired B−A |
|---|---:|---:|---:|
| Launch median | 1,098.724 ms | **1,089.544 ms** | **−14.247 ms** |
| Launch IQR | 28.913 ms | 12.785 ms | 27.474 ms |
| Launch min / max | 1,081.970 / 1,339.752 ms | **1,082.933 / 1,098.710 ms** | −241.589 / +11.848 ms |
| Launch sample stddev | 77.192 ms | 6.824 ms | 74.304 ms |
| Peak-memory median | 394.978 MiB | **402.556 MiB** | **+10.281 MiB** |
| Peak-memory IQR | 7.570 MiB | 12.578 MiB | 18.512 MiB |
| Peak-memory min / max | 363.595 / 405.954 MiB | 393.001 / 439.829 MiB | −4.406 / +49.172 MiB |
| Peak-memory sample stddev | 12.830 MiB | 14.826 MiB | 16.770 MiB |

B's 1.090 s launch median and 1.099 s maximum are under the absolute 1.700 s
ceiling. Its paired median memory increase is 10.3 MiB and worst paired
increase is 49.2 MiB, both below the allowed rev1 +90 MiB.

### Post-optimization regression and G8

- full suite: **150/150**, 209.925 seconds;
- all 30 plan hashes unchanged, P7/P8 exact, Y1 +1.550713;
- narration template: **100/100 byte-identical**;
- total model calls: **2**;
- universal arm64+x86_64 simulator Debug and optimized Release:
  **BUILD SUCCEEDED**; no warning originates in an MP-7 changed file;
- fresh install: zero Ayurveda inserts and no search rebuild (suite green);
- largest git-tracked file:
  `WiseEating/Food/food_archive_480.mp4` at **82,726,160 bytes**;
- tracked files at or above 90,000,000 bytes: **0**.

The gitignored 285 MB `food_archive_1024.mp4` was not moved, changed, or added.

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
