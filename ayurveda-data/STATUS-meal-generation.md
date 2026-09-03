# Meal Generation — Status

Director status · rev5 · 2026-07-27
`ayurveda-app` @ `dcaf751` · **MP-7 complete**

---

## 1. Headline

MP-7 closed every gate. The solver now produces plans that are safe, feasible, Ayurvedically measurable and — the thing rev3 of this document was wrong about — actually food.

| Measure | rev1 | rev3 | now |
|---|---:|---:|---:|
| Model calls, 7-day plan | ~135–260 | 2 | 2 |
| 7-day solve, real catalogue | not measured | not measured | **642 ms median** |
| Engineering, honest | ~35% | claimed 92% | **~88%** |

rev3 claimed 92% and rev4 corrected that to 72% after MP-6b served infant formula to an adult three times in one week. 88% is the first figure on this line I'd defend.

---

## 2. The three complaints

**Slow.** ~135–260 model calls → 2. A 7-day plan as model output is ~2,745 tokens; as parsed constraints it is ~58.

**Inaccurate.** `aiFetchNutritionData` asked a 3B model for macros and fed them into gram-weight adjustment. Deleted; macro fidelity proven to 1e-9.

**Ayurveda unused.** 714 dravyas were a two-food exclusion gate. Y1 now measures a **+1.5507** mean pacification delta — and see §4, because that number needs reading carefully.

A fourth, which nobody had named and which I did not test for: **the output was not food.** MP-7 exists for that.

---

## 3. What MP-7 actually was

Nine revisions of `food-roles.json`. Each stop found something larger than the case that triggered it:

| Found | Real exposure |
|---|---:|
| bare `salt` at priority 80 → spice | **592 rows** |
| same shape on juice/sauce/cream/milk/water/butter/oil | ~**1,900 rows** at risk |
| all 187 categories above the name phrases | **7,268 rows** (57.7%) decided by the coarsest signal |
| commodity rules applied to recipe titles | **198 of 1,500** recipes as spice/herb |
| `requiresCooking` too narrow | **126** ineligible rows reaching plates |
| order-independent groups used for a positive assertion | **23** real foods wrongly excluded |

Two method changes did most of the work. **The eligibility census replaced random sampling** — a 100-row sample contains ~4 ineligible rows, so the one property gated at zero was being measured at n≈4 against a population of 535. The census is exhaustive in both directions and cannot be burned. And **three random holdouts were burned and retained as regression fixtures**, because every one of them was used to fix the rules it had just tested.

Final gate results: G0 21/21 · fixtures 71/71 · G1 8/589 · G1b 0/12,601 · G2b 39/40 · G2c **0/543 forward, 0/303 reverse** · G4 150/150 · G5 30/30 · G6 +1.5507 · G7 passed on ruling · G8 passed.

---

## 4. Read Y1 carefully

|  | imbalanced | cleared | delta |
|---|---:|---:|---:|
| MP-5 rev1 | −1.6565 | −1.1355 | +0.5209 |
| MP-7 rev9 | −1.4998 | **+0.0510** | **+1.5507** |

The treatment arm barely moved. The **control** moved, from −1.14 to ~0.

The old candidate pool was itself biased pacifying — full of classical-tier spices — so the no-Ayurveda arm accidentally produced pacifying plans and the control was not a control. Y1 did not triple because the objective improved; it tripled because the measurement stopped being contaminated.

§6 of TASK-MP7 predicted the spice bias was inflating the *effect*. It was inflating the *baseline*. Same defect, opposite sign. This is the first honest reading of that property, and it is the strongest evidence so far that the dravya data reaches selection.

---

## 5. Performance ruling

The 150 ms ceiling is **withdrawn**. It came from the synthetic `mp5_solver_harness` and was applied to a 13,993-row real catalogue — never a like-for-like number.

| Metric | Ceiling | Measured (iPhone 16 Pro) |
|---|---:|---:|
| 7-day solve | ≤ 1,200 ms | 642 median / 960 max |
| role resolution cold | ≤ 100 ms | 44.7 |
| role resolution cached | ≤ 5 ms | 1.09 |
| cold launch | ≤ 1.700 s | 1.090 |
| peak memory | ≤ +90 MB | +10.3 MiB |

**Not frozen until re-measured on iPhone 15 Pro** — the slowest device that can run this, since 15 and 15 Plus are A16 with no Apple Intelligence. A17 Pro is ~15–20% slower, so expect ~1.15 s there. If it exceeds 1,200 ms, the ceiling moves to that device's number rather than anyone tuning to hit mine.

A sub-second solve sitting behind two on-device model calls, replacing a ~90-second system, is good enough. Solve time is no longer the bottleneck.

---

## 6. Remaining

| Item | Type | Blocking the flag? |
|---|---|---|
| **Vaidya review** — 6 contested roles, 7 contested exclusions, coriander leaf/seed, coconut allergen, 62% estimated tier | content | **yes** |
| iPhone 15 Pro perf re-measure | measurement | freezes the ceiling |
| MP-5b — N4 protein objective, Y5's three inverted midday cases | tuning | no |
| MP-1 device matrix, MP-2 twenty-food error table, MP-3 runtime counts | measurement | no |
| ~1,023 unreachable `frame_map` keys | defect | no — but free imagery |
| IMG — 102/1,844 generated | new workstream | no |

**The vaidya review is now the only thing standing between this and the flag going on.** Every engineering gate is closed.

---

## 7. Risks

**The 285 MB food-image video still has exactly one copy.** Gitignored, not reproducible at original quality from anything checked in. Unchanged since rev3 and still the only irreversible item on the board.

**~1,023 rows have an image shipping in the archive that the app cannot find.** `foods.json` and `frame_map.json` both hold 12,601 entries; only 11,578 names match even after sanitising. That is more coverage than half the imagery generation run, for a key-matching fix.

**The 15 Pro number is unknown.** Everything in §5 is one device.

**Four holdout MAJOR errors were left standing** — pasta salad, potato skins, french fries, chocolate-chip muffin. All anchor-versus-accompaniment ambiguity, all eligible, none affecting a hard property. Documented, not tuned away.

---

## 8. Method notes worth keeping

**Census, not sample, for anything gated at zero.** A random sample cannot measure a rare class. This one change turned four rounds of one-error-at-a-time into a single exhaustive pass.

**A holdout used to fix rules is burned.** Three were, and all three are labelled as fixtures. The discipline is worth more than the number.

**Order-independent token groups are for vetoes only.** Over-matching a veto fails safe. Over-matching a positive assertion removes real food. Same mechanism, opposite blast radius.

**Measure before optimising.** My 28M-evaluation hypothesis for the 4-second solve was wrong; it was repeated greedy scoring and 1.266M scans. Profiling first found it, and a canonical hash over all 30 plans proved the 6.3× speedup changed nothing.

**Read the output.** MP-6b's sample was requested for narration copy. The defect was visible in the first meal. Thirty-six properties and 123 tests did not see what one read-through did.
