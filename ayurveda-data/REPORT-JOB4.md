# JOB4 regeneration report

This report records the measured inputs, retained exceptions, regenerated
artifacts, and release gates for the one-time JOB4 shipped-artifact rebuild.

## Three-record investigation before Phase H

Commit `3e79448` has no explanatory body, but its diff and the contemporaneous
NUT-3 ruling establish **Case A: ruled duplicates**, not records deleted to
satisfy a hard-coded count. The same commit emptied `batch-31.json`, added the
three aliases to their retained targets, and taught the canon validator those
targets. `TASK-NUT3.md` records the reviewed dispositions:

| Removed record | Retained target | Recorded reason | Alias state |
| --- | --- | --- | --- |
| `dravya.malai` — Fresh cream (malai) | `dravya.cream` — Cream, heavy | “existing alias `malai`; add `Santanika` as sanskrit” | `Fresh cream (malai)`, `malai`, `milk cream`, and `clotted milk skin` are present; `Santanika` is the Sanskrit name |
| `dravya.shakkar` — Powdered jaggery (shakkar) | `dravya.jaggery` — Jaggery | “shakkar is granulated gud, same substance” | `Powdered jaggery (shakkar)`, `shakkar`, `jaggery powder`, and `granulated jaggery` are present |
| `dravya.vida-salt` — Vida salt | `dravya.black-salt` — Black salt | “exact sanskrit match” (`Vida lavana`) | `Vida salt`, `bid lavan`, and `vit lavan` are present |

The NUT-3 canon id for the second record is `dravya.powdered-jaggery`, while
the short-lived batch-31 id was `dravya.shakkar`; the exact display-name alias
and the commit's validator mapping both resolve the identity to
`dravya.jaggery`. No alias is missing. Consequently the correct entity counts
remain 705 dravyas, 1,511 recipes, 14,488 catalogue entries, 1,877 imagery
jobs, and 14,477 physical archive frames. Restoring the alias-only rows would
reintroduce duplicate entities, so phases D–G were not repeated.

## Frame inventory before regeneration

- Catalogue: 14,488 entries.
- Encoded archive: 14,466 frames.
- Catalogue resolution: 14,477 entries resolve, including 23 extra references
  sharing an already-addressed frame; 11 recipes have no frame.
- Physical archive reconciliation: 14,454 frames are addressed and 12 are
  retained but unaddressed by the primary name map.
- The 11 missing recipes already have accepted image files from the `e37a00d`
  generation run. Phase D therefore generated nothing.
- The files for Fresh cream (malai), Powdered jaggery (shakkar), and Vida salt
  are retained on disk but excluded from encoding because those records are
  aliases, not catalogue entities.

The two physical sharing pairs are Panchamrita and Raisins. The two near-miss
pairs are Golden milk / Golden Milk and Mung Rice Peya / Mung-Rice Peya; each
near-miss currently has two distinct frames but is one normalization step away
from a collision. All four pairs belong in the TASK-IDKEY verification set.

`Date Banana Smoothie` became `Date-banana Smoothie` while retaining the slug
`recipe-date-banana-smoothie`. That surviving display-name change is luck, not
an identity guarantee, and is a concrete TASK-IDKEY exhibit.

### Retained unaddressed frames

All 12 are confirmed outputs of the imagery run for current dravya records.
Each dravya profile attaches to an existing legacy FoodItem whose displayed
name differs from the generated dravya-name frame key. They are not presumed
merge casualties, and they remain encoded while the name-keyed fallback stack
and `frame_map2.json` still exist.

| Previous → new index | Retained frame key | Source dravya | Bound FoodItem | Confirmed origin |
| ---: | --- | --- | --- | --- |
| 2404 → 3413 | Spiced buttermilk (takra) | `dravya.takra` | 8107 — Milk, buttermilk, fluid, cultured, lowfat | generated dravya job |
| 4013 → 6827 | Wheat, whole grain | `dravya.whole-wheat` | 6388 — Wheat flour, whole-grain (USDA distribution-program row) | generated dravya job |
| 5786 → 2810 | Sweet potato | `dravya.sweet-potato` | 6012 — Sweet potato, raw, unprepared (USDA distribution-program row) | generated dravya job |
| 7591 → 9780 | Rice kheer | `dravya.kheer-rice` | 239 — Pudding, rice | generated dravya job |
| 8462 → 6892 | Black mustard seed | `dravya.mustard-seed-black` | 8154 — Spices, mustard seed, ground | generated dravya job; reuse explicitly denied |
| 8465 → 6895 | Sardine | `dravya.sardine` | 11733 — Pacific sardine, canned in tomato sauce, drained with bone | generated dravya job |
| 9779 → 11924 | Lamb | `dravya.lamb` | 9619 — New Zealand ground lamb, raw | generated dravya job |
| 11193 → 13447 | Rice, brown | `dravya.brown-rice` | 7124 — Brown long-grain rice, raw (USDA distribution-program row) | generated dravya job |
| 11432 → 12983 | Lotus seeds (makhana) | `dravya.lotus-seed` | 6121 — Seeds, lotus seeds, raw | generated dravya job; reuse explicitly denied |
| 11610 → 14394 | Curry leaf powder | `dravya.curry-leaf-powder` | 12542 — Curry leaf powder (legacy row notes whole/dried) | generated dravya job |
| 12804 → 14402 | Grapes | `dravya.grapes` | 11330 — Red or green European-type grapes, raw | generated dravya job |
| 13030 → 10192 | Dosa | `dravya.dosa` | 2783 — Dosa, plain | generated dravya job |

## Imagery master regeneration

- `jobs.json`: 1,877 prompts.
- `reuse-map.json`: 293 reviewed reuses.
- `styleHash`: `c8d83786a68f` (unchanged).
- Removed from the master: the three alias records above.
- Renamed in place: Date-banana Smoothie, with its existing slug retained.

An external `--out` directory previously caused `build_batches.py` to look for
`reuse-deny.json` under the output directory. Absence silently became an empty
guard, producing the invalid 1,851 / 319 result. The builder now resolves the
denial list from its source directory, requires it to be readable, asserts 26
entries, and prints the loaded count. Its external-output regression test
reproduces 1,877 / 293.

The adjacent imagery-script audit found no other source input rooted
incorrectly at `--out`. It did find optional operational-state behavior that
was not changed in this ruling: `status.py` and `runner.js` treat a missing
ledger as empty, `runner.js` can fall back to legacy batches when invoked
directly without `jobs.json`, and the superseded batch validator tolerates a
missing per-batch result until it checks the batch files. The normal `run.sh`
entry point still invokes fail-closed `verify.py` before generation.

### The 26 reviewed reuse denials

The shipped state is clean: every denied food has a committed generation job,
is absent from `reuse-map.json`, and has its own physical archive index distinct
from the rejected shared frame.

| Dravya id | Own image | Rejected shared frame | Review reason |
| --- | --- | --- | --- |
| `dravya.alphonso-mango` | Alphonso mango | Mangos, raw | a distinct cultivar, smaller and deep orange |
| `dravya.bajra` | Pearl millet | Millet, raw | bajra is grey-green and larger than proso |
| `dravya.bay-leaf` | Bay leaf, Indian | Spices, bay leaf | tej patta is larger and three-veined; the frame is Mediterranean laurel |
| `dravya.black-grapes` | Black grapes | Grapes, red or green (European type, such as Thompson seedless), raw | the frame cannot be both red and green; black grapes need their own |
| `dravya.chana-dal` | Chana dal (split bengal gram) | Chickpeas (garbanzo beans, bengal gram), mature seeds, raw | split yellow dal, not a whole chickpea |
| `dravya.chickpea-black` | Black chickpea | Chickpeas (garbanzo beans, bengal gram), mature seeds, raw | kala chana is small and dark brown; the frame is pale kabuli |
| `dravya.dry-coconut` | Dry coconut (copra) | Nuts, coconut meat, dried (desiccated), not sweetened | copra is a whole dried half-shell; the frame is shredded desiccated coconut |
| `dravya.dry-dates` | Dry dates (chhuara) | Dates, medjool | chhuara is pale and shrivelled; medjool is dark and plump |
| `dravya.elaichi-banana` | Elaichi banana (small) | Bananas, raw | a small finger banana, not the standard cavendish in the frame |
| `dravya.green-grapes` | Green grapes | Grapes, red or green (European type, such as Thompson seedless), raw | shares the same ambiguous grape frame as black grapes, so both get their own |
| `dravya.long-brinjal` | Brinjal (long purple) | Eggplant, raw | long slender fruit, not the globe eggplant in the frame |
| `dravya.lotus-seed` | Lotus seeds (makhana) | Seeds, lotus seeds, raw | makhana is white puffed popped seed; the raw-lotus-seed frame is what kamal gatta looks like |
| `dravya.masoor-dal` | Split red lentil | Lentils, pink or red, raw | split masoor dal, not the whole lentil |
| `dravya.mishri` | Rock sugar (mishri) | Sugars, granulated | irregular crystal lumps, not granulated sugar |
| `dravya.mung-dal-split` | Split mung dal | Mung beans, mature seeds, raw | yellow split dal, not the whole green bean |
| `dravya.mustard-seed-black` | Black mustard seed | Spices, mustard seed, ground | whole dark seed, not ground powder |
| `dravya.mustard-seed-yellow` | Yellow mustard seed | Spices, mustard seed, ground | whole pale seed, not ground powder |
| `dravya.ragi` | Finger millet | Millet, raw | ragi is dark red-brown; the frame is pale proso millet |
| `dravya.raw-jackfruit` | Raw jackfruit (kathal) | Jackfruit, raw | unripe kathal is pale green-white; the frame reads as the golden ripe fruit |
| `dravya.red-amaranth-greens` | Red amaranth greens (lal chaulai) | Amaranth leaves, raw | lal chaulai is red-purple; the frame is the green leaf |
| `dravya.red-banana` | Red banana | Bananas, raw | red skin |
| `dravya.red-onion` | Red onion | Onions, raw | purple-red skin and flesh |
| `dravya.red-yellow-capsicum` | Red/yellow capsicum | Peppers, sweet, red, raw | covers yellow as well, which a red-pepper frame cannot show |
| `dravya.small-brinjal` | Brinjal (small round) | Eggplant, raw | small round fruit, not the globe eggplant in the frame |
| `dravya.white-onion` | White onion | Onions, raw | white skin, not the brown onion in the frame |
| `dravya.white-peas` | White peas (safed vatana) | Peas, green, split, mature seeds, raw | cream-coloured whole peas, not green split peas |

## Regeneration gates

### Phase E — unified archive

`prepare_frames.py` completed without `--allow-missing`: 14,466 existing keys
had zero unmatched source images, the three alias files were skipped, and 11
new recipe keys were appended. The staged total is 14,477 frames: 12,601 from
the immutable ZIP and 1,876 distinct generated keys (the Panchamrita dravya
remains the explicit winner over the same-key recipe image).

All three runtime variants were encoded without B-frames. Each contains 14,477
packets on the exact 600 Hz timeline.

| Variant | Bytes | SHA-256 | Packets |
| ---: | ---: | --- | ---: |
| 144 | 43,591,000 | `9f293eee0c4c00d9e13ce161e2829e0fcba76160defe244c8fbda98347392d92` | 14,477 |
| 480 | 85,383,373 | `1ef3f05c2ea72db95b4b36599522379668a2d51757f65c13afbbd7622808f178` | 14,477 |
| 1024 restored | 351,950,638 | `bdc69c2823f95d0a9cba3dfa5d370fd00eceda2be9ee7354c59a710130a747e1` | 14,477 |

The 1024 gzip remains five parts: four at 73,400,320 bytes and part `ae` at
58,432,675 bytes. Concatenating and inflating the parts reproduced the restored
SHA and packet count above.

- GE1: pass — 480 is 4,616,627 bytes below 90,000,000.
- GE2: pass — no tracked file is at or above 90,000,000 bytes; 480 is largest.
- GE3: pass — 14,465 physical frames are addressed, 23 catalogue entries share
  one of those frames, all 14,488 entries resolve, and the 12 inventoried frames
  above remain encoded but unaddressed.
- Frame map SHA: `b0fffc11279025e7e5e95606e0954357ba942ebbb202635e49d8ca4b3d80ca85`.
- Timestamp SHA: `d3666f4a56036440f7922e1af59ae9641f1e77ed112c70b89adc616ec11c6d34`.
- Repository suite after the archive replacement: 161/161 tests passed.

### Phase F — rebuilt preseed

The preseed was manufactured from a fresh simulator install after deleting the
whole app, so its container and `UserDefaults` were absent. The manufacturing
launch started from the 12,601-row USDA base, inserted the target catalogue,
and built search cache v7 at 14,488 foods. The completed SQLite store passed
`PRAGMA integrity_check` before export.

`build_preseeded_store.py` was run twice from that completed store. Both runs
produced byte-identical gzip parts and the same reconstructed store:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `preseeded_db.store.gz.part-aa` | 73,400,320 | `e7b2fb2c9a3e03e3a76247a6988e5e9b033a4a2e95f89ad389a08d15d0e15d11` |
| `preseeded_db.store.gz.part-ab` | 21,398,959 | `89b06ea707d798e20756098c0cd6f83f273c798bf12cb034b42bcc20dba9ed2b` |
| reconstructed `default.store` | 211,791,872 | `a6ddf152234fee2b12c9d9efcdffb70c3d01fdc4d4980418a46686b2f57d25a0` |

Measured rebuilt-store population:

- 14,488 foods, 2,216 Ayurveda profiles, and 2,336 Ayurveda links.
- 10,644 ingredient links across 1,511 recipe owners.
- Recipe nutrition: 1,508 full, 3 estimated, 0 none.
- Search cache: version 7, 14,488 foods; 4,223 facet foods, 4,223 metadata
  rows, 2,007 linked rows, 89 keys, and 59,114 assignments.
- Safety metadata: 155 dravyas and 1,190 recipes with allergens; 391 recipes
  at the 12-month floor and 5 at the 24-month floor.

The reconstructed bundled store passed `validate.py --store` with 705 dravyas,
1,511 recipes, the exact placeholder band 900001–900376, and mapping SHA
`bc7afbfce...36441b`.

A second whole-app deletion followed by installing the normally built product
produced this fresh-launch evidence:

```text
✅ Successfully prepared pre-seeded MAIN database.
✅ Large bundled assets are ready.
   ✅ Ayurveda v6 preseed stamp verified; no inserts or updates.
✅ SearchIndexStore: Index is up-to-date (version: 7, DB: 14488). Skipping rebuild.
✅ Seeding process completed.
```

- GF1: pass — full store validation succeeded.
- GF2: pass — all target counts above match exactly.
- GF3: pass — fresh install performed zero Ayurveda inserts/updates and no
  search-index rebuild.
- GF4: pass — exact placeholder band and mapping SHA retained.
- GF5: pass — all 25 production search goldens and both Sanskrit synonym cases
  are exact; the complete repository suite passed 161/161 after the reseed.
- GF6: pass — all 11 formerly frameless recipes resolved through the app's
  exact-timestamp `AVAssetImageGenerator` path at 144, 480, and 1024: 33/33
  successful frame extractions.
- Debug and Release simulator builds both succeeded with the rebuilt preseed
  and required-asset guard enabled.

### Phase G — same-session cold launch

The comparison used the retained iPhone 17 Pro iOS 26.2 simulator. A was the
pre-batch tip `8ba4099`; B was the pushed JOB4 tip `768354f`. Both were arm64
Debug builds with the same build settings, separate bundle IDs and containers,
identical calendar/reminder permissions, and an untimed fresh plus warm setup.
No Xcode, `xcodebuild`, Swift compiler, Maestro, Blender, or Spotlight work was
active; Spotlight measured 0.0% CPU and system-wide free memory was 84%.

Host `time.monotonic()` was captured immediately before
`simctl launch --console-pty`, and the terminal event was
`AYURA_PROFILE|first-interactive-frame|...`. Each process was terminated before
the next launch. Order was strict AB repeated ten times. Every accepted launch
emitted the Ayurveda version skip and search-cache `Skipping rebuild` line.

One earlier attempted series was discarded in full: pair 8B emitted
`root-view-appeared` but no terminal `first-interactive-frame` marker. None of
its samples enter this table.

| Pair | A `8ba4099` | B `768354f` | B − A |
| ---: | ---: | ---: | ---: |
| 1 | 1.397948s | 1.379781s | −0.018167s |
| 2 | 1.380127s | 1.391588s | +0.011461s |
| 3 | 1.392522s | 1.396792s | +0.004270s |
| 4 | 1.397177s | 1.393859s | −0.003317s |
| 5 | 1.411310s | 1.398863s | −0.012447s |
| 6 | 1.378527s | 1.396514s | +0.017987s |
| 7 | 1.402408s | 1.365718s | −0.036689s |
| 8 | 1.396650s | 1.389624s | −0.007026s |
| 9 | 1.413169s | 1.407776s | −0.005393s |
| 10 | 1.388324s | 1.382990s | −0.005334s |

| Series | N | Median | IQR (Q1–Q3) | Min | Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| A `8ba4099` | 10 | **1.396913s** | 0.011919s (1.389373–1.401293) | 1.378527s | 1.413169s |
| B `768354f` | 10 | **1.392724s** | 0.012074s (1.384648–1.396722) | 1.365718s | 1.407776s |
| Paired delta | 10 | **−0.005364s** | 0.013465s (−0.011092–0.002373) | −0.036689s | +0.017987s |

The candidate median is below both the 1.650s profiling-paydown trigger and the
1.700s hard ceiling. The paired delta is smaller than both arm IQRs, so no
launch change is resolvable from this sample.

### Phase H — corrected §5 registry table

Every value below was measured from the current source, shipped JSON/gzip
artifacts, reconstructed SQLite store, media files, or the accepted Phase G
series. Historical milestone/performance rows in §5 are not reinterpreted;
they remain explicitly historical. The current-state portion of §5 is:

| Thing | Measured value |
| --- | --- |
| Dravyas / recipes / profiles | 705 / 1,511 / 2,216 |
| AyurvedaLink rows (v6 seed) | 2,336 = 306 exact + 64 near + 1,966 derived |
| Tier coverage | classical 370 · derived 1,966 · estimated 10,265 = 12,601 |
| Placeholder FoodItems | 376, exact band 900001–900376 |
| Post-seed ZFOODITEM total | 14,488 = 12,601 USDA + 376 placeholders + 1,511 recipes |
| Category rules / modifiers | 187 / 14; modifiers fire on 6,351 of the 12,231 non-classical foods |
| Crosswalk | 1,966 rows · 164 distinct dravyas · 59 contested rows, each with recorded loser(s) · 2 curated denies |
| Recipe nutrition | 1,508 full · 3 estimated · 0 none · 39-field schema on per-serving and per-100g bases. Gond Ladoo is missing `dravya.acacia-gum` composition; Sol Kadhi is missing `dravya.kokum`; Ugadi Pachadi is missing `dravya.neem-flower` |
| Recipe IngredientLinks | 10,644 positive-gram rows · 1,511 owners |
| Safety projection | 2,216 review-required rows · 155 allergen dravyas · 1,190 allergen recipes · 754 Vegan recipes |
| Age provenance | dravyas 391 authored / 314 legacyImport · recipes 1,457 / 54 · ingredient contributors 4,957 / 5,687 |
| Search cache | v7 · 14,488 DB/compact rows · 4,223 metadata/faceted rows = 2,216 direct + 2,007 linked-only · 89 keys · 59,114 assignments |
| Seed / rules | seed v6, SHA `7687498a8012aa6e14b71781fe9721ab2d7b968005618ace9dc6e09a0fe50f3f`; rules SHA `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` |
| Preseed v7 | `aa` SHA `e7b2fb2c9a3e03e3a76247a6988e5e9b033a4a2e95f89ad389a08d15d0e15d11` · `ab` SHA `89b06ea707d798e20756098c0cd6f83f273c798bf12cb034b42bcc20dba9ed2b` · restored store SHA `a6ddf152234fee2b12c9d9efcdffb70c3d01fdc4d4980418a46686b2f57d25a0` |
| Food concepts | artifact v1 / rev5 matching semantics · 25 concepts · 75 aliases · 14,488 catalogue rows · 32,166 bytes · SHA `a90d8dd82ce36bfd967e1f698e502dda6fef9e072e64d90a9f7a7ec7ba398cba` |
| Food roles | rev9 · 15 roles / 34 rules · 14,488 rows · plain USDA: 108 `other`, 543 ineligible, 304 not-ready · recipe anchors 1,043/1,511 · prohibited recipe roles 0 |
| Imagery master | 1,877 jobs · 293 reviewed reuses · 26 reviewed denials · styleHash `c8d83786a68f` |
| Unified food archive | 14,477 encoded frames · 14,465 catalogue-addressed indices · 23 extra catalogue references share an addressed frame · 12 inventoried retained orphans · 14,488/14,488 catalogue entries resolve |
| Archive sizes | 144: 43,591,000 bytes · 480: 85,383,373 bytes · restored 1024: 351,950,638 bytes in five parts · 14,477 packets each · zero B-frames |
| Archive map identity | frame map SHA `b0fffc11279025e7e5e95606e0954357ba942ebbb202635e49d8ca4b3d80ca85` · timestamps SHA `d3666f4a56036440f7922e1af59ae9641f1e77ed112c70b89adc616ec11c6d34` |
| JOB4 regression | 161/161 tests · 25+2 search goldens exact · Debug and Release builds pass · fresh install zero Ayurveda inserts/updates and no index rebuild |
| JOB4 cold launch | candidate 1.392724s median, IQR 0.012074s, min 1.365718s, max 1.407776s; `8ba4099` median 1.396913s; paired median −0.005364s; N=10 same-session AB |

Commit `8e659b8` changed the core §5 rows during Phase B, before the Phase H
director gate. Its intermediate preseed hashes and stale 14,484 concept/role
rows are corrected forward in the normal follow-up commit that records this
report. History is not rewritten.
