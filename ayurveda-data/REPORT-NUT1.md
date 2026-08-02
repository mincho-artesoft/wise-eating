# NUT-1 report

## Phase 0 — reverse IFCT collision quarantine

Accepted in commit `07cca4a`.

- Before: 7 IFCT rows fed 15 dravyas through unreviewed reverse collisions.
- After: 0 unreviewed reverse collisions.
- Nutrition-populated dravyas: 61 → 55.
- The six withdrawn matches retain `_review.status` and their former IFCT code:
  - `D001`: Ash gourd murabba (petha)
  - `A011`: Kanda poha
  - `A017`: Foxtail millet
  - `E067`: Elephant apple (ou-tenga)
  - `E034`: Sweet lime juice
  - `B002`: White chickpea
- `D073` remains shared by Punjabi tinda and Round gourd; the probable duplicate
  is tracked in issue #4 rather than treated as a nutrition-match defect.
- The two raw Ash gourd forms remain identical by construction and are flagged
  for review.

## NUT-3 catalogue-count migration

The source and bundled artifacts intentionally describe two populations until
job 4 regenerates the shipped artifacts:

| Population | Foods | Profiles | Recipes | Ingredient links | Ingredient owners | AyurvedaLinks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TARGET | 14,488 | 2,216 | 1,511 | 10,644 | 1,511 | 2,336 |
| SHIPPED | 14,477 | 2,205 | 1,500 | 10,571 | 1,500 | 2,336 |

The complete repin checklist is in `JOB4-REPIN.md`.

### Stale AyurvedaLink registry entry — record only

`PROJECT-HANDBOOK.md` §5 states 2,305 AyurvedaLinks as 278 exact + 58 near +
1,969 derived. Measurement found 2,336 = 306 exact + 64 near + 1,966 derived
in both the source seed and the shipped store. This was already stale before
NUT-1, most likely after the 714 → 705 dravya merge in `ad22c6d`.

Job 4 must re-derive the three tiers and update §5 from measurement; it must not
copy either decomposition merely because the total remains 2,336.

## Remaining phases

Phase 0.5, the individual-fatty-acid mapping, the Phase 1b schema director gate,
and the final unresolved/fill accounting are recorded here as they land.
