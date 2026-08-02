# JOB4 regeneration report

This report records the measured inputs, retained exceptions, regenerated
artifacts, and release gates for the one-time JOB4 shipped-artifact rebuild.

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

Phase F, Phase G, and the proposed Phase H registry table follow below.
