# REPORT WE-6 — Cold-launch profiling and bounded fix

Date: 2026-07-25
Branch: `ayurveda-app`
Status: **COMPLETE — 1.662s median cold launch; all local gates green**

## Summary

WE-6 measured the existing launch path before changing it, found one dominant
app-controlled cost, and applied one bounded fix:

- before: **3.405s median** from `simctl launch` to the first interactive frame;
- after: **1.662s median** over the same five-run method;
- delta: **−1.744s / −51.2%**;
- fix: stop decoding the 28 MB persisted FoodSearch index during every app
  launch; load the same version-checked cache when FoodSearch is first used;
- first on-demand index load plus tomato query: **1.691s**, then the established
  warm query latencies apply; and
- fresh install still reports **zero Ayurveda inserts/updates and no search
  rebuild**.

The target was met after the largest measured fix, so no additional launch-path
changes were attempted. There are no schema, architecture, content, lifecycle,
or claims changes.

Implementation commit: `a245b58` (`WE-6 defer search index load from launch path`).

## Measurement method

Environment:

- Mac host and iOS 26.2 simulator
  `AF937668-3BFE-45E8-B42A-A76B914038DD`
  (`WiseEating-WE2-Baseline`);
- Debug simulator build with `-uiTestNoAds`;
- app process terminated before every sample; simulator remained booted;
- existing preseeded app data retained for cold-process measurements;
- system Calendar permission resolved before sampling so an OS prompt could not
  block the app-controlled launch path; and
- five samples before and five after; the median is the gate metric.

`WE6LaunchProbe` emits Points of Interest signposts and monotonic timestamp
lines only when the `-we6LaunchProfile` launch argument is present. Host
`time.monotonic()` is recorded immediately before `simctl launch`; both clocks
use the same host uptime basis. The terminal event is dispatched on the next
main-queue turn after `RootView.onAppear`:

```text
WE6_PROFILE|first-interactive-frame|<system uptime>
```

The five raw totals were:

| Sample | Before | After |
|---:|---:|---:|
| 1 | 3.405s | 2.592s |
| 2 | 5.495s | 1.651s |
| 3 | 3.379s | 1.630s |
| 4 | 3.502s | 1.662s |
| 5 | 3.250s | 2.755s |
| **Median** | **3.405s** | **1.662s** |

All samples remain in the median. The long samples coincided with observed
unrelated host work, including the `oie-backups` Git remote at roughly 90–95%
CPU and WindowServer at roughly 60–80%. The clustered samples, rather than a
selected minimum, establish the repeatable app result.

### Reconciliation with the WE-2 4.34s baseline

WE-2 recorded **4.34s** from the host launch command to “cached index loaded.”
It did not have phase signposts and used index-ready, rather than the current
first-interactive-frame terminal event. WE-6 therefore re-established the
baseline before changing code, as required:

| Baseline bridge | Time |
|---|---:|
| Historical WE-2 host launch → cached index loaded | 4.340s |
| Current pre-fix host launch → first interactive frame | 3.405s |
| Environment/cache/terminal-definition shift | −0.935s |
| **Re-established WE-6 baseline** | **3.405s** |

The full historical 4.34s is accounted for by that measured bridge; its missing
phase detail is not retroactively fabricated. All before/after deltas below use
the internally comparable WE-6 series.

## Phase profile

The table uses the representative sample equal to each series median, not
independently selected phase medians. Its rows sum exactly to the total.
“Ayurveda check” is honest about the runtime behavior: on an already stamped
store the app checks the bundled seed version; it does not materialize all
2,214 profiles into memory.

| Phase | Before | After | Delta |
|---|---:|---:|---:|
| Process/framework bootstrap | 0.623s | 0.588s | −0.035s |
| Schema/config construction | 0.432s | 0.420s | −0.012s |
| Preseed copy check | 0.000s | 0.000s | 0.000s |
| Store opening/migration checks | 0.041s | 0.042s | +0.001s |
| UI/framework handoff to launcher task | 0.295s | 0.239s | −0.055s |
| Theme snapshot/accent analysis | 0.075s | 0.069s | −0.006s |
| Ayurveda bundle version/profile-stamp check | 0.179s | 0.183s | +0.004s |
| Other seed/cache checks | 0.047s | 0.024s | −0.024s |
| **Search index decode/load on launch path** | **1.591s** | **0.000s** | **−1.591s** |
| Calendar reconstruction check | 0.037s | 0.024s | −0.013s |
| Root render → interactive marker | 0.085s | 0.073s | −0.012s |
| Marker handoffs/rounding | 0.001s | 0.000s | −0.000s |
| **Total** | **3.405s** | **1.662s** | **−1.744s** |

The persisted index was the only dominant app phase. Store open/migration was
about 41ms and the preseed existence check was below displayed precision, so
neither justified another fix.

## Bounded fix

`RootLauncher` no longer calls
`SearchIndexStore.shared.ensureLoaded(container:)`. `FoodSearchView` retains its
existing nonblocking load wrapper, while `searchCompact` and `searchResults`
now use an awaited lazy-load path before taking an index snapshot. This latter
guard is necessary because programmatic search previously relied on the launch
preload having already populated the singleton.

The cache itself is unchanged:

- persisted index version remains 4;
- row count remains 14,484;
- canonical facet ownership remains exactly 2,214 seeded profiles; and
- cache validation/rebuild behavior is unchanged.

No caching policy was added, no data is permitted to go stale, and no feature
was removed. The cost is paid once on first FoodSearch use rather than on every
launch.

## First-search and latency evidence

A temporary, uncommitted production-engine harness exercised
`SmartFoodSearch3.searchCompact` in the simulator. It was removed after capture.
Starting with an empty in-memory singleton:

```text
SearchIndexStore: Loaded from cached index (version: 4, 14484 foods).
WE6_SEARCH_LOAD|1691.400|5
```

The 1.691s wraps both cache loading and that first tomato search. The call
returned five results, proving that the awaited lazy path does not return an
empty transient result. All **25/25** WE-4 legacy golden arrays then matched
exactly.

Five warmups plus 30 samples per query were compared with the WE-5 final median:

| Query | WE-5 median | WE-6 median / p95 | Median delta |
|---|---:|---:|---:|
| `t` | 50.69ms | 48.28 / 49.98ms | −4.7% |
| `tom` | 15.97ms | 15.33 / 16.43ms | −4.0% |
| `tomato` | 15.25ms | 15.19 / 16.08ms | −0.4% |
| `rice` | 14.45ms | 14.94 / 15.77ms | +3.4% |
| `chicken` | 19.02ms | 18.93 / 19.32ms | −0.5% |
| `lentil soup` | 14.12ms | 13.52 / 14.53ms | −4.2% |

Worst regression: **+3.4%**. Gate: **≤ +10%**.

## Fresh-install and idempotence evidence

The simulator app alone was uninstalled, the final built artifact reinstalled,
and Calendar permission pre-granted. The one-time preseed copy and SwiftData
open took their expected fresh-install path. The authoritative lines are:

```text
✅ Ayurveda v3 preseed stamp verified; no inserts or updates.
✅ SearchIndexStore: Index is up-to-date (version: 4, DB: 14484). Skipping rebuild.
```

The first fresh-install interactive frame was 6.277s. That measurement includes
the one-time 0.465s bundled-store copy, 1.907s initial ModelContainer open, and
2.315s seed-v3 stamp verification; it is reported separately and is not the
repeatable cold-process <2s gate.

A second launch reported:

```text
Ayurveda seed version already applied, skipping.
SearchIndexStore: Index is up-to-date (version: 4, DB: 14484). Skipping rebuild.
```

The permanent tests independently assert zero fresh-store inserts, no fresh
rebuild, and zero rows inserted on the second seed run. Reconstructed artifact
counts remain 14,484 foods, 2,214 profiles, and 2,305 links.

## Local gate rerun

| Gate | Result |
|---|---|
| Final artifact validator + D34 resolver | PASS — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA rows |
| Complete repository suite | PASS — 38/38 |
| New WE-6 launch/lazy-load contracts | PASS — 4/4 |
| WE-2 nutrition/kitchari/coverage | PASS |
| WE-2 fresh no-insert/no-rebuild + idempotence | PASS |
| WE-3 display/accessibility | PASS |
| WE-4 grammar/facet ownership/persisted index | PASS |
| WE-5 border cases | PASS — 15/15 methods |
| Production WE-4 goldens | PASS — 25/25 exact |
| Search latency | PASS — worst median delta +3.4% |
| iOS 26.2 simulator build | PASS |
| Cold-process launch target | PASS — 1.662s median, target <2.0s |
| Lifecycle | PASS — all 2,214 canonical profiles remain `aiDraft` |
| Claims boundary | PASS — no content/index mutation; unprofiled USDA rows receive no Ayurveda facets or claims |

## Repeat on a physical device

1. Build and install the same commit from Xcode; add launch arguments
   `-uiTestNoAds -we6LaunchProfile`.
2. Resolve Calendar permission once before sampling. Do not uninstall between
   repeatable cold-process samples.
3. In Instruments, use the App Launch template and include Points of Interest
   for subsystem `WiseEating.Arte-Soft`.
4. Terminate the app process, start recording, launch it, and stop after the
   `first-interactive-frame` signpost.
5. Record at least five runs and report the median plus all raw totals. Keep
   fresh-install timing as a separate series.
6. Do not compare a Release physical-device number directly with this Debug
   simulator threshold; compare like with like and retain the phase table.

## Follow-up candidates

Candidates only; none was started:

1. Repeat the signpost series on the Founder’s physical device in Release.
2. If first-entry FoodSearch UX becomes a priority, separately profile moving
   persisted-index decoding off the main actor; no new cache policy is needed.
3. Profile the one-time fresh-install seed-v3 stamp verification (2.315s)
   before considering a separately authorized metadata-only fast path.
