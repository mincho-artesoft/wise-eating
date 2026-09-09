# REPORT — same food, different name

Director audit · 2026-07-30 · `ayurveda-data/`

Every food name in the catalogue was compared against every dravya name,
sanskrit name and alias, to find substances that are the same thing recorded
twice under different names.

Method: names are lowercased, accents stripped, parentheses and punctuation
removed, obvious plurals reduced, and purely bureaucratic USDA qualifiers
(`NFS`, `unspecified`, `all types`) dropped. Preparation words — raw, dried,
roasted, boiled — are **not** dropped, because in Ayurveda they change virya and
guna and therefore change the dravya. Two names match only when their remaining
token sets are identical. Nothing here is a fuzzy or scored match.

---

## 1. How the catalogue is actually put together

Worth stating plainly, because it changes what "coverage" means.

The 14,484 food rows are three different populations:

| rows | ids | what they are | how they reach a profile |
|---|---|---|---|
| 12,601 | 1–12601 | real USDA rows | via `ZAYURVEDALINK` |
| 383 | 900001+ | placeholder rows built *from* a dravya that had no USDA match | the profile points at the row directly |
| 1,500 | 1000001+ | recipes | the profile points at the row directly |

So 2,305 links + 383 placeholders + 1,500 recipes = 4,188 rows carry a profile.
No profile is orphaned. The honest coverage figure for the *USDA* catalogue is
**2,305 of 12,601, or 18.3 %** — the earlier 26 % counted the placeholder and
recipe rows, which are profiled by construction.

The audit therefore has two distinct jobs: find real USDA foods that should be
linked to a dravya and are not, and find placeholder rows that duplicate a real
USDA row that already exists.

---

## 2. Foods that are a dravya but were never linked — 33 found, 32 applied

These are USDA rows whose name is exactly a dravya's name, sanskrit name or
alias, and which carry no link at all today.

Twenty-six are bound `exact`; six are bound `near` because the USDA row mixes
two forms in one row or names a preparation rather than a substance:

- `4470 Pickles, dill` — the dravya is the fermented pickle, USDA dill pickles
  are usually vinegar-brined
- `11912 Carrots (often julienned and caramelized with sugar)` — the row names a
  dish, the substance is carrot
- `11938 Mulberries (fresh and dried)` and `11972 Onions (fresh and dried)` —
  one row, two dravyas
- `12059 Pomegranate (fresh seeds and molasses)` — fruit and syrup in one row
- `12116 Apple Cider / Cider Vinegar` — cider and cider vinegar are not the same
  substance and should not share a row

One was **not** applied. `12174 Butter / Clarified Butter` names butter and ghee
together; binding it to either is wrong, and the row wants splitting upstream.

Notable among the 32: `8500 Butter, Clarified butter (ghee)` is a second ghee row
that was never linked, and `5 Milk, fat free (skim)` gives `dravya.skimmed-milk`
a real USDA row for the first time — it had none.

## 3. Two foods linked to the less specific of two dravyas

| food | was (derived) | now (exact) |
|---|---|---|
| 8242 Oil, walnut | `dravya.walnut` | `dravya.walnut-oil` |
| 8243 Oil, almond | `dravya.almond` | `dravya.almond-oil` |

I started with four and withdrew two of them, because the data already has a
better mechanism than I gave it credit for. `rules/modifiers.json` carries
`dried`, `raw`, `canned`, `frozen` and ten others, each a vpk delta applied on
top of a base dravya. So `3623 Apricot, dried` resolving to `dravya.apricot`
plus the `dried` modifier — vpk `[0,1,-1]` — is not a weak link, it is the
designed expression of "the dried form of this dravya", and `validate.py:564`
asserts that exact resolution. Retiering it to `dravya.dried-apricot` would
have bypassed working machinery and broken a spot check. The same applies to
`7536 Seeds, lotus seeds, dried`.

The two oils are different: there is no `oil` modifier, so `Oil, almond`
resolving to `dravya.almond` gives a pressed oil whole-almond properties with
nothing correcting them. That is a real defect.

## 4. The trap this audit had to be built around

Six foods look like mislinks by name and are correctly linked today.

In USDA, **raw means uncooked**. In the dravya names, **raw means unripe**. They
are opposite claims about the substance. `Mangos, raw` is ripe mango eaten
uncooked; `dravya.raw-mango-vegetable` is aam, the sour green fruit — a
different rasa, a different virya, a different dravya. The same applies to
`Bananas, raw`, `Papaya(s), raw` and `Jackfruit, raw`.

A name matcher that trusted the word "raw" would have rewritten all six links to
the wrong dravya, and the result would have looked correct in every automated
check. These are recorded in the patch script's `HELD` list so the next audit
does not rediscover and "fix" them.

Also held: `2021 Peanuts, NFS` and `12000 Peanuts (Ginguba)`, claimed by three
peanut dravyas at once, and `11934 Apricots (fresh and dried)`, claimed by two —
all blocked on §5 rather than genuinely ambiguous.

---

## 5. Thirteen dravyas recorded twice — this is the larger problem

Thirteen clusters of dravyas have primary names that normalise identically.
Some are genuine distinctions. Several are the same substance entered twice with
**different Ayurvedic values**, which means the app currently gives two different
answers for one food depending on which row the user lands on.

**Contradictions, in order of seriousness:**

`dravya.mango-ripe` says **heating**, `dravya.ripe-mango` says **cooling**. This
is a disagreement about virya on the same substance. Classically, pakva amra
(ripe mango) is madhura, snigdha, guru, **sheeta**, and vata-pitta-shamaka;
ushna belongs to ama amra, the unripe fruit. So the heating value looks like
unripe-mango properties attached to the ripe entry — and it is the entry that
holds the exact USDA link, so it is the one users see. Worth a vaidya
confirmation before changing, since some modern sources do call ripe mango
mildly heating.

`dravya.jackfruit` (ripe) says vata **+1**, `dravya.ripe-jackfruit` says vata
**−1**. Panasa is guru and snigdha, which is vata-pacifying; −1 is the defensible
value and +1 appears to be an error.

`dravya.banana-ripe` says pitta **0**, `dravya.ripe-banana` says pitta **−1**.
Kadali phala is madhura and sheeta, so −1 is better supported.

`dravya.garlic` says kapha **−1**, `dravya.garlic-fresh-bulb` says **−2**.
Lashuna is strongly kapha-hara; −2 is the classical reading. The two also
disagree on category (spice vs vegetable).

`dravya.mahua-flower-dry` and `dravya.mahua-flower-fresh` are not duplicates —
they are two genuinely different forms carrying **identical** values. Drying
should make the dried form lighter and warmer. As recorded, the distinction is
cosmetic.

**Pure duplicates, no data conflict:** `apricot` / `apricot-fresh` and
`fig-fresh` / `fresh-fig` are field-for-field identical, differing only in
confidence. `green-chili` / `green-chili-fresh` differ only in category.
`peanut` / `peanut-raw` are duplicates (though `peanut-roasted` is a legitimate
third entry), and the cluster cannot agree whether peanut is `dry-fruit-nut` or
`legume` — botanically and Ayurvedically it behaves as a legume.

`dravya.khus-root` and `dravya.vetiver` are both named "Vetiver root". **This is
the frameKey collision already blocking `build_archive2.py`** — the two dravyas
produce the same frame key, so the imagery index refuses to build. Fixing the
duplicate fixes the build. `khus-root` is the one to keep: higher confidence, and
`medicinal` is the right category for ushira.

**Genuine distinctions, keep both:** `baby-corn` / `corn`, and `long-brinjal` /
`small-brinjal` (classical texts do rate the small round vartaka differently).

`ash-gourd`, `ash-gourd-juice-flesh` and `ash-gourd-strips` are one substance in
three culinary uses, carrying three different dosha vectors with no classical
basis for the difference. Kushmanda is one dravya; the uses belong in `servings`
and `preparation`, not in three separate entries.

**None of this is applied.** Merging dravyas removes ids that imagery frame keys
depend on, and four of the thirteen need a judgement about which Ayurvedic value
is right rather than which record is newer. That is a reviewed change, not a
script.

---

## 6. Sixteen placeholder rows that duplicate a real USDA row

Placeholder rows exist because a dravya had no USDA match. Sixteen of the 383
have one anyway, under a different name — so the same food appears twice in
search, once with a profile and once without.

The clearest: `dravya.full-cream-milk` (row 900113) against `2 Milk, whole`;
`dravya.skimmed-milk` (900316) against `5 Milk, fat free (skim)`, fixed in §2;
`dravya.bay-leaf` "Bay leaf, Indian" against `12187 Bay Leaf (Tej Patta)` — tej
patta *is* Indian bay leaf; `dravya.raisins` (900266) against `3638 Raisins`;
`dravya.urad-papad` against `5647 Papad`; `dravya.rice-gruel` against
`2852 Congee`; `dravya.kamal-gatta-dry` against `7536 Seeds, lotus seeds, dried`,
fixed in §3.

Several of the rest are near rather than exact — `dravya.badam-milk` against
`27 Almond milk, NFS` is not the same thing, since badam milk is sweetened and
spiced — and the `raw` trap from §4 accounts for three more. This section needs
one pass by hand; it is listed here rather than patched.

---

## 6b. Where the duplicate dravyas came from

`canon/canon-05..11` is a planning index — a Director knowledge dump listing
dravyas that *should* exist, at scaffolding grade (`vpk` and `virya` only, no
rasa, vipaka or gunas). The scaffold expanded each canon entry into a full
dravya. In nine cases the substance already existed under a different id from
the earlier batches, so the scaffold produced a twin: `dravya.ripe-mango`
beside `dravya.mango-ripe`, `dravya.vetiver` beside `dravya.khus-root`.

The twins are not independent judgements. In every one of these clusters the
scaffolded dravya's dosha vector equals the canon `vpk` verbatim and its virya
equals the canon `virya`. So where a pair disagrees, one value is canon's
headline reading and the other is the older entry's — which is why the
disagreements cluster on exactly one field at a time.

This was partly known. `dravyas/predraft/check.py` flagged
`dravya.vetiver: exact normalized name already authored as dravya.khus-root`
and it was waved through as "canon alias ambiguity for report".

## 6c. Nine merged, four left alone

Merged, keeping the id the rest of the data already references and folding the
loser's aliases and USDA bindings into it:

| removed | kept | value changed |
|---|---|---|
| `dravya.vetiver` | `dravya.khus-root` | — |
| `dravya.apricot-fresh` | `dravya.apricot` | — |
| `dravya.fresh-fig` | `dravya.fig-fresh` | — |
| `dravya.ripe-banana` | `dravya.banana-ripe` | pitta 0 → −1 |
| `dravya.ripe-jackfruit` | `dravya.jackfruit` | vata +1 → −1 |
| `dravya.garlic-fresh-bulb` | `dravya.garlic` | kapha −1 → −2 |
| `dravya.green-chili-fresh` | `dravya.green-chili` | vata 0 → −1 |
| `dravya.peanut-raw` | `dravya.peanut` | vata 0 → −1, category → legume |
| `dravya.ripe-mango` | `dravya.mango-ripe` | **virya heating → cooling** |

Which id survives is a mechanical question — keep the one recipes and crosswalk
rows already point at, so nothing stops resolving. Which set of values is right
is a separate question, so each field change is listed in the script with its
own reason and can be vetoed on its own. Nothing is "canon wins".

**The mango change is the one that wants a vaidya.** Pakva amra is classically
madhura, snigdha, guru and *sheeta*; ushna belongs to ama amra, the unripe
fruit. But some modern sources do call ripe mango mildly heating, and this is
the single change here that most affects what the app tells a pitta user in
summer. It is also the only one where the surviving record and the twin
disagree about virya rather than a dosha number.

Left alone: `long-brinjal` / `small-brinjal` and `mahua-flower-dry` /
`mahua-flower-fresh` are both **pairs of canon entries** — the canon lists the
two forms deliberately, and they carry identical values, so the distinction is
unpopulated rather than wrong. Same for the three ash gourd entries. And
`baby-corn` / `corn` was never a duplicate: they collided only because "baby"
sat in the matcher's stoplist of bureaucratic USDA qualifiers, which was my
error.

## 6d. One wrong link, found by accident

`750 Fish, raw` resolved to `dravya.peanut-raw`, matched by rule M1 on the
single token **`raw`**. Fish was carrying peanut's Ayurvedic profile. Exactly
one row in the crosswalk has a single-token key like this, so it is a one-off
rather than a pattern, but nothing in the pipeline would have caught it — the
row is well-formed and the dravya exists.

There is no fish dravya for it to fall back to, so the row is removed and the
food goes back to having no Ayurvedic profile, which is the honest state.

## 7. Applied, and what it came to

```
python3 tools/apply_name_matches.py     # 34 edits: 32 links added, 2 retiered
python3 tools/merge_duplicate_dravyas.py  # 9 merges, 1 wrong crosswalk row removed
```

Both refuse to write unless every edit validates first — the dravya exists, the
food is not already bound, a retier's crosswalk row says what the patch claims
it says, and a field change finds the old value it expects. The merge script
additionally refuses to write while any deleted id is still named in a `.py`
file, and lists them. Two were:

- `validate.py:562` asserted `dravya.garlic-fresh-bulb` loses fdcId 11971. After
  the merge that id does not exist and the row is uncontested, so the assertion
  was rewritten to check the same rule (R3) without the contest.
- `build_seed.py:272` listed `dravya.peanut-raw` in the peanut allergen set.

Final counts, recomputed independently from the data afterwards and matching
`build_seed.py` exactly:

| | before | after |
|---|---|---|
| dravyas | 714 | **705** |
| links | 2305 | **2336** |
| of which derived | 1969 | **1966** |
| V1_LINK_COUNT | 336 | **370** |
| placeholders | 383 | **376** |
| primaries | 331 | **329** |
| catalogue rows | 14484 | **14477** |

Checked afterwards: no duplicate dravya ids, no dravya binding the same fdcId
twice, crosswalk still sorted by fdcId as `build_seed.py` requires, no crosswalk
row or `losers` entry naming a dravya that no longer exists, no recipe
referencing one, and canon's 161 unscaffolded entries unchanged.

`build_seed.py` itself has **not** been run — it needs the source USDA store,
which is not in the repo. That is the remaining verification.

Two things to know before rebuilding. Seven placeholder rows disappear, and the
placeholder band is assigned by ordinal, so **every placeholder food id shifts**
— this wants to land before the imagery archive is rebuilt, not after. And nine
dravyas no longer exist while `jobs.json` still lists them; do not rebuild
`jobs.json` to match, because `verify.py` check C exists to catch a moved
styleHash. The extra images are harmless. Removing `dravya.vetiver` is what
lets `archive/build_food_index.py` build at all.

## 8. What this does not answer

Name matching finds foods recorded twice. It cannot find a food whose
Ayurvedic values are simply wrong, and it cannot find the 10,000-odd USDA rows
that have no dravya at all — those need the coverage strategy in
`DESIGN-ayurveda-search-facets.md` §4.1, not another matcher.
---

## Appendix — the complete edit manifest

The two one-shot scripts that applied this (`tools/apply_name_matches.py`,
`tools/merge_duplicate_dravyas.py`) were removed after the change landed; they
refuse to run twice by design. Every edit they made is listed here.

### A. USDA rows bound to a dravya for the first time (32)

| fdcId | food | dravya | tier |
|---|---|---|---|
| 5 | Milk, fat free (skim) | `dravya.skimmed-milk` | exact |
| 12 | Goat milk | `dravya.goat-milk` | exact |
| 35 | Yogurt, whole milk, plain | `dravya.yogurt` | exact |
| 158 | Cream, heavy | `dravya.cream` | exact |
| 282 | Cheese, cottage, NFS | `dravya.cottage-cheese` | exact |
| 1880 | Lima beans, NFS | `dravya.lima-bean` | exact |
| 1891 | Kidney beans, NFS | `dravya.rajma` | exact |
| 1926 | Chickpeas, NFS | `dravya.chickpea` | exact |
| 1994 | Almonds, NFS | `dravya.almond` | exact |
| 2001 | Brazil nuts | `dravya.brazil-nut` | exact |
| 2002 | Cashews, NFS | `dravya.cashew` | exact |
| 2008 | Chestnuts | `dravya.chestnut` | exact |
| 2009 | Coconut, fresh | `dravya.coconut-fresh` | exact |
| 2011 | Hazelnuts | `dravya.hazelnut` | exact |
| 2030 | Pecans, NFS | `dravya.pecan` | exact |
| 2035 | Pine nuts | `dravya.pine-nut` | exact |
| 3629 | Date | `dravya.dates` | exact |
| 3630 | Fig, dried | `dravya.dried-fig` | exact |
| 4328 | Leeks | `dravya.leek` | exact |
| 4470 | Pickles, dill | `dravya.dill-pickle` | near |
| 8227 | Oil, palm | `dravya.palm-oil` | exact |
| 8500 | Butter, Clarified butter (ghee) | `dravya.ghee` | exact |
| 11895 | Pistachios | `dravya.pistachio` | exact |
| 11912 | Carrots (often julienned and caramelized with sugar) | `dravya.carrot` | near |
| 11938 | Mulberries (fresh and dried) | `dravya.mulberry` | near |
| 11972 | Onions (fresh and dried) | `dravya.onion` | near |
| 12059 | Pomegranate (fresh seeds and molasses) | `dravya.pomegranate` | near |
| 12116 | Apple Cider / Cider Vinegar | `dravya.apple-cider-vinegar` | near |
| 12151 | Apple Cider Vinegar | `dravya.apple-cider-vinegar` | exact |
| 12163 | Scallions | `dravya.spring-onion` | exact |
| 12225 | Green cardamom | `dravya.cardamom` | exact |
| 12231 | Poppy seed (Posto) | `dravya.poppy-seed` | exact |

### B. Retiered from a derived crosswalk link to an exact binding (2)

| fdcId | food | was | now |
|---|---|---|---|
| 8242 | Oil, walnut | `dravya.walnut` (derived) | `dravya.walnut-oil` (exact) |
| 8243 | Oil, almond | `dravya.almond` (derived) | `dravya.almond-oil` (exact) |

### C. Dravyas merged (9)

| removed | kept | value changes |
|---|---|---|
| `dravya.vetiver` | `dravya.khus-root` | — |
| `dravya.apricot-fresh` | `dravya.apricot` | — |
| `dravya.fresh-fig` | `dravya.fig-fresh` | — |
| `dravya.ripe-banana` | `dravya.banana-ripe` | `dosha.pitta` 0 → -1 |
| `dravya.ripe-jackfruit` | `dravya.jackfruit` | `dosha.vata` 1 → -1 |
| `dravya.garlic-fresh-bulb` | `dravya.garlic` | `dosha.kapha` -1 → -2 |
| `dravya.green-chili-fresh` | `dravya.green-chili` | `dosha.vata` 0 → -1 |
| `dravya.peanut-raw` | `dravya.peanut` | `dosha.vata` 0 → -1; `category` 'dry-fruit-nut' → 'legume' |
| `dravya.ripe-mango` | `dravya.mango-ripe` | `virya` 'heating' → 'cooling' |

### D. Crosswalk rows removed (3)

| fdcId | food | was | why |
|---|---|---|---|
| 8242 | Oil, walnut | `dravya.walnut` | retiered to an exact binding, see B |
| 8243 | Oil, almond | `dravya.almond` | retiered to an exact binding, see B |
| 750 | Fish, raw | `dravya.peanut-raw` | matched on the single token `raw`; wrong link |

### E. Name matches deliberately NOT changed

- **3623 Apricot, dried** — derived to dravya.apricot with the 'dried' modifier, giving vpk [0,1,-1]. dravya.dried-apricot exists, but the modifier path is the designed mechanism and validate.py:564 asserts this exact resolution. Left alone.
- **7536 Seeds, lotus seeds, dried** — same: derived to dravya.lotus-seed plus the 'dried' modifier. dravya.kamal-gatta-dry exists but the modifier path already handles it.
- **3650 Banana, raw** — linked to nothing; name suggests raw-banana/plantain-green, but USDA raw = uncooked ripe fruit. 10677 'Bananas, raw' is already bound to dravya.banana-ripe, which is correct.
- **10677 Bananas, raw** — bound exact to dravya.banana-ripe — correct, see above
- **7297 Mangos, raw** — bound exact to dravya.mango-ripe — correct; aam/unripe mango is a different USDA row
- **7313 Papayas, raw** — bound exact to dravya.papaya — correct
- **3672 Papaya, raw** — derived to dravya.papaya — correct
- **11334 Jackfruit, raw** — bound exact to dravya.jackfruit (ripe) — correct
- **12174 Butter / Clarified Butter** — the row names butter AND ghee. Binding it to either is wrong; the row should be split upstream.
- **12213 Turmeric (Holud)** — near-bound to dravya.turmeric-fresh; holud usually means dried turmeric, so dravya.turmeric may be the better target. Moving it would make turmeric-fresh a placeholder and renumber the placeholder band, so it needs a decision, not a script.
- **11909 Galangal** — exact to dravya.galangal; dravya.greater-galangal is a variant, not a better match for an unqualified row
- **2021 Peanuts, NFS** — three peanut dravyas claim the name (peanut / peanut-raw / peanut-roasted). Ambiguous until those are merged.
- **12000 Peanuts (Ginguba)** — same three-way ambiguity as 2021
- **11934 Apricots (fresh and dried, ...)** — dravya.apricot and dravya.apricot-fresh are duplicates; resolve the duplicate first

- **dravya.long-brinjal / dravya.small-brinjal** — both are canon entries — the canon lists the two forms on purpose, and classical texts do rate the small round vartaka differently. They currently carry identical values and the same USDA row, so the distinction is unpopulated rather than wrong. Enrich, do not merge.
- **dravya.mahua-flower-dry / dravya.mahua-flower-fresh** — same situation: two canon entries with identical values. Drying should make the dried form lighter and warmer. Populate the difference.
- **dravya.ash-gourd / -juice-flesh / -strips** — three canon entries for one substance in three culinary uses, with three different dosha vectors. Whether kushmanda should be one dravya with servings or three dravyas is a content decision, not a duplicate.
- **dravya.baby-corn / dravya.corn** — not a duplicate. These collided in the audit only because 'baby' was in the matcher's stoplist of bureaucratic USDA qualifiers, which was my error.
- **dravya.peanut-roasted** — roasting genuinely changes the dravya and it holds its own USDA row.
