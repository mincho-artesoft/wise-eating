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
This is the final scope ruling recorded in `DECISIONS-NUT.md` §N9, not a backlog.

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

## Phase 2 — reviewed sourcing and final accounting

Accepted implementation: `7c7c0e9`.

The honest headline is **61 populated records at the start and 68 at the
end**:

| Change | Records | Running populated total |
| --- | ---: | ---: |
| NUT-1 baseline | — | 61 |
| Phase 0 wrong IFCT bindings withdrawn | −6 | 55 |
| Late F016 wrong-species binding withdrawn | −1 | 54 |
| Director-reviewed direct IFCT identities | +6 | 60 |
| Direct published-literature measurements | +2 | 62 |
| Manually resolved ambiguous IFCT identities | +6 | 68 |

Thus NUT-1 added 14 defensible records and removed 7 wrong bindings. The
explicit final provenance split is 12 newly reviewed IFCT records, 2 new
published-literature records, and 54 pre-existing populated records. Of the 22
ambiguous records, 6 were resolved and 16 were deferred with their candidates
and reasons recorded.

The brief asked to fill 298 unmatched records. The defensible result is not
298 fills: it is 14 records added, 7 removed, and 178 records permanently
unmatchable to IFCT for a documented reason. Avoiding a false species identity
is more important than raising a coverage number.

### §N1 derivation investigation: zero members

No nutrient value was derived. All 13 candidates failed the §N1 rule: drying
retention varies by temperature and variety; juice extraction does not retain
nutrients at one uniform yield; ajwain, barley, coriander, cumin, and fenugreek
waters are infusions; badam milk adds dairy and spices; and sattu adds roasting
and sometimes barley. §N1 remains valid policy, but `_review.provenance` is
`derived` on zero records.

The useful recovery path was direct measurement or a manually reviewed
identity, not a transformation multiplier.

### Shared-name species failures

IFCT F016 is *Eleocharis dulcis*, while the project's fresh singhara record is
*Trapa natans*. The F016 binding on `dravya.fresh-water-chestnut` was stripped,
its former code and a wrong-species explanation remain in `_review`, and all
nutrient values are null. This was the seventh withdrawn binding and the one
wrong binding already present in shipped data.

Three shared-name species failures surfaced across the packet: elephant apple,
surmai/“king mackerel”, and singhara/“water chestnut”. They are one matcher
failure mode: an English or vernacular name shared by different organisms.

### Six direct IFCT identities

These are manually reviewed ratio-1.000 identity bindings with ordinary IFCT
2017 provenance. None is derived:

| Dravya | IFCT row |
| --- | --- |
| Fresh amla | `E021` Gooseberry |
| Fresh green pea | `D061` Peas, fresh |
| White/button mushroom | `J001` Button mushroom, fresh |
| Brown lentil / whole masoor | `B014` Lentil whole, brown |
| Split mung dal | `B010` Green gram, dal |
| Pink elephant yam | `F017` Yam, elephant |

Two plausible direct bindings were reviewed and declined. Ripe karonda was not
bound to E032 because another karonda already uses the row and IFCT does not
state maturity; sugar and acid change materially with ripening. Sweet parwal
was not bound to D060 because a named sweet cultivar cannot inherit the generic
pointed-gourd measurement. Both remain null with the declined candidate and
reason recorded.

### Two direct literature measurements

Only fields measured by each study were populated:

- Fresh amla juice: total sugars 5.87 g/100 g, vitamin C 550.25 mg/100 g, and
  total polyphenols 3,220 mg/100 g. Source: Kumari and Khatkar, “Effect of
  processing treatment on nutritional properties and phytochemical contents
  of aonla juice,” *Journal of Food Science and Technology* 56(4), 2019,
  2010–2015, DOI `10.1007/s13197-019-03674-0`. The record includes the reported
  triplicate standard deviations.
- Water-chestnut flour: protein 8.4 g/100 g, fat 0.47 g/100 g, starch
  65.86 g/100 g, water 7.08 g/100 g, and ash 2.59 g/100 g. Source: Ahmed,
  Al-Attar, and Arfat, “Effect of particle size on compositional, functional,
  pasting and rheological properties of commercial water chestnut flour,”
  *Food Hydrocolloids* 52, 2016, 888–895, DOI
  `10.1016/j.foodhyd.2015.08.028`. The study reports no variation for the
  whole-sample proximate values; the record notes the reported effect of
  sieving on ash and explicitly avoids F016 because the flour is Indian
  *Trapa natans*.

### Ambiguous IFCT dispositions

Six identities were resolved manually. Every losing candidate remains in
`_review.manualResolution`:

| Dravya | Selected | Losing candidates |
| --- | --- | --- |
| Broad bean pod | `D047` | `B007`, `B008`, `B009`, `D003`, `D048`, `E001`–`E004` |
| Dry dates | `E017` | `E018`, `E019` |
| Red pumpkin | `D066` | `D065` |
| Raisins | `E058` | `E057` |
| Raw jackfruit | `D051` | `D052`, `E030` |
| White radish | `F010` | `F009`, `F011`, `F012` |

The other 16 remain null and retain every candidate plus a food-specific
reason: betel leaf, betel nut, elephant-foot yam, field bean, French bean,
fresh dates, gherkin, green grapes, green peas pod, hung curd, jamun, khus
root, manathakkali greens, niger seed, taro stem, and wild celery seed.

### G4 — the 178 no-token-relation records

The 178 are defined by IFCT matchability, not nullness. They have no subset or
superset token relationship to any of the 3,435 IFCT keys and remain unmatched
by IFCT. Of them, 176 are null; Black rice and Camel milk retain their
pre-NUT-1 published-literature values. Zero records in this set acquired or
changed a value during Phase 2.

| Category | Count | Category | Count |
| --- | ---: | --- | ---: |
| preparation | 29 | medicinal | 24 |
| spice | 22 | regional | 21 |
| beverage | 16 | vegetable | 12 |
| fruit | 11 | fermented | 8 |
| grain | 7 | animal | 6 |
| salt-mineral | 4 | sweetener | 4 |
| oil-fat | 3 | leafy-green | 3 |
| seed | 2 | dairy | 2 |
| dry-fruit-nut | 2 | legume | 2 |

### Final gates

- Matcher: 56 strict matches, 6 manual direct matches, 6 manually resolved
  ambiguous matches, 61 active IFCT matches, 16 ambiguous, 292 unmatched,
  7 withdrawn, and 0 unreviewed reverse collisions.
- Population: 376 records, 68 populated, 7 withdrawn. Comparing to the NUT-1
  baseline gives exactly 14 newly populated and 7 newly null records.
  Comparing Phase 2 against `bd7d4b3` finds no nutrient-value change outside
  the 14 additions and the F016 withdrawal.
- Two-run determinism:
  - `dravya_foods.json`:
    `3ed8055e5ed509f7c6fe6dcaafd4f87c3763cc7270de08ab60caeaa0dfe542ad`
  - `ifct-unresolved.json`:
    `7e21d9cc3f1e3084ff19b66828d39183b7b634c0b7ee54c8d8ea4e5f28e57b95`
- Recipe panels retain the same 39-field schema. Coverage is 1,508 full,
  3 estimated, 0 none; the remaining three are acacia gum, kokum, and neem
  flower recipes.
- Source and reconstructed-shipped validation both pass at 705 dravyas, 1,511
  recipes, placeholder band 900001–900376, and mapping SHA
  `bc7afbfce5b0ec708aec1fea387a72806bbe5e6b4fd9d48747ae01d60736441b`.
- The full suite ran 157 tests. Its only failures are the six proven
  pre-existing failures at `9cb6fda`: the 480 archive size gate, the three
  WE-3 display gates, recursive `xcuserdata` ignore, and lazy search-index
  loading.
- No `Ayura/**/*.swift` file changed. No seed, preseed, food archive,
  `jobs.json`, or search-cache artifact was regenerated or committed.
