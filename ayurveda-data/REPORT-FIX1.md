# FIX-1 — Food video frame-key lookup

Date: 2026-07-28

Branch: `ayurveda-app`

Base: `281599b`

## Outcome

FIX-1 passes all five gates. `FoodVideoSource` now attempts the raw catalogue
name first, then replaces exactly the filename-unsafe characters
`/ \ : * ? " < > |` with `_` for a second lookup. `%` is deliberately
unchanged.

The same lookup path is used by `hasVideo(for:)`, frame extraction, and
`availableFoodKeys`. Neither `frame_map.json` nor any video archive changed.
The gitignored `food_archive_1024.mp4` remains untouched.

## Gate summary

| Gate | Actual | Result |
|---|---:|---|
| F1 — catalogue rows resolving | **12,601 / 12,601** | pass |
| F2 — shifted prior raw mappings | **0 / 11,192** | pass |
| F2 — shifted prior slash-plus-percent-guess mappings | **0 / 11,578** | pass |
| F2 — shifted existing `FoodItem.foodImage` fetch mappings | **0 / 12,601** | pass |
| F3 — distinct resolved indices | **12,601 / 12,601** | pass |
| F4 — newly resolving rows rendering an image | **10 / 10** | pass |
| F5 — full Python regression | **150 / 150** in 696.240 s | pass |
| F5 — MP-7 real-catalogue plans | **30 / 30**, identical ledger | pass |
| Debug app build | `BUILD SUCCEEDED` | pass |
| Optimized Release app build | `BUILD SUCCEEDED` | pass |

## F1–F3 — exhaustive lookup audit

The permanent gate is
`ayurveda-data/tests/validate_fix1_video_lookup.py`. It reads the shipped
12,601-row catalogue and 12,601-entry frame map, applies the production lookup
order, and asserts coverage, mapping stability, and index uniqueness.

Measured results:

- raw dictionary hits before FIX-1: **11,192**;
- raw-first `/` plus `%` guess hits: **11,578**;
- rows newly resolved relative to that guess: **1,023**;
- existing `FoodItem.foodImage` sanitized-fetch mappings: **12,601**;
- final raw-first plus exact filename-unsafe normalization: **12,601**;
- shifted indices in any of the three prior-resolving populations: **0**; and
- final distinct index count: **12,601**.

The raw-first branch is load-bearing. It guarantees that a name already
present verbatim in `frame_map.json` cannot be redirected by normalization.
The test also asserts that the raw access precedes the normalized access in
the Swift source.

The packet's 1,023 figure is reproduced exactly against the documented
slash-plus-percent guess. The direct pre-fix `hasVideo(for:)` implementation
was stricter still because it performed only a raw dictionary hit; the fix
closes both populations without shifting either.

## F4 — production-source UI spot-check

A focused UIKit simulator harness compiled the production
`FoodVideoSource.swift`, loaded the shipped `frame_map.json`,
`frame_timestamps.json`, and `food_archive_144.mp4`, and requested frames with
the raw catalogue names. This bypassed only the full app's unrelated
database-preparation screen; it did not duplicate or replace the lookup or
frame-extraction implementation.

The harness displayed a two-column grid with the final summary:

`FIX-1 UI spot check: 10/10 images rendered`

| Food ID | Family | Expected frame | UI |
|---:|---|---:|---|
| 90 | Hot chocolate / cocoa | 11,194 | image rendered |
| 91 | Hot chocolate / cocoa | 11,651 | image rendered |
| 99 | Hot chocolate / cocoa | 11,972 | image rendered |
| 100 | Hot chocolate / cocoa | 11,762 | image rendered |
| 104 | Hot chocolate / cocoa | 12,514 | image rendered |
| 6,148 | porterhouse, `1/8" fat` | 11,125 | image rendered |
| 6,149 | t-bone, `1/8" fat` | 2,840 | image rendered |
| 6,150 | t-bone, `1/8" fat` | 436 | image rendered |
| 6,167 | porterhouse, `1/8" fat` | 10,943 | image rendered |
| 6,170 | porterhouse, `1/8" fat` | 12,128 | image rendered |

The reproducible harness and its bundle metadata are:

- `ayurveda-data/tests/FIX1VideoSpotCheckApp.swift`
- `ayurveda-data/tests/FIX1VideoSpotCheckInfo.plist`

All ten cards displayed non-empty food imagery and the expected catalogue ID
and frame index.

## F5 — regression and MP-7 no-movement proof

The complete repository suite finished:

```text
Ran 150 tests in 696.240s
OK
```

That run includes the MP-7 role artifact, role fixtures, C1–C10, all 30 hard
properties, all 16 measured soft properties, P7/P8 reachability, P10 honest
infeasibility, resolution and exclusion corpora, search goldens, narration
determinism, the two-call total, and fresh-preseed assertions.

A separate optimized real-catalogue run then regenerated all 30 canonical
plans over 13,993 candidates:

| Evidence | MP-7 registry | FIX-1 rerun |
|---|---|---|
| Plans produced | 30 / 30 | **30 / 30** |
| Ordered profile/horizon/hash ledger SHA-256 | `542c8524e27fddd3322cf694ebc0cb08a4194bfb6cf9fe3b291718b355282de0` | **identical** |
| P7 daily energy | 1,200 kcal | **1,200 kcal** |
| P8 daily energy | 3,600 kcal | **3,600 kcal** |
| P8 seven-day plan SHA-256 | `e9e623f8944d368ea5ec0bb50e9cc47ebf5f76795886e765f6b259f23bca5aea` | **identical** |
| Y1 mean delta | +1.550713 | **+1.550713** |

No MP-7 plan, constraint result, or Ayurvedic selection signal moved.

## Scope audit

Changed:

- centralized lookup behavior in `FoodVideoSource.swift`;
- one exhaustive data/source validator;
- one focused, reproducible UI spot-check harness; and
- this report plus the director-delivered task/status records.

Not changed:

- `frame_map.json`;
- `frame_timestamps.json`;
- every food video archive, including the gitignored 285,519,148-byte
  `food_archive_1024.mp4`;
- `ayurveda-data/imagery/`; and
- `ayurveda-data/tools/ref_resolve.py`.
