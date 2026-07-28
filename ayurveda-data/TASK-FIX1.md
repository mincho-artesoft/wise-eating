# TASK FIX-1 / PERF-1

Director packet · 2026-07-27 · branch `ayurveda-app`, base = `dcaf751` (MP-7 complete)
Two small independent tasks. Neither blocks the `MP5AyurvedicSolverEnabled` flag.

---

## FIX-1 — 1,023 rows have an image they cannot find

`WiseEating/Food/FoodVideoSource.swift` looks up frames with a raw dictionary hit:

```swift
func hasVideo(for foodName: String) -> Bool {
    return frameMap[foodName] != nil
}
```

`frame_map.json` was built from **filenames**, so its keys carry the filesystem-unsafe characters replaced by `_`. The catalogue names do not. Every row whose name contains `/` or `"` therefore fails the lookup and shows no image — while its frame sits in `food_archive_1024.mp4`, shipping, paid for, and unreachable.

### Measured

`foods.json` and `frame_map.json` both hold **12,601** entries. Matching by raw name plus the current `/`→`_`, `%`→`_` guess leaves **1,023 unmatched on both sides** — 1,023 rows with no key, and exactly 1,023 keys no row claims. They are the same rows.

The rule is the filesystem-unsafe set, and `%` is **not** part of it:

| Normalisation | Unmatched rows |
|---|---:|
| raw name only | 1,023 |
| `/` → `_`, `%` → `_` *(what we assumed)* | **1,023** |
| `/` → `_` | 962 |
| `/` and `"` → `_` | 1 |
| `/ \ : * ? " < > \|` → `_` | **0** |

Worked examples:

```
row  Hot chocolate / cocoa, made with lowfat (1%) or fat free (skim) milk
key  Hot chocolate _ cocoa, made with lowfat (1%) or fat free (skim) milk
                  ^ slash                       ^ percent survives

row  Beef, top sirloin, steak, ... trimmed to 1/8" fat, ...
key  Beef, top sirloin, steak, ... trimmed to 1_8_ fat, ...
                                                ^ ^ slash and double-quote
```

Replacing `%` is what broke it: it corrupted names that were already correct.

### Do

Normalise the key on lookup in `FoodVideoSource`, applied consistently in `hasVideo(for:)`, the frame fetch, and `availableFoodKeys`:

```swift
private static let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|")
private func frameKey(_ name: String) -> String {
    String(name.unicodeScalars.map { Self.unsafe.contains($0) ? "_" : Character($0) })
}
```

Try the raw name first and the normalised key second, so nothing that resolves today can regress.

Do **not** rebuild `frame_map.json`, re-encode any archive, or touch `food_archive_1024.mp4`. This is a lookup bug, not a data bug.

### Gates

| Gate | Requirement |
|---|---|
| **F1** | all **12,601** rows resolve to a frame index; report the count, it must be 12,601 |
| **F2** | every row that resolved *before* the change resolves to the **same index** after. A fix that shifts an existing mapping is a defect — it would silently repaint foods that were already correct |
| **F3** | no duplicate index collisions introduced: the resolved index set is still 12,601 distinct values |
| **F4** | a UI spot-check on 10 of the newly-resolving rows — pick from the `Hot chocolate / cocoa` and `1/8" fat` families — confirming an image now appears |
| **F5** | full regression green: 150/150, and no change to any MP-7 gate |

Stop and report if F1 lands below 12,601 or F2 shows a single shifted mapping.

---

## PERF-1 — freeze the ceiling on the slowest supported device

MP-7's G7 numbers are from **iPhone 16 Pro**. The slowest device that can run this feature is **iPhone 15 Pro** — 15 and 15 Plus are A16 and have no Apple Intelligence at all — and A17 Pro is roughly 15–20% slower.

Repeat the G7 arms on an iPhone 15 Pro, same method as MP-7: signed Release build, quiesced host, N≥10, strict ABAB for launch and memory, monotonic timing around `solve`.

| Metric | Provisional ceiling | iPhone 16 Pro measured |
|---|---:|---:|
| 7-day solve | ≤ 1,200 ms | 642 median / 960 max |
| role resolution, cold | ≤ 100 ms | 44.7 |
| role resolution, cached | ≤ 5 ms | 1.09 |
| cold launch | ≤ 1.700 s | 1.090 |
| peak memory | ≤ +90 MB | +10.3 MiB |

Expect roughly 1.15 s max solve on the 15 Pro. **If anything exceeds its ceiling, report the number and stop — do not optimise to hit it.** The ceiling exists to catch regression, not to be met; I set 150 ms once from a synthetic harness and it cost a full stop cycle. The final ceiling gets set from whatever the 15 Pro actually does.

If no iPhone 15 Pro is available, say so and mark PERF-1 not-run rather than substituting a 16 Pro or simulator number.

---

## Order and protocol

FIX-1 first — it is self-contained and has real user-visible value. PERF-1 needs hardware and can wait for it.

One commit per task, prefix `FIX-1:` / `PERF-1:`. Branch `ayurveda-app`, no force-push, no GitHub Actions, `main` untouched. Report every gate with its measured number. Stop and report on failure; never fix a gate by loosening it.

Out of scope, do not touch: the imagery working tree under `ayurveda-data/imagery/`, `ayurveda-data/tools/ref_resolve.py`, and the gitignored `food_archive_1024.mp4`.
