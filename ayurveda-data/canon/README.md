# Dravya Canon — Batches 5–18 (Director knowledge dump, 2026-07-11)
Machine-readable canon index authored by Fable-5 from classical Dravyaguna knowledge
(Bhavaprakasha Nighantu, Charaka/Sushruta ahara chapters, common usage). Complements
`docs/content/food/DRAVYA-CANON-LIST-V1.md` batches 1–4 (125 items already named there —
NOT duplicated here) and the 10 shipped exemplar dravyas.

**Status: every entry is `aiDraft`-grade.** Properties are headline-level (dosha effect
+ virya) for scaffolding and expert review — NOT publishable facets. The scaffold tool
expands each entry into full dravya YAML (rasa/vipaka/gunas/servings/FDC binding);
the expert reviewer corrects and promotes.

## Schema (one JSON object per line inside each file's `items` array)
- `id` — slug, `dravya.<kebab>`
- `name` / `sanskrit` — English name / Sanskrit-Hindi traditional name (null = none established)
- `category` — spice · medicinal · grain · legume · vegetable · leafy-green · fruit ·
  dry-fruit-nut · seed · dairy · oil-fat · sweetener · preparation · beverage ·
  fermented · animal · salt-mineral · regional
- `vpk` — [vata, pitta, kapha] effect, −2 pacifies strongly … +2 aggravates strongly
  (matches AyurvedaFacet doshaEffect and recipe vataEffect/pittaEffect/kaphaEffect)
- `virya` — heating | cooling | neutral
- `fdc` — mapping hint per canon policy: direct | nearest | recipe-composed | estimated
- `note` — optional disambiguation/caution

## Files
canon-05-spices-medicinal · canon-06-grains-legumes · canon-07-vegetables ·
canon-08-greens-fruits · canon-09-nuts-seeds-dairy-oils-sweeteners ·
canon-10-preparations-beverages-fermented · canon-11-animal-salts-regional

Counts fall slightly short of some category budgets (honest coverage over padding);
the reviewer/Codex fill gaps via the scaffold. Items known to vary between classical
texts carry a note; the expert arbitrates ("traditions vary" UI is supported).
