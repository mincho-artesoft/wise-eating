# R3 Recipe Authoring Report

## Batches completed

Completed batches r19-r30 with 50 recipes in every batch:

- r19: regional South Indian mains
- r20: regional North, West, and East Indian mains
- r21: festival and vrat foods
- r22: 25 vata-pacifying and 25 pitta-pacifying complete meals
- r23: 25 kapha-pacifying and 25 tridoshic complete meals
- r24: ritu-specific seasonal menus across all six seasons
- r25: convalescent and light meals
- r26: 30-minute one-pot and weeknight dinners
- r27: raw and summer preparations with explicit vata cautions
- r28: Indian and international breads and flatbreads
- r29: chutneys, raitas, pickles, and spice blends
- r30: seasonal sherbets, dosha teas, warm tonics, and plant-milk drinks

Total authored: **600 recipes**. The complete r01-r30 collection contains 1,500 unique recipe IDs and 1,500 unique recipe names. Every R3 batch has `qualityState: "aiDraft"` and uses only the permitted `everyday` and `international` categories.

## Validation output

Each batch was validated cumulatively against the rebuilt `/tmp/pre` store before its isolated commit.

```text
r19
Checked 210 dravyas, 950 recipes
All checks passed.

r20
Checked 210 dravyas, 1000 recipes
All checks passed.

r21
Checked 210 dravyas, 1050 recipes
All checks passed.

r22
Checked 210 dravyas, 1100 recipes
All checks passed.

r23
Checked 210 dravyas, 1150 recipes
All checks passed.

r24
Checked 210 dravyas, 1200 recipes
All checks passed.

r25
Checked 210 dravyas, 1250 recipes
All checks passed.

r26
Checked 210 dravyas, 1300 recipes
All checks passed.

r27
Checked 210 dravyas, 1350 recipes
All checks passed.

r28
Checked 210 dravyas, 1400 recipes
All checks passed.

r29
Checked 210 dravyas, 1450 recipes
All checks passed.

r30
Checked 210 dravyas, 1500 recipes
All checks passed.
```

Final cumulative validation after the R3-wide writing audit and correction:

```text
Checked 210 dravyas, 1500 recipes
All checks passed.
```

## Dravya-link coverage and viruddha flags

The link percentage is the number of ingredients carrying a valid `dravyaId` divided by all ingredients in the batch. The only FDC-linked R3 ingredients are store-validated water (`10444`), dry tapioca pearls (`7138`), and dry rice noodles (`7163`). No dravya IDs or FDC IDs were invented.

| Batch | Dravya-linked ingredients | Total ingredients | Link percentage | Viruddha-flagged recipes |
| --- | ---: | ---: | ---: | ---: |
| r19 | 412 | 451 | 91.4% | 0 |
| r20 | 379 | 426 | 89.0% | 1 |
| r21 | 275 | 310 | 88.7% | 0 |
| r22 | 312 | 364 | 85.7% | 0 |
| r23 | 326 | 376 | 86.7% | 0 |
| r24 | 314 | 364 | 86.3% | 0 |
| r25 | 240 | 290 | 82.8% | 0 |
| r26 | 300 | 350 | 85.7% | 0 |
| r27 | 330 | 330 | 100.0% | 0 |
| r28 | 242 | 292 | 82.9% | 0 |
| r29 | 244 | 244 | 100.0% | 0 |
| r30 | 182 | 232 | 78.4% | 0 |

Total viruddha-flagged recipes: **1**. `Punjabi Urad Rajma Makhani` in r20 flags its tomato-and-cream combination and supplies a clearly labeled compliant tomato-free and cream-free variant. The R3 compatibility audit found no unflagged modern fruit+dairy or tomato+cheese dishes. Traditional South Indian coconut-and-yogurt preparations were not treated as modern sweet-fruit/dairy combinations.

All R3 recipes are lacto-vegetarian. The dravya catalog contains no animal-category ingredient, and the three FDC-only foods listed above are vegetarian.

## Mandatory ingredient display-name scan

The scan lowercased and whitespace-normalized every ingredient display name and every step, then compared every ingredient against every step in its own recipe. A batch could not be written when any full ingredient display name appeared verbatim in a step. An additional R3-wide scan was run after all batch commits.

```text
R3 ingredient-display-name scan
recipes=600
steps=1800
ingredientStepComparisons=12087
verbatimMatches=0
duplicateStepStrings=0
```

Confirmed: **no ingredient display name appears verbatim in any R3 step**. The final independent scan also found no repeated full step sentence across r19-r30.

## Canon-12 coverage

No canon-12 names were assigned to R3. Canon-12 was R1's primary worklist; R3 specified twelve completion-tier themes instead. There are therefore no R3 canon-12 omissions to report.

## Review notes

No `reviewNote` or `reviewNotes` fields were added. The validator, collision audit, compatibility audit, and writing-rule scan found no unresolved item requiring one.

## Batch commits

- `91fbc99` — r19
- `99426a9` — r20
- `fa6323a` — r21
- `6402fe1` — r22
- `bb99524` — r23
- `cbf26b2` — r24
- `aa19772` — r25
- `10a9288` — r26
- `aa67848` — r27
- `559bd42` — r28
- `2e5f89f` — r29
- `42d0337` — r30
- `0f25d5c` — final cross-batch step-text correction

No commits were pushed.

## R3-FIX Step Expansion

Expanded the `steps` arrays for all 600 recipes in batches r19-r30. The final
collection contains 3,472 steps, and every recipe now has 5-8 steps.

| Batch | 5 steps | 6 steps | 7 steps | 8 steps | Initial step-only diff (+/-) | Follow-up step-only diff (+/-) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| r19 | 0 | 3 | 29 | 18 | 365 / 150 | 318 / 318 |
| r20 | 0 | 2 | 22 | 26 | 374 / 150 | 310 / 310 |
| r21 | 48 | 2 | 0 | 0 | 252 / 150 | 1 / 1 |
| r22 | 0 | 50 | 0 | 0 | 300 / 150 | 9 / 9 |
| r23 | 0 | 50 | 0 | 0 | 300 / 150 | 8 / 8 |
| r24 | 0 | 50 | 0 | 0 | 300 / 150 | 16 / 16 |
| r25 | 45 | 5 | 0 | 0 | 255 / 150 | 4 / 4 |
| r26 | 24 | 26 | 0 | 0 | 276 / 150 | 3 / 3 |
| r27 | 50 | 0 | 0 | 0 | 250 / 150 | 0 / 0 |
| r28 | 0 | 50 | 0 | 0 | 300 / 150 | 0 / 0 |
| r29 | 50 | 0 | 0 | 0 | 250 / 150 | 0 / 0 |
| r30 | 50 | 0 | 0 | 0 | 250 / 150 | 0 / 0 |
| **Total** | **267** | **238** | **51** | **44** | **3,472 / 1,800** | **669 / 669** |

The initial diffs replace the original three steps in each recipe. Follow-up
diffs record step-only editorial refinement and the final exact-string
anti-template cleanup. For every batch transformation, a raw-text comparison
with each `steps` array masked produced identical before-and-after hashes. The
per-batch diffs likewise contained no changed field outside `steps`; all other
bytes were preserved.

The final case-insensitive scan compared every complete ingredient display name
with every step in its own recipe. A separate exact-string scan checked all
3,472 steps against one another.

```text
R3-FIX ingredient-display-name and anti-template scan
recipes=600
steps=3472
ingredientStepComparisons=23865
verbatimMatches=0
duplicateStepStrings=0
outOfRangeStepCounts=0
```

Final cumulative validation after the step expansion and writing audit:

```text
Checked 210 dravyas, 1500 recipes
All checks passed.
```

No commits were pushed.
