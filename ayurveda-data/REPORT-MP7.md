# MP-7 — Culinary plausibility

Date: 2026-07-27

Branch: `ayurveda-app`

Current pushed tip: `810780e`

Status: **STOPPED at MP7-G2c: 1 reverse-direction readiness leak**

## Outcome

MP-7a rev6 is implemented and pushed. The build-time projection, immutable
runtime cache, solver eligibility check, narration fixture adapter, solver
harness, and C1–C10 checker now use `notReadyToEat`; no shipped artifact item
retains `requiresCooking`.

The implementation matches every numeric rev6 reference:

| Reference population | Actual |
|---|---:|
| Plain USDA catalogue | **12,601** |
| Plain `other` | **108 (0.857%)** |
| Ineligible plain rows | **526** |
| Ineligible breakdown | **322 infantProduct · 154 ingredientOnly · 30 nonFood · 20 supplement** |
| Plain `notReadyToEat` | **303 (2.405%)** |
| Authored recipes on an anchor role | **1,039/1,500** |
| Authored recipes in a prohibited role | **0/1,500** |
| Role training cases | **71/71, zero deviations** |

The ordered gates then reached G2c. The forward census is clean, but the
reverse census contains one row previously accepted by the director as a real
rev5 leak:

| Food ID | Name | Role | `notReadyToEat` | Finding |
|---:|---|---|---:|---|
| 5751 | Raspberry juice concentrate | beverage | false | Bare juice concentrate remains directly placeable |

The G2c reverse gate is zero, so execution stopped. No G2b sample and no third
random holdout were drawn. G4–G8 were not run.

## Commits and push state

| Work | Commit | State |
|---|---|---|
| Rev6 director artifacts, unmodified | `a506d0f` | pushed |
| MP-7a rev6 implementation and deterministic role cache | `810780e` | pushed |
| Burned fixtures and this stop report | report commit | committed after stop |

Director artifact SHA-256:

- `food-roles.json`: `72ecd3b4361cac894d107d860079b136105e6d9c638006eb6d1ad5aef9dd628b`
- shipped `food_roles.json.gz`: `928503024ed36f88ed7d2fa7d54d15e974154c53d455b2ab8f707695b1e8e9ed`

## MP-7a rev6 implementation

The readiness evaluator follows the authored order exactly:

1. `unprepared`, qualifying `uncooked`, and explicit unreconstituted markers
   win even when the same name contains a preparation word.
2. Otherwise, a contiguous prepared indicator makes the row ready.
3. Only then do concentrate, dough, ready-to-bake/fry, commodity-flour, and
   dry-pulse/grain structural triggers run.

The original `dryPulseRule` remains intact. It uniquely contributes 89 plain
rows. `ready-to-heat` was not added as a trigger.

| Trigger | Plain rows |
|---|---:|
| unprepared | **87** |
| dry-pulse-or-grain | **89** |
| commodity-flour | **58** |
| unreconstituted | **26** |
| uncooked | **12** |
| dough | **11** |
| ready-to-bake | **10** |
| concentrate | **10** |
| **Total** | **303** |

The descriptive `measured` block inside the unedited director JSON still says
301 total and 87 dry-pulse rows. The dispatch reference, director Python
resolver, shipping derivation, and live catalogue all agree on **303 / 89**.
This is recorded as stale descriptive metadata; it was not edited.

Focused Python tests: **17/17 green**. They include explicit precedence for
“Sweet Potatoes, french fried, crosscut, frozen, unprepared,” preparation
suppression for made-from-dry-mix rows, dried-fruit and sourdough vetoes,
commodity flour, raw lentils, and the deliberate non-trigger
“Pasta with tomato-based sauce, ready-to-heat.”

The legacy rev2 flag fixture is named `requiresCookingCases` and predates the
generalized semantics. It has one intentional migration delta:
“Chickpea flour (besan)” was false under the narrow cooking flag and is true
under rev6 `notReadyToEat`. This is not included in the 71 role-training
zero-deviation statement.

## Ordered gate evidence

### G0 — known-bad MP-6b plan

| Required finding | Actual |
|---|---:|
| Meals failing at least one hard plausibility property | **21/21** |
| Named infant-formula meals fail C1 | **3/3** |
| Four-chocolate-drink breakfast fails C6 | **yes** |
| Six-herb dinner fails C2 and C3 | **yes / yes** |
| Named raw mung/lentil meals fail C5 | **3/3** |

### Fixtures — training/self-consistency only

All **71/71** role cases match with zero deviations. This is a training corpus,
not a score.

### G1 — role coverage

Fixed seed: **20260727**.

The 500-row proportional sample contains 13 classical, 78 derived, and 409
estimated rows. It was unioned with the 91 distinct food IDs in the real MP-6b
sample; two overlapped, producing 589 unique rows.

| Metric | Actual | Gate |
|---|---:|---:|
| Rows resolving `other` | **7/589 (1.188%)** | ≤10% |

The seven IDs were 5222, 5577, 5580, 6463, 6469, 7202, and 12052.

### G1b — category coverage

All **187/187** live `FoodItem.category[0]` values are present in the combined
sensitive/fine/coarse category maps. Unmapped rows: **0/12,601 (0%)**.

### G2c — exhaustive eligibility census

The marker matcher uses the same normalization, contiguous phrase matching,
plural tolerance, and token boundaries as the shipping resolver.

| Direction | Population | Wrong | Gate |
|---|---:|---:|---:|
| Forward: role is ineligible | **526** | **0** | ≤10 |
| Reverse: marker-bearing, role-eligible, and ready | **303** | **1** | **0 — STOP** |

Forward is a strict subset of the previously reviewed rev5 population: rev6
adds no new ineligible ID and removes nine. The four known false positives
(1631, 2144, 2145, 2310) are fixed; the other five removed rows are prepared
pie-crust products. The remaining 526 retain their prior genuine-ineligible
adjudications.

For the reverse direction, all 126 IDs adjudicated as genuine rev5 leaks were
compared directly with the rev6 artifact. **125/126** now carry
`notReadyToEat`; **1/126** does not:

```text
5751 | Raspberry juice concentrate | beverage | notReadyToEat=false
```

The exact cause is structural. Its normalized tokens are
`raspberry juice concentrate`. It has none of the explicit-unready markers.
The authored concentrate groups are only `frozen+concentrate`,
`dry+concentrate`, and `protein+concentrate`, so no group matches. It also
matches no other structural trigger. Both the director reference function
`not_ready_to_eat` and the shipping build return no trigger.

No rule was broadened after observing this result. The director must author
the intended membership path; adding `juice` as an executor proxy would repeat
the signal-substitution failure this packet explicitly forbids.

## Gates not run after stop

| Gate | State |
|---|---|
| G2b — 40 hand-labelled recipes | **NOT RUN** |
| G2 — third 100-row holdout | **NOT DRAWN** |
| G3 cross-derivation review | Prior exact reference match retained; no new review started |
| G4 full regression | **NOT RUN** |
| G5 30-solve feasibility | **NOT RUN** |
| G6 Y1 before/after | **NOT RUN** |
| G7 solve/role/launch/memory | **NOT RUN** |
| G8 tracked-file size | **NOT RUN** |

The third holdout remains uncreated, as required.

## Burned fixtures

Both prior samples are committed solely as regression fixtures and are marked
in-file as burned training data:

- `food-role-burned-regression-seed-20260727.json` — 60 cases.
- `food-role-burned-regression-seed-2026072702.json` — 100 cases.

Neither result is quoted as a held-out score.

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
