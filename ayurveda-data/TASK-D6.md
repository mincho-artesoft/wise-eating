# TASK-D6 — Implement Ayurveda schema + one-time seeder (executor packet)

*Dispatched by director per `DESIGN-D6.md` (normative — read it first, follow it
exactly). Repo: wise-eating. Do not push. Touch only the files listed below.*

## Deliverables

| # | File | Action |
|---|---|---|
| 1 | `ayurveda-data/build_seed.py` | create |
| 2 | `WiseEating/ayurveda_seed.json.gz` | generate via #1, commit |
| 3 | `WiseEating/Ayurveda/AyurvedaProfile.swift` | create (both models, per DESIGN §Model definitions, verbatim field set) |
| 4 | `WiseEating/Ayurveda/AyurvedaResolver.swift` | create (A9) |
| 5 | `WiseEating/Main/DBSeed/AyurvedaSeeder.swift` | create (the insert pass) |
| 6 | `WiseEating/Main/DBSeed/SeedManager.swift` | edit: add `await seedAyurvedaIfNeeded(context: ctx)` directly after `seedFoodsIfNeeded` |
| 7 | `WiseEating/Main/DBSeed/DatabaseSetup.swift` | edit: append `AyurvedaProfile.self, AyurvedaLink.self` to `mainTypes` |
| 8 | `ayurveda-data/REPORT-D6.md` | create (format below) |

No other file may change. `git diff --stat` in the report must show exactly these.

## 1. build_seed.py

Inputs: `dravyas/batch-*.json`, `recipes/batch-*.json`, the preseeded store
(`--store` arg, same convention as `validate.py`). Steps:

1. Load all items; fail on duplicate ids.
2. **Primary food resolution (DESIGN A3)** — two passes. Pass 1: per distinct
   fdcId, winner = best-tier claimant (`exact` > `near`), tie → lexicographically
   smaller dravya id. Pass 2: each dravya takes its first binding (exact before
   near) that it won; if it won none (or has no bindings) it gets a placeholder:
   `900000 + ordinal` over the id-sorted list of placeholder-needing dravyas,
   `foodIsPlaceholder: true`. Verify every chosen fdcId exists in the store
   (`ZFOODITEM.ZID`).
3. Recipe foodIds: `1000000 + ordinal` over id-sorted recipes.
4. Resolve every recipe ingredient to a concrete `foodId` (`dravyaId` → that
   dravya's foodId; `fdcId` → verified against store). Zero unresolved allowed.
5. Links: one row per distinct bound fdcId → the A3-winning dravya, with its tier.
6. `engineExcluded: true` for exactly `dravya.betel-nut` and `dravya.vanaspati`.
7. Emit the JSON envelope from DESIGN A5 (sorted keys, `sort_keys=True`,
   `generatedAt` allowed only in the envelope header), gzip with `mtime=0` so the
   artifact is **byte-deterministic**; write to `WiseEating/ayurveda_seed.json.gz`.
8. Print a summary block (counts, contested-fdcId table, placeholder list) — paste
   it into the report.

Gate: run twice, `sha256sum` identical; counts = 714 dravyas / 1500 recipes /
336 links / **383 placeholders / 331 primaries** (director-simulated — deviation
means your resolution differs; stop and report); unresolved ingredients = 0;
excluded = 2.

## 2. Swift

- Models: copy the DESIGN definitions exactly (field names/types are normative).
  Memberwise inits with defaults matching the declarations.
- `AyurvedaSeeder.swift`: `@MainActor enum AyurvedaSeeder { static func run(context:) throws }`
  - Decode bundle resource `ayurveda_seed` (`.json.gz`) via `ZlibGzip.decompress`
    into plain `Decodable` structs (do not decode into @Model types).
  - **Band check first**: fetch any existing FoodItem ids in `900000..<1002000`;
    if non-empty → print diagnostic and `throw` (fail-open, DESIGN A6).
  - Insert order, batched `context.transaction` every ~200 items:
    (a) placeholder FoodItems, (b) dravya profiles, (c) links,
    (d) recipe FoodItems + IngredientLinks (build an `[Int: FoodItem]` map of the
    12,601 store foods + placeholders **once** with one fetch, not per-ingredient
    fetches), (e) recipe profiles.
  - Recipe FoodItem: name, `isRecipe: true`, `isUserAdded: false`,
    `prepTimeMinutes = prep + cook`, `itemDescription` = `"1. …\n2. …\n\n" + guidance`.
  - No writes to UserDefaults here; the version key is SeedManager's job.
- `SeedManager.seedAyurvedaIfNeeded`: guard `databaseIsEmpty(AyurvedaProfile.self)`
  **and** `UserDefaults.standard.integer(forKey: "ayurvedaSeedVersion") < seedVersion`;
  call the seeder; on success `set(seedVersion)`; on catch: log, do not set the key,
  return normally.
- `AyurvedaResolver`: enum result `.classical/.recipe/.derived/.none` per DESIGN A9
  (`.estimated` as a documented stub returning `.none` until D4). One
  `FetchDescriptor` per lookup, using the indexed fields.

## 3. Verification you must run (sandbox has no Xcode — these are the substitutes)

1. `python3 ayurveda-data/validate.py --store /tmp/pre` — still green.
2. build_seed determinism + counts gate (above).
3. A Python re-check that reads the generated gz and asserts: every profile foodId
   is unique within its kind, every recipe ingredient foodId exists among
   (store ids ∪ placeholder ids ∪ recipe ids is NOT allowed — ingredients may not
   reference other recipes in v1; assert none do), kitchari total ingredient grams
   ≈ 1852.
4. Swift files: no force-unwraps except decode of a malformed-bundle fatal path;
   no changes to `FoodItem.swift`; `swift-format`-clean if available, otherwise
   match surrounding style.

Compilation and device behavior are checked at the founder gate (Mac) — say so in
the report rather than claiming a build passed.

## 4. REPORT-D6.md format

Sections: Summary · build_seed output block · Contested fdcIds (40 rows: fdcId,
winner, tier, losers) · Placeholder dravyas (count + full id list) · Gate results
(each gate, pass/fail, evidence) · Files changed (`git diff --stat`) · Open items
for founder gate. Commit message: `D6: Ayurveda schema + seeder (models, seed bundle, SeedManager hook)`.
One commit per deliverable group is fine; do not push.
