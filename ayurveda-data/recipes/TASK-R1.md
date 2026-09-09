# TASK R1 — Ayurvedic Recipe Authoring (executor: Codex / Sonnet 4.5+)

You are a content-authoring agent working in the wise-eating repository.
Your director (Fable 5) will verify your output with `ayurveda-data/validate.py`
and by spot-reading recipes. Follow this spec exactly.

## Mission

Author original Ayurvedic recipes as JSON batches in `ayurveda-data/recipes/`.
Target for this task: batches r01–r06, 50 recipes each = 300 CLASSICAL recipes.
Write ORIGINAL instruction text — never copy from websites or books.

## Coverage plan (50 each)

- r01: kitchari variations (per dosha, per season), peya/vilepi rice gruels, yushas (dal soups)
- r02: classical dals & soups (mung, masoor, toor, kulthi styles), rasam, sambar family
- r03: vegetable sabzis (lauki, karela, bhindi, kushmanda, methi, palak…), poriyals, kootus
- r04: breakfast & grains (upma, poha, dalia, idli, dosa, ragi porridge, pancakes)
- r05: sweets & tonics (kheers, laddus, halwas, panjiri, chyawanprash-style jams, golden milk)
- r06: drinks & condiments (takra variations, sherbets, teas, chutneys, achars, spice churnas)

Use `ayurveda-data/canon/canon-12-recipes.json` (133 named recipe stubs) as the
primary worklist — cover those names first, then fill each batch theme to 50.

## File format

`ayurveda-data/recipes/batch-rNN.json`:

```json
{
  "formatVersion": "1.0",
  "batch": "recipe-batch-r01",
  "qualityState": "aiDraft",
  "items": [
    {
      "id": "recipe.classic-mung-kitchari",
      "name": "Classic Mung Kitchari",
      "category": "classical",
      "meal": "lunch",
      "servings": 4,
      "prepMinutes": 15,
      "cookMinutes": 35,
      "ingredients": [
        {"dravyaId": "dravya.white-rice", "name": "White basmati rice", "grams": 185},
        {"dravyaId": "dravya.mung-bean", "name": "Split yellow mung dal", "grams": 200},
        {"dravyaId": "dravya.ghee", "name": "Ghee", "grams": 27},
        {"dravyaId": "dravya.cumin", "name": "Cumin seeds", "grams": 4},
        {"dravyaId": "dravya.turmeric", "name": "Turmeric powder", "grams": 3},
        {"dravyaId": "dravya.ginger-fresh", "name": "Fresh ginger, grated", "grams": 6},
        {"dravyaId": "dravya.rock-salt", "name": "Rock salt", "grams": 4}
      ],
      "steps": [
        "Rinse rice and dal together until the water runs clear; soak 15 minutes and drain.",
        "Warm the ghee in a heavy pot; add cumin seeds and let them sizzle until aromatic.",
        "Stir in ginger and turmeric for a few seconds, then add rice and dal; coat in the spiced ghee.",
        "Add 6 cups hot water and the salt; bring to a boil, then simmer covered 30–35 minutes.",
        "Stir toward a soft, porridge-like consistency; rest 5 minutes and serve warm."
      ],
      "dosha": {"vata": -1, "pitta": -1, "kapha": 0},
      "seasons": ["vasanta", "grishma", "varsha", "sharad", "hemanta", "shishira"],
      "timeOfDay": ["midday"],
      "viruddhaFlags": [],
      "guidance": "The archetypal tridoshic healing meal. Vata: add extra ghee. Pitta: swap ginger for coriander. Kapha: add black pepper and reduce ghee.",
      "provenance": ["classical kitchari tradition (Charaka: krisara)"],
      "confidence": {"ayur": 0.9}
    }
  ]
}
```

## Hard rules

1. **Enums** — meal: breakfast|lunch|dinner|snack|drink|dessert. category:
   classical|everyday|international. seasons: vasanta|grishma|varsha|sharad|hemanta|shishira.
   timeOfDay: morning|midday|evening|night. dosha values: −2…+2 integers.
2. **Ingredient linking** — every ingredient needs `dravyaId` (preferred) or `fdcId`.
   Valid dravya IDs = every `id` in `ayurveda-data/dravyas/batch-*.json` (extract them
   first; there are 210). At least 50% of each recipe's ingredients MUST be dravya-linked
   (validator enforces; aim for 80%+). If an ingredient has no dravya and no obvious
   fdcId, choose a different ingredient — do NOT invent IDs.
3. **grams** — realistic weights for the stated servings; always > 0.
4. **steps** — 3–15 steps, imperative voice, original text, no brand names.
5. **dosha** — score the finished dish (ingredients + preparation), not the raw sum.
   Add per-dosha adaptation notes in `guidance`.
6. **viruddhaFlags** — if a recipe intentionally includes a traditional incompatibility
   (e.g., fruit+dairy in a modern smoothie), name it here as a string. Classical batches
   r01–r06 should have zero viruddha content.
7. **Safety** — no medicinal dosing claims, no disease-cure language. `guidance` may say
   "traditionally used for…" only with a classical provenance.
8. **qualityState** stays `aiDraft`. Where traditions disagree, add `"reviewNote"`.

## Validation (must pass before every commit)

```
cat Ayura/preseeded_db.store.gz.part-aa Ayura/preseeded_db.store.gz.part-ab > /tmp/pre.gz && gunzip -f /tmp/pre.gz
python3 ayurveda-data/validate.py --store /tmp/pre
```

Zero errors required. If git complains about stale locks:
`rm -f .git/*.lock .git/refs/heads/main.lock && git reset`

## Process

One batch at a time: write batch → validate → commit
(`git commit -m "Recipes batch rNN: <theme> (50 items, validated)"`) → next.
Do not modify any file outside `ayurveda-data/recipes/`. Do not push.

## Final report (for the director)

Append to `ayurveda-data/recipes/REPORT-R1.md`: batches completed, recipe count,
validation output (paste), dravya-link percentage per batch, any canon-12 names
you could not cover and why, any reviewNotes added.
