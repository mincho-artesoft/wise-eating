# TASK-D34 — D3 crosswalk + D4 estimated tier, end to end (executor packet)

*Dispatched by director per `DESIGN-D34.md` (normative — read it first, follow it
exactly; copy the three constant lists verbatim). Repo: wise-eating, branch
`ayurveda-app`. Do not push. Touch only the files listed below. Director-authored
inputs `rules/category-rules.json`, `rules/modifiers.json`,
`crosswalk/overrides.json` already exist — read them, never rewrite them.*

## Deliverables

| # | File | Action |
|---|---|---|
| 1 | `ayurveda-data/match_crosswalk.py` | create (DESIGN B2/B3/B5) |
| 2 | `ayurveda-data/crosswalk/crosswalk.csv` | generate via #1, commit |
| 3 | `ayurveda-data/crosswalk/REVIEW-D3.md` | generate via #1, commit |
| 4 | `ayurveda-data/build_seed.py` | edit (DESIGN B7: derived links + rules emission + seedVersion 2) |
| 5 | `Ayura/ayurveda_seed.json.gz` | regenerate, commit |
| 6 | `Ayura/ayurveda_rules.json` | generate via #4, commit |
| 7 | `ayurveda-data/validate.py` | edit (new D34 checks, section 3) |
| 8 | `Ayura/Ayurveda/AyurvedaRules.swift` | create (DESIGN B9 rules loader + modifier engine) |
| 9 | `Ayura/Ayurveda/AyurvedaResolver.swift` | edit (`.estimated` live, derived modifiers) |
| 10 | `Ayura/Main/DBSeed/AyurvedaSeeder.swift` | edit (top-up path, DESIGN B8) |
| 11 | `Ayura/Main/DBSeed/SeedManager.swift` | edit (guard = version key only) |
| 12 | `ayurveda-data/REPORT-D34.md` | create (format below) |

No other file may change. `git diff --stat` in the report must show exactly these.

## 1. match_crosswalk.py

`python3 ayurveda-data/match_crosswalk.py --store /tmp/pre` (store convention as
validate.py). Steps: load dravya batches → build normalized keys (name + aliases +
overrides.extraKeys, minus stopKeys, tracking name-vs-alias source) → for every
store food (ordered by ZID): skip if fdcId ∈ v1-bound set (all `usda[].fdcId`
across batches), primary category ∉ ELIGIBLE, or fdcId ∈ overrides.deny → match
target per DESIGN B2 (segment 1, group-prefix hop to segment 2) → rules M1/M2 →
adjudicate O1,R1–R4 → emit.

Outputs (byte-deterministic, sorted by fdcId, no timestamps):
- `crosswalk.csv` — `fdcId,name,category,dravyaId,rule,key,contested,losers`;
  CSV-quote name/category; losers `;`-joined sorted.
- `REVIEW-D3.md` — three tables: contested (67 rows: fdcId, name, winner, deciding
  rule R1–R4, losers), M2 matches (112 rows: fdcId, name, key, dravya), denies (2).

**Gate G1 (director-simulated — deviation means your normalization or ladder
differs from DESIGN; stop and report, do not "fix" constants to force the number):**
run twice → identical sha256; rows **1,969**; contested **67**; M2 **112**; F **0**;
distinct dravyas **166**; 0 fdcIds overlapping the v1-bound 336; denied fdcIds
8244/12546 absent from CSV.

## 2. build_seed.py (v2)

- Append crosswalk rows to `links` as `{"fdcId": n, "dravyaId": s, "tier": "derived"}`.
  Fail hard on: fdcId missing from store, fdcId already in v1 links, unresolvable
  dravyaId, duplicate fdcId within the CSV.
- Envelope: `seedVersion: 2`; counts add `derivedLinks: 1969, categoryRules: 187,
  modifiers: 14`; total links 2,305. Everything else (dravyas/recipes/placeholders/
  A3/A4 resolution) byte-for-byte as v1 — do not re-derive.
- Emit `Ayura/ayurveda_rules.json`: `{"rulesVersion": 1, "categories": …,
  "default": …, "modifiers": …}` — content lifted verbatim from the two rules files
  (sorted keys, compact separators, deterministic).

**Gate G2:** two runs → byte-identical gz and rules.json (sha256 both); counts
block prints `dravyas 714 · recipes 1500 · links 2305 (336 v1 + 1969 derived) ·
placeholders 383 · categoryRules 187 · modifiers 14 · engineExcluded 2`.

## 3. validate.py additions (run: existing checks must stay green)

- crosswalk.csv: row count 1,969; fdcIds unique, all in store, none v1-bound; all
  dravyaIds resolve; rule ∈ {M1,M2,F}; denied fdcIds absent.
- rules: every store primary category (exactly **187**) has a rule and every rule's
  category occurs in the store (0 dead); vpk and modifier deltas ∈ [−2,2]; virya ∈
  {heating,cooling,neutral}; gunas ⊆ the 10-term enum; modifier ids unique.
- seed gz: links 2,305; seedVersion 2.
- **Resolver simulation (Python mirror of B9):** every one of the 12,601 store
  foods resolves; tier totals **classical 336 / derived 1,969 / estimated 10,296**;
  modifier engine fires on **6,357** of 12,265 non-classical foods; print the
  per-modifier histogram (expect: raw 1356, dry-heat 1031, moist-heat 771,
  sweetened 643, canned 640, rich 565, frozen 548, processed 424, lowfat 344,
  fried 329, cured 212, dried 206, fermented-sour 63, pungent 26).

**Gate G3:** all of the above pass; `python3 ayurveda-data/validate.py --store
/tmp/pre` fully green.

**Gate G4 — spot values (assert in the simulation, list PASS/FAIL per row in the
report):** the 9-row table in DESIGN §Simulated reference numbers, verbatim —
8641 → broiler-chicken [−1,1,2] (fried); 6556 → orange-juice over orange (R2);
4106 → sweet-potato over potato (R1); 11971 → garlic over garlic-fresh-bulb (R3);
3623 → apricot [0,1,−1] (dried); 3923 → estimated [1,0,1] (processed);
68 → [2,−1,2] (frozen); 6148 → [0,2,0] (dry-heat); 2655 → [2,0,−1] (none).

## 4. Swift

- `AyurvedaRules.swift`: `struct` singleton decoding bundle `ayurveda_rules.json`
  once (thread-safe lazy). Must reproduce B6 normalization **exactly** (lowercase,
  strip parentheticals, `&`→" and ", non-`[a-z0-9,;'\- ]`→space, `[,;]`→space for
  modifier matching, tokens split on whitespace/`-`/`'`/`/`, contiguous phrase
  match, each modifier ≤1×, sum, clamp [−2,2], gunas union). Public:
  `rule(forCategory:) -> CategoryRule`, `modifiers(forName:) -> [AppliedModifier]`,
  `estimated(category:name:) -> EstimatedAyurveda`.
- `AyurvedaResolver.swift`: implement DESIGN B9 case set. Derived case computes
  modifiers/adjusted vpk only when `link.tier == "derived"`; confidence
  `max(profile.confidenceAyur − 0.15, 0.1)`. `.estimated` uses first category
  entry, default rule fallback; `.none` only when no category exists.
- `AyurvedaSeeder.swift`: top-up path per B8 — if `AyurvedaProfile` non-empty:
  one fetch of existing `AyurvedaLink.fdcId`s, insert missing links in batched
  transactions, insert nothing else. Fresh path unchanged except 2,305 links.
- `SeedManager.swift`: guard becomes
  `UserDefaults.standard.integer(forKey: "ayurvedaSeedVersion") < seedVersion`;
  success writes the bundle seedVersion (2); catch path unchanged (log, no key).
- Style rules as TASK-D6 §2: no force-unwraps outside the malformed-bundle fatal
  path; no changes to `FoodItem.swift`; match surrounding style. Sandbox has no
  Xcode — compilation and the two seeding paths (fresh + v1→v2 top-up) are founder
  gate items; say so in the report, do not claim a build passed.

## 5. REPORT-D34.md format

Sections: Summary · match_crosswalk output block · Gate results G1–G4 (each with
evidence: counts, sha256 pairs, spot-value PASS/FAIL table) · Contested sample
(10 rows with deciding rule) · Modifier histogram · Files changed
(`git diff --stat`) · Open items for founder gate (build, fresh seed = 2,305 links,
v1→v2 top-up = +1,969 links & idempotent relaunch, existing flows unaffected).
Commit message: `D34: USDA crosswalk + category rules — all 12,601 foods classified
(derived + estimated tiers)`. One commit per deliverable group is fine; do not push.
