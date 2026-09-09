# INT-1 — Branch integration report

**Date:** 2026-07-26

**Target branch:** `ayurveda-app`

**Baseline:** `f46a107`

**Status:** **PASS — all authorized simulator/host gates green; physical-device
evidence remains explicitly deferred.**

## Executive result

The MP and food-concept histories are integrated without rebasing, squashing,
or rewriting any task commit:

1. `ec3cb7c` merges `mp-3-deterministic-resolution` at `e7e9409`, bringing
   MP-1 (`4b8307f`), MP-2 (`24ac931`), MP-3 (`fc2d835`), MP-3b (`348d8fc`),
   and MP-3c (`e7e9409`).
2. `18be042` merges `fc-1-food-concepts` at `70f75ce`, retaining both FC-1
   commits (`771eccd`, `70f75ce`).
3. `01ae3e0` is the bounded INT-1 launch paydown required by the handbook's
   1.650s profiling trigger.

The integrated suite is **95/95**, the resolution and exclusion corpora retain
their exact branch-local results, rebuilt artifacts are byte-reproducible,
fresh install performs zero Ayurveda inserts and no search-index rebuild, and
final cold launch is **1.461324s median**.

## Merge audit

### Conflicts

Git reported **no textual merge conflicts** in either merge.

- The Xcode project uses a `PBXFileSystemSynchronizedRootGroup`, so
  `PlannerTelemetry.swift` and `FoodConcepts.swift` entered the target through
  the synchronized tree without manual `.pbxproj` edits.
- `build_seed.py` was changed only by FC-1, as expected.
- Both histories carried the corrected resolution holdout, but the merged blob
  was identical; no intent choice was required.
- The rebuilt seed pipeline has three outputs. The canonical Ayurveda seed
  remains unchanged because concept membership is deliberately emitted as the
  separate `food_concepts.json.gz` resource. The preseed store was nevertheless
  re-audited, vacuumed, recompressed, and replaced rather than retaining stale
  physical bytes.

No conflict required a behavior decision.

## Gate ledger

| Gate | Result | Evidence |
|---|---|---|
| INT1-G1 Debug + Release | **PASS** | From-empty generic-simulator Debug and Release builds passed before the bounded paydown; post-paydown Debug and Release rebuilds passed. `f46a107` has 46 normalized warning messages; final Debug/Release have 45, with zero additions and one pre-existing unused-`head` warning removed. |
| INT1-G2 full suite | **PASS — 95/95** | Final discovery run: 95 tests, 95.221s. Reconciliation below. |
| INT1-G3 search goldens | **PASS — 25/25 + 2/2 exact** | The production legacy and negative-safety golden assertions run in the full suite; no baseline was changed. |
| INT1-G4 validator | **PASS** | Classical 336 + derived 1,969 + estimated 10,296 = 12,601; 714 dravyas and 1,500 recipes; all checks passed against the rebuilt preseed. |
| INT1-G5 deterministic artifacts | **PASS** | Two complete seed builds and two complete preseed builds from byte-identical source stores reproduced byte-for-byte. SHAs below. |
| INT1-G6 fresh install | **PASS** | `Ayurveda v5 preseed stamp verified; no inserts or updates.` Search cache version 5 / DB 14,484: `Skipping rebuild.` |
| INT1-G7 cold launch | **PASS — 1.461324s median** | Final same-session ABAB N=10 against `f46a107`; paired median −0.195318s. Under the 1.650s paydown trigger and 1.700s hard ceiling. |
| INT1-G8 resolution corpora | **PASS — 59/59 expectations; 40/48 held-out** | Training: 56/56 positive cases plus 3/3 unresolved controls. Held-out: 40 pass, 8 honestly unresolved, 0 wrong-confident; all 5 controls unresolved. |
| INT1-G9 exclusion corpus | **PASS — exact FC-1b values** | Non-contested must-exclude 61/75 pass, 14 unresolved, 0 fail. Must-not-exclude 26/34 pass, 8 unresolved, 0 fail. Eight contested cases remain separately non-blocking. |

## Combined-test reconciliation

The branch-local totals overlap; they are not additive:

| Component | Tests |
|---|---:|
| Shared pre-MP/FC base | 62 |
| MP-only additions | 23 |
| FC-1-only additions | 9 |
| **Merged suite before INT paydown** | **94** |
| INT-1 warm-version-check regression | 1 |
| **Final integrated suite** | **95** |

Therefore:

- MP branch: 62 shared + 23 MP = **85**.
- FC branch: 62 shared + 9 FC = **71**.
- Integrated: 62 shared + 23 MP + 9 FC + 1 INT = **95**.

No test disappeared and the total reconciles exactly.

## Artifact rebuild and determinism

The seed builds used a 12,601-ID USDA source projection. The preseed builds
used separate byte-identical copies of the completed 14,484-row store, then
audited, vacuumed, deterministically gzipped, and split each copy.

| Artifact | Build A SHA-256 | Build B SHA-256 | Shipped result |
|---|---|---|---|
| `ayurveda_seed.json.gz` | `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` | same | byte-identical; unchanged by design |
| `ayurveda_rules.json` | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` | same | byte-identical |
| `food_concepts.json.gz` | `44716a1990817318c837ef98103e2a3785745a15d27adc6a372a80e4846c6111` | same | byte-identical; 29,740 bytes |
| `preseeded_db.store.gz.part-aa` | `99a977616c554f3e67d683de045b11bf2a2dd6567f41702d71cc5788f42bb817` | same | byte-identical; 73,400,320 bytes |
| `preseeded_db.store.gz.part-ab` | `f6b0cd508ccd2a5d2e343ce87b166e6f72df75b3b24f5eda528d08cb1e0b291c` | same | byte-identical; 19,162,561 bytes |

The completed-store audit remains 14,484 foods, 2,214 profiles, 2,305 links,
10,571 IngredientLinks / 1,500 owners, cache version 5, 14,484 compact foods,
2,214 faceted rows, 64 facet keys, and 20,114 assignments.

## Cold launch and required paydown

### Method

- Retained iOS 26.2 simulator `WiseEating-WE2-Baseline`
  (`AF937668-3BFE-45E8-B42A-A76B914038DD`); exactly one booted device.
- A = frozen `f46a107`; B = integrated `ayurveda-app`.
- Both were arm64 Debug apps with separate bundle IDs/containers and the same
  ignored 285,519,148-byte `food_archive_1024.mp4`.
- Each app received untimed fresh/warm setup and calendar permission before
  measurement. Fresh B proved zero insert/update and no rebuild.
- Xcode, `xcodebuild`, Swift compilers, Maestro, and CI were absent. Chrome,
  Claude, and CleanMyMac processes were suspended and restored around each
  accepted series. Spotlight workers were 0.0% for the first accepted series
  and 0.1% aggregate for the final series; host free memory was 86% and 81%.
- Host `time.monotonic()` was captured before `simctl launch --console-pty`.
  Terminal marker: `WE6_PROFILE|first-interactive-frame|<uptime>`. Every app
  was terminated before every sample. Order was strict AB repeated ten times.
- One attempted post-paydown series was interrupted after three pairs and
  discarded because its preflight showed Spotlight at 26.7% CPU and free
  memory at 49%. None of those contended values enter a table or gate.

### Initial integrated measurement

| Series | N | Median | IQR | Min | Max | Population stddev |
|---|---:|---:|---:|---:|---:|---:|
| `f46a107` | 10 | 1.692478s | 0.026358s | 1.641067s | 1.715649s | 0.022463s |
| Integrated before paydown | 10 | **1.697238s** | 0.051576s | 1.617185s | 1.745192s | 0.036930s |
| Paired delta | 10 | +0.011873s | 0.054603s | −0.083524s | +0.075008s | 0.046269s |

The candidate remained under the 1.700s hard ceiling, and its delta was smaller
than both series' IQRs, so no integration regression was resolvable. Its median
nevertheless exceeded 1.650s and correctly triggered same-task profiling.

Signposts identified the largest bounded warm-path cost: both revisions spent
about 0.228s decoding all 2,214 seed records merely to read `seedVersion`.
`01ae3e0` keeps the same compressed bundle and full decoder for real seed work,
but the version check decodes only `AyurvedaSeedVersionDTO`.

### Final post-paydown raw pairs

| Pair | `f46a107` A | Integrated B | B − A |
|---:|---:|---:|---:|
| 1 | 2.712791s | 1.575848s | −1.136942s |
| 2 | 1.736120s | 1.453753s | −0.282367s |
| 3 | 1.637515s | 1.476736s | −0.160780s |
| 4 | 1.734297s | 1.540388s | −0.193909s |
| 5 | 1.694324s | 1.496777s | −0.197547s |
| 6 | 1.659795s | 1.463615s | −0.196180s |
| 7 | 1.647778s | 1.439969s | −0.207809s |
| 8 | 1.640015s | 1.459033s | −0.180982s |
| 9 | 1.623284s | 1.428828s | −0.194456s |
| 10 | 1.624501s | 1.436438s | −0.188062s |

| Series | N | Median | IQR | Min | Max | Population stddev |
|---|---:|---:|---:|---:|---:|---:|
| `f46a107` | 10 | 1.653787s | 0.086164s | 1.623284s | 2.712791s | 0.316421s |
| Integrated final | 10 | **1.461324s** | 0.048351s | 1.428828s | 1.575848s | 0.045343s |
| Paired delta | 10 | **−0.195318s** | 0.015719s | −1.136942s | −0.160780s | 0.282605s |

The baseline's first sample is retained, not trimmed. Median is the registered
gate statistic. The warm Ayurveda check fell from a 0.226336s baseline median
to 0.043991s; total seed checks fell from 0.249819s to 0.068091s. All 20 final
runs emitted the first-interactive marker, seed-version skip, and search-cache
`Skipping rebuild` line.

## Explicitly deferred physical-device evidence

The durable registry is `ayurveda-data/DEFERRED-VALIDATION.md`. It records:

- MP-1 nine-run device matrix, G6 plan-identical comparison, and G8 device
  launch;
- MP-2 twenty-food AI-vs-USDA error table and G7 runtime telemetry counts;
- MP-3 G8 runtime zero-model-call confirmation.

Each entry records what it proves, exact commit endpoints, and why simulator
evidence cannot substitute. MP-1 G6 remains measurable because both `f46a107`
and `4b8307f` persist in the merged history.

## Final scope

No branch commit was rebased, squashed, or rewritten. No golden baseline,
resolver behavior, ontology artifact, FoodSearch ranking, lifecycle rule, or
Ayurvedic claim boundary changed during integration. The only post-merge source
change is the measured warm seed-version decode paydown in `01ae3e0`.
