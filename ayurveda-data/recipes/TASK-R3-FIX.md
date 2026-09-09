# TASK R3-FIX — Expand step text in batches r19–r30 (executor: Codex / Sonnet 4.5+)

Director verification of R3 found: every one of the 600 recipes has exactly 3
steps, versus the 5-step norm of approved batches r01–r18. The prose style is
good — keep it. The problem is missing practical detail.

## Mission

Rewrite ONLY the `steps` arrays of every recipe in batches r19–r30.
Do not change any other field (ids, names, ingredients, grams, dosha, seasons,
guidance, flags all stay byte-identical).

## Requirements per recipe

1. 5–8 steps (match the depth of r01–r18; complex dishes may use more, simple
   drinks may stay at 4).
2. Include the concrete craft details a cook needs, where applicable:
   - liquid quantities in cups/ml when water/stock is added
   - soak, rest, and cooking times in minutes
   - heat levels (low/medium/high) and doneness cues ("until the edges dry",
     "until aromatic", "until a knife slides through")
   - the order and timing of ingredient additions
3. Keep the anti-template rule from TASK-R3: natural prose, never paste
   ingredient display names verbatim.
4. Steps must remain original text, imperative voice, no brand names.

## Process

One batch at a time: rewrite steps → `python3 ayurveda-data/validate.py --store /tmp/pre`
→ zero errors → verify with `git diff` that only `steps` changed in that batch →
commit ("R3-FIX rNN: expand steps to full craft detail") → next.
Do not push. Touch only ayurveda-data/recipes/batch-r19..r30.json.

## Final report

Append to `ayurveda-data/recipes/REPORT-R3.md`: new step-count distribution for
r19–r30, confirmation (with diff stats) that only steps changed, and your
verbatim-name scan output.
