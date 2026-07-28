# IMG — imagery for the 1,845 rows without an image

Director packet · 2026-07-27 · runs in parallel with MP-7, touches nothing the solver uses.

---

## What this covers

The catalogue has 14,484 rows and `frame_map.json` has 12,601 entries. The gap is **2,168**, not the 1,883 I quoted earlier: 1,500 authored recipes and 668 dravyas.

**323 of those 668 dravyas need no generation at all.** Their `usda[]` link already points at a name that is in `frame_map` at tier `exact` — Ghee → "Ghee, clarified butter", Turmeric → "Spices, turmeric, ground", Mung bean → "Mung beans, mature seeds, raw". That is a lookup, not a render. `build_batches.py` writes them to `reuse-map.json` and excludes them from the queue.

**Generation set: 1,845** — 1,500 recipes + 345 dravyas, at 100 per batch, 19 batches.

There is also a **separate free win worth doing first**: `foods.json` and `frame_map.json` both hold 12,601 entries, but only 11,578 names match even after sanitising `/` and `%` to `_`. About **1,023 rows already have an image in the shipping archive and cannot find it.** That is a key-matching bug, not a missing asset, and it is more coverage than a third of this whole generation run. Fix it before spending a credit.

---

## Style

The prompt suffix is copied **verbatim** from `gemini-food-stylist/App.tsx`, the Michelin 5-star block that produced the existing 12,601 frames. Do not paraphrase it. The new images have to sit beside the old ones in the same grid without reading as a second set, and the fastest way to lose that is a reworded style clause.

`tools/style-reference.png` in this repo is four frames pulled straight out of `food_archive_1024.mp4` — tangerines, sirloin, lentil soup, dried lime leaf — as the visual acceptance target.

Every job is 1:1, and `validate_batch.py` enforces ≥1024×1024 square, so frames drop into the archive without rescaling.

---

## The four scripts

```
build_batches.py     catalogue + frame_map  ->  queue/batch-001.json … batch-019.json
runner.js            queue/  ->  bridge  ->  images on disk, batch moved to done/ or failed/
validate_batch.py    images  ->  accepted/batch-NNN.json
build_archive2.py    accepted/  ->  dist/food_archive2_*.mp4 + frame_map2.json
```

Nothing in the chain makes a judgement call. The prompt, the filename and the settings all come out of the batch file; the runner submits them in order; the validator applies fixed numeric thresholds.

### 1. Build the queue

```bash
cd ayurveda-data/imagery
python3 build_batches.py --repo /Users/minchomilev/work/wise-eating
```

### 2. Run one batch

Start the bridge and open an authenticated Flow tab, then:

```bash
node bridge/server.js                        # in the chrome plugin folder
node runner.js --out ~/wise-eating-images --once
```

The runner is **serial on purpose**. Flow is a single authenticated tab driven through the DOM; parallel submissions interleave and the downloads come back attached to the wrong food. It logs every job to `runner.log`, writes `results/batch-NNN-results.json`, and moves the batch to `done/` or `failed/`.

Without `--auto` it stops after one batch and tells you to validate. That is the checkpoint you asked for.

### 3. Validate before the next batch

```bash
python3 validate_batch.py --batch 1 --images ~/wise-eating-images
```

Five checks, in order of how badly each one bites:

| Check | Catches |
|---|---|
| planned filename exists | a job that silently produced nothing |
| decodes, square, ≥1024 | wrong geometry |
| stddev ≥ 8 | Flow returned a grey card |
| perceptual hash unique, within the batch **and against every previously accepted image** | the same picture served for two different foods |
| corner mean ≥150, sd ≤18 | style drift — a dark or busy background |

The duplicate check is the one that matters most at this scale. With 1,845 renders, the failure you will actually hit is not a bad image, it is the same image quietly attached to four different kitcharis.

Exit code is non-zero if anything failed. **Do not lower a threshold to make a batch pass** — re-queue the row with a better subject clause, or accept the gap and let that row keep its placeholder.

### 4. Build the second archive

```bash
python3 build_archive2.py --repo /Users/minchomilev/work/wise-eating
```

---

## Why a second archive

`food_archive_1024.mp4` is 285 MB, gitignored, and has exactly one copy that is not reproducible at original quality from anything checked in. `food_archive_480.mp4` **is** git-tracked at 82.7 MB — 7 MB under your 90 MB limit — so appending 1,845 frames to it would breach that gate on its own.

So: never touch either. Write `food_archive2_<variant>.mp4` and `frame_map2.json` alongside, and have `FoodVideoSource` resolve in three steps — map 1, then map 2, then `reuse-map.json`. `build_archive2.py` refuses to run if any new `frameKey` already exists in map 1, because a duplicate key would silently shadow the original frame.

Encoder settings are copied verbatim from your `generate_video_with_map.py`: libx265, crf 24, `hvc1`, `keyint=30:min-keyint=30`, `-vsync 0`, `-bf 0`. The last two are load-bearing — B-frames break the strictly linear frame order the iOS seek depends on. The build also aborts if the ffprobe timestamp count and the image count disagree, because that mismatch shows up as the app serving the wrong food rather than as a crash.

---

## Suggested order

1. **Back up `food_archive_1024.mp4`.** Still one copy. Unrelated to this work and still the only irreversible item on the board.
2. Fix the ~1,023 unmatched `frame_map` keys. Free coverage.
3. Wire the 323-row `reuse-map.json` fallback into `FoodVideoSource`.
4. Batch 1 of 100 → validate → look at the images against `style-reference.png`.
5. If batch 1 holds up, continue. If the style has drifted, fix the subject clause before batch 2, not after batch 19.
