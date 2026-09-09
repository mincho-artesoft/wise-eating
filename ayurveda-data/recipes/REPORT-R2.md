# R2 Recipe Authoring Report

## Batches completed

Completed batches r07-r18, with 50 recipes in each batch:

- r07: everyday Indian mains
- r08: everyday Indian tiffin and breakfast
- r09: international soups and stews
- r10: warm grain bowls and salads
- r11: Mediterranean dishes
- r12: East and Southeast Asian mains
- r13: Latin American dishes
- r14: continental comfort dishes
- r15: international breakfasts
- r16: snacks and sides
- r17: drinks and smoothies
- r18: international desserts

Total authored: **600 recipes**. All recipe IDs and names are unique across r07-r18, and all recipe IDs are unique across the complete r01-r18 collection. Every R2 batch has `qualityState: "aiDraft"`.

## Validation output

Each batch was validated cumulatively against the rebuilt `/tmp/pre` store before its isolated commit.

```text
r07
Checked 210 dravyas, 350 recipes
All checks passed.

r08
Checked 210 dravyas, 400 recipes
All checks passed.

r09
Checked 210 dravyas, 450 recipes
All checks passed.

r10
Checked 210 dravyas, 500 recipes
All checks passed.

r11
Checked 210 dravyas, 550 recipes
All checks passed.

r12
Checked 210 dravyas, 600 recipes
All checks passed.

r13
Checked 210 dravyas, 650 recipes
All checks passed.

r14
Checked 210 dravyas, 700 recipes
All checks passed.

r15
Checked 210 dravyas, 750 recipes
All checks passed.

r16
Checked 210 dravyas, 800 recipes
All checks passed.

r17
Checked 210 dravyas, 850 recipes
All checks passed.

r18
Checked 210 dravyas, 900 recipes
All checks passed.
```

Final cumulative validation repeated after all twelve batch commits:

```text
Checked 210 dravyas, 900 recipes
All checks passed.
```

## Dravya-link coverage and viruddha flags

The link percentage is the number of ingredients carrying a valid `dravyaId` divided by all ingredients in the batch. Unlinked ingredients carry validated store `fdcId` values; no dravya IDs or FDC IDs were invented.

| Batch | Dravya-linked ingredients | Total ingredients | Link percentage | Viruddha-flagged recipes |
| --- | ---: | ---: | ---: | ---: |
| r07 | 377 | 427 | 88.3% | 1 |
| r08 | 327 | 378 | 86.5% | 1 |
| r09 | 345 | 395 | 87.3% | 1 |
| r10 | 400 | 450 | 88.9% | 0 |
| r11 | 322 | 364 | 88.5% | 4 |
| r12 | 347 | 407 | 85.3% | 0 |
| r13 | 342 | 387 | 88.4% | 3 |
| r14 | 287 | 327 | 87.8% | 7 |
| r15 | 303 | 328 | 92.4% | 6 |
| r16 | 275 | 300 | 91.7% | 0 |
| r17 | 194 | 231 | 84.0% | 5 |
| r18 | 279 | 281 | 99.3% | 7 |

Total viruddha-flagged recipes: **35**. Every flagged recipe includes a clearly labeled compliant variant in its guidance. A cross-batch audit found no unflagged fruit+dairy or tomato+cheese recipes.

## Canon-12 coverage

No canon-12 names were assigned to R2. Canon-12 was R1's primary worklist; R2 instead specified the twelve everyday and international coverage themes above. Consequently there are no R2 canon-12 omissions to report.

## Review notes

No `reviewNote` or `reviewNotes` fields were added. The validator and final audits found no unresolved item requiring a review note.

## Batch commits

- `04a05ab` — r07
- `ada7062` — r08
- `bd1f0a7` — r09
- `5b29bbd` — r10
- `b743117` — r11
- `3bc2493` — r12
- `340038c` — r13
- `3fee6e4` — r14
- `6f4a2b2` — r15
- `6cd94b6` — r16
- `8089910` — r17
- `85f0695` — r18

No commits were pushed.
