# Decision record — nutrition, age gating, canon backlog

Director session 2026-08-01. Founder rulings from this session, recorded so they
do not become folklore. These sit under PROJECT-HANDBOOK §3; none of them
amends a numbered fixed decision.

---

## N1. Form variants: derive only pure water loss or dilution

**Context.** 101 of the 298 unmatched dravyas are *supersets* of an IFCT key —
the dravya carries a form qualifier IFCT has no row for. `Fresh amla`,
`Dried amla`, `Amla juice` and `Amla murabba` all reduce to IFCT's `amla`.
Filling them means deriving from a base row, not sourcing a measurement.

**Ruling.** Derivation is permitted **only** where the transform is pure water
loss or dilution, carries a cited per-food yield factor, and is stamped
`derived` in `_review.provenance`. Anything with added sugar, fat, or another
ingredient stays null. This is not an exception to "never invent a nutrient
value" — a cited yield factor applied to a measured base *is* a source. An
uncited factor is not.

**Consequence, measured.** Of the 101: 5 water loss, 8 dilution/extraction,
17 added-ingredient, 71 coincidental token overlap with no real base
relationship (`Ash plantain` → `Potato, brown skin, big` via the alias
`alu kesel`). The honest candidate set is **13**, and several of those 13 fail
on inspection — an ajwain or cumin *water* is an infusion, not a dilution, and
almost no solids transfer. **Expect 2–4 fills, not 298.**

## N2. The 298 is not a synonym-gap problem

Not a ruling, a finding that changes N1's framing. 178 of the 298 have no token
relationship to any of the 3,435 IFCT keys — IFCT has no row, and never will.
By dravya category: preparations 29, medicinals 24, spices 22, regional 21.
These stay null permanently and that is the correct outcome.

Loosening `match_ifct.py` to "recover" the supersets would fill 101 form
variants with their base food's numbers — the petha failure (§N3) reproduced
101 times by construction. Do not loosen the matcher.

## N3. The matcher needs a reverse-collision assertion

`match_ifct.py` flags one-dravya→many-IFCT-rows as ambiguous. It never checks
many-dravyas→one-IFCT-row. Seven IFCT rows currently feed 15 dravyas identical
numbers; at least five are substantively wrong food. Detail and dispositions in
`TASK-NUT1.md` §2.

The mechanism is the point: strict matching did not protect against this,
because the imprecision is in IFCT's own `Local Name; lang` column. That column
is a colloquial synonym list, not botany — it lists `E. Elephant apple` as a
synonym of Wood Apple (*Limonia acidissima* vs *Dillenia indica*). Treat `lang`
as a candidate generator, never as an identity assertion.

## N4. Age floors: authored and cited, with a display fix

**Ruling.** The 373 `_review` age proposals become `authored`, hard-filtering
floors — which is what fixed decision 10 already permits. "Today the only
authored age rule is honey at 12 months" describes state, not a cap. No
handbook amendment; no sign-off step.

**Discipline.** Cite the rule or do not ship it. A category rule with no source
does not ship, and the foods under it keep their current floor.

**Outcome of the citation pass (2026-08-01), superseding the assumption that
all 373 become authored.** Two of seven category rules survive; five do not,
and two are *contradicted* by the sources rather than merely unsupported —
`animal → 12 mo` against WHO Recommendation 4a (animal-source foods should be
consumed **daily** at 6–23 months), and `fermented → 24 mo` against paediatric
consensus placing plain yoghurt at 6 months. Shipping either would have been a
nutrition harm dressed as caution. The nut/seed rule ships revised to **60
months and whole forms only** (NHS, not the proposed 48). Citable authored set:
**187 at 6 months**, plus R2–R5. Roughly 177 proposals do not become floors.
Full table, sources and gates in `TASK-NUT2.md`.

**The display fix, which is the part that matters.** 701 dravyas carry
`legacyImport` age provenance with a value of 0, and the app renders that as a
number — the detail view shows Achiote as "Min. Age 6 mo". A never-assessed 0
renders identically to a cited "safe from birth", so the app makes an
affirmative infant-safety claim it has no basis for, on a medicinal decoction.
**Do not render an age at all when provenance is `legacyImport`.** This changes
display only; the filter is untouched. It is consistent with decision 10 rather
than an exception to it.

## N5. Job 4 ships name-keyed once more

`TASK-IDKEY.md` is entirely unimplemented — `FoodVideoSource.frameMap` is still
`[String: Int]`, `frameMap2` still exists, `FoodItem.swift:784` still calls
`getFrame(named: sanitizedName)`, `build_food_index.py` has no `db_id` or
`--store`, and `frame_map.json` + `reuse-map.json` still ship with no
`frame_index.json`.

**Ruling.** Job 4 ships name-keyed. The id-key migration is a separate packet
afterwards, accepting that the archive is encoded twice.

**Why this is safe here, and would not always be.** TASK-IDKEY §2's ordinal
renumbering trap does not fire for this batch: job 3 authors **zero new
dravyas** (§N6), so the 900001–900376 placeholder band does not move. The 11
new recipes take ids in the 1000001+ band and append. Verified: none of the 26
canon names collides exactly with any existing dravya or recipe name, so the
batch adds no fourth collision.

**What stays broken until the id-key packet lands.** Three names are each held
by two foods and therefore share one addressable frame: `Golden milk`
(dravya + recipe), `Panchamrita` (dravya + recipe), and `Mung Rice Peya`
(**two recipes** — the dravya/recipe distinction does not resolve this one).
TASK-IDKEY §1 names only Panchamrita; there are three.

## N6. Canon backlog: alias duplicates onto the existing dravya

**Ruling.** Canon entries that duplicate an existing dravya become aliases on
that dravya, not new entries. Canon ids resolve, nothing new is imaged, no new
placeholder ids are issued.

**Consequence, measured.** All **15** pure-dravya canon entries are duplicates.
Job 3 authors **zero new dravyas and 11 new recipes**. Disposition table in
`TASK-NUT3.md`.

## N7. IFCT Phase 1b stores totals, not uninterpretable mass sums or isomers

**Ruling.** Store the 15 approved top-level classes and 51 approved detailed
measurements in the source-only `dravya_foods.json` schema. Do not store IFCT
`vit` (total vitamins by mass) or `vitb` (total vitamin-B mass): adding masses
across compounds normally expressed on both microgram and milligram scales has
no useful interpretation.

The 37 individual polyphenol compounds and eight tocopherol/tocotrienol isomers
remain in the source CSV without schema fields. Their published totals are
stored. This is a final scope decision, not a backlog item to revisit by
default.

Phase 1b is source-only. It does not expand recipe nutrition panels or any
shipped artifact. Propagation and display require a separate packet measuring
cold launch against the 1.700 s ceiling and 1.650 s paydown trigger. Aluminium,
arsenic, cadmium, lead, mercury and the toxic-mineral total are stored with
`notForDisplay`; no consumer view may surface them under this ruling.

---

## Open items this session did not resolve

1. **`Shatapushpa` is claimed twice.** `dravya.fennel-seed` holds it as its
   sanskrit name; canon calls dill `Shatapushpa Shaka`, and `dravya.dill` holds
   `Shatahva`. Classical usage genuinely splits — many nighantus read
   Shatapushpa as *Anethum sowa* (dill) and give fennel Mishreya/Madhurika.
   Our data has it the other way and fennel-seed already ships. Flagged as a
   reviewNote for the vaidya, not silently reassigned.
2. **Pre-existing duplicate pairs the earlier merge missed.**
   `dravya.lotus-seed` (Makhanna) vs `dravya.makhana` (Makhanna / Padma Beeja);
   `dravya.round-melon-tinda-punjabi` vs `dravya.tinda` — the latter pair is
   what produced the D073 IFCT collision.
3. **An alias bug.** `dravya.methi-leaves` carries the alias
   `kasuri methi (dried)` while `dravya.fenugreek-leaf-dry` *is* Kasuri Methi.
   Fresh leaf can be matched by a dried-leaf name.
4. **`Ayura/Food/food_archive_480.mp4` is tracked at 85,356,519 bytes** —
   4.6 MB under the 90 MB split line, with 11 new recipe frames to add. Job 4
   must re-check it against the threshold; the 1024 archive is already split
   four ways and the 480 is not.
5. **Registry numbers are stale.** Handbook §5 and PROGRESS.md both say 714
   dravyas; the batch files hold **705** after the merge in `ad22c6d`. Every
   derived count in §5 descends from 714. Re-derive after job 4, not before.
