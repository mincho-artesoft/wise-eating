# FC-1e — rev5 ontology, rev4 corpus, and FC-2 wiring

Date: 2026-07-26
Branch: `fc-1c-g12-rulings`
Starting commit: `06c767b`
Implementation commits: `34a5047`, `55cd5ae`
Status: **COMPLETE — all authorized host/simulator gates pass; not merged or pushed**

## Executive result

The director's rev5 corrections close every FC-1d blocker:

- the coconut disagreement falls from **1 to 0**;
- oyster mushroom is vetoed in both authored and USDA-inverted token order;
- non-contested must-not-exclude has **zero failures**;
- equivalent WE-8/FC-1 disagreements fall from **80 to 77**;
- water chestnut remains outside tree nuts; and
- `meat` remains bounded at **3,785 / 14,484 (26.132%)**.

FC-2 is therefore wired. Planner exclusions are canonical ID-set operations,
the hardcoded alcohol keyword list is gone, and the 75 ontology aliases feed
the frozen MP-3 scorer without changing a scorer weight, threshold, or
hand-authored MP-3 alias. Training remains **59/59** and held-out resolution
improves from **40/48 to 44/48**, with four honest unresolved foods and zero
wrong-confident matches.

The final suite is **98/98**, search goldens remain **25/25 + 2/2 exact**,
Debug and Release build, validator and fresh-install gates pass, and cold
launch is **1.433328s median**, below the 1.700s hard ceiling.

## Director inputs

The director-authored files were committed as received and were not tuned:

| Input | SHA-256 | Parsed state |
|---|---|---|
| `ayurveda-data/rules/food-concepts.json` | `1f432b23e233f4bece7f3f2ee92d55f99ac6a6d4ad537bd03007a04211e4b095` | rev5; 25 concepts; 75 aliases; plural veto groups on the eight affected concepts |
| `ayurveda-data/tests/exclusion-goldens.json` | `fe721b8ef08e5a6f893c26f312245df1725a5a5ebc036f38a8eaa07091a89f42` | rev4; 81 must-exclude; 36 must-not-exclude; 7 contested |

## Part A — rev5 matcher and FC-1 rerun

`vetoTokens` keeps the specified precedence:

`vetoTokens → negativePhrases → phrases`

The generic token comparison now accepts an identical catalogue token or the
authored token plus a trailing `s`. It does not perform arbitrary stemming.
Thus authored `mushroom` matches both `mushroom` and `mushrooms`, while token
order remains irrelevant. Rev5 also carries explicit plural groups as the
director's belt-and-braces data path.

### Gate movements

| Measurement | FC-1d | FC-1e actual | Result |
|---|---:|---:|---|
| Non-contested must-exclude | 62 pass / 14 unresolved / 0 fail | **62 / 14 / 0** | Stable; corpus still lacks the known oat/plural fixtures |
| Non-contested must-not-exclude | 25 pass / 8 unresolved / 1 fail | **26 / 8 / 0** | Blocking G6 fixed |
| Coconut disagreement | 1 | **0** | Complete convergence |
| Equivalent G12 total | 80 | **77** | 73 WE-8-only / 4 FC-1-only |
| Oyster USDA row | incorrectly mollusc + shellfish | **neither** | Veto works |
| Water chestnut | not tree nuts | **not tree nuts** | Stable |
| `meat` membership | 3,785 / 14,484 (26.132%) | **3,785 / 14,484 (26.132%)** | Below 40% |
| Largest tracked file | 82,726,160 bytes | **82,726,160 bytes** | Below 90 MB split point |

### Direct veto evidence

| Name | Normalized tokens | `["oyster","mushroom"]` |
|---|---|---|
| `Oyster mushroom` | `oyster`, `mushroom` | matched |
| `Mushrooms, oyster, raw` | `mushrooms`, `oyster`, `raw` | matched through plural tolerance |

Food ID 6110 (`Mushrooms, oyster, raw`) is absent from `mollusc`,
`shellfish`, and `meat`. Water-chestnut rows remain vetoed from
`tree_nuts`. The former mixed peanut/coconut recipe now inherits tree-nut
membership from its coconut ingredient because the dead owner-level `peanut`
negative phrase is gone.

### Contested — awaiting ruling

Contested cases are reported but do not enter blocking G5/G6 arithmetic.

| Direction | Concept / pattern | Current outcome |
|---|---|---|
| must exclude | pork / `salami` | pass: 18/18 matching rows excluded |
| must exclude | pork / `pepperoni` | pass: 32/32 |
| must exclude | fish / `caesar` | current ontology does not exclude the 9 matches |
| must exclude | shellfish / `scallop` | 7/26 matching rows excluded |
| must exclude | alcohol / `vanilla extract` | 2/3 matching rows excluded |
| must not exclude | fish / `fishcake, vegetarian` | unresolved: no catalogue fixture |
| must not exclude | poultry / `chicken of the woods` | unresolved: no catalogue fixture |

### G12 equivalent-predicate recount

Honey remains omitted because “not Vegan” is not an equivalent honey
predicate.

| Concept/direction | Rows |
|---|---:|
| Dairy, WE-8-only | 25 |
| Gluten, WE-8-only | 23 |
| Meat, WE-8-only | 14 |
| Fish, WE-8-only | 4 |
| Soy, WE-8-only | 4 |
| Tree nuts, WE-8-only | 3 |
| Meat, FC-1-only | 3 |
| Dairy, FC-1-only | 1 |
| **Total** | **77 = 73 WE-8-only + 4 FC-1-only** |

The three remaining tree-nut rows are `dravya.brazil-nut`,
`dravya.panchmeva`, and `dravya.thandai`. Coconut and both oyster directions
are no longer residual causes.

### Missing exclusion-corpus fixtures

The corpus still lacks independent must-exclude fixtures for:

- oats: `oat`, `oats`, `oatmeal`, `rolled oats`, `oat bran`, `oat flour`;
- tree-nut plurals: `almonds`, `cashews`, `walnuts`, `pecans`,
  `pistachios`, `hazelnuts`, `macadamias`, `brazil nuts`, `pine nuts`,
  `chestnuts`; and
- regional tree-nut names: `badam`, `kaju`, `pista`, `akhrot`, `chironji`.

### Nine viaIngredient patterns without recipe fixtures

- absent from the catalogue: `butter chicken`, `aioli`, `marzipan`;
- present only as plain USDA rows, not recipes: `caesar`,
  `worcestershire`, `mayonnaise`, `meringue`, `hollandaise`, `praline`.

This remains a director corpus-fixture gap, not an implementation failure.

## Part B — FC-2 planner wiring

### Authority and set operations

`PlannerConceptExclusions` resolves prompt restrictions to canonical concepts
or explicit food IDs. Candidate filtering is:

```swift
let allowedIDs = candidateIDs.subtracting(blockedIDs)
```

For the 12,601 plain USDA rows, `FoodConcepts.members(of:)` supplies
membership. For the 2,214 seeded rows, the existing WE-8 diets/allergens are
authoritative wherever an equivalent predicate exists. This preserves the
FC-1 authority boundary despite the remaining diagnostic G12 residue.

The live changes are:

| Former path | FC-2 path |
|---|---|
| `containsExcluded` | canonical concept/explicit-ID membership |
| `violatesExcluded` | removed with its dormant placement helper |
| `deriveHardExcludes` | `hardExclusionTerms` + `makePlannerExclusions` |
| `filterCandidates` substring bans | concept ID subtraction plus token-set guards |
| `removeBannedCuisineKeywords` | removed; conceptual components resolve to IDs before exclusion |
| 30-item `alcoholKeywords` | deleted; canonical `alcohol` concept added to every planner exclusion set |

The alcohol artifact excludes real alcoholic rows while its authored negatives
spare every matching root-beer and ginger-ale row.

### No substring exclusion proof

Repository grep returns no definitions or uses of:

```text
containsExcluded
violatesExcluded
deriveHardExcludes
removeBannedCuisineKeywords
alcoholKeywords
```

The permanent FC-2 test also rejects the prior
`excluded/banned.contains { name.contains(...) }` shape. Remaining substring
uses in the planner classify meal structure (protein, fruit, day/meal wording);
they do not decide food exclusions.

### Resolver alias result

| Corpus | Before FC-2 | FC-1e |
|---|---:|---:|
| Training expectations | 59/59 | **59/59** |
| Held-out real foods | 40/48 | **44/48** |
| Wrong-confident matches | 0 | **0** |
| Held-out controls unresolved | 5/5 | **5/5** |

The four remaining real-food gaps are `dahi`, `steamed broccoli`,
`chicken stock`, and `nutritional yeast`. The ontology aliases are consumed
only in their authored `surface → canonical` direction. A trial reverse
expansion was rejected before commit because it changed the established
`lentils` training result; no scorer logic or ranking was changed.

## Final gate ledger

| Gate | Result | Evidence |
|---|---|---|
| Debug + Release | **PASS** | Generic-simulator Debug and Release builds succeeded; modified sources add no warnings |
| Full suite | **PASS — 98/98** | Final discovery run, 39.457s |
| Search goldens | **PASS — 25/25 + 2/2 exact** | No baseline or FoodSearch ranking change |
| Validator | **PASS** | 714 dravyas, 1,500 recipes; D34 12,601/12,601; final preseed audit green |
| G5/G6 | **PASS** | Non-contested 62/14/0 and 26/8/0 |
| Resolution | **PASS** | Training 59/59; held-out 44/48; zero wrong-confident; controls 5/5 unresolved |
| No substring exclusion | **PASS** | Static grep + permanent FC-2 regression test |
| Cold launch | **PASS — 1.433328s** | N=10 same-session ABAB; below 1.650s paydown trigger and 1.700s ceiling |
| Determinism | **PASS** | Two complete seed/rules/concept builds and two preseed builds were pairwise byte-identical |
| Fresh install | **PASS** | `Ayurveda v5 preseed stamp verified; no inserts or updates.` and index version 5 / DB 14,484 `Skipping rebuild.` |
| Tracked artifact size | **PASS** | 992 tracked files scanned; none ≥90 MB |

## Deterministic artifacts and sizes

Seed/rules/concepts were rebuilt twice from the same 12,601-row source
projection. Preseed parts were rebuilt twice from the same audited 14,484-row
source. Each A/B pair was byte-identical.

| Shipped artifact | Bytes | SHA-256 |
|---|---:|---|
| `ayurveda_seed.json.gz` | 1,438,588 | `886c6a3908b9661ae85223b13cc353326a93ef2ac552129b6a60e529e481872e` |
| `ayurveda_rules.json` | 21,151 | `e92ad29fda7616a011090bd3674f9653d33b9553357c49f43ffd87f850c0364c` |
| `food_concepts.json.gz` | 31,165 | `fe200fe30b1a25dfd091fef6099fe5c34844d8460262ec0ab87986a6399dd7b1` |
| `preseeded_db.store.gz.part-aa` | 73,400,320 | `99a977616c554f3e67d683de045b11bf2a2dd6567f41702d71cc5788f42bb817` |
| `preseeded_db.store.gz.part-ab` | 19,162,561 | `f6b0cd508ccd2a5d2e343ce87b166e6f72df75b3b24f5eda528d08cb1e0b291c` |
| tracked 480 video | 82,726,160 | size-gate maximum |
| tracked 144 video | 37,571,026 | below split point |

The preseed projection did not change in FC-1e, so its shipped parts remain the
INT-1 bytes and SHAs. A re-compaction of the reconstructed shipped store
produced a different physical SQLite gzip representation, but two builds from
that identical source reproduced each other exactly and retained all audited
logical counts. No stale store or search artifact was introduced.

The ignored 1024 video was not changed. Its previously confirmed
non-reproducibility remains an IMG-workstream founder item.

## Same-session cold launch

Method:

- retained iOS 26.2 simulator `WiseEating-WE2-Baseline`
  (`AF937668-3BFE-45E8-B42A-A76B914038DD`), the only booted simulator;
- A = `06c767b`; B = final FC-1e;
- separate bundle IDs and containers, arm64 Debug, identical build settings,
  package checkout, preseed resources, and the same ignored 285,519,148-byte
  1024 video;
- both received untimed fresh/warm setup and calendar/reminder permission;
- Xcode, xcodebuild, Swift compiler, Maestro, and CI were absent during the
  accepted series; Spotlight workers were present at 0.0% CPU; Codex,
  CoreSimulator, WindowServer, and ordinary services remained;
- host `time.monotonic()` immediately before `simctl launch --console-pty`;
  terminal marker `WE6_PROFILE|first-interactive-frame|<uptime>`;
- strict AB repeated ten times, terminating the process before every launch.

| Pair | A `06c767b` | B FC-1e | B − A |
|---:|---:|---:|---:|
| 1 | 1.432083s | 1.455626s | +0.023543s |
| 2 | 1.450219s | 1.458849s | +0.008630s |
| 3 | 1.411101s | 1.432131s | +0.021031s |
| 4 | 1.447882s | 1.411632s | −0.036249s |
| 5 | 1.424165s | 1.433406s | +0.009241s |
| 6 | 1.422499s | 1.433250s | +0.010751s |
| 7 | 1.425138s | 1.443772s | +0.018634s |
| 8 | 1.420366s | 1.419741s | −0.000625s |
| 9 | 1.416062s | 1.444165s | +0.028103s |
| 10 | 1.439853s | 1.424607s | −0.015247s |

| Series | N | Median | IQR (Q1–Q3) | Min | Max | Population stddev |
|---|---:|---:|---:|---:|---:|---:|
| A | 10 | **1.424652s** | 0.017011s (1.420900–1.437911) | 1.411101s | 1.450219s | 0.012557s |
| B | 10 | **1.433328s** | 0.017579s (1.426488–1.444066) | 1.411632s | 1.458849s | 0.014320s |
| Paired delta | 10 | **+0.009996s** | 0.018743s (0.001689–0.020431) | −0.036249s | +0.028103s | 0.018698s |

The paired median delta is smaller than both A and B IQRs; the difference is
not resolvable from this sample. Every one of the 20 accepted launches emitted
the version-5 `Skipping rebuild` line.

## Scope and handoff

No FoodSearch ranking, lifecycle, claim, schema, UI-copy, or media-pipeline
change was made. Work is committed only on `fc-1c-g12-rulings`; it is not
merged and not pushed.
