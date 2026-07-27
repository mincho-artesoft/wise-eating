# MP-6b — Deterministic narration copy pass

Date: 2026-07-27
Branch: `ayurveda-app`
Accepted MP-6 base: `b410238`
Implementation commits: `909d518`, `e7752f9`
Status: **COMPLETE — all gates green**

## First confirmation: the MP-6 three-day sample was a fixture

**Confirmed.** The repeated Oat porridge / kitchari / pumpkin-soup sample in
`REPORT-MP6.md` came from the dedicated `facts(days:)` narration fixture in
`test_mp6_narration.py`. It supplied the same three fact records on each day
to exercise template, mismatch, timeout, and model-call behavior. It was not
emitted by `DeterministicMealPlanSolver`.

The MP-5 property harness independently ran real solver output and remained
green. MP-6b additionally runs its full seven-day copy sample through the
production `DeterministicMealPlanSolver`; its two-day no-repeat check is true
and it selects 91 distinct food IDs. There is therefore no hidden V1/V3
contradiction behind the accepted MP-6 fixture.

## Copy implementation

`MP6TemplateNarrator` now has five deterministic sentence frames. The frame is
selected only from `(day, slotIndex)`:

```text
frame = (((day - 1) mod 5) × 3 + (slotIndex mod 5)) mod 5
```

For a normal three-meal day this advances one frame at every adjacent meal,
including the day boundary. It remains a pure function of finished facts.

Clauses are conditional:

- balanced agni produces no agni clause;
- `mixed` or `unrecorded` thermal character produces no thermal clause;
- one recorded taste is folded into the main sentence;
- multiple tastes use a frame-specific recorded-taste sentence;
- absent tastes produce no taste filler; and
- a real thermal value keeps the exact “Traditionally considered” register.

No food, figure, property, recommendation, effect, or adjective was added.
The model-side disease-claim prohibition, traditional-guidance instruction,
`aiDraft` lifecycle, one-call schema, timeout, mismatch validation, and
Foundation-only fallback boundary are unchanged.

## Real seven-day solver sample

This is not a handwritten candidate fixture. The regression harness reads the
shipped `WiseEating/Legacy/foods.json`, `ayurveda_seed.json.gz`,
`food_concepts.json.gz`, and `ayurveda_rules.json`; maps the same nutrition,
safety, role, portion, Ayurveda-tier, rasa, thermal, and age inputs used by the
planner adapter; and invokes the production `DeterministicMealPlanSolver`.

Sample request:

- 7 days × Breakfast/Lunch/Dinner;
- 2,000 kcal/day and 80 g protein target;
- vegetarian, adult, no allergen exclusions;
- balanced agni, Ayurveda scoring flag off (shipping default);
- season `varsha`;
- deterministic seed `0x4D503662`;
- 13,993 usable shipped catalogue candidates;
- 91 distinct selected food IDs; and
- two-day no-repeat check: **true**.

The labels before each line identify the solved slot and test frame. The title
after the colon is verbatim production-template output.

```text
Day 1 · Breakfast · frame 0: Frozen yogurt, chocolate, Chocolate milk, whole, Milk shake with malt, and Soy milk, chocolate — 500 kcal and 16.5 g protein. Recorded tastes: astringent and sweet. Traditionally considered cooling.
Day 1 · Lunch · frame 1: Frozen yogurt bar, chocolate, Cowpeas, common (blackeyes, crowder, southern), mature seeds, raw, Garlic (dried), Wild garlic (dried), and Garlic powder (post-contact): 800 kcal, 40.9 g protein. Its recorded tastes are astringent, bitter, pungent, salty, and sweet.
Day 1 · Dinner · frame 2: At 700 kcal and 32.1 g protein, this dinner includes Rosemary, fresh, Yogurt, whole milk, fruit, Hot chocolate / cocoa, dry mix , made with non-dairy milk, Yogurt, whole milk, flavors other than fruit, Kasuri methi (dried fenugreek leaf), and Milk shake, home recipe, chocolate, light. Taste record: astringent, bitter, and pungent.
Day 2 · Breakfast · frame 3: 30.8 g protein and 500 kcal come from Cilantro Coriander Herb Salt, Infant formula, organic, powder, made with water, Infant formula, store brand, added rice, Spices, fenugreek seed, Mung Dal with Okra, and Mung beans, mature seeds, raw. The recorded tastes are astringent, bitter, pungent, and sweet.
Day 2 · Lunch · frame 4: Lunch includes Turmeric Fennel Finishing Salt, Pigeon peas (red gram), mature seeds, raw, Milk shake, bottled, chocolate, Cheese, mozzarella, nonfat, Milk, lactose free, reduced fat (2%), and Besan Methi Chilla, totaling 800 kcal and 57.9 g protein. Recorded taste set: astringent and sweet.
Day 2 · Dinner · frame 0: Lime leaf (dried), Curry Leaves, Black Cumin (Kalo Jeera), Yogurt, low fat milk, fruit, Sambar, vegetable stew, and Nigella Seed (Kalonji) — 700 kcal and 38.2 g protein. Recorded tastes: bitter, pungent, sour, and sweet.
Day 3 · Breakfast · frame 1: Mung Zucchini Stew, Cabbage and Peas Sabzi, Hot chocolate / cocoa, made with non-dairy milk, Baby Toddler yogurt, with fruit, Milk, malted, and Cabbage Fennel Chutney: 500 kcal, 17.4 g protein.
Day 3 · Lunch · frame 2: At 800 kcal and 37.4 g protein, this lunch includes Hot chocolate / cocoa, made with whole or reduced fat (2%) milk, Chocolate milk, reduced sugar, whole, Frozen yogurt cone, vanilla, waffle cone, Breadfruit leaf (dried, aromatic), Strawberry milk, reduced fat (2%), and Chickpea flour (besan). Taste record: astringent and sweet.
Day 3 · Dinner · frame 3: 33.1 g protein and 700 kcal come from Nigella seed, Toddler formula, store brand, pediatric shake, Marjoram (dried), Spices, marjoram, dried, Carom Seed (Jowan), and Black pepper (post-contact). The recorded tastes are bitter, pungent, and sweet.
Day 4 · Breakfast · frame 4: Breakfast includes Vegetable dip, yogurt based, Holy basil (dried), Spinach dip, yogurt based, and Chocolate milk, reduced sugar, reduced fat (2%), totaling 500 kcal and 31.8 g protein. Recorded taste set: bitter and pungent.
Day 4 · Lunch · frame 0: Almond milk, sweetened, Papad, Papad, grilled or broiled, Crisp Cumin Black Beans, Milk shake, fast food, flavors other than chocolate, and Mung Spinach Parsley Pot — 800 kcal and 47.8 g protein. Recorded tastes: astringent, pungent, salty, and sweet.
Day 4 · Dinner · frame 1: Infant formula, premature, powder, made with water, Hot chocolate / cocoa, NFS, Milk shake, home recipe, flavors other than chocolate, Rosemary, fresh, Curry leaf (dried), and Black Pepper: 700 kcal, 25.6 g protein. Its recorded tastes are astringent, bitter, and pungent.
Day 5 · Breakfast · frame 2: At 500 kcal and 28.8 g protein, this breakfast includes Cilantro Coriander Herb Salt, Ranch dip, yogurt based, Mung beans, mature seeds, raw, Yogurt tube, Gujarati Spinach Mung Shaak, and Cabbage Mung Dal. Taste record: astringent and sweet.
Day 5 · Lunch · frame 3: 62.4 g protein and 800 kcal come from Turmeric Fennel Finishing Salt, Fenugreek Seed (Methi), Pigeon peas (red gram), mature seeds, raw, Spices, fenugreek seed, Besan Methi Chilla, and Cheese, Mozzarella, nonfat or fat free. The recorded tastes are astringent, bitter, pungent, and sweet. Traditionally considered heating.
Day 5 · Dinner · frame 4: Dinner includes Curry Leaves, Tulsi (dried), Black Cumin (Kalo Jeera), Lime leaf (dried), Lentils, pink or red, raw, and Nigella Seed (Kalonji), totaling 700 kcal and 40.8 g protein. Recorded taste set: astringent, bitter, pungent, sour, and sweet.
Day 6 · Breakfast · frame 0: Cabbage and Peas Sabzi, Egg, white, raw, fresh, Bhindi Sabzi, Cabbage Fennel Chutney, Frozen yogurt sandwich, and Frozen yogurt cone, vanilla, waffle cone — 500 kcal and 21.8 g protein, with sweet as its recorded taste.
Day 6 · Lunch · frame 1: Breadfruit leaf (dried, aromatic), Strawberry milk, low fat (1%), Cheese, mozzarella, nonfat, Black Bean Cilantro Dip, Mung Mint Dip, and Chickpea flour (besan): 800 kcal, 58.7 g protein. Its recorded tastes are astringent and sweet.
Day 6 · Dinner · frame 2: At 700 kcal and 31.9 g protein, this dinner includes Carom Seed (Jowan), Nigella seed, Yogurt, whole milk, plain, Lemongrass leaf (not powder), Yogurt, whole milk, fruit, and Hot chocolate / cocoa, dry mix, reduced sugar, made with water. Taste record: astringent, bitter, and pungent.
Day 7 · Breakfast · frame 3: 16.2 g protein and 500 kcal come from Almond milk, chocolate, Milk shake with malt, Almond milk, sweetened, and Milk, NFS, with sweet as its recorded taste.
Day 7 · Lunch · frame 4: Lunch includes Yogurt, low fat milk, plain, Vegetable dip, yogurt based, Papad, Rajasthani Fenugreek Lentil Stew, Rajma Spinach Curry, and Mung Spinach Parsley Pot, totaling 800 kcal and 50.0 g protein. Recorded taste set: astringent, pungent, and salty.
Day 7 · Dinner · frame 0: Yogurt, low fat milk, fruit, Kasuri methi, Goat milk, Soy milk, chocolate, Rosemary, fresh, and Kala jeera — 700 kcal and 38.3 g protein. Recorded tastes: astringent, bitter, pungent, and sweet.
```

The sample deliberately remains unedited. Any odd catalogue combination is a
solver-quality input for a future task, not something narration is authorized
to hide or repair.

## Frame distribution

| Frame | Meals |
|---:|---:|
| 0 | 5 |
| 1 | 4 |
| 2 | 4 |
| 3 | 4 |
| 4 | 4 |
| **Total** | **21** |

The sequence is `0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0,1,2,3,4,0`.
No adjacent meals share a frame.

## Gate ledger

| Gate | Result |
|---|---|
| MP6b-G1 Debug + Release, flag on/off | **PASS** — final arm64 iOS 26.2 simulator Debug and optimized Release builds succeeded; runtime first-frame smoke passed with `MP5AyurvedicSolverEnabled` off and with `-mp5AyurvedicSolver` on. Only pre-existing project warnings remain. |
| MP6b-G2 full suite | **PASS — 125/125** in 71.931s = 123 accepted MP-6 tests + 2 new copy/real-plan tests |
| MP6b-G3 MP-5 hard properties | **PASS — 23/23** |
| MP6b-G4 determinism | **PASS** — 100 repeated seven-day template runs are byte-identical; frame selection is a pure `(day, slotIndex)` function |
| MP6b-G5 total model calls | **PASS — exactly 2**: one MP-4 interpretation + one MP-6 whole-plan narration call |
| MP6b-G6 real seven-day sample | **PASS** — 21/21 nonempty titles from the production solver over 13,993 usable shipped candidates; verbatim sample above |
| MP6b-G7 adjacent frames | **PASS** — zero adjacent repeats; distribution 5/4/4/4/4 |
| MP6b-G8 search/launch/size | **PASS** — search goldens 25/25 legacy + 2/2 safety exact; final cold-launch median 1.543055s; largest tracked file 82,726,160 bytes |

Mismatch and timeout fixtures remain complete all-template fallbacks. The
Foundation-only harness still has zero `FoundationModels` dynamic linkage.

## Final cold-launch sample

Method: final Debug app, retained iOS 26.2 simulator
`76DCB533-2487-4BD3-B9D5-1087CADC5625`, one unmeasured warm-up, then ten
cold-process launches. The simulator stayed booted and app data was retained;
the app process was terminated before every run. Timing is host monotonic time
immediately before `simctl launch --console-pty` to
`WE6_PROFILE|first-interactive-frame|...`.

| Run | Seconds |
|---:|---:|
| 1 | 1.534132 |
| 2 | 1.555531 |
| 3 | 1.538131 |
| 4 | 1.541022 |
| 5 | 1.559152 |
| 6 | 1.551923 |
| 7 | 1.551587 |
| 8 | 1.534163 |
| 9 | 1.545089 |
| 10 | 1.501733 |

| N | Median | IQR (Q1–Q3) | Min | Max | Population stddev |
|---:|---:|---:|---:|---:|---:|
| 10 | **1.543055s** | 0.016684s (1.535155–1.551839) | 1.501733s | 1.559152s | 0.015595s |

The median is below both the 1.650s profiling-paydown trigger and the 1.700s
hard ceiling.
