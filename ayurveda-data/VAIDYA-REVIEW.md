# Vaidya Review — decisions needed before the Ayurvedic meal planner is switched on

Prepared for clinical review · 2026-07-27 · Ayura

---

## What this is

The app now builds meal plans using Ayurvedic reasoning rather than just calories. Before that is turned on for users, fourteen questions need a practitioner's ruling. They are not engineering questions — each one is a judgement about food, tradition or safety that we should not be making on our own.

**You do not need to read any code.** Each item below states what the app does today, what the alternatives are, and what actually changes for a user depending on which way you rule. Every item has a default we will keep if you have no strong view, so nothing is blocked by an item you would rather not decide.

**Scale, for context.** The app holds 714 dravyas, 1,500 authored recipes and 12,601 USDA food rows — 14,484 items in total. A plan is built by choosing from those, subject to allergies, diet, age and dislikes, then scored for how well it pacifies the user's stated imbalance.

**One thing already settled, so you know the frame.** Constitutional assessment is treated as a *preference*, never a filter. Published agreement between qualified physicians assessing the same person's prakriti runs about 0.20–0.40. That is far too noisy to remove foods from someone's options, so vikriti only ever nudges the ranking. Only allergens, dislikes and hard incompatible combinations actually exclude a food.

---

## A. Safety — please rule on this one first

### A1. The honey floor for infants

**Current, and the reason this is first.** Honey before twelve months carries a risk of infant botulism. On the new branch we added an authored twelve-month floor for honey with that clinical basis recorded. **The shipping app has no such rule.** It enforces whatever number arrived in the imported data, and those numbers were never authored by anyone: among 36 rows whose name contains "honey", the imported minimum ages are 6 months on one row, 12 on twenty-five, 24 on one, and 48 on nine. The plain `Honey` row happens to say 12. `Honey (especially Leatherwood)` says 6.

So today a six-month-old's profile can be shown a honey product, by accident, because a spreadsheet said 6.

**Decision.** Confirm the authored floor of 12 months for all honey and honey-containing products, and confirm it should override any imported value.

**Recommended default:** confirm 12 months, override imports.

**If you rule otherwise,** please state the age and the basis, because this is the only age rule in the project with a cited clinical justification and we would rather have your number than a spreadsheet's.

### A2. Age gating hides two thirds of the catalogue from infants

**Current.** The app hides any food whose imported minimum age exceeds the profile's age. At 9 months that hides **8,248 of 12,601 rows — 65.5%**. At 24 months it hides 794.

Those minimum ages are untraced. 6,438 rows carry exactly 24 months, which is a bulk default rather than anyone's clinical judgement.

**Decision.** Should an untraced imported age *hide* a food, or *flag* it?

| Option | What a parent sees |
|---|---|
| **Hide** (today) | the food does not appear in search at all |
| **Flag** | the food appears with an age caution badge |
| **Hide only authored, flag imported** | authored rules like honey hide; untraced bulk values only badge |

**Recommended default:** the third. Authored clinical rules hide; untraced imported values badge. It keeps the honey protection absolute while not silently removing two thirds of the food list from a nine-month-old's parent on the strength of an unsourced default.

---

## B. What counts as what — role rulings

The planner assigns every food a *role*: is it a main dish, a staple, an accompaniment, a drink, a seasoning, a fat, a sweet, a medicine. The role controls the portion size offered and how many of that kind may appear in one meal. Six are genuinely ambiguous and we have deliberately not decided them.

### B1. Kheer, and sweet dishes generally
Currently **sweet** — capped at one per meal, 5–120 g.
The alternative is **staple**, a legitimate part of the meal at 40–350 g.
*Western framing calls it dessert; Indian practice often does not.*
**Default if unruled:** sweet.

### B2. Buttermilk / chaas
Currently **beverage** — counts against the limit of two drinks per meal.
The alternative is **side**, a digestive taken alongside rather than a drink.
*This decides whether takra after a meal displaces water or tea from the plan.*
**Default:** beverage.

### B3. Ghee
Currently **fat** — its own component with its own portion, 2–30 g.
The alternative is **condiment**, or arguably not a listed component at all but a property of the dish it was cooked in.
*Affects whether a user sees "ghee, 10 g" as a line item on their plate.*
**Default:** fat.

### B4. Chyawanprash
Currently **medicinal** — one per meal, 0.5–10 g.
The alternative is **sweet**; it is roughly 60% sugar by mass.
*A rasayana taken by the spoonful, or a confection?*
**Default:** medicinal.

### B5. Coconut, raw
Currently **side** at 40–250 g. The alternative is **fat**.
*Interacts with C1 below.*
**Default:** side.

### B6. Hummus and similar dips
Currently **side** at 40–250 g. The alternative is **condiment** at 5–60 g — a fourfold difference in what lands on the plate.
**Default:** side.

### B7. Should therapeutic dravyas appear in meal plans at all?

Ashwagandha, shatavari, triphala, guduchi, brahmi and similar are currently eligible as meal components, capped at one per meal and 0.5–10 g. They are classical dravyas, so excluding them felt presumptuous; including them may equally be wrong if these belong in a separate therapeutic regimen rather than on a dinner plate.

**Decision.** Keep them in plans, or move all 43 medicinal dravyas to a separate list the planner never draws from?

**Default:** keep, capped at one per meal.

### B8. Is a cap of two seasonings per meal compatible with real cooking?

To stop the planner producing "dinner: six dried herbs", no more than two seasonings may appear in one meal. But an authored recipe may legitimately name a masala, salt and a tempering spice — three.

**Decision.** Is two right, or should authored recipes be exempt because their seasonings are part of the dish rather than separate items?

**Default:** two, with authored recipes exempt.

---

## C. What should be excluded — allergen and diet rulings

When a user says "no shellfish" or "vegetarian", the app has to decide what that covers. Seven cases are genuinely contested and are currently reported rather than enforced.

### C1. Coconut — its own allergen, or part of tree nuts?

**Current:** coconut counts as a tree nut, which is the cautious direction.

**Consequence:** **94 of the 297 recipes flagged as containing nuts are coconut-only.** A user avoiding tree nuts therefore loses 94 recipes that contain no nut other than coconut.

Botanically coconut is a drupe, not a nut. Many people who avoid tree nuts tolerate it; some allergy guidance treats it separately, some does not.

**Decision.** Keep coconut inside tree nuts, or give it its own tag so users can avoid nuts and coconut independently?

**Default:** keep it inside tree nuts, and accept losing the 94 recipes.

### C2. Salami and pepperoni under "no pork"
Usually pork, sometimes a pork/beef blend, occasionally all beef. **Default:** exclude under pork.

### C3. Scallop under "no shellfish"
A mollusc, not a crustacean. Some shellfish allergies cover both, some do not. **Decision:** does "shellfish" span molluscs? **Default:** yes, exclude.

### C4. Caesar dressing under "no fish"
Contains anchovy, which is not visible in the name. **Default:** exclude under fish.

### C5. Vanilla extract under "no alcohol"
Ethanol is the carrier; the quantity in a serving is trace. Relevant both to abstention for religious reasons and to recovery. **Default:** do not exclude, but this one genuinely needs your view — the two motivations point opposite ways.

### C6. Vegetarian fishcake under "no fish"
A plant analogue whose name contains "fish". Must **not** be excluded from a fish-free plan. **Default:** do not exclude. Confirm.

### C7. Chicken of the woods under "no poultry"
A mushroom. Must **not** be excluded. **Default:** do not exclude. Confirm.

---

## D. Data quality — what you should know before signing off

### D1. Most Ayurvedic scoring runs on derived values, not classical sources

Every one of the 14,484 items carries dosha effects, but they come from three tiers:

| Tier | Items | Share of catalogue | Share of what the planner picks |
|---|---:|---:|---:|
| classical — from texts | 336 | 2.67% | **17.18%** |
| derived — reasoned from a classical relative | 1,969 | 15.6% | 20.51% |
| estimated — rule-generated | 10,296 | 81.7% | **62.31%** |

**Read the last column against the third.** Classical items are 2.67% of the catalogue and make up 17.18% of what the planner chooses — it is selecting them at **6.4 times their availability**. That is the system reaching for good data.

But 62% of what lands on a plate is still rule-generated. Anything we say about a specific USDA item's dosha effect is a reasoned estimate, not a citation.

**Decision.** Is that acceptable to launch with, given the app tells users this is guidance rather than treatment? If not, which foods must be classical-sourced before they may appear at all?

### D2. The Ayurvedic scoring demonstrably works

We test by building the same plan twice — once with the dosha scoring on, once off — and comparing. With scoring on, plans are substantially more pacifying to the user's stated imbalance: a measured difference of **+1.55** on our scale, consistently across vata, pitta and kapha profiles.

This matters because it proves the dravya data actually reaches the choice of food rather than sitting unused, which was true of the previous version of the app.

### D3. "Coriander" is ambiguous and we picked one

British usage means the leaf; American usage means the seed. They are different dravyas with different properties. We defaulted to **seed**, to match the food database's naming.

**Decision.** Confirm, or split the two so a recipe naming coriander leaf never resolves to the seed.

---

## How to record your decisions

For each item, one line is enough: **the item number, your ruling, and a sentence of reasoning.** The reasoning matters more than the ruling — it lets us apply the same logic to the next case without asking again.

If you would rather not rule on an item, say so and we will keep the stated default and note that it is unreviewed.

**A1 and A2 are the ones we would most like back first.** They are the only items on this list where getting it wrong could hurt someone rather than merely produce an odd meal plan.
