# REPORT — NUT-2

Status: **COMPLETE**

Branch: `ayurveda-app`

Commits:

- `4ab06a0` — retained-stone preparation amendments
- `0b9b011` — lower-mercury tuna preparation amendment
- `0899471` — propagation modes and authored age rules
- `3e79448` — NUT-3 canon backlog resolution
- this commit — this report and the TASK-NUT1 §3.0 ingest amendment

No archive re-encode, `jobs.json` regeneration, database reseed, or preseed
rebuild was run. PROJECT-HANDBOOK §5 remains deferred until the reseed.

## Director rulings and propagation

### R1 — complementary-feeding display guidance

All final 705 dravyas were evaluated. The authored complementary-feeding rule
is display-only and applies to 367 unique records. The pre-revert total was 369;
removing the duplicate `dravya.malai` and `dravya.shakkar` records correctly
collapsed those identities onto existing cream and jaggery records.

### R2 — whole-form choking guidance

The dry-fruit-nut plus seed set is exactly 42 records: 18 carry the ruled
60-month display floor and 24 carry no age floor. Zero records are unruled.
The 60-month rule is display-only and does not alter enforced recipe
visibility.

### R3 — honey contaminant rule

Honey is the only rule with propagation mode `contaminant`. Its 12-month floor
is both displayed and enforced through recipes.

### R4 — salts

Exactly four salt identities carry dietary display guidance. It does not
propagate into recipe visibility.

### R5 — fish ruling withdrawn

No dravya carries a mercury- or fish-derived age floor or source. Seer fish is
display 0 / enforced 0. Tuna remains display 60 / enforced 0 solely because of
its pre-existing `legacyImport` display floor; it has no authored mercury age
rule or age source. The tuna record instead carries the ruled lower-mercury
preparation guidance.

## Preparation amendments

The retained-stone wording was amended for dry dates, panchmeva, prunes, and
munakka in `4ab06a0`. Tuna's preparation was amended to prefer smaller species
such as skipjack in `0b9b011`. Neither preparation commit changed age metadata.

## NUT-3 canon backlog

Fifteen identities were resolved as aliases rather than new dravyas:
fenugreek leaves, green amaranth greens, dill greens, tender taro leaves, soft
dates, dry fig, dry apricot, popped lotus seed, malai, cultured butter, cane
jaggery, powdered jaggery/shakkar, stevia leaf, vida salt, and iodized table
salt.

The final set is 705 dravyas and 1,511 recipes. All 26 canon ids resolve to
exactly one built entity. The placeholder band is exactly 900001–900376 and its
mapping SHA-256 is
`bc7afbfce5b0ec708aec1fea387a72806bbe5e6b4fd9d48747ae01d60736441b`.
Exactly three normalized-name collisions remain, with no fourth.

Eleven new recipes were retained, including the corrected ids
`recipe.khajur-smoothie`, `recipe.samak-rice-fasting`, and
`recipe.singhara-pakora-fasting`. Khajur smoothie flags the banana-and-milk
viruddha and supplies the compliant almond-milk variant. Duplicate identity
follow-up is tracked by GitHub issue #1.

## Nutrition coverage transition

The active build currently classifies 1,501 recipes as full, 10 as estimated,
and zero as none, out of 1,511 total. These exact full/estimated counts are a
transitional pre-ingest snapshot, not a permanent invariant. The permanent
test invariants require zero `none`, require the three classifications to sum
to the recipe count, and require every estimated recipe to be explained by a
null nutrient value in the active build source.

| estimated recipe | blocking dravya | disposition |
|---|---|---|
| `recipe.amla-chutney` | `dravya.amla-fresh` | NUT-1 review/form |
| `recipe.amla-ginger-shot` | `dravya.amla-fresh` | NUT-1 review/form |
| `recipe.gond-ladoo` | `dravya.acacia-gum` | permanently unfillable |
| `recipe.horse-gram-soup` | `dravya.horse-gram` | ingest-only; exact IFCT B012 values exist |
| `recipe.parwal-sabzi` | `dravya.pointed-gourd` | ingest-only; exact IFCT D060 values exist |
| `recipe.samak-rice-fasting` | `dravya.barnyard-millet` | ingest-only; hand-sourced values exist |
| `recipe.singhara-pakora-fasting` | `dravya.water-chestnut-flour` | NUT-1 review/form |
| `recipe.sol-kadhi` | `dravya.kokum` | permanently unfillable |
| `recipe.tinda-sabzi` | `dravya.tinda` | ingest-only; exact IFCT D073 values exist |
| `recipe.ugadi-pachadi` | `dravya.neem` | permanently unfillable |

TASK-NUT1 §3.0 and GitHub issue #3 own the ingest gap. The four ingest-only
recipes must move estimated → full without new sourcing, and the transitional
snapshot must change in the same commit.

## Final gates

- **G0:** 705 dravyas and 1,511 recipes.
- **G1:** placeholder ids 900001–900376; mapping hash unchanged at
  `bc7afbf...36441b`.
- **G2:** dry-fruit-nut plus seed is 18 at 60 months plus 24 at no floor, 42
  total and zero unruled.
- **G3:** zero mercury- or fish-derived age floors.
- **G4:** all 26 canon ids resolve exactly once.
- **G5:** every authored-age record has a non-empty WHO, NHS, or SACN source;
  zero exceptions. Provenance is 314 `legacyImport` and 391 `authored`.
- **G6:** source-to-source comparison against `0b9b011` found 2,213 common,
  six removed, and three added records, with zero decreases in either display
  or enforced minimum age.
- **G7:** historical enforced visibility is 1,496 / 1,500 / 1,500 at 9 / 24 /
  60 months. The 11 new recipes are reported separately below.
- **G7b:** contaminant propagation is exactly `{honey-min-age: 12}`.
- **G7c:** final display histogram is 6: 1, 12: 1, 24: 1,203, 48: 109,
  60: 195, 192: 2. The exact R2 60-month display count is 18.
- **G8:** all 25 production search goldens and both safety goldens pass.
- **G9:** exactly three normalized-name collisions, no fourth.
- **G10:** archive, jobs, reseed, and handbook work was not run.
- **G11:** the baseline at `9cb6fda` ran 150 tests: 144 passed and the same six
  pre-existing tests failed. The final suite ran 152 tests: 146 passed and only
  those same six failed. GitHub issue #2 owns their repair.

The 11 new recipes have display / enforced floors as follows:

| recipe | display | enforced |
|---|---:|---:|
| `recipe.amla-chutney` | 24 | 0 |
| `recipe.amla-ginger-shot` | 24 | 12 |
| `recipe.gond-ladoo` | 60 | 0 |
| `recipe.horse-gram-soup` | 24 | 0 |
| `recipe.khajur-smoothie` | 24 | 0 |
| `recipe.parwal-sabzi` | 24 | 0 |
| `recipe.samak-rice-fasting` | 48 | 0 |
| `recipe.singhara-pakora-fasting` | 48 | 0 |
| `recipe.sol-kadhi` | 24 | 0 |
| `recipe.tinda-sabzi` | 24 | 0 |
| `recipe.ugadi-pachadi` | 24 | 0 |

The exact safety profile count is 2,216. The largest tracked archive is the
480 variant at 85,356,519 bytes, below the 90 MB limit.

## Permitted pre-existing failures

The unchanged six failures are the stale tracked-archive size assertion, three
WE-3 display assertions, the WE-5 recursive `xcuserdata` ignore assertion, and
the WE-6 literal `ensureLoaded` assertion. They are documented with their
stale-dating commits in GitHub issue #2 and were not repaired in this packet.
