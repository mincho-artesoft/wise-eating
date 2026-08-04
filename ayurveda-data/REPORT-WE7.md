# WE-7 Legacy Target Audit

Date: 2026-07-25
Branch: `ayurveda-app`
Audited starting commit: `14a2e9ff24044a14e49aac41941baaf3d36028a6`
Status: **COMPLETE — one proven-dead cluster removed; all local gates green**

## Scope and method

`PROJECT-HANDBOOK.md` marks `WiseEating/Legacy/` as the legacy area and does not mark another directory as legacy. The audit covered every file directly under that directory and checked:

- synchronized Xcode target membership and the generated Debug `WiseEating.SwiftFileList`;
- Swift declaration names and exact-symbol references outside `WiseEating/Legacy/`;
- bundle-resource lookups and direct filesystem references;
- storyboard, XIB, and property-list references;
- `@objc`, `NSClassFromString`, `objc_getClass`, `_typeByName`, selector, and string-literal lookup patterns.

The Xcode project uses a `PBXFileSystemSynchronizedRootGroup` for `WiseEating`, so the nine Swift files are automatically target members. All nine occur in the generated compiler file list. The five JSON files occur in the built app bundle. `LaunchScreen.storyboard` and `Info.plist` contain no legacy class references; there are no XIB files. No ambiguous runtime or string-instantiation reference was found.

## Phase 1 classification table

This table was written before any removal, as required.

| File | Bytes | Declares or contains | Shipping membership | Inbound evidence | Classification |
|---|---:|---|---|---|---|
| `ContentView.swift` | 3,093 | No compiled declaration; commented archive of `ContentView`, `startOfDay`, and `seedMockProgress` | Swift compiler input | No exact-symbol, interface, Objective-C runtime, selector, or string lookup | **DEAD** |
| `FoodSearchVM.swift` | 35,076 | No compiled declaration; commented archive of `FoodSearchVM`, `SearchContext`, and helpers | Swift compiler input | No exact-symbol, interface, Objective-C runtime, selector, or string lookup | **DEAD** |
| `IndexingJob.swift` | 401 | No compiled declaration; commented archive of `IndexingJob` | Swift compiler input | No exact-symbol, interface, Objective-C runtime, selector, or string lookup | **DEAD** |
| `IndexingQueueManager.swift` | 6,488 | No compiled declaration; commented archive of `IndexingQueueManager` | Swift compiler input | No exact-symbol, interface, Objective-C runtime, selector, or string lookup | **DEAD** |
| `NameIndex.swift` | 803 | No compiled declaration; commented archive of `NameEntry` and `NameIndex` | Swift compiler input | No exact-symbol, interface, Objective-C runtime, selector, or string lookup | **DEAD** |
| `NutrientIndex.swift` | 2,739 | No compiled declaration; commented archive of `FoodRank`, `NutrientIndex`, and an extension | Swift compiler input | Outside-name matches are comments describing removed behavior; no compiled or runtime reference | **DEAD** |
| `SmartFoodSearch 2.swift` | 5,428 | No compiled declaration; commented archive of `SmartFoodSearch_2` | Swift compiler input | No exact-symbol, interface, Objective-C runtime, selector, or string lookup | **DEAD** |
| `SmartFoodSearch.swift` | 43,865 | No compiled declaration; commented archive of `SmartFoodSearch` and nested scoring/signal types | Swift compiler input | Outside-name matches are comments describing old/current engine history; no compiled or runtime reference | **DEAD** |
| `SmartSearchView.swift` | 7,859 | No compiled declaration; commented archive of `SmartSearchView` and `SearchDomain` | Swift compiler input | No exact-symbol, interface, Objective-C runtime, selector, or string lookup | **DEAD** |
| `foods.json` | 68,749,883 | 12,601 USDA food records | Copied into app bundle | `SeedManager.swift:131`; also build/test inputs in `build_seed.py:107` and `test_we2_nutrition.py:19` | **LIVE** |
| `product_buckets.json` | 65,629,090 | 7,639 product-bucket records | Copied into app bundle | `SeedManager.swift:80` | **LIVE** |
| `sports.json` | 1,059,339 | 2,918 exercise records | Copied into app bundle | `SeedManager.swift:174` | **LIVE** |
| `vocabulary.json` | 13,442,886 | 544,453 vocabulary entries | Copied into app bundle | `SeedManager.swift:60` | **LIVE** |
| `workouts.json` | 2,509,350 | 1,777 workout-template records | Removed from app bundle | Template-plan feature removed | **REMOVED** |

The nine Swift sources have 2,288 nonblank lines in total, and every nonblank line begins with `//`. They compile to empty object files but declare no symbols. They form one closed **DEAD** cluster. There are no files classified **REACHABLE-BUT-OBSOLETE**.

## LIVE-file founder decision list

The four remaining JSON resources stay. They are part of the runtime empty-table/fallback seed path, even though the WE-2 preseed normally makes that path unnecessary on a fresh install.

| Live resource | What removal would require |
|---|---|
| `foods.json` | Replace or remove the `FoodItem` empty-table fallback in `SeedManager`, and replace its build/test input use. |
| `product_buckets.json` | Replace or remove the product-bucket fallback seed path in `SeedManager`. |
| `sports.json` | Replace or remove the exercise fallback seed path in `SeedManager`. |
| `vocabulary.json` | Replace or remove the vocabulary fallback seed path in `SeedManager`. |
The former `workouts.json` template seed and its runtime lookup were removed together with the training-plan template feature.

## Before-removal size baseline

Both baselines were built from the untouched starting commit. Debug used the final clean WE-6 build; Release was rebuilt from a fresh DerivedData directory with whole-module optimization.

| Configuration | App regular-file bytes | App allocated size | Main executable | Debug dylib |
|---|---:|---:|---:|---:|
| Debug simulator | 813,856,564 | 794,852 KiB | 39,640 bytes | 120,310,232 bytes |
| Release simulator | 761,065,060 | 743,292 KiB | 67,655,064 bytes | n/a |

The five live legacy JSON resources total 151,390,548 bytes. The removable comment-only Swift sources total 105,752 source bytes; source size is not app-bundle size.

## Phase 2 removals

One closed cluster was removed in commit `90074e0` (`WE-7 remove dead Legacy
Swift cluster`):

- the nine **DEAD**, comment-only Swift compiler inputs in the table above;
- 2,288 commented nonblank lines / 105,752 source bytes;
- no live JSON resource; and
- no `.pbxproj` edit, because deleting files from the synchronized
  `WiseEating/Legacy/` group removes their target membership automatically.

The generated Debug and Release `WiseEating.SwiftFileList` files contain zero
`WiseEating/Legacy/*.swift` paths after the removal. A clean Debug build and the
complete 38-test repository suite passed before the cluster commit. No removal
was reverted, and there was no ambiguous file to retain.

## Phase 3 gates and after measurements

### Binary and bundle size

Before/after builds use the same arm64 iOS 26.2 simulator destination and
configuration. The five live JSON resources and every other bundled resource
are unchanged.

| Configuration / measure | Before | After | Delta |
|---|---:|---:|---:|
| Debug app regular-file bytes | 813,856,564 | 813,858,516 | +1,952 |
| Debug allocated bundle size | 794,852 KiB | 794,856 KiB | +4 KiB |
| Debug launcher | 39,640 bytes | 39,640 bytes | 0 |
| Debug dylib | 120,310,232 bytes | 120,312,072 bytes | +1,840 |
| Release app regular-file bytes | 761,065,060 | 761,064,644 | **−416** |
| Release allocated bundle size | 743,292 KiB | 743,292 KiB | 0 |
| Release optimized executable | 67,655,064 bytes | 67,654,648 bytes | **−416** |

The optimized shipping measurement is a 416-byte reduction. The unstripped
Debug product is not byte-stable across fresh DerivedData paths; its launcher
is unchanged and its 1.8 KiB dylib increase is consistent with regenerated
debug/build-path metadata; the diff adds no source or resource. Both products
have the same file count as before, because Swift source files are not copied
into the app bundle.

### Launch, fresh-install, and idempotence

The WE-6 method was repeated on simulator
`AF937668-3BFE-45E8-B42A-A76B914038DD`: Debug build, `-uiTestNoAds
-we6LaunchProfile`, process terminated before each sample, simulator left
booted, Calendar permission resolved, and host monotonic launch time compared
with the first-interactive-frame marker.

| Sample | Cold-process launch |
|---:|---:|
| 1 | 1.527s |
| 2 | 1.494s |
| 3 | 1.497s |
| 4 | 1.504s |
| 5 | 1.505s |
| **Median** | **1.504s** |

The WE-6 final median was 1.662s; WE-7 remains below the 2.0s gate and is
0.158s / 9.5% faster in this series. The one-time fresh-install launch was
4.864s and is reported separately from the repeatable cold-process gate.

The fresh run logged:

```text
✅ Ayurveda v3 preseed stamp verified; no inserts or updates.
✅ SearchIndexStore: Index is up-to-date (version: 4, DB: 14484). Skipping rebuild.
WE6_PROFILE|search-index-load-deferred|...
```

The next launch logged `Ayurveda seed version already applied, skipping.` and
again skipped the index rebuild. Thus fresh install is no-insert/no-rebuild,
the second seed pass is a version-stamped no-op, and WE-6's lazy-index behavior
remains active.

### Golden queries and performance

All **25/25** WE-4 legacy golden arrays matched exactly. The retained WE-6
instrumented production-engine build was used for runtime capture so no
temporary current source change outside the authorized Legacy scope was
needed. This is valid for the removal audit because
`git diff 8885cbb..90074e0 -- WiseEating/FoodSearch` is empty; the current
38-test run independently compiles and checks the same source. First lazy index
load plus a real tomato query returned five results in **1,700.583ms**.

Five warmups plus 30 samples per query were compared with the WE-4 baseline:

| Query | WE-4 median | WE-7 median / p95 | Median delta |
|---|---:|---:|---:|
| `t` | 48.25ms | 46.23 / 47.95ms | −4.2% |
| `tom` | 16.01ms | 15.00 / 15.92ms | −6.3% |
| `tomato` | 15.63ms | 14.01 / 14.77ms | −10.3% |
| `rice` | 14.57ms | 13.46 / 14.06ms | −7.6% |
| `chicken` | 18.64ms | 17.10 / 18.39ms | −8.2% |
| `lentil soup` | 13.83ms | 13.06 / 13.50ms | −5.6% |

Worst median delta: **−4.2%**. Gate: no query may exceed **+10%**.

### Full local gate rerun

| Gate | Result |
|---|---|
| Phase-1 target/reference/runtime audit | PASS — 14/14 files classified; no ambiguity |
| Artifact validator + D34 resolver | PASS — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA foods |
| Complete repository suite | PASS — 38/38 |
| WE-2 nutrition + fresh no-insert/no-rebuild + idempotence | PASS |
| WE-3 display/accessibility contracts | PASS |
| WE-4 grammar/facets/persisted-index contracts | PASS |
| WE-5 border cases | PASS — 15/15 methods |
| WE-4 production golden queries | PASS — 25/25 exact |
| WE-4/WE-5 search latency budget | PASS — worst delta −4.2%, limit +10% |
| WE-6 cold-process launch | PASS — 1.504s median, target <2.0s |
| Fresh install / second seed run | PASS — no insert, no rebuild, stamped no-op |
| Clean Debug arm64 simulator build | PASS |
| Clean Release arm64 simulator build | PASS |
| Lifecycle | PASS — 714 dravyas + 1,500 recipes remain `aiDraft` |
| Claims boundary | PASS — no content, active search, seed, profile, or claim data changed |

## Outcome

`WiseEating/Legacy/` now contains only the five **LIVE** JSON fallback
resources. There are no remaining Swift compiler inputs under that directory,
no closed obsolete cluster left to remove, and no LIVE Swift file requiring a
founder decision.
