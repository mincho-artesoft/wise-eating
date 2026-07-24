# REPORT WE-5 — FoodSearch border-case fixes

Date: 2026-07-24
Branch: `ayurveda-app`
Status: **COMPLETE — all local gates green**

## Summary

WE-5 closes the five bounded FoodSearch defects without changing the search
index, Ayurveda content, lifecycle, or claims ownership:

- every constrained nutrient column now renders; missing data is `—` with
  accessibility label “no data,” while a stored zero remains `0.0`;
- Tokenizer, ConstraintMapper, and numeric fallback nutrients feed one
  deduplicated, query-ordered display list, and `activeConstraint` is populated;
- pH filtering, neutral range, missing-data handling, exclusion counts, and
  sort direction share one definition;
- command heuristics use token/phrase boundaries rather than substrings; and
- the engine source is now
  `WiseEating/FoodSearch/VM/SmartFoodSearchEngine.swift`.

All 25 WE-4 production golden queries are byte-for-byte identical at the
five-result boundary. The final idle performance repeat is within the WE-4
median budget for every query; the worst delta is **+5.1%**, below +10%.

Commits are one per diagnosed defect:

| Defect | Commit |
|---|---|
| D1 | `1ad2953` |
| D2 | `a28c4ca` |
| D3 | `b92c4bb` |
| D4 | `754efc7` |
| D5 | `83a9eba` |

## Diagnosis audit — confirm or refute

The cited behavior was checked against the post-WE-4 source before each change.

| Diagnosis | Verdict | Evidence |
|---|---|---|
| D1 chips disappear when normalization returns `nil` | **Confirmed** | The entire nutrient `HStack` was inside `if let`; a missing value emitted no label or value. The legacy accessor also used `0.0` for both missing and stored zero. |
| D2 display source ignores the constraint engine; `activeConstraint` is always `nil` | **Partly refuted / partly confirmed** | `activeConstraint: nil` was exactly confirmed. The display list did not literally ignore all mapped constraints: it read the final merged `intent.nutrientGoals`, which already included many mapped numeric goals. What was missing was explicit provenance from both parsers and stable query order. The implementation now records Tokenizer + ConstraintMapper + fallback display nutrients directly, then deduplicates them in query order. |
| D3a pH 7 can satisfy both high and low | **Confirmed** | The prior switches rejected high only below 7 and low only above 7, so exactly 7 passed both. |
| D3b unknown pH is silently removed/hidden | **Confirmed** | `ph == 0` was excluded without a count; the row view rendered pH only when `food.ph > 0`. |
| D3c sort-only pH does not set `isPhActive` | **Refuted** | Before WE-5, UI sort already mapped to `.lowest`/`.highest`; that non-`nil` `intent.phConstraint` made `isPhActive` true. WE-5 preserves and explicitly tests that path; no redundant state was added. |
| D4 substring heuristics activate on unrelated words | **Confirmed** | `lowerQuery.contains("ph")` matched phosphorus/sulphate/phyllo, and the fallback nutrient parser rejected any nutrient phrase containing the letters `ph`. `contains("free")` and `"no "` had the same boundary weakness. |
| D5 source filename hygiene | **Confirmed with founder amendment** | The initially requested `SmartFoodSearch.swift` name collided with the tracked `WiseEating/Legacy/SmartFoodSearch.swift` in Xcode’s localized-strings output. No legacy file was changed. Per the founder amendment, the source is `SmartFoodSearchEngine.swift`; `**/xcuserdata/` is recursively ignored. |

## Before / after behavior

| Area | Before | After |
|---|---|---|
| Missing searched nutrient | Whole chip absent | Nutrient label plus `—`; accessibility says “no data” |
| Stored nutrient value `0.0` | Indistinguishable from missing through the legacy numeric sentinel | A stored relationship with a unit renders `0.0`; only a unitless zero is missing |
| Numeric/constraint display | Relied on the final merged goal array; order could follow parser/set order | Tokenizer, ConstraintMapper, and fallback sources are explicitly combined, deduplicated, and sorted by query occurrence |
| Active nutrient context | Always `nil` | Human-readable constraint text, including `<`, `≤`, `>`, `≥`, ranges, and ranking modes |
| pH directional boundary | `7.0` passed both high and low | low `< 7.0`; high `> 7.0`; neutral remains inclusive `6.5...7.5` |
| Unknown pH in a pH result set | Excluded silently; no displayed placeholder | Still excluded, never fabricated; context reports the candidate count. If displayed, the row shows `—` |
| pH sort-only display | Already visible | Preserved and regression-tested |
| `high phosphorus` | Could activate pH and could reject phosphorus in fallback parsing | Phosphorus nutrient path; `isPhActive == false` |
| `sulphate`, `phyllo` | Could activate pH heuristic | Ordinary text path |
| `no` | Space-sensitive substring | Exact token, including query-final position |
| `free` | Any substring could activate the constraint engine | Only a recognized compound such as `gluten free`, `fat-free`, or `free of sodium` |
| `freeze-dried` | Could activate the `free` heuristic | Ordinary text path |

## pH contract and runtime evidence

`PhSearchSemantics` is the single source for the directional threshold,
neutral interval, missing sentinel, matching, and pH sort preference.

Compiled Swift unit cases verify:

| Value | High | Low | Neutral |
|---:|---:|---:|---:|
| 6.99 | false | true | true |
| 7.00 | false | false | true |
| 7.01 | true | false | true |
| 0.00 sentinel | false | false | false |

The production simulator capture additionally recorded:

```text
high phosphorus: ph=false; displayed nutrient=phosphorus
pH sort low-to-high: ph=true; 383 foods without pH data excluded
```

The count is candidate-set specific. Thus the all-food sort reports all 383
unknown-pH rows, while the already text-narrowed `alkaline foods` candidate set
contains no unknown-pH rows and correctly reports zero.

## Border-case tests

`test_we5_search.py` contains 15 test methods. Its compiled Swift helper runs
29 explicit boundary/value cases, supplemented by production-source contract
checks and the clean simulator build:

- standalone `ph` positive cases and explicit negative cases for `phosphorus`,
  `sulphate`, and `phyllo`;
- query-initial and query-final `no`, with nonmatches such as `nori` and
  `quinoa`;
- `gluten free`, `fat-free`, `free of sodium`, and `sugar free`, with
  nonmatches for `freeze-dried`, `freezer`, and unrelated `free standing`;
- pH `6.49`, `6.5`, `6.99`, `7.0`, `7.01`, `7.5`, `7.51`, and the `0.0`
  sentinel;
- missing nutrient and pH `—` surfaces with “no data” accessibility;
- stored-zero `0.0` path;
- both nutrient parser sources, numeric constraint context, query order, and
  deduplication;
- pH-sort visibility and the exclusion-count message; and
- amended filename plus recursive `xcuserdata` ignore.

The repository has no Xcode unit-test target. As in WE-2 through WE-4, tests
compile the isolated production Swift helpers where possible, assert the
SwiftUI/source contracts, then pair them with a clean production simulator
build and a production-engine runtime capture.

## Golden-query regression

The same `SmartFoodSearch3.searchCompact` production path, 14,484-row index,
and five-result limit used by WE-4 were run again. All **25/25** legacy arrays
match `tests/fixtures/we4_golden_queries.json` exactly, including:

- `tomatoes low fat`, `more iron than spinach`, and `ph 7` retaining their
  existing empty behavior;
- nutrient queries such as `high iron`, `low sodium soup`, and
  `vitamin c orange`;
- diet/negation queries such as `gluten free bread`, `dairy free yogurt`, and
  `no peanuts`; and
- ordinary text queries from `tomato` through `olive oil`.

Production border capture also verified that `high phosphorus` returns the
phosphorus food result with pH inactive. Unknown border vocabulary degrades
honestly to the existing text path; no fallback result is manufactured.

## Performance

Environment: the same iOS 26.2 simulator and Mac as WE-4; production
`searchCompact` over 14,484 compact rows; five warmups plus 30 timed iterations
per query. The comparison baseline is the WE-4 final table, and its gate metric
is median latency.

| Query | WE-4 median | WE-5 median / p95 | Median delta |
|---|---:|---:|---:|
| `t` | 48.25 ms | 50.69 / 61.31 ms | +5.1% |
| `tom` | 16.01 ms | 15.97 / 17.15 ms | −0.3% |
| `tomato` | 15.63 ms | 15.25 / 18.92 ms | −2.5% |
| `rice` | 14.57 ms | 14.45 / 15.22 ms | −0.9% |
| `chicken` | 18.64 ms | 19.02 / 19.73 ms | +2.0% |
| `lentil soup` | 13.83 ms | 14.12 / 17.34 ms | +2.1% |

Worst median delta: **+5.1%**. Gate limit: **+10%**.

One sample taken while three unrelated backup processes consumed almost 300%
CPU was discarded before this table; the final idle repeat above is the
authoritative result. This follows the same host-contention discard policy
documented in WE-4.

## Full local gate rerun

| Gate | Result |
|---|---|
| Final artifact validator + D34 resolver simulation | PASS — 714 dravyas / 1,500 recipes; 12,601/12,601 USDA foods resolved |
| Complete repository test suite | PASS — 34/34 |
| New WE-5 test methods | PASS — 15/15; 29 compiled border/value cases plus UI/source contracts |
| WE-2 nutrition coverage and kitchari gate | PASS |
| WE-2 fresh-store no-insert/no-rebuild and idempotence | PASS |
| WE-3 display/accessibility tests | PASS |
| WE-4 grammar, exact facet ownership, and persisted-index tests | PASS |
| 25 production legacy goldens | PASS — 25/25 exact, zero mismatches |
| Production border capture | PASS — phosphorus path, numeric display, pH count/sort state |
| WE-4 performance budget | PASS — worst median +5.1%, limit +10% |
| Clean-derived-data iOS simulator build | PASS |
| Lifecycle | PASS — all 2,214 canonical profiles remain `aiDraft` |
| Claims boundary | PASS — no content/index mutation; USDA rows received no Ayurveda data or claims |
| Scope | PASS — implementation is in `WiseEating/FoodSearch/`; only tests, required docs, and the founder-authorized `.gitignore` line are outside it |
| Legacy ownership | PASS — no file under `WiseEating/Legacy/` changed |

The existing seeded runtime also logged version-4 cache / 14,484 rows as
up-to-date and skipped rebuilding. The permanent fresh-store tests independently
assert zero Ayurveda inserts and no index rebuild.

## Follow-up candidates

Candidates only; none was started:

1. Add an Xcode test target so SwiftUI row rendering can be asserted without
   the current source-contract plus simulator-build pairing.
2. Consolidate duplicate human-readable `activeConstraint` descriptions when
   two existing parsers independently emit the same semantic constraint.
3. Consider surfacing `phDataExclusionMessage` in the visible filter summary in
   a separately approved UI task.
