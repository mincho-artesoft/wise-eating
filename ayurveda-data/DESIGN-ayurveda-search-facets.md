# DESIGN — Ayurvedic filtering in food search

Director design note · 2026-07-30 · `ayurveda-data/`

Scope: which properties of a dravya should drive search and filtering in the app,
which should rank rather than exclude, and which look like filters but are not.

Everything here is grounded in the **actual** dravya schema, not textbook
Ayurveda. Fields that do not exist in the data are not proposed.

---

## 1. What the data actually carries

Every dravya has 23 fields. Taking Ghee as the worked example throughout:

```json
{
  "id": "dravya.ghee",  "name": "Ghee",  "sanskrit": "Ghrita",
  "aliases": ["clarified butter"],       "category": "oil-fat",
  "rasa": ["sweet"],                     "virya": "cooling",
  "vipaka": "sweet",
  "gunas": ["heavy", "oily", "soft", "smooth"],
  "prabhava": "Enhances agni despite being heavy; the finest fat for mind and ojas.",
  "dosha": { "vata": -2, "pitta": -2, "kapha": 1 },
  "agniEffect": 1,  "digestibility": 3,
  "seasons": ["sharad", "hemanta", "shishira"],
  "timeOfDay": ["morning", "midday"],
  "combinations": ["warm rice", "kitchari", "digestive spices", "warm milk"],
  "viruddha": ["honey in equal weight"],
  "contraindications": ["obesity", "high ama", "dairy sensitivity"],
  "preparation": "...",
  "usda": [{ "fdcId": 4558, "name": "Ghee, clarified butter", "tier": "exact" }],
  "servings": [...], "provenance": [...],
  "confidence": { "ayur": 0.9, "sci": 0.8 }
}
```

Classified by how they can be used:

| usable as | fields |
|---|---|
| **facet** (enumerable, small vocabulary) | `rasa`, `virya`, `vipaka`, `gunas`, `category`, `seasons`, `timeOfDay` |
| **score** (numeric, orderable) | `dosha.{vata,pitta,kapha}`, `agniEffect`, `digestibility`, `confidence.*` |
| **exclusion** (user-profile driven) | `contraindications` |
| **display / context only** | `prabhava`, `combinations`, `preparation`, `provenance` |
| **relational — NOT a search facet** | `viruddha` |
| **plumbing** | `id`, `name`, `sanskrit`, `aliases`, `usda`, `servings` |

---

## 2. Facets to ship

### Tier 1 — the four that carry most of the value

**`dosha` — the headline control.**
Signed −2…+2 per dosha, which is strictly better than a boolean. "Vata-pacifying"
is `dosha.vata < 0`, and the *magnitude* gives ranking for free: Ghee at −2 sorts
above something at −1. One control, three doshas, tri-state each
(pacifies / neutral / aggravates).

**`rasa` — six tastes, multi-select.**
Users already know this vocabulary. It also connects to *sarva-rasa-abhyasa*: the
app can show which tastes are under-represented across the rolling window and
offer a one-tap filter to fill the gap. That turns a filter into a
recommendation.

**`virya` — heating / cooling, binary.**
Trivial to implement and immediately meaningful to users.

**`seasons` + `timeOfDay` — defaults, not filters.**
The app knows the date and the hour. Ghee lists sharad/hemanta/shishira and
morning/midday. These should quietly *boost* ranking rather than appear as
controls the user has to find and set. A control the user must discover to get
correct behaviour is a design failure.

### Tier 2 — worth having, lower priority

- **`gunas`** — texture and quality pairs (heavy/light, oily/dry). Good for
  "something light" queries.
- **`digestibility`, `agniEffect`** — numeric; back a single "easy on digestion"
  control rather than exposing two raw scales.
- **`category`** — ordinary browsing, no Ayurvedic knowledge required.
- **`contraindications`** — set **once in the user profile**, applied silently to
  every search. Not a per-search control.
- **`confidence`** — not a filter. Mark low-confidence entries visibly instead;
  filtering by it is a power-user affordance at best.

---

## 3. Rank, do not exclude

**Dosha filters must reorder results, not delete them.**

This is not a UX preference; it follows from a measurement already established in
this project. Prakriti assessment has an inter-rater reliability of **0.20–0.40**,
which is why the meal solver treats vikriti as a *soft objective and never a hard
gate*. The same reasoning applies to search: hard-excluding on a signal that
unreliable will hide foods the user legitimately wants, and they will have no way
to tell why.

Concretely: selecting "vata-pacifying" should sort `dosha.vata` ascending and
visually de-emphasise aggravating foods — not remove them from the list.

Suggested ranking contribution, to be tuned against real queries:

```
score  =  w_dosha   * (-dosha[targetDosha])       // −2 aggravating … +2 pacifying
        + w_season  * (currentRitu   in seasons)
        + w_time    * (currentPeriod in timeOfDay)
        + w_agni    * agniEffect
        + w_rasa    * (rasa ∩ underrepresentedRasa ≠ ∅)
```

Weights are deliberately unspecified. They should be fitted against real queries
and reported with before/after numbers, the same way the solver's objectives were.

---

## 4. Three traps

### 4.1 Coverage — the biggest one

The database holds **14,484 foods** but only **2,214 Ayurveda profiles** and
**2,305 links**. Any Ayurvedic facet therefore silently hides roughly **85%** of
the catalogue, and the user cannot tell whether their food is missing because it
was filtered out or because it was never profiled.

Two mitigations, not mutually exclusive:

1. Show unprofiled matches in a clearly-labelled second section
   ("no Ayurvedic profile yet") rather than dropping them.
2. Propagate properties through the `usda[]` links. Ghee already links to
   `fdcId 4558` at tier `exact` and `10258` at tier `near`. An exact-tier link is
   strong enough to inherit a profile; a near-tier link should inherit with the
   result marked as inferred.

**Decide this before building any facet UI.** It determines whether the facets
operate over 2,214 rows or 14,484.

### 4.2 `prabhava` outranks everything and cannot be filtered

The classical precedence is **rasa < vipaka < virya < prabhava**. `prabhava` is
free text, so it cannot be a facet — but it overrides every property that can.

Ghee is the example sitting in the data: `gunas` say **heavy** and **oily**, yet
its prabhava says it *enhances* agni. A user filtering "light, agni-boosting" on
gunas alone would wrongly exclude one of the most agni-supportive substances in
the entire corpus.

Minimum viable handling: whenever `prabhava` is non-empty, surface it on the
result card so the exception is visible. Better: flag results whose prabhava
contradicts the active filter rather than silently dropping them.

### 4.3 `viruddha` is not a search facet

Incompatible combinations — Ghee's `"honey in equal weight"` — are **relational**.
They depend on what else is in the meal, not on the food alone. Filtering search
by viruddha is meaningless; the check belongs at plan level, as a warning when
two incompatible items appear in the same meal or day.

---

## 5. Open questions

1. **Coverage strategy** (§4.1) — inherit through `usda[]` links, or show
   unprofiled separately? Blocks facet UI.
2. **Ranking weights** (§3) — need fitting against real queries, with measured
   before/after.
3. **Does search target the user's prakriti or their vikriti?** Prakriti is
   stable, vikriti is current state. The solver already distinguishes these; the
   search should use the same source rather than inventing its own.
4. **`confidence` display** — how to mark a low-`ayur`-confidence entry without
   making the whole feature feel unreliable.

---

## 6. What this deliberately does not propose

No facet is proposed for any field the data does not carry. In particular there
is no ama, ojas, srotas or agni-type filter, because those are not fields on a
dravya — `agniEffect` is a single number, not a classification.

If any of those are wanted, they are a **data** change first: extend the dravya
schema, populate the field across 2,214 entries, then expose it. Adding the
control before the data exists produces a filter that returns nothing.
