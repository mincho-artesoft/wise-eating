# MP-7 — Culinary plausibility

Date: 2026-07-27

Branch: `ayurveda-app`

Status: **STOPPED at MP7-G2c forward: 23/566 false ineligible rows; gate is at most 10**

## Outcome

Rev8 reproduces every director reference total, and the rule-training fixtures
remain exact. The enlarged forward eligibility census nevertheless exposes a
blocking over-capture in `X-CONCENTRATED-MILK`: its unordered whole-name token
groups classify 23 ready-to-eat foods as `ingredientOnly`.

The ordered gates reached this result:

| Gate | Actual | State |
|---|---:|---|
| G0 known-bad meals detected | **21/21** | pass |
| Role training fixtures | **71/71** | pass |
| G1 `other` coverage | **8/589 (1.358%)** | pass |
| G1b unmapped category rows | **0/12,601** | pass |
| G2c forward | **23/566 wrong** | **STOP** |
| G2c reverse | not run | stopped before gate |
| G2b authored-recipe sample | **39/40 (97.5%)** | retained; recipe mapping unchanged |
| G2 random holdout | seed 2026072704 is burned | no fourth sample drawn |
| G3 accepted independent cross-derivation | **4/4 reference populations exact** | retained |
| G4–G8 | not run | stopped before gates |

No director rule, expected label, threshold, match scope, or veto was changed
after this finding. In particular, the 60-band was not scoped to the first
comma segment, and no proxy signal was introduced.

## Commit and push ledger

| Work | Commit | State |
|---|---|---|
| Rev8 director artifacts, unmodified | `c3d0352` | pushed |
| Rev8 projection, runtime binding, cache, and burned-fixture marker | `30e9d79` | pushed |
| This stop report | report commit | committed and pushed after stop |

Artifact SHA-256:

- `food-roles.json`: `5206ff364a02b81cd597c7a226539116b27450992465b5349c87960ef9981cc0`
- `food-role-goldens.json`: `5dae3f4ff44ee904b38dbb207c6a2affa3fbfaaa6ea8b02f62b4765915b337f2`
- `food_roles.json.gz`: `d6c6125f5dc69ee6676bd6a164cee97ae5b60420693421ee04e5f2056d9b7037`
- burned seed-2026072704 fixture: `bbb5251643eacfa7067708b2781093b43628e4195c2f178ee8f3414bfc8724e7`

## Rev8 projection

The build-time and runtime readers are bound to `rolesVersion: 8` and 34
rules. The deterministic artifact contains all 14,484 canonical rows.

The plain USDA catalogue matches the supplied reference exactly:

| Metric | Actual |
|---|---:|
| `other` | **109/12,601 (0.87%)** |
| ineligible | **566** |
| `infantProduct` | **322** |
| `ingredientOnly` | **194** |
| `nonFood` | **30** |
| `supplement` | **20** |
| `notReadyToEat` | **304 (2.41%)** |

Recipe references also remain exact:

| Metric | Actual |
|---|---:|
| Recipes on an anchor role | **1,039/1,500** |
| Recipes in a prohibited role | **0/1,500** |

This retains the director-accepted G3 cross-derivation result: the independent
director derivation and the repo projection agree exactly on catalogue
`other`, recipe anchors, prohibited recipe roles, and the 71 training
fixtures. No new 100-row disagreement sample was started at rev8 because the
ordered run stopped at forward G2c.

Focused MP-7 tests are **21/21 green**. They cover G0, all role fixtures, the
reference populations, the rev8 corn/egg-roll/staple/concentrated-milk cases,
the 304-row readiness partition, runtime metadata, and deterministic artifact
encoding.

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

All **71/71** director cases match with zero deviations. The rev3 correction
for `Milk, dry, whole` resolves to `ingredientOnly`. These cases remain a
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

### G2c forward — blocking failure

Rev8 increases the forward population from 526 to 566:

| Role | Rows |
|---|---:|
| `infantProduct` | **322** |
| `ingredientOnly` | **194** |
| `nonFood` | **30** |
| `supplement` | **20** |
| **Total** | **566** |

All 40 newly ineligible rows are produced by `X-CONCENTRATED-MILK`. Manual
review finds 17 genuine concentrated or dry-milk ingredients and **23 false
ineligible prepared foods**.

The 23 false rows are:

| Food ID | Catalogue name | Why it is ready food |
|---:|---|---|
| 13 | Milk, dry, reconstituted, nonfat | reconstituted milk |
| 14 | Milk, dry, reconstituted, whole | reconstituted milk |
| 99 | Hot chocolate / cocoa, dry mix, made with whole or reduced fat (2%) milk | prepared beverage |
| 104 | Hot chocolate / cocoa, dry mix, reduced sugar, made with whole or reduced fat (2%) milk | prepared beverage |
| 6287 | Egg custards, dry mix, prepared with whole milk | prepared custard |
| 6297 | Puddings, vanilla, dry mix, instant, prepared with whole milk | prepared pudding |
| 6305 | Rennin, vanilla, dry mix, prepared with whole milk | prepared dessert |
| 6308 | Flan, caramel custard, dry mix, prepared with whole milk | prepared flan |
| 6326 | Puddings, banana, dry mix, regular, prepared with whole milk | prepared pudding |
| 6328 | Puddings, coconut cream, dry mix, instant, prepared with whole milk | prepared pudding |
| 6330 | Puddings, coconut cream, dry mix, regular, prepared with whole milk | prepared pudding |
| 6331 | Puddings, lemon, dry mix, instant, prepared with whole milk | prepared pudding |
| 7044 | Puddings, chocolate, dry mix, instant, prepared with whole milk | prepared pudding |
| 7048 | Puddings, chocolate, dry mix, regular, prepared with whole milk | prepared pudding |
| 7049 | Puddings, rice, dry mix, prepared with whole milk | prepared pudding |
| 7051 | Puddings, tapioca, dry mix, prepared with whole milk | prepared pudding |
| 7054 | Puddings, vanilla, dry mix, regular, prepared with whole milk | prepared pudding |
| 7061 | Rennin, chocolate, dry mix, prepared with whole milk | prepared dessert |
| 7079 | Puddings, banana, dry mix, instant, prepared with whole milk | prepared pudding |
| 7765 | Potatoes, au gratin, dry mix, prepared with water, whole milk and butter | prepared side |
| 7767 | Potatoes, scalloped, dry mix, prepared with water, whole milk and butter | prepared side |
| 8099 | Dessert topping, powdered, 1.5 ounce prepared with 1/2 cup milk | prepared topping |
| 11540 | Bread, white, prepared from recipe, made with nonfat dry milk | prepared bread |

The 17 genuine new ingredient rows are IDs 15–19, 8109–8111, 8469, 8470,
8472, 8473, 8494, 9245–9247, and 10295.

#### Cause

`X-CONCENTRATED-MILK` uses eight `tokenGroups` at priority 93 with
`matchScope: wholeName`. Token-group semantics deliberately require each
authored token to occur somewhere in the scoped name; they do not require
adjacency or order. Consequently:

```text
["milk", "dry", "whole"]
```

matches both the intended `Milk, dry, whole` and unrelated finished products
whose full names contain separated words such as `dry mix ... prepared with
whole milk`. The same group also catches reconstituted milk. This is not a
counting discrepancy: the reference total of 566 is reproduced exactly, but
23 of its members violate the eligibility boundary.

The forward result is therefore **23/566 wrong**, above the gate ceiling of
10. Per the packet, work stopped immediately. The resolver was not patched
with ad-hoc vetoes, the director artifact was not edited, and the previously
rejected first-segment workaround was not reapplied.

### G2c reverse and later gates

The reverse census was **not run** because the forward direction already
failed a blocking gate. Rev8 does not alter recipe post-pass mapping, so the
frozen G2b result remains **39/40 (97.5%)**, with 1,039 anchor recipes and zero
prohibited recipes. The seed-2026072704 G2 sample is burned by rev8 and was not
rescored or quoted as a holdout; per director instruction, no fourth random
sample was drawn. G4, G5, G6, G7, and G8 were not run.

The handbook and progress milestone are not advanced while MP-7 is stopped.

## Burned regression fixtures

The three general role samples are now retained only as labelled regression
fixtures:

- seed 20260727 — 60 rows;
- seed 2026072702 — 100 rows;
- seed 2026072704 — 100 rows, burned by rev8.

None may be quoted as a fresh held-out score.

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
