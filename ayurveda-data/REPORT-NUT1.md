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

## Phase 0.5 — stable placeholder-nutrition ingest

`dravya_foods.json` is now ingested by stable `dravyaId`; the unstable numeric
placeholder id, `_review`, and `dravyaId` metadata do not enter the nutrition
panel. Null remains null, and a withdrawn Phase 0 match cannot fall back to its
former USDA binding.

- Coverage: 1,501 full / 10 estimated / 0 none → 1,505 full / 6 estimated /
  0 none.
- `recipe.horse-gram-soup`, `recipe.parwal-sabzi`, `recipe.tinda-sabzi`, and
  `recipe.samak-rice-fasting` moved from estimated to full without new sourcing.
- Two independent builds were byte-identical; the seed SHA-256 was
  `822e16ba1bbfaef2a8c8be99ee94b6f8ced5a9ccf3affc049f696cefaa4ceaaa`.

## Phase 1a — individual fatty acids

The existing 44-field lipid schema now receives every identity-compatible IFCT
individual-fatty-acid column: 12 saturated, 6 monounsaturated, 1 trans, and
8 polyunsaturated fields. All source columns and destination fields are grams
per 100 g with multiplier 1.

- Ever-populated schema fields: 67 → 94.
- New non-null cells: 1,350 across 27 lipid fields.
- Existing non-null cells changed: 0.
- Matcher population stayed 56 exact / 22 ambiguous / 298 unmatched, with
  0 unreviewed reverse collisions.
- Applying `match_ifct.py` and `apply_ifct_values.py` twice was byte-identical:
  - `dravya_foods.json`: `ee29daf6bc1c43cec1b9f0c0bf51166a4212521fe640057c1f36b82bc9a1bbe1`
  - `ifct-unresolved.json`: `13c9da97f67d3c14a741dfc0afe5c5e7a022d57cd9645c3455dca990348b0825`

IFCT `f11d0` and `f22d2n6` have no identity-equivalent field in the current
schema and were not forced into a differently named field. Conversely, schema
fields for acids IFCT does not measure remain null.

## Phase 1b — ruled source-only IFCT classes

The director approved 66 source mappings: 15 top-level classes and 51 detailed
measurements. `vit` and `vitb` were rejected because mass sums across compounds
normally expressed at both microgram and milligram scales have no useful
interpretation. The 37 individual polyphenols and eight tocopherol/tocotrienol
isomers remain in the CSV without schema fields; their totals are retained.
This is the final scope ruling recorded in `DECISIONS-NUT.md` §N7, not a backlog.

The ruling contains 66 newly populated mappings but 65 structural additions:
`vitd` maps to the already-existing `vitamins.vitaminD`. Adding a duplicate
field merely to make the structural delta 66 would contradict that explicit
ruling. The measured counts are therefore:

- Schema fields per dravya source row: 122 → 187, exactly 65 additions.
- Ever-populated fields: 94 → 160, exactly 66 newly populated mappings.
- New non-null cells: 3,250 in new fields plus 50 in existing `vitaminD`.
- Existing non-null values changed: 0.
- Approved mappings present: 66/66; rejected or deferred mappings present: 0.
- Two-run `dravya_foods.json` SHA-256:
  `f1dcc367e0783ecc0873186cf38910b420cb39c9693cba9141b9647daacea173`.
- Two-run `ifct-unresolved.json` SHA-256:
  `13c9da97f67d3c14a741dfc0afe5c5e7a022d57cd9645c3455dca990348b0825`.

The source-only ingest catalogue has 66 entries and validates their units,
values and display policy. The recipe catalogue remains at 39 fields. Recipe
panels before and after Phase 1b were byte-identical, SHA-256
`63bb2dc4897eb0cd2ff6c566615f1b61ed8e8cdb0453de4839b99dd19bdc1612`.
No Phase 1b field entered a recipe panel or shipped artifact.

The full suite ran 153 tests with only the six failures proven pre-existing at
`9cb6fda`: the 480 archive size gate, three WE-3 display tests, recursive
`xcuserdata`, and lazy search-index loading. Source and reconstructed-shipped
validation both passed at 705 dravyas, 1,511 recipes, placeholder band
900001–900376, and mapping SHA
`bc7afbfce5b0ec708aec1fea387a72806bbe5e6b4fd9d48747ae01d60736441b`.

Aluminium, arsenic, cadmium, lead, mercury and the toxic-mineral total carry
`notForDisplay: true`. None is wired to a view.

Seed propagation and app display require a future packet with a measured cold
launch delta against the 1.700 s ceiling and 1.650 s paydown trigger in fixed
decision 11.

## Remaining phases

The Phase 2 derivation gate and the final unresolved/fill accounting are
recorded here as they land.
