# Codex dispatch prompt — D8 (copy verbatim into Codex on the Mac)

You are the executor for task D8 in the repo `wise-eating`, branch `ayurveda-app`
(verify with `git branch --show-current`; if it is not `ayurveda-app`, stop).

Read, in this order, before writing any code:
1. `ayurveda-data/DESIGN-D8.md` — normative design (U1–U12 + Simulated reference
   numbers are binding; copy color hexes, tier mapping, percentage formula, and
   all expected numbers verbatim).
2. `ayurveda-data/TASK-D8.md` — your packet: deliverables, anchors, gates G1–G6,
   report format.
3. `PROJECT-HANDBOOK.md` §3 (fixed decisions) and §4 (type-checker budget rules:
   small sub-views, extracted closure handlers, explicit Sendable on shared value
   types).

Then implement exactly the 11 deliverables in TASK-D8.md. Hard rules:
- Touch ONLY the listed files. Never modify `FoodItem.swift`,
  `AyurvedaProfile.swift`, `AyurvedaRules.swift`, the seeder, any JSON/seed/store
  file, or `validate.py`.
- Do not relitigate design decisions; do not "improve" wording, colors, formulas,
  or expected counts.
- Stop-and-report rule: if any gate fails, an anchor named in the packet doesn't
  exist, or you hit any unexpected state (compiler expression-complexity errors
  you cannot resolve by mechanical view-splitting, missing scheme, seed count
  mismatch), capture the exact output verbatim in `ayurveda-data/REPORT-D8.md`,
  commit nothing further, and stop. Never tune constants to force a gate.

Run gates G1–G6 in order (G2 math check → G3 baseline+build → G4 simulator spot
checks with screenshots → G5 editor round-trip → G6 validator) and record
evidence for each in `ayurveda-data/REPORT-D8.md` in the format the packet
specifies. Expected G2 output: `D8 MATH CHECK: 31/31 PASS`.

Commit with message:
`D8: Ayurveda UI — detail section (signed dosha bars, tier labels, chips,
viruddha/exclusion warnings) + user-food editability (tier "user")`
Do not push. Your report will be independently re-verified by the director.
