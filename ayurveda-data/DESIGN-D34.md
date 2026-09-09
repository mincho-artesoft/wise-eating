# D34 Design — D3 Crosswalk + D4 Category Rules (Director)

*Status: APPROVED FOR DISPATCH · 2026-07-22 · Design authority: RESTART-PLAN.md D3+D4,
DESIGN-D6.md (A2, A6, A9 are extended here, not changed in spirit). Implementation:
Codex packet `TASK-D34.md`.*

## Objective

Complete the three-tier promise of RESTART-PLAN decision 2: **every one of the 12,601
USDA foods resolves to a dosha profile**, tier always visible:

| Tier | Source | Foods | Storage |
|---|---|---|---|
| classical | D6 `AyurvedaLink` tier exact/near | 336 | already seeded (v1) |
| derived | D3 crosswalk → `AyurvedaLink` tier `derived` | **1,969** | +rows in same model (D6 A2) |
| estimated | D4 category rules + name modifiers | **10,296** | nothing stored; computed at lookup (D6 A2) |

336 + 1,969 + 10,296 = 12,601. All D34 numbers in this document were
**director-simulated against the real store on 2026-07-22** (reference simulation:
name-match of 714 dravya names+aliases against `ZFOODITEM.ZNAME`/`ZCATEGORY`).

Out of scope: all UI (D8), expert review promotion, recipe changes, any edit to
existing dravya/recipe batches.

## Data reality (measured 2026-07-22)

| Fact | Value |
|---|---|
| Store foods / distinct primary categories | 12,601 / **187** (every food has ≥1 category; primary = first array entry; 1,994 foods have >1 — only the first is used) |
| `ZCATEGORY` format | JSON array of strings in a BLOB column (e.g. `["Spices and Herbs"]`) |
| v1-bound fdcIds (all dravya bindings, exact+near) | 336 distinct |
| Dravya match keys (names + aliases, normalized, deduped) | 1,608 |
| D3-eligible categories (whole-food classes, list below) | 89 of 187 |
| Simulated derived matches | **1,969** (67 contested, 112 via stopword-stripped rule M2), covering **166 dravyas** |
| Curated denies at dispatch | 2 (fdcId 8244 apricot-kernel oil, 12546 avocado leaf) |
| Estimated remainder | **10,296** foods across **178** categories (9 categories fully consumed by classical+derived) |
| Foods (derived+estimated) firing ≥1 name modifier | **6,357** of 12,265 |
| No classical beef dravya | deliberate (gomamsa unbound) → all 991 beef-category foods are estimated-tier |

## Decisions

**B1 — Storage exactly as D6 A2 promised.** Derived tier = new `AyurvedaLink` rows,
tier `"derived"` — no schema change. Estimated tier stores nothing: rules ship as a
small bundle resource and are evaluated at lookup. Total links after D34: **2,305**
(336 v1 + 1,969 derived).

**B2 — Normative matching algorithm (D3).** Implemented in a new
`ayurveda-data/match_crosswalk.py`; the constants below are **normative — copy them
verbatim**, they are what the simulation used and the gates assume.

Normalization `norm(s)`: lowercase → strip parentheticals `\([^)]*\)` → `&`→` and `
→ replace every char not in `[a-z0-9,;'\- ]` with space.
Tokens `toks(s)`: split on `[\s\-'/]+`, drop empties.
Segments: split `norm(name)` on `[,;]`, trim, drop empties.

Match target: the token tuple of segment 1; **if segment 1 is a group prefix**
(list below) and a segment 2 exists, use segment 2 instead (USDA writes
"Spices, turmeric, ground", "Nuts, coconut water").

Keys per dravya: `name` + every `aliases[]` entry (+ `extraKeys` from overrides),
normalized to token tuples. A store food is a candidate only if it passes the
**category gate** (its primary category is in ELIGIBLE) and its fdcId is not among
the 336 v1-bound and not denied.

Match rules, evaluated per key:
- **M1**: key tokens == target tokens exactly.
- **M2**: key tokens == target tokens after removing DESCRIPTOR_STOPWORDS
  (only if the stripped target is non-empty).

No other rule. Subsequence/substring matching is deliberately excluded (it produced
garlic-bread→garlic class errors in simulation).

**B3 — Adjudication ladder (the D3 crosswalk adjudication rules).** When several
dravyas claim one food, the winner is chosen by the first rule that discriminates;
this ladder is total and deterministic:

| # | Rule | Rationale / example |
|---|---|---|
| O1 | `overrides.force[fdcId]` wins outright; `deny` removes the food from D3; `denyPairs` removes one candidate | curated layer, survives regeneration |
| R1 | M1 beats M2 | "Sweet potato, baked" → `dravya.sweet-potato` (M1), not `dravya.potato` (M2 via stripped "sweet") |
| R2 | longer key (more tokens) beats shorter | "Orange juice, chilled" → `dravya.orange-juice`, not `dravya.orange` |
| R3 | key that is a dravya's `name` beats a key that is only an `alias` | "Garlic (fresh and dried)" → `dravya.garlic` (name), not `dravya.garlic-fresh-bulb` (alias "garlic") |
| R4 | lexicographically smaller dravya id | same tie-break as D6 A3; e.g. `dravya.almond-milk` over `dravya.badam-milk` |

A food matched by several keys of the *same* dravya yields one row. Losers are
recorded in the CSV and the review file — the expert re-points via `overrides.json`,
never by editing the CSV.

**B4 — Overrides file** `crosswalk/overrides.json` (authored, committed, this is the
review interface): `force {fdcId: dravyaId}`, `deny [fdcId]` (+`denyNotes`),
`denyPairs [[fdcId, dravyaId]]`, `stopKeys [key]` (kills a key globally),
`extraKeys {dravyaId: [key]}`. Ships with 2 denies (8244, 12546).

**B5 — Outputs.** `match_crosswalk.py --store …` writes both, byte-deterministically
(fixed ordering by fdcId, no timestamps):
- `crosswalk/crosswalk.csv` — header
  `fdcId,name,category,dravyaId,rule,key,contested,losers`
  (rule ∈ M1/M2/F; contested 0/1; losers `;`-joined, empty allowed). 1,969 rows.
- `crosswalk/REVIEW-D3.md` — review packet: contested table (67), M2-only table
  (112), denies (2). This is the "human-reviewed" artifact RESTART-PLAN D3 requires;
  reviewer actions land in `overrides.json`.

**B6 — D4 rules (authored by director, committed with this design).**
- `rules/category-rules.json` — **187 rules**, one per store category, each
  `{category, vpk:[v,p,k], virya, gunas[], note?}` + a `default` (vpk [0,0,0],
  neutral) that the validator forbids reaching for the current store. Matched on the
  **first** entry of the food's category array. Estimated confidence: fixed
  `ayur 0.25`, qualityState `aiDraft`.
- `rules/modifiers.json` — **14 name modifiers** (fried, dry-heat, raw, dried,
  canned, frozen, fermented-sour, cured, sweetened, rich, pungent, lowfat,
  moist-heat, processed). Matching: phrases as contiguous token sequences against
  the **full** normalized name with `[,;]` replaced by space (so "cooked, fried"
  fires; token matching keeps "unsalted"/"refried" from firing "salted"/"fried").
  Each modifier fires ≤1×; deltas sum onto base vpk; **clamp to [−2,2]**; gunas
  union; virya unchanged.
- Modifiers apply to **derived and estimated tiers only**. Classical (exact/near)
  and dravya-primary foods show the hand-authored profile untouched.
- Derived-tier confidence: `max(dravya.confidence.ayur − 0.15, 0.1)`.

**B7 — Seed bundle v2.** `build_seed.py` (extended, not rewritten):
- reads `crosswalk/crosswalk.csv` and appends `{"fdcId", "dravyaId", "tier": "derived"}`
  entries to the existing `links` array → 2,305 links; envelope `seedVersion: 2`;
  `counts` gains `"derivedLinks": 1969`, `"categoryRules": 187`, `"modifiers": 14`.
- additionally emits `Ayura/ayurveda_rules.json` — a small uncompressed bundle
  resource `{rulesVersion, categories, default, modifiers}` consumed by the resolver
  at runtime (loading the 12MB seed gz per lookup-cache init would be absurd).
- determinism gate unchanged: two runs → byte-identical gz **and** rules.json.
- consistency: every crosswalk fdcId must exist in the store, must not collide with
  a v1-bound fdcId, and every dravyaId must resolve — hard failures.

**B8 — Seeder upgrade path (the only D6-behavior change).**
`SeedManager.seedAyurvedaIfNeeded` guard becomes **version-key only**
(`UserDefaults "ayurvedaSeedVersion" < bundle seedVersion`) — the
`databaseIsEmpty(AyurvedaProfile.self)` conjunct is removed, because v1-seeded dev
installs must be able to take the v2 top-up. `AyurvedaSeeder.run` gains two paths:
- **fresh** (`AyurvedaProfile` empty): the unchanged v1 full pass, now inserting all
  2,305 links.
- **top-up** (profiles exist): fetch existing link fdcIds once, insert only missing
  links (→ +1,969 on a v1 install), touch nothing else.
Both paths end with the version key set to 2; failure still rolls back, doesn't set
the key, fail-open (D6 A6). Idempotence: a second run inserts 0 rows. Nothing here
threatens shipped users — the app is pre-release; bands, models, recipes untouched.

**B9 — Resolver: `.estimated` goes live (closes the D6 A9 stub).**
New `Ayura/Ayurveda/AyurvedaRules.swift`: singleton that decodes
`ayurveda_rules.json` once, mirrors the normalization of B6 exactly, and exposes
`categoryRule(for:)` + `appliedModifiers(name:)`. `AyurvedaResolver.resolve(for:)`
becomes total for store foods:
- `.classical(profile)` / `.recipe(profile)` — unchanged (foodId lookup).
- `.derived(profile, via: link, modifiers: [AppliedModifier], vpk: (Int,Int,Int))`
  — via fdcId link; `modifiers`/adjusted vpk computed only when
  `link.tier == "derived"`, empty/base otherwise.
- `.estimated(EstimatedAyurveda)` — value struct (not a @Model):
  `{vpk, virya, gunas, appliedModifiers, categoryRule, confidence: 0.25}` from the
  food's first category (default rule if the category is unknown — user-added foods
  included, so the resolver **never returns nil for a food with a category**).
- `.none` only for items with no category at all.

## Simulated reference numbers (gate source of truth)

| Metric | Value |
|---|---|
| crosswalk.csv rows (derived) | **1,969** |
| … contested (losers non-empty) | **67** |
| … rule M2 | **112** |
| … rule F (force) | 0 |
| distinct dravyas receiving derived foods | **166** |
| denied fdcIds (in overrides, absent from CSV) | **2** |
| top derived targets | pork 347 · lamb 296 · broiler-chicken 233 · turkey 140 · corn 67 · chicken-egg 56 |
| links in seed v2 | **2,305** |
| estimated foods | **10,296** (12,601 − 336 − 1,969) |
| category rules / dead rules / uncovered categories | **187 / 0 / 0** |
| foods (derived+estimated) firing ≥1 modifier | **6,357** of 12,265 |
| modifier histogram | raw 1356 · dry-heat 1031 · moist-heat 771 · sweetened 643 · canned 640 · rich 565 · frozen 548 · processed 424 · lowfat 344 · fried 329 · cured 212 · dried 206 · fermented-sour 63 · pungent 26 |

Spot values (director-verified against the real store; report must reproduce):

| fdcId | Food | Expect |
|---|---|---|
| 8641 | Chicken, broilers or fryers, breast, … fried | derived `dravya.broiler-chicken`, base [−1,0,1], mods [fried] → **[−1,1,2]** |
| 6556 | Orange juice, chilled | derived `dravya.orange-juice` (R2; loser `dravya.orange`) |
| 4106 | Sweet potato, baked | derived `dravya.sweet-potato` (R1; loser `dravya.potato`) |
| 11971 | Garlic (fresh and dried) | derived `dravya.garlic` (R3; loser `dravya.garlic-fresh-bulb`) |
| 3623 | Apricot, dried | derived `dravya.apricot`, mods [dried] → **[0,1,−1]** |
| 3923 | Potato, mashed, from dry mix | estimated, cat rule [0,0,1] + processed → **[1,0,1]** |
| 68 | Frozen yogurt, NFS | estimated, [1,−1,2] + frozen → **[2,−1,2]** |
| 6148 | Beef, porterhouse … broiled | estimated, [−1,1,1] + dry-heat → **[0,2,0]** |
| 2655 | Popcorn, NFS | estimated, **[2,0,−1]**, no modifiers |

## Normative constants (copy verbatim into match_crosswalk.py)

GROUP_PREFIXES (21):
```
alcoholic beverage · alcoholic beverages · beverages · candies · cereals ·
cereals ready to eat · crustaceans · fish · fruit juice · game meat ·
leavening agents · mollusks · nuts · oil · sauce · seeds · soup · spices ·
sweetener · syrups · vegetable oil
```

ELIGIBLE categories (89) — D3 runs only inside these; everything else is
mixed/processed and goes straight to D4:
```
American Indian/Alaska Native Foods · Apple juice · Apples · Bacon · Bananas ·
Bean · Beans · Beef · Beef Products · Beer · Blueberries and other berries ·
Bottled water · Breakfast Cereals · Broccoli · Butter and animal fats · Cabbage ·
Carrots · Cereal Grains and Pasta · Cheese · Chicken · Citrus fruits ·
Citrus juice · Coffee · Cold cuts and cured meats · Corn ·
Cottage/ricotta cheese · Cream and cream substitutes · Cream cheese ·
Dairy and Egg Products · Dried fruits · Eggs and omelets · Enhanced water ·
Fats and Oils · Finfish and Shellfish Products · Fish · Fruit drinks ·
Fruits and Fruit Juices · Grapes · Grits and other cooked cereals · Ground beef ·
Lamb · Legumes and Legume Products · Lettuce and lettuce salads ·
Liver and organ meats · Mango and papaya · Melons · Milk ·
Mustard and other condiments · Not included in a food category ·
Nut and Seed Products · Nuts and seeds · Oatmeal · Olives · Onions ·
Other dark green vegetables · Other fruit juice · Other fruits and fruit salads ·
Other red and orange vegetables · Other starchy vegetables ·
Other vegetables and combinations · Pasta · Peaches and nectarines · Pears ·
Pineapple · Plant-based milk · Pork · Pork Products · Poultry Products · Rice ·
Salad dressings and vegetable oils · Sausages · Shellfish · Spices and Herbs ·
Spinach · Strawberries · String beans · Sugars and honey · Tap water · Tea ·
Tomatoes · Turkey · Vegetable juice · Vegetables and Vegetable Products ·
Vegetables on a sandwich · Baby water · White potatoes · Wine · Yogurt · peas
```

DESCRIPTOR_STOPWORDS (132) — removed from the match target for rule M2 only:
```
added all as baked bitter boiled bone boneless bottled bulb canned chili chopped
coarse cold commercial common concentrate cooked crushed cultivated dark
dehusked dehydrated domestic drained dried dry edible enriched expeller extra
fat fine flesh flour fluid form fresh from frozen grain grains green ground
hot hulled husked immature in instant juice kernel kernels large leaf leaves
light liquid low mature meat medium milled nfs nonfat ns organic paste peeled
plain pod pods polished portion powder powdered prepared pressed quick raw
reconstituted red reduced refined regular ripe roasted root salt salted seed
seeds shell shelled skin skinless slice sliced small solids split steamed stick
sticks stone style sweet sweetened tap to type uncooked unenriched unhulled
unpeeled unprepared unripe unsalted unshelled unsweetened varietal varieties
variety virgin white whole wild with without yellow young
```

## Risks

- **M2 precision** (112 rows): stopword stripping can over-reach ("Wild onion
  (dried)"→onion is right; "Avocado leaf"→avocado was wrong and is denied). All 112
  are individually listed in REVIEW-D3.md; the override file is the correction
  channel. Accepted for aiDraft.
- **Modifier false fires**: `mix` (processed) also hits "snack mix"/"trail mix" —
  deltas are ±1 and directionally defensible; review pass can tune phrases in one
  file without touching code.
- **Executor divergence from simulation**: any count drift means the normalization
  or ladder differs — the gates instruct stop-and-report, exactly like D6's
  383-placeholder gate.
- **Guard relaxation (B8)**: removing the empty-table conjunct makes the version key
  the single authority. A user who wipes UserDefaults but keeps the store would
  trigger a top-up pass — which inserts 0 rows (idempotent), harmless.
- **Category drift in future USDA imports**: unknown categories fall to `default`
  neutral with the lowest confidence; validator pins today's 187 exactly.
