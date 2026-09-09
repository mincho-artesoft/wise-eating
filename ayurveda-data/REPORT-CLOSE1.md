# CLOSE1 completion report

Date: 2026-08-03

Branch: `ayurveda-app`

Parent commit: `75b8901` (`SAFE1`)

## Source and derived catalogue

- 704 dravyas and 1,511 recipes produce 14,487 foods, 2,215 profiles,
  2,336 Ayurveda links, and 10,644 ingredient links across 1,511 owners.
- The placeholder band is contiguous at `900001...900375`. Its mapping SHA-256
  is `c0348d706d03685c93aa78b5f3ed9741b5f43eb772d1ab230cbbeb360944aba3`.
- CLOSE1 merged `dravya.makhana` into `dravya.lotus-seed` and
  `dravya.round-melon-tinda-punjabi` into `dravya.tinda`. They added no new
  placeholder, so 175 later placeholders shifted by the expected offset with
  zero deviations. The previous mapping SHA was
  `bc7afbfce5b0ec708aec1fea387a72806bbe5e6b4fd9d48747ae01d60736441b`.
- Engine exclusions are 11; six rows are explicitly `edible: false`.
- Recipe nutrition is 1,508 full, three estimated, zero none.

The temporary base gate caught real stale derived state, not bookkeeping. The
base supplied to the first export held `ZSEARCHINDEXCACHE` for 14,489 foods and
old ingredient links. That cache referenced two food rows removed by CLOSE1.
The build now asserts, before seeding, exactly 12,601 USDA foods and zero rows
in `ZAYURVEDAPROFILE`, `ZAYURVEDALINK`, `ZINGREDIENTLINK`, and
`ZSEARCHINDEXCACHE`. The final base was regenerated from `Legacy/foods.json`.

All 375 `minerals.fluoride.unit` declarations were relabelled from `mg` to
`µg`; no value changed. A schema test now compares every dravya-food nutrient
unit with `NUTRIENT_CATALOG`, treating `ug` and `µg` as equivalent.

## Archive and ID map

- Every 144/480/1024 variant has 14,479 packets, `has_b_frames=0`, and video
  time base 1/600.
- Every variant embeds 14,487 DB-ID/frame pairs. `foods_index.csv` also has
  exactly 14,487 rows.
- The reviewed orphan inventory is 14, including `Fox nut (makhana)` and
  `Punjabi tinda (apple gourd)`. Their encoded frames were retained.
- The final ID metadata update was a stream-copy remux. It did not re-encode
  the already-approved video streams.
- `food_archive_480.mp4` is 85,697,754 bytes, below 90,000,000.
- The reassembled 1024 archive is 352,139,375 bytes, SHA-256
  `eb528aa141a8464f84b680eb53f979778ab96a2b6716861a12958da0cd8cb5f8`,
  split into five parts.
- The frame-content audit sampled 402 DB IDs (200 base, 200 Ayurveda plus
  boundary cases). Worst mean absolute difference was 0.8203 at DB ID 900162,
  `Kachampuli vinegar`, below the 5.0 gate.

## Upgrade migration

The earlier statement that upgrades were already safe because
`placeholderMoves` existed was wrong. That conclusion was drawn from the
function's presence without reading its guard. The v7 fixture proved the code
was nested inside a v5-to-v6-only condition and could never run for shipped v7
profiles.

Placeholder ID migration is now separate from the unchanged v5-to-v6
migration. It runs when an incoming placeholder and an existing same-slug
profile disagree on `foodId`, independent of seed version, and runs before
canonical ownership validation. Seed version is 8.

Runtime upgrade from the byte-for-byte `75b8901` v7 preseed printed:

```text
Placeholder migration: remapped 175 FoodItem ids; deleted 2 obsolete placeholder foods; rebuilt search cache for 14487 foods.
```

`RunResult.remappedFoodIDs` was 175 and `deletedFoods` was two (old IDs 900201
and 900288). Five named moved rows retained the same SwiftData/SQLite persistent
identifier:

| profile | move | persistent identifier / SQLite Z_PK |
|---|---:|---:|
| `dravya.mamsa-rasa` | 900202 → 900201 | 14242 |
| `dravya.manathakkali-greens` | 900203 → 900202 | 14440 |
| `dravya.mango-ginger` | 900204 → 900203 | 13746 |
| `dravya.mango-pickle` | 900205 → 900204 | 13449 |
| `dravya.marathi-moggu` | 900206 → 900205 | 14294 |

The upgraded store finished with 14,487 foods, 2,215 profiles, 375
placeholders, seed version 8, and a search cache covering 14,487 foods. A clean
USDA-base seed reached the same counts and the same placeholder mapping SHA.
The exported v8 preseed then verified at the same state. The upgrade case is a
permanent, parameterized fixture in
`tests/fixtures/placeholder_upgrade_fixtures.json`; it reconstructs its v7
baseline directly from commit `75b8901`.

A final uninstall/reinstall from the actual bundled v8 preseed printed
`Ayurveda v8 preseed stamp verified; no inserts or updates` and
`Index is up-to-date (version: 9, DB: 14487). Skipping rebuild.`

## Gates

- `validate.py`: passed.
- Python suite: 179 tests, zero failures.
- Debug simulator build: succeeded; required assets 8/8.
- Release simulator build: succeeded; required assets 8/8.
- Largest tracked file: 85,697,754 bytes, below 90 MB.
- No force push and no change to `main`.
