# TASK R3 — Completion tier: 600 recipes to reach 1,500 (executor: Codex / Sonnet 4.5+)

R1 and R2 are approved. Base rules: `TASK-R1.md`; R2 deltas still apply
(`TASK-R2.md`). This file adds R3 scope and one new writing rule.

## NEW WRITING RULE (defect found in R1/R2 verification)

Never paste an ingredient's display name verbatim into step text. Ingredient
names use catalog form ("Carrot, diced"); steps must use natural prose form
("the diced carrot"). Write steps as human sentences, not templates. Batches
with template-generated step text will be rejected.

## Mission

Batches r19–r30, 50 recipes each = 600. Still lacto-vegetarian. IDs must not
collide with r01–r18 (extract existing ids first).

## Coverage plan (50 each)

- r19: regional Indian mains I — South (Kerala/Tamil/Andhra/Karnataka: avial, olan, theeyal, kootu variants not yet covered)
- r20: regional Indian mains II — North/West/East (Gujarati, Rajasthani, Bengali, Punjabi vegetarian classics)
- r21: festival & vrat (fasting) foods — sabudana, rajgira, kuttu, singhara-style dishes using existing dravyas
- r22: dosha-targeted meal sets I — 25 vata-pacifying + 25 pitta-pacifying complete meals
- r23: dosha-targeted meal sets II — 25 kapha-pacifying meals + 25 tridoshic meals
- r24: seasonal menus — ritu-specific dishes (vasanta through shishira, ~8 each)
- r25: convalescent & light meals — peya/manda extensions, soft foods, post-illness cooking
- r26: one-pot & weeknight — 30-minute dosha-tagged dinners
- r27: raw & summer preparations — salads, cold soups, summer plates (honest vata cautions)
- r28: breads & flatbreads — rotis, theplas, parathas, international flatbreads
- r29: condiments II — chutneys, raitas, pickles, spice blends, masalas not yet covered
- r30: beverages II — seasonal sherbets, dosha teas, warm tonics, plant-milk drinks

## Rules recap (enforced)

Enums per R1 · ≥50% dravya-linked (aim 80%+) · realistic grams · 3–15 original
steps · honest dosha scores · viruddhaFlags where rules are broken + compliant
variant in guidance · no medicinal claims · qualityState aiDraft · reviewNote
where traditions disagree.

## Process & report

Same loop: one batch → `python3 ayurveda-data/validate.py --store /tmp/pre` →
zero errors → commit → next. Do not push; touch only `ayurveda-data/recipes/`.
Final report: `ayurveda-data/recipes/REPORT-R3.md` (same sections as R2's, plus
confirmation that no ingredient display names appear verbatim in steps —
include your own scan output proving it).
