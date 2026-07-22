# TASK D8.3 — Ayurveda editor restyle (founder-approved design)
Executor: Codex on the founder's Mac, branch ayurveda-app. Protocol: founder is
the hands for UI evidence; you never navigate the simulator. Launch only with
-uiTestNoAds. Stop-and-report on ambiguity. Update the handbook ledger at the end.

## Scope
Restyle the MANUAL Ayurveda form (`AyurvedaEditorSection`) used by Add Food and
by the recipe/menu "Set manually" override. Pure presentation: the form model,
bindings, save logic (kind "user" profile), and the automatic computed preview
are UNCHANGED. A founder-approved mock exists (attached image, if provided) —
this text is normative where they differ.

## Component spec (normative)

Card header: title "Dosha Effects", subtitle "Adjust how this food affects the
doshas", trailing "Reset all" text button (arrow.counterclockwise icon) that
sets all three doshas to 0, clears rasa and gunas selections, and unsets
virya/vipaka.

1. DOSHA ROWS (new `DoshaScaleSelector` view, one per dosha):
   - Leading: circular tinted icon + name + subtitle. Vata: SF "wind", soft
     blue. Pitta: SF "flame", warm orange. Kapha: SF "leaf", sage green.
   - Control: a 5-segment discrete selector: −2 · −1 · 0 · +1 · +2.
     Segment text tint: −2/−1 green, 0 neutral primary, +1/+2 orange.
     Selected segment = filled capsule in state color (green when negative,
     dosha-neutral blue/gray at 0, orange when positive) with a small caret
     and word under it: "pacifying" / "neutral" / "aggravating".
   - Caption line under the control: e.g. "−2 · strongly pacifies",
     "+1 · aggravates", "0 · neutral" (reuse existing effectLabel strings).
   - Haptic light impact on change.

2. RASA (taste): six multi-select chips with small leading icons
   (Sweet, Sour, Salty, Pungent, Bitter, Astringent). Unselected: frosted
   neutral background, primary label. Selected: accent-tinted fill (Sweet
   purple, Sour yellow, Salty teal, Pungent red, Bitter green, Astringent
   violet — muted pastels) + small checkmark badge at top-right corner.
   New reusable `AyurvedaChip` + wrapping `ChipGrid` (use the existing
   flow-layout helper if the app has one; otherwise a simple wrapping layout).

3. VIRYA (energy): 3-option single-select segmented row — "Cooling"
   (snowflake, ice-blue when selected) · "Neutral" (minus) · "Heating"
   (flame, warm when selected). Tapping the selected option deselects it
   (virya remains optional/unset). VIPAKA (post-digestive): same component
   with Sweet · Sour · Pungent, no icons, deselectable.

4. GUNAS (qualities): twelve chips in the wrapped grid — Dense, Dry, Heavy,
   Light, Liquid, Oily, Penetrating, Rough, Sharp, Slimy, Smooth, Soft —
   same chip behavior as rasa (neutral until selected + checkmark badge).

5. FOOTER: info banner (info.circle.fill icon, subtle tinted background):
   "Saved as tier 'User' — shown in this food's Ayurveda section."

## Constraints
- Match the app's glassmorphism (`glassCardStyle`) and support dark mode.
- Type-checker budget: every component above is its own small file/struct
  under WiseEating/Ayurveda/Views/ (DoshaScaleSelector, AyurvedaChip,
  ChipGrid, EffectSegmentPicker); extracted handlers; explicit Sendable where
  shared value types arise.
- Accessibility: VoiceOver labels ("Vata effect", value "minus two, strongly
  pacifies", hint "adjusts dosha effect"); chips report selected state;
  all targets ≥ 44pt.
- No changes outside WiseEating/Ayurveda/Views/ + the report + handbook.

## Gates
- G1 build PASS, zero new warnings vs baseline.
- G2 behavior parity: founder sets V−1/P0/K+1, rasa sweet, virya heating,
  gunas oily+heavy on a user food and saves → sqlite row identical in shape
  and values to pre-restyle behavior (kind "user", same fields); relaunch
  persistence.
- G3 founder screenshots: Add Food editor (light + dark mode), recipe
  "Set manually" override, one dosha selector mid-change.
- G4 validator green; diff proves scope.
REPORT-D8.md gains a "D8.3" section; handbook ledger updated; commit per
deliverable group; push.
