# TASK — address frames by food id, not by name

Director packet · 2026-07-30 · `ayurveda-data/`

---

## 1. Why

The addressing chain today is `FoodItem.name` → `sanitize()` → `frame_map.json`
→ index → timestamp → seek. The key is a human-readable string, so every
property of that string is a correctness risk. In one afternoon this cost:

- **29 unmatched frames.** `extra_images.zip` carries the UTF-8 flag bit on none
  of its 12,603 entries, so `zipfile` decodes names as cp437 per spec, and macOS
  writes them decomposed. cp437 recovery alone left 22 unmatched; cp437 **plus**
  NFC left 0.
- **Panchamrita**, one name held by both a dravya and a recipe. Two images were
  generated and only one is addressable, because one name has exactly one frame.
- **Six USDA row pairs** differing only in punctuation and spacing.
- **A stale `reuse-map.json`** in `Ayura/Food` silently serving old frames.

None of these are possible when the key is an integer.

The point is not that name matching disappears. It **moves from runtime to build
time**, where it happens once, against a full expected set, with an assertion
that fails loudly. `prepare_frames.py` stopping and printing 29 names is the
argument: a wrong frame slot does not produce one bad image, it shifts every
later frame by one. Runtime name lookup cannot fail that way — it fails
silently, one food at a time, and surfaces months later in a screenshot.

---

## 2. The trap: there are three id spaces

| space | range | who holds it |
|---|---|---|
| **DB `ZFOODITEM.ZID`** | 1–12601, 900001+ placeholders, 1000001+ recipes | `FoodItem.id` — what the app has at lookup time |
| gemini CSV id | 1–12622 | `foods_names_with_id.csv`, and `foods_index.csv` inherits it |
| `foods_index` new rows | 13001+ | assigned by `build_food_index.py --new-id-base` |

**Only 252 of 12,601 ids agree between the DB and the CSV.** Measured. Keying
frames on `foods_index.id` would give roughly 12,349 foods someone else's
picture — the same failure `build_food_index.py` already warns about for the
wrong CSV, at fifty times the scale.

**The map must be keyed on the DB `ZID`.** `foods_index.csv` does not carry it
today; adding it is step 3.1.

Second trap: the reserved bands move. Placeholder ids are assigned by ordinal,
so the merge that took 383 placeholders to 376 renumbered every one after the
first. **Build the id map after the database rebuild, and ship map and archive
as a matched pair.**

---

## 3. Work

### 3.1 `build_food_index.py` — add the DB id

Take `--store <preseeded .store>`, read `ZFOODITEM(ZID, ZNAME)`, and resolve each
row to a DB id by NFC-normalised name. Emit a new `db_id` column.

Refuse to write unless the resolution is a bijection over the rows it claims to
cover: every DB row matched exactly once, every index row matched exactly once,
no name matching two DB ids. Print the unmatched names on both sides — that
output is the whole value of doing this at build time.

Normalise with `unicodedata.normalize("NFC", ...)` on both sides before
comparing. That single call is what would have prevented 29 of today's 29.

### 3.2 `order_and_encode.py` — emit and embed the id map

After ordering, write `frame_index.json` as `{db_id: frame_index}` — 14,466
integer pairs, about 116 KB raw.

Then embed it in the container so map and archive cannot drift apart, which is
exactly the failure the stale `reuse-map.json` caused:

```
ffmpeg ... -i ffmeta.txt -map_metadata 1 ...
```

Measured at roughly **91 KB** in `udta`. It must go through an `ffmetadata` file
— passing it with `-metadata` on the command line exceeds `ARG_MAX` around 1 MB.
Keep `frame_index.json` shipped as well for now; the embedded copy is the
integrity check, not yet the source.

Do **not** add per-frame timed metadata. MP4 supports it, AVFoundation makes
reading it per seek expensive, and it buys nothing once the frame index is
already the addressing primitive.

### 3.3 Swift

`FoodVideoSource`: key the maps `[Int: Int]` instead of `[String: Int]`, and take
`getFrame(id:variant:)`. `FoodItem.foodImage(variant:)`: pass `self.id` instead
of the sanitised name — the three `replacingOccurrences` calls at
`FoodItem.swift:779-782` go away entirely, which is the point.

Delete in the same change: `frame_map2.json`, the `secondaryGenerators`
fallback, and the `reuseMap` lookup. The unified archive makes all three dead,
and leaving them is how the stale-map bug returns.

### 3.4 Obfuscation — set expectations

Asked for, and worth being straight about: encoding the names inside the
metadata makes a downloaded archive **inconvenient** to decode, not secure.
Anyone who can play the video can screenshot every frame, and the map ships
inside the app bundle regardless. Worth doing as friction; not worth describing
to anyone as protection.

---

## 4. Order of operations

1. Rebuild the database (`SeedManager` on an empty store — delete the whole app
   so `UserDefaults` goes with it, or the Ayurveda pass silently skips because
   `seedAyurvedaIfNeeded` gates on a stored seedVersion, not on the database).
2. `build_food_index.py --store <new store>` → `foods_index.csv` with `db_id`.
3. `order_and_encode.py` → archive + `frame_index.json` + embedded table.
4. Swift change, then delete the name-keyed path.

Steps 2 and 3 must both re-run after any step 1. That coupling is real and
should be a line in the README, not folklore.

---

## 5. Verification

- Bijection assertion in 3.1 passes with zero unmatched on both sides.
- `frame_index.json` has exactly 14,466 entries, all distinct, indices covering
  0…14465 with no gaps.
- Round-trip 200 random foods on device: `FoodItem.id` → frame → image, compared
  against the name-keyed result from the current build. **Any disagreement is a
  bug in the new map, not in the old one** — the old one is what shipped.
- Confirm the embedded `udta` table matches `frame_index.json` byte for byte
  after encoding.
