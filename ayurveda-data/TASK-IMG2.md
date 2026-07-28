# TASK IMG-2 — make the generated images reachable from the app

Director packet · 2026-07-27 · branch `ayurveda-app`, base = `5af9b91`

Deliberately independent of how many images exist. Build the resolution path now, against whatever has been generated, and every later batch drops in with a rebuild. Do not wait for all 1,844.

---

## 1. Where images live after this

Three sources, resolved in order:

| Order | Source | Covers | State |
|---|---|---:|---|
| 1 | `frame_map.json` + `food_archive_<v>.mp4` | 12,601 USDA rows | shipping, untouched |
| 2 | `frame_map2.json` + `food_archive2_<v>.mp4` | generated recipes and dravyas | **new** |
| 3 | `reuse-map.json` | **324** dravyas that point at an existing USDA frame | **new** |

Source 3 is the cheap one and worth doing first: 324 dravyas already have a perfectly good picture sitting in archive 1 because their `usda[]` link resolves to a name in `frame_map` at tier `exact` — Ghee → "Ghee, clarified butter", Turmeric → "Spices, turmeric, ground", Mung bean → "Mung beans, mature seeds, raw". No generation, no new bytes, ~324 rows gain imagery from a lookup.

**Never touch `food_archive_1024.mp4`.** 285 MB, gitignored, one copy, not reproducible at original quality. Archive 2 is a separate file precisely so archive 1 is never re-encoded.

---

## 2. Do

### IMG-2a — three-tier resolution in `FoodVideoSource`

Extend the lookup to try, in order: map 1 (with the FIX-1 normalisation already in place) → `reuse-map.json` → map 2. Each tier needs its own `AVAssetImageGenerator` for archive 2, cached the same way archive 1's is.

`hasVideo(for:)`, the frame fetch and `availableFoodKeys` must all use the same resolution, or the UI will offer an image it cannot then produce.

Resolution must be **deterministic and total**: a given name always resolves to the same tier and index, and a name resolving in more than one tier always takes the lowest-numbered tier.

### IMG-2b — build archive 2 from whatever is accepted

`ayurveda-data/imagery/build_archive2.py` already does this. Run it, ship its output, and read its guardrails rather than reimplementing them:

- it refuses if any new `frameKey` already exists in map 1, because a duplicate key would silently shadow the original frame;
- it aborts if the ffprobe timestamp count and the image count disagree, because that mismatch shows up as the app serving the *wrong food*, not as a crash;
- encoder settings are copied verbatim from the original `generate_video_with_map.py` — libx265, crf 24, `hvc1`, `keyint=30:min-keyint=30`, `-vsync 0`, `-bf 0`. The last two are load-bearing: B-frames break the strictly linear frame order the iOS seek depends on.

Sort order is by `frameKey`, so a rebuild with the same inputs produces byte-identical output.

### IMG-2c — rebuild is routine, not a migration

Every new batch of images means re-running `build_archive2.py` and shipping a new `food_archive2_*.mp4` **and** `frame_map2.json` **together**. Indices shift on every rebuild; the map and the archive are a matched pair and must never be shipped apart. Make that impossible to get wrong — same build step, same commit.

---

## 3. Gates

| Gate | Requirement |
|---|---|
| **I1** | all **324** `reuse-map.json` dravyas resolve to a frame, via tier 3 → tier 1 |
| **I2** | every image in archive 2 is reachable by its food name; report `accepted count == map2 count == resolvable count` |
| **I3** | zero keys shared between map 1 and map 2 — a collision means one food permanently shows another's picture |
| **I4** | frame count == timestamp count for **every** variant built |
| **I5** | no git-tracked file over 90 MB. `food_archive_480.mp4` is already 82.7 MB, so check the total, and gitignore the 1024 variant of archive 2 the way archive 1's is if it lands over |
| **I6** | **FIX-1 does not regress**: all 12,601 tier-1 rows still resolve to the *same* index as before |
| **I7** | launch and peak memory with two `AVAsset` generators instead of one, same ABAB method as MP-7, N≥10. Ceilings unchanged: ≤1.700 s, ≤ +90 MB |
| **I8** | 150/150 tests, Debug and Release |

Stop and report on I3 or I6 — both mean a food is showing the wrong picture, which is worse than showing none.

---

## 4. Expected sizes, so a surprise is visible

Archive 1 is 12,601 frames at 285 MB — about 22.6 KB per frame at 1024. Archive 2 at ~1,844 frames should land near **42 MB** at 1024, proportionally less at 480 and 144. Materially more than that means the encoder settings did not take, and the fix is the settings, not the gate.

---

## 5. Not in this task

**Re-rendering the whole catalogue.** The intention is eventually to regenerate imagery for all 14,484 items in one consistent style. That is a much larger piece of work — it retires archive 1, needs a fresh style decision, and needs the 285 MB original backed up first. IMG-2 deliberately builds the *mechanism* for a second archive so that when the time comes it is a data swap rather than a rewrite.

**Anything under `ayurveda-data/imagery/`** except running `build_archive2.py`. The generator, runner, loop and verification scripts are a working tree; leave them alone.

---

## 6. Queue after this

| Task | Blocked on |
|---|---|
| **PERF-1** | an iPhone 15 Pro — recorded not-run, correctly |
| **MP-5b** — N4 protein objective, Y5's three inverted midday cases | nothing; available now |
| **MP-1 / MP-2 / MP-3 deferred validation** — device call matrix, twenty-food AI-vs-USDA error table, runtime call counts | nothing; available now |
| **Vaidya review** | a practitioner, not an engineer. `VAIDYA-REVIEW.md` |

MP-5b is the natural companion to IMG-2 if there is capacity — it is pure tuning behind a flag that is still off.

---

## 7. Protocol

One commit per sub-task, prefix `IMG-2a:` etc. Branch `ayurveda-app`, no force-push, no GitHub Actions, `main` untouched. Report every gate with its measured number. Stop and report on failure; never fix a gate by loosening it.
