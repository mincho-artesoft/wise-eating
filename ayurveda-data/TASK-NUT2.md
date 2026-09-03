# TASK — NUT-2: authored age floors, cited; and the legacyImport display fix

Director packet · 2026-08-01 · `ayurveda-data/nutrition/dravya_foods.json`
Ruling this packet executes: `DECISIONS-NUT.md` §N4.
Governing decision: PROJECT-HANDBOOK §3 fixed decision 10 (unamended).

**Stop-and-report rule applies.**

---

## 1. Result up front

The citation pass was run against the seven category rules in
`build_dravya_foods.py` `AGE_RULES`. **Two survive. Five do not, and two of
those are contradicted by the sources**, not merely unsupported.

| rule as proposed | records | verdict |
|---|---|---|
| `medicinal`, `salt-mineral` → 48 mo | 42 | **does not ship** — no authority sets an age threshold |
| `dry-fruit-nut`, `seed` → 48 mo | 12 | **ships, revised to 60 mo, whole forms only** |
| `spice` → 24 mo | 31 | **does not ship** — no authority; only commercial blogs |
| `fermented` → 24 mo | 12 | **does not ship, contradicted** — plain yoghurt is safe from 6 mo |
| `animal` → 12 mo | 12 | **does not ship, contradicted by a strong WHO recommendation** |
| `beverage`, `preparation` → 12 mo | 80 | **does not ship as stated** — replaced by narrower cited rules |
| everything else → 6 mo | 187 | **ships** |

So of 373 proposals, the citable authored set is **187 at 6 months plus a
revised nut/seed rule**, and roughly 177 proposals do not become authored floors.
Those records keep their current value and — under §3 — stop rendering an age at
all, which is the actual safety improvement in this packet.

**The most important line in this packet is not a floor.** It is §3: stop
rendering a number for `legacyImport` provenance. That fixes an affirmative
infant-safety claim the app has no basis for, on 701 dravyas, and it needs no
citation because it removes a claim rather than making one.

---

## 2. The citable rule set

Each rule ships with `ageProvenance: "authored"` and the citation in
`ageSource`. A rule without a source does not ship — §N4.

### R1 · Weaning floor, 6 months — 187 records

> "introduction of nutritionally-adequate and safe complementary (solid) foods
> at 6 months together with continued breastfeeding up to 2 years of age or
> beyond" — WHO, *Infant and young child feeding*, 20 Dec 2023.

Applies to `grain`, `legume`, `vegetable`, `leafy-green`, `fruit`, `dairy`,
`oil-fat`, `sweetener`, `regional`. This coincides with *annaprashana* in the
sixth month (Kashyapa Samhita), and the build script's comment already says so.
Cite WHO as the enforcing source; keep the classical note as commentary.

### R2 · Whole nuts and seeds, 60 months — whole forms only

> "Whole nuts should not be given to children under 5 years old, as they can
> choke on them" — NHS, *Foods to avoid giving babies and young children*.
> Corroborating: AAP choking policy names nuts and seeds among round, firm foods
> for children under 4.

**Two corrections to the proposal.** The floor is **60 months, not 48** — NHS is
both more specific and stricter, and the project's posture is conservative
(fixed decisions 5, 9). And it is a **form** rule, not a substance rule: the same
NHS page allows ground or crushed nuts from around 6 months. Applying it to the
`dry-fruit-nut`/`seed` *category* would floor `Coconut sugar`, `Coriander seed
water` and `Badam milk` at 5 years, which is wrong.

Executor: apply to whole-form entries only. Produce the candidate list from the
12 category records, hand it back for director ruling per item, and do not
self-resolve. This is the one rule where the category is the wrong unit.

### R3 · Honey, 12 months — already authored, now cited

> "Do not give your child honey until they're over 1 year old" — NHS, ibid.

No change in behaviour. Attach the citation to the existing rule so the only
pre-existing authored floor stops being uncited.

### R4 · No added salt under 12 months

> "Do not add salt to your baby's food or cooking water" — NHS, ibid.
> Maximum daily salt: "<1g/day" at 0–6 months, "1g/day" at 6–12 months,
> "2g/day" at 1–3 years — SACN, via Action on Salt.

This replaces the `salt-mineral` half of the failed 48-month rule, at 12 months
rather than 48, and applies to salt dravyas specifically — `rock-salt`,
`sea-salt`, `black-salt`, `sambhar-salt` — not to the whole category.

**Note the category is a grab-bag.** `salt-mineral` also contains
`Edible lime (chuna)` (calcium hydroxide), `Edible silver leaf (vark)`
(metallic foil), `Edible acacia gum`, and `Tragacanth gum`. A salt rule does not
cover those, and they are the more concerning members. Route them to §4.

### R5 · High-mercury fish, 192 months

> "All babies and children under 16 years old should avoid eating shark,
> swordfish or marlin" — NHS, ibid.

One match in the 376: **Seer fish (surmai)** — king mackerel, on the same
high-mercury list. Director ruling: apply. Report if the executor finds others.

### R6 · WHO Recommendation 5 — a prohibition, not a floor

> "Sugar-sweetened beverages should not be consumed"; "Foods high in sugar, salt
> and trans fats should not be consumed" (both **strong**) — WHO complementary
> feeding guideline, 2023.

This is not an age floor and must not be encoded as one. It is a
never-recommend signal for the 6–23-month band and belongs with the engine
exclusion mechanism (fixed decision 4), not with `minAgeMonths`. **Out of scope
for this packet** — recorded so it is not lost.

---

## 3. The display fix — do this first, it is independent of everything above

701 dravyas carry `ageProvenance: legacyImport` with `minAgeMonths` 0, and the
detail view renders it as a number: Achiote shows as "Min. Age 6 mo". A
never-assessed 0 is presently indistinguishable from a cited "safe from birth",
so the app makes an affirmative infant-safety claim it has no basis for — on,
among other things, a medicinal decoction.

**Change:** when `ageProvenance == "legacyImport"`, render no age row at all.
Not "unknown", not "0" — absent.

- Display only. `enforcedMinAgeMonths` and every filter are untouched.
- Consistent with fixed decision 10, which already treats `legacyImport` as
  display metadata; this stops that metadata from asserting something.
- No citation required — it removes a claim.

**Gate G0.** Age row renders for exactly the records with
`ageProvenance == "authored"`; absent for all 701 `legacyImport` records.
WE-8c's recipe visibility gates (1,496/1,500/1,500 at 9/24/60 months) are
**unchanged** — if any of the three moves, the change has leaked into the
filter and must stop.

---

## 4. What does not ship, and why it is recorded rather than dropped

The five failed rules are not "not yet done". Four of them were wrong.

- **`animal` → 12 mo is contradicted.** WHO Recommendation 4a (**strong**):
  *"Animal source foods, including meat, fish, or eggs, should be consumed
  daily"* — for 6–23 months. A 12-month floor on animal dravyas would hide
  exactly the iron- and zinc-dense foods WHO says should be eaten daily from 6
  months. Shipping it would have been a nutrition harm, not a caution.
- **`fermented` → 24 mo is contradicted.** Paediatric consensus places plain
  yoghurt at 6 months. This rule would have floored `takra`, `buttermilk` and
  `dahi` — foundational Ayurvedic infant foods — at two years.
- **`spice` → 24 mo has no authority.** Searching returns commercial weaning
  blogs and no health body. Culinary spice quantities are generally treated as
  introducible with complementary feeding. Does not ship.
- **`medicinal` → 48 mo has no age threshold in any source.** The nearest
  authority is the National Capital Poison Center, which advises against herbal
  supplements for infants — citing seizures from herbal teas, lead and mercury
  in traditional remedies, and a fatal pennyroyal case in an 8-week-old — but
  **states no age**. Under §N4 discipline that cannot become a 48-month
  enforced floor.

  This is the uncomfortable one: 37 medicinal dravyas keep a floor of 0. The
  §3 display fix means the app no longer *claims* they are safe from birth,
  which is the honest position while uncited. Recommend a separate
  founder/vaidya ruling on a `notAFood` or `medicinalUse` flag — a different
  mechanism from `minAgeMonths`, and the right one for chuna, vark, shilajit
  and the gums. **Do not solve it by inventing an age.**
- **`beverage`/`preparation` → 12 mo** ("compound preparation, often sweetened")
  is reasoning, not a source. Replaced by R3 for honey-bearing preparations and
  by the §2 R6 note for sweetened ones.

---

## 5. Gates

- **G0** — §3 display fix; 701 records render no age; the three WE-8c recipe
  visibility numbers unchanged.
- **G1** — authored floors written: **187** at 6 months (R1), R2's
  director-approved whole-form list, R3 honey unchanged in behaviour, R4 salt
  dravyas at 12, R5 one record at 192. Every authored record has a non-empty
  `ageSource`. Zero authored records without one — assert it.
- **G2** — `legacyImport` count falls by exactly the number of records promoted
  to `authored` and by nothing else.
- **G3** — WE-8c re-run: recipe visibility 1,496/1,500/1,500 at 9/24/60 months,
  display histogram, 25+2 search goldens, full test suite.
- **G4** — no record's `minAgeMonths` decreases. Floors may rise, never fall.

## 6. Sources

- WHO, *Infant and young child feeding* fact sheet, 20 Dec 2023 —
  https://www.who.int/news-room/fact-sheets/detail/infant-and-young-child-feeding
- WHO, *Guideline for complementary feeding of infants and young children
  6–23 months of age*, 2023, Recommendations 2a/2b, 4a, 5 —
  https://www.ncbi.nlm.nih.gov/books/NBK596423/
- NHS, *Foods to avoid giving babies and young children* —
  https://www.nhs.uk/baby/weaning-and-feeding/foods-to-avoid-giving-babies-and-young-children/
- AAP choking policy statement (2010), summary —
  https://www.nationwidechildrens.org/newsroom/news-releases/2010/02/american-academy-of-pediatrics-releases-new-policy-statement-on-choking
- SACN salt recommendations by age, via Action on Salt —
  https://www.actiononsalt.org.uk/salthealth/recommendations-on-salt/
- National Capital Poison Center, *Don't give herbal supplements to infants* —
  https://www.poison.org/articles/dont-give-herbal-supplements-to-infants
