# WE-8c — Provenance-Gated Age Enforcement

Date: 2026-07-26
Branch: `ayurveda-app`
Starting tip: `1c9c023` (one commit ahead of `origin/ayurveda-app`)
Status: **COMPLETE — replacement absolute launch gate passed; pushed**

## Outcome

The B5 enforcement split is implemented and all correctness, safety,
determinism, search, fresh-install, build, and replacement cold-launch gates
are green. A same-session, 12-pair ABAB comparison measured the final WE-8c
median at **1.607s**, below the new **1.700s hard ceiling** and the **1.650s
profiling-paydown trigger**.

No FoodSearch ranking, ingredient-level age, propagation rule, UI copy, schema,
or authored content value changed. The former per-task percentage gate was
withdrawn by founder ruling because it ratcheted; its original failure evidence
is retained below and superseded by the WE-8c-FINAL measurement.

## Implementation

Each canonical seed safety block now stores:

- `minAgeMonths`: display floor, still the maximum over all ingredient floors;
- `enforcedMinAgeMonths`: maximum over `authored` ingredient floors only;
- `ageProvenance`: `authored` or `legacyImport`;
- `ageContributors`: one entry per contributing ingredient, including its
  display floor, enforced floor, provenance, ingredient ID, and grams.

`authored` currently means exactly the deliberate 12-month honey/infant-
botulism rule. Values inherited from `WiseEating/Legacy/foods.json` are
`legacyImport`. The v5 compact index persists both floors. Existing age badges
continue reading `CompactFoodItem.minAgeMonths`
(`FoodSearchView.swift:441–444`); both age-filter paths now read
`enforcedMinAgeMonths` (`SmartFoodSearchEngine.swift:985` and `:1076–1077`).
Noncanonical USDA/user rows retain their prior behavior by persisting their
existing `minAgeMonths` as both display and enforced values.

The cache and seed versions are both 5. This is a representation/version bump,
not a SwiftData schema change.

## Provenance breakdown

| Scope | Total | `authored` | `legacyImport` |
|---|---:|---:|---:|
| Dravya safety blocks | 714 | 4 | 710 |
| Recipe safety blocks | 1,500 | 4 | 1,496 |
| Recipe ingredient contributors | 10,571 | 4 | 10,567 |

All four authored dravyas have an enforced 12-month floor:
`dravya.chyawanprash`, `dravya.honey`, `dravya.honey-aged`, and
`dravya.panchamrita`. Three are placeholder dravyas; `dravya.honey` is the
USDA-bound canonical honey row. The four authored recipes are:
`recipe.drink-ginger-oat-warmer`, `recipe.ginger-lemon-honey-tea`,
`recipe.panchamrit-classic`, and `recipe.vasanta-kapha-clearer`.

Among legacy-import dravyas, 330 carry a positive display floor and 380 carry
zero. All 1,496 legacy-import recipes carry a positive display floor. Their
enforced floor is zero because no cited authored age rule contributes.

## G1 — honey protection

**PASS.** All four honey recipes and all three honey placeholder dravyas remain
hidden below 12 months. The USDA-bound canonical honey dravya also remains
hidden. At 12 months and above all eight are eligible.

Permanent derivation and persisted-artifact tests check these exact sets and
floors.

## G2 — recipe visibility

**PASS; actuals equal the founder simulation.**

| Profile age | Visible recipes | Hidden recipes |
|---:|---:|---:|
| 9 months | **1,496** | 4 honey recipes |
| 24 months | **1,500** | 0 |
| 60 months | **1,500** | 0 |

## G3 — display floors

**PASS; byte-for-byte values are unchanged from WE-8.**

| Display `minAgeMonths` | Recipe count |
|---:|---:|
| 6 | 1 |
| 24 | 1,201 |
| 48 | 226 |
| 60 | 70 |
| 192 | 2 |
| **Total** | **1,500** |

The enforced recipe histogram is `0: 1,496; 12: 4`.

## G4 — dravya visibility delta

The same provenance rule is applied to dravyas; no grandfathering preserves
the untraced legacy hard gate.

| Profile age | Visible before (display floor enforced) | Visible with B5 | Delta |
|---:|---:|---:|---:|
| 9 months | 457 | 710 | **+253** |
| 24 months | 684 | 714 | **+30** |
| 60 months | 706 | 714 | **+8** |

Ten-row sample:

| Dravya | Display | Enforced | Newly visible at |
|---|---:|---:|---|
| `dravya.chamomile-tea` | 192 | 0 | 9, 24, 60 months |
| `dravya.hibiscus-tea` | 192 | 0 | 9, 24, 60 months |
| `dravya.oats` | 60 | 0 | 9, 24 months |
| `dravya.carrot` | 24 | 0 | 9 months |
| `dravya.white-rice` | 24 | 0 | 9 months |
| `dravya.mung-bean` | 24 | 0 | 9 months |
| `dravya.olive-oil` | 24 | 0 | 9 months |
| `dravya.pumpkin` | 24 | 0 | 9 months |
| `dravya.lemon` | 24 | 0 | 9 months |
| `dravya.cumin` | 24 | 0 | 9 months |

The dravya display histogram remains:
`0:380, 6:64, 8:12, 9:1, 12:17, 24:210, 48:19, 60:3, 192:8`.
The enforced histogram is `0:710, 12:4`.

## G5 — production goldens

**PASS.** A temporary production-engine probe (removed after capture) called
`SmartFoodSearch3.searchCompact` against the final v5 cache:

- legacy goldens: **25/25 exact**;
- `without dairy`: Amaranth Kheer absent;
- `no allergens`: **0** allergen-bearing seeded recipe violations.

No baseline was edited and no age-sensitive golden moved.

## G6 — complete local gates

| Gate | Result |
|---|---|
| Validator + D34 resolver | PASS — 714 dravyas, 1,500 recipes, 12,601/12,601 USDA rows |
| Complete repository suite | PASS — **62/62** |
| WE-8c methods | PASS — 9/9 derivation/artifact checks |
| Deterministic seed | PASS — two builds and shipped file SHA `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| Deterministic compact store | PASS — two builds byte-identical |
| Artifact audit | PASS — 14,484 foods/cache rows, cache v5, 2,214 profiles, 2,305 links, 10,571 IngredientLinks |
| Fresh install | PASS — `Ayurveda v5 preseed stamp verified; no inserts or updates` |
| Fresh search index | PASS — v5 / DB 14,484, `Skipping rebuild` |
| Second seed run | PASS — version-stamped no-op |
| Production goldens | PASS — 25/25 legacy + 2/2 safety |
| Debug arm64 simulator build | PASS |
| Clean Release arm64 simulator build | PASS |
| Lifecycle | PASS — 2,214/2,214 profiles remain `aiDraft` |
| Claims boundary | PASS — exactly 2,214 canonical rows have Ayurveda facets; plain USDA rows receive none |

Artifact hashes:

| Artifact | SHA-256 |
|---|---|
| `ayurveda_seed.json.gz` | `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| `preseeded_db.store.gz.part-aa` | `9509d74422f90a2a178955cede10729077fe328fda871fee477a47d08bfe4896` |
| `preseeded_db.store.gz.part-ab` | `0e7b8a44ad9c9a5bd934ed5308e36c04d96d5d3c39df52cb2ae6dd5b17bb41ee` |

The seed grew 88,323 bytes. The two preseed parts grew 27,211 bytes combined;
total bundled seed-plus-store growth is 115,534 bytes.

## G7 — cold launch

**WITHDRAWN by founder ruling.** The original failure capture is retained
verbatim as historical evidence; it is not the completion gate.

Method: final uninstrumented Debug app, `-uiTestNoAds -we6LaunchProfile`,
process terminated before each run, Calendar permission resolved, simulator
left booted, and host monotonic launch time compared with the
`first-interactive-frame` marker. The final series used the exact retained
baseline device, `WiseEating-WE2-Baseline`
(`AF937668-3BFE-45E8-B42A-A76B914038DD`), with the other simulator shut down.

Fresh install completed in 5.181s and separately proved no insert/no rebuild.
Final cold-process samples:

| Sample | Total |
|---:|---:|
| 1 | 1.653s |
| 2 | 1.634s |
| 3 | 1.674s |
| 4 | 1.649s |
| 5 | 1.649s |
| 6 | 1.654s |
| 7 | 1.650s |
| **Median** | **1.650s** |

Recorded baseline: 1.592s. Authorized ceiling: 1.62384s (reported as 1.624s).
Actual delta: **+0.058s / +3.62%**. The best sample (1.634s) also exceeds the
ceiling. No launch behavior was changed to chase the gate.

For completeness, an initial series on a different iPhone 17 Pro simulator
measured 1.663s median, and the correct baseline device while both simulators
were booted measured 1.672s. Those noncomparable/control-contaminated series
were not used as the final gate result.

## Additional audit — plain USDA rows on `main`

**Yes.** This is a pre-existing `main` behavior independent of Ayurveda.
At pristine-main tip `2508c74`,
`WiseEating/FoodSearch/VM/SmartFoodSearch 3.swift:834` applies
`item.minAgeMonths` to profile constraints and line 925 applies it to parsed
age intent. Both paths `continue`, so nonmatching rows are hard-hidden rather
than badged or downranked. `SearchIndexStore.swift:403` copies the legacy value
into every compact row.

The shipping `WiseEating/Legacy/foods.json` has exactly 12,601 plain USDA rows.
Its impact is:

| Profile age | Visible plain USDA | Hidden plain USDA |
|---:|---:|---:|
| 9 months | 4,353 | 8,248 |
| 24 months | 11,807 | 794 |
| 60 months | 12,243 | 358 |

WE-8c deliberately does not fix that production-main issue. Noncanonical rows
on `ayurveda-app` likewise preserve the pre-existing enforcement behavior.
The separate founder decision record is
`ayurveda-data/ISSUE-MAIN-AGE-GATING.md`.

## Commit and push disposition

The implementation chain completed by this report is:

1. `36431cb` — provenance-gated enforcement and tests;
2. `589f4c0` — deterministic v5 seed and prebuilt cache artifacts;
3. `8b6f451` — corrected the stale fresh-cache test version literal;
4. `840e4d7` — retained the original, correctly triggered G7 stop report;
5. this WE-8c-FINAL completion documentation commit.

The branch also includes its already-approved starting WE-8b audit commit
`1c9c023`. With the replacement gate green, the complete local chain is
authorized for a normal push to `origin/ayurveda-app`.

## WE-8c-FINAL — Phase 1: same-session cold-launch re-measurement

### Method and quiescence

The retained baseline simulator was used:
`WiseEating-WE2-Baseline`
(`AF937668-3BFE-45E8-B42A-A76B914038DD`, iOS 26.2). WE-8b at `1c9c023` and the
WE-8c working tip at `840e4d7` were built from the same temporary checkout with
the same Xcode, Debug arm64 simulator configuration, dependency products, and
compiler settings. Separate bundle identifiers (`WiseEating.Arte-Soft.we8b`
and `.we8c`) gave each revision an independent application container and
preseed state.

Each app received one untimed fresh launch first. Calendar permission was
resolved before measurement. The fresh logs proved cache v4/14,484 and
v5/14,484 respectively were up to date and skipped rebuilding. The app process
was terminated before every measured sample; the required simulator stayed
booted.

The measurement window was quiesced as follows:

- Xcode IDE was closed; no `xcodebuild`, Swift compiler, Maestro, CI, or test
  process was running;
- exactly one simulator—the required baseline device—was booted;
- Spotlight's `mds`/`mdworker` processes were present but measured 0.0% CPU, so
  no active indexing was accepted into the sample window;
- unrelated Claude and Chrome processes were temporarily suspended, not
  terminated, for the measurement and resumed immediately afterward;
- Codex, Simulator/CoreSimulator, WindowServer, ordinary system services, and
  a low-CPU background VM/helper remained running; host free-memory pressure
  was 84%.

Host `time.monotonic()` was captured immediately before each
`simctl launch --console-pty`. The terminal
`WE6_PROFILE|first-interactive-frame|<uptime>` timestamp uses the same monotonic
host clock. Order was strict ABAB: WE-8b then WE-8c, repeated for 12 pairs
(N=12 per revision). Every one of the 24 launches emitted all 17 expected
phase markers and the prebuilt-index `Skipping rebuild` line.

### Raw paired series

| Pair | WE-8b | WE-8c | WE-8c − WE-8b |
|---:|---:|---:|---:|
| 1 | 1.588892s | 1.610627s | +0.021734s |
| 2 | 1.546783s | 1.596463s | +0.049680s |
| 3 | 1.579416s | 1.626161s | +0.046744s |
| 4 | 1.546557s | 1.575930s | +0.029373s |
| 5 | 1.545704s | 1.625378s | +0.079673s |
| 6 | 1.556416s | 1.615385s | +0.058969s |
| 7 | 1.586173s | 1.598511s | +0.012338s |
| 8 | 1.544133s | 1.602655s | +0.058522s |
| 9 | 1.572773s | 1.645319s | +0.072545s |
| 10 | 1.592086s | 1.582999s | −0.009087s |
| 11 | 1.586035s | 1.590569s | +0.004533s |
| 12 | 1.565302s | 1.642104s | +0.076801s |

Quartiles below use the inclusive definition; standard deviation is
population standard deviation.

| Series | N | Median | IQR (Q1–Q3) | Min | Max | Stddev |
|---|---:|---:|---:|---:|---:|---:|
| WE-8b | 12 | **1.569038s** | 0.039343s (1.546726–1.586070) | 1.544133s | 1.592086s | 0.018122s |
| WE-8c | 12 | **1.606641s** | 0.030584s (1.594990–1.625573) | 1.575930s | 1.645319s | 0.021285s |
| Paired delta | 12 | **+0.048212s** | 0.042978s (+0.019385–+0.062363) | −0.009087s | +0.079673s | 0.028386s |

The paired mean delta is +0.041819s. The +0.048212s paired median is larger
than both WE-8b's 0.039343s IQR and WE-8c's 0.030584s IQR. Under the founder's
specified IQR test, the delta is therefore resolvable in this data; it is not
being dismissed as within either series' IQR. Its paired dispersion is reported
without claiming a causal phase.

## WE-8c-FINAL — Phase 2: replacement launch gate

The per-task percentage gate is retired. `PROJECT-HANDBOOK.md` §3 now records:

> Cold launch is governed by an absolute product budget, not a per-task
> percentage. HARD CEILING 1.700s median. Any task whose measured median exceeds
> 1.650s must include a profiling paydown in the same task. Per-task deltas are
> always reported; they are not individually gated. Percentage-of-previous
> gates are forbidden for launch because they ratchet.

The number registry now records the same-session WE-8c median as **1.607s**.
It is 0.093s below the hard ceiling and 0.043s below the profiling-paydown
trigger. No launch-path code was reverted or redesigned.

## WE-8c-FINAL — Phase 3: completion ruling

**PASS.** The Phase 1 median is 1.606641s, which is at or below 1.700s.
The founder's automatic completion ruling therefore applies. All previously
green correctness gates remain the accepted WE-8c evidence:

- recipe visibility 1,496 / 1,500 / 1,500 at 9 / 24 / 60 months;
- all honey protection exact;
- display histogram unchanged;
- 62/62 repository tests;
- 25/25 legacy plus 2/2 safety goldens;
- deterministic seed/store artifacts;
- fresh install zero inserts and no rebuild;
- Debug and Release builds green.

The final documentation-only rerun also passed the complete 62-test repository
suite, validator/artifact audit, and artifact-hash check. No production code,
seed artifact, search ranking, lifecycle value, claim, or UI copy changed
during WE-8c-FINAL.

## WE-8c-FINAL — Phase 4: separate `main` issue

`ayurveda-data/ISSUE-MAIN-AGE-GATING.md` now records the pre-existing shipping
issue independently of this Ayurveda report. It includes the 4,353 / 11,807 /
12,243 visible-row counts, the full 12,601-row age histogram, and the exact
JSON → DTO → compact index → hard-filter code path.

The answer to the additional authored-rule audit is **no**: `main` has no
auditable authored 12-month honey floor. Its source copies imported ages
unchanged, contains no infant-botulism rule/citation, and its 36 honey-named
rows span 6, 12, 24, and 48 months. Thus the shipping app enforces the untraced
fill while lacking this project's only cited age rule. No `main` file or branch
was changed.
