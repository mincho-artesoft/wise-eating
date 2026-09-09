# TASK — NUT-1: quarantine bad IFCT matches, complete the mapping, fill what is honestly fillable

Director packet · 2026-08-01 · `ayurveda-data/nutrition/`
Rulings this packet executes: `DECISIONS-NUT.md` §N1, §N2, §N3.

**Stop-and-report rule applies.** Any gate that misses its stated number → capture
verbatim, stop, do not tune the constant to make it pass.

---

## 0. Read first

- `ayurveda-data/nutrition/README.md` — especially "THERE IS NO SYNONYM LIST"
  and "WHY THE REJECTED MATCHER IS KEPT".
- `DECISIONS-NUT.md` §N1–N3.

The priority in this packet is inverted from the obvious one. **Fixing the 56
matches you already have is worth more than filling the 298 you do not**, and
completing the nutrient mapping for those 56 is worth more than both. Do the
phases in order.

---

## 1. The shape of the problem, measured

Reproduce these before changing anything. They are the gates for phase 0.

| Quantity | Value |
|---|---|
| IFCT rows / value columns | 542 / 214 |
| Match keys built from `name` + `lang` | **3,435** |
| dravya food records | 376 |
| records with ≥1 non-null nutrient | **61** = 56 IFCT + 5 hand-sourced |
| hand-sourced, outside IFCT | `barnyard-millet`, `black-rice`, `buffalo-ghee`, `camel-milk`, `chana-dal` |
| unresolved | 320 = 22 ambiguous + 298 unmatched |
| schema nutrient fields / ever populated | 122 / **67** |
| of the 298: no token relation to any key | **178** (permanently unfillable) |
| of the 298: superset of a key (form variant) | **101** |
| of the 298: subset of a key | **19** |

---

## 2. Phase 0 — the reverse-collision assertion (do this first)

`match_ifct.py` flags one-dravya→many-rows as ambiguous. It has no check for
**many-dravyas→one-row**. Add it, and make it refuse to write when it fires.

Expected today: **7 IFCT rows feeding 15 dravyas.** Exact set and disposition:

| IFCT row | dravyas fed | ruling |
|---|---|---|
| `D001` Ash gourd | Ash gourd (juicing flesh), Ash gourd (tender, for sabzi), **Ash gourd murabba (petha)** | **strip petha** — sugar-preserved, added ingredient, §N1. Keep the two raw forms, flag identical-by-construction |
| `A011` Rice flakes | Flattened rice, **Kanda poha** | **strip kanda poha** — cooked dish with onion, potato, oil |
| `A017` Varagu | Kodo millet, **Foxtail millet** | **strip foxtail millet** — *Setaria italica* vs *Paspalum scrobiculatum*. IFCT's own `lang` reads `E. Kodo millet`; kodo is correct |
| `E067` Wood Apple | Wood apple (kaith), **Elephant apple (ou-tenga)** | **strip elephant apple** — *Dillenia indica* vs *Limonia acidissima*. IFCT lists `E. Elephant apple` as a synonym; IFCT is wrong |
| `E034` Lime, sweet, pulp | Sweet lime (mosambi), **Sweet lime juice** | **strip juice** — pulp ≠ juice; requeue under §N1 dilution with a cited yield |
| `B002` Bengal gram, whole | Black chickpea, White chickpea | **strip White chickpea** — B002 is desi/kala chana per `lang`; kabuli differs in fibre and protein |
| `D073` Tinda, tender | Punjabi tinda (apple gourd), Round gourd (tinda) | **keep both, open a dedup issue** — these two dravyas are duplicates of each other, not a nutrition bug |

**Gate G0.** After the strip: assertion reports 0 unreviewed collisions;
6 records lose all nutrition (petha, kanda poha, foxtail millet, elephant apple,
sweet lime juice, white chickpea); records with ≥1 non-null nutrient falls
**61 → 55**. Any other number, stop.

Each stripped record keeps `_review` with
`status: "withdrawn — wrong IFCT row, see TASK-NUT1 §2"` and the withdrawn code,
so the mistake stays auditable. Do not silently blank them.

---

## §3.0 Phase 0.5 — wire dravya_foods.json into the build

The build currently reads Ayura/Legacy/foods.json for placeholder nutrition,
so nothing in dravya_foods.json reaches a recipe, a panel or the app. Every
value sourced in this packet is inert until this is done, and four recipes
are wrongly classified "estimated" today for this reason alone
(recipe.horse-gram-soup, recipe.parwal-sabzi, recipe.tinda-sabzi,
recipe.samak-rice-fasting).

Make dravya_foods.json the source for the 376 placeholder dravyas, keyed on
dravyaId and never on the numeric id — the placeholder band renumbers
whenever the dravya set changes (build_seed.py:2524). Strip _review and
dravyaId at ingest. A null stays null and must never become 0.

Gate G0.5: the four recipes above move estimated → full with no new sourcing,
and the transitional snapshot in the nutrition coverage test is updated in the
same commit that changes it.

---

## 3. Phase 1 — complete the mapping for the rows already matched

Pure gain, no matching risk: these are rows whose identity is already settled.

### 3.1 Individual fatty acids

The schema has 44 lipid fields; only the 4 totals are ever populated. IFCT ships
per-acid columns. Map them: `f4d0`…`f24d0` → `sfa*`, `f14d1`…`f24d1cn9` →
`mufa*`, `f18d2cn6`/`f18d3n3`/`f20d4n6`/`f20d5n3`/`f22d6n3` → `pufa*`,
`f18d1tn9` and the trans set → `tfa*`. All are g/100 g; multiplier 1.

### 3.2 The unmapped IFCT nutrient classes

Add schema fields for what IFCT measures and we discard: polyphenols (the
~30 individual compounds), phytate, oxalates (total / soluble / insoluble),
the fibre split (`fibins` / `fibsol`), organic acids, saponins, the
tocopherol and tocotrienol splits, oligosaccharides (raffinose, stachyose,
verbascose, ajugose), and the toxic-mineral set. Derive the exact list from the
214 value columns minus the 67 currently populated; report it before writing.

**Landmine — read before extending `MAP`.** IFCT's header labels column `glu`
as *"Glucose"*, but it sits in the amino-acid block and it is **glutamic acid**.
Verified: green gram `glu` = 4.188 g while ripe papaya `glu` = 0.058 g; free
glucose is the separate `glus` column (papaya 1.15 g). The current mapping is
correct. Anyone extending `MAP` by reading header labels will write glutamic
acid into the sugar field.

**Gate G1.** No existing non-null value changes. Report populated-field count
67 → N with the new N stated. Two-run determinism.

---

## 4. Phase 2 — fill what is honestly fillable

### 4.1 Do not loosen the matcher (§N2)

The 101 supersets are form variants, not synonym gaps. Loosening produces the
petha failure 101 times. The `OTHER QUALIFIER` bucket — 71 of the 101 — is
coincidental token overlap with no real base relationship at all
(`Ash plantain` → `Potato, brown skin, big`, via the alias `alu kesel`).

### 4.2 The §N1 candidates

**13 total**, and they do not all survive:

- **Water loss, 5.** Dried amla, Dried water chestnut, Jamun seed powder,
  Roasted gram flour (sattu), Water chestnut flour.
- **Dilution/extraction, 8.** Amla juice, Ash gourd juice, Badam milk,
  Ajwain water, Barley water, Coriander seed water, Cumin water, plus one more.

Director's read, to be argued with rather than accepted: the four *waters* are
**infusions, not dilutions** — almost no solids transfer, and a cited dilution
factor would still be the wrong model. Badam milk carries added milk and sugar,
so it is §N1 added-ingredient and stays null. Roasted gram flour changes both
water and the base grain state. That leaves roughly **Amla juice, Ash gourd
juice, Dried amla, Dried water chestnut** as defensible, each needing a cited
per-food yield factor before a single number is written.

**Gate G2.** Every filled record carries `_review.provenance: "derived"`, a
base IFCT code, and a citation for the yield factor. A record without all three
does not ship. Expected fills: **2–4**. If a run reports more than 6, stop —
the derivation rule has been stretched.

### 4.3 The 22 ambiguous

Resolve by hand, one at a time, recording the losing candidates. `betel-nut`
(H002/H003/H004) and `betel-leaf` (C010/C011) are engine-excluded (fixed
decision 4) — they still get correct nutrition, they are simply never
recommended.

### 4.4 The 178

The 178 have no token relationship to any of the 3,435 IFCT keys and remain
unmatched by IFCT. Of those records, 176 are null. Black rice and Camel milk
retain their pre-existing published-literature values, which predate NUT-1.
Zero records in this set acquire a value during Phase 2.

The 178 is defined by IFCT matchability, not by nullness. A record can be
unmatchable and still be sourced from published literature. Record the count
and category breakdown in the report so that "why is this null" has a durable
answer.

---

## 5. Report

`REPORT-NUT1.md`, with: the phase-0 strip list and G0 arithmetic; the new
populated-field count; the exact §4.2 fill list with citations; the 22
ambiguous resolutions with losing candidates; and the final
`61 → 55 → 55 + fills` chain. State plainly that the 298 was not filled and
why — that sentence is the deliverable, not a shortfall.
