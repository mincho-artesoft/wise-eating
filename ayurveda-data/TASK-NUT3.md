# TASK — NUT-3: resolve the canon backlog (14 aliases, 1 restored dravya, 11 new recipes)

Director packet · 2026-08-01 · `ayurveda-data/nutrition/canon-unbuilt.json`
Ruling this packet executes: `DECISIONS-NUT.md` §N6.

**Stop-and-report rule applies.**

---

## 1. Result up front

`canon-unbuilt.json` lists 26 entries "planned but never built". Checked against
all 705 dravyas and 1,500 recipes by name, sanskrit, and alias:

- **14 are duplicates of an existing dravya.** They become aliases (§N6).
- **Vida salt is a distinct dravya.** It was initially merged into black salt
  because black salt carried the incorrect Sanskrit name `Vida lavana`; the
  correction below restores Vida and names black salt `Sauvarchala lavana`.
- **11 are genuinely new recipes.** No name or alias match anywhere.

The file's own note predicted this — *"canon frequently uses a different id for
a substance that was built under another one"* — it just understated how
completely.

The original §N5 conclusion was therefore wrong: restoring the distinct Vida
record renumbers the placeholder band to 900001–900377. TASK-IDKEY must build
its DB-id map only after the corrected preseed has been rebuilt. The 11 recipes
remain appended in the 1000001+ band.

---

## 2. Disposition table

| canon id | canon name | disposition | target | evidence |
|---|---|---|---|---|
| `dravya.fenugreek-greens` | Fenugreek greens (methi) | **alias** | `dravya.methi-leaves` (Fenugreek leaves, skt Methika patra) | Methika Shaka = Methika Patra, same leaf |
| `dravya.green-amaranth-greens` | Green amaranth greens | **alias** | `dravya.amaranth-leaves` (Amaranth leaves, skt Tanduliya) | plain Marisha against our Marisha (rakta) red variant; add reviewNote on the Tanduliya/Marisha split |
| `dravya.dill-greens` | Dill greens (suva) | **alias** | `dravya.dill` (Dill, fresh, skt Shatahva) | existing entry already aliases `soa`/`suva`; see §4 Shatapushpa conflict |
| `dravya.taro-tender-leaf` | Tender taro leaf (patra use) | **alias** | `dravya.colocasia-leaf` (Colocasia leaf, skt Pindalu Patra) | existing entry already aliases `taro leaf` and `patra` |
| `dravya.soft-dates` | Soft dates (khajur) | **alias** | `dravya.dates` (Dates, skt Kharjura) | dry-dates and fresh-dates already exist separately |
| `dravya.dry-fig` | Dry fig (anjeer) | **alias** | `dravya.dried-fig` (Fig, dried, skt Shushka anjeera) | existing alias `dry anjeer` |
| `dravya.dry-apricot` | Dry apricot (khubani) | **alias** | `dravya.dried-apricot` (Apricot, dried) | existing entry, alias `sukhi khubani` |
| `dravya.lotus-seed-popped` | Popped lotus seed | **alias** | `dravya.lotus-seed` (Lotus seeds (makhana), skt Makhanna) | existing alias `phool makhana`; see §4 duplicate pair |
| `dravya.malai` | Fresh cream (malai) | **alias** | `dravya.cream` (Cream, heavy) | existing alias `malai`; add `Santanika` as sanskrit |
| `dravya.cultured-butter` | Cultured butter | **alias** | `dravya.butter` (Butter, unsalted, skt Navanita) | Navanita *is* cultured butter, churned from dahi |
| `dravya.cane-jaggery` | Cane jaggery (gud) | **alias** | `dravya.jaggery` (Jaggery, skt Guda) | Guda = Guda, exact sanskrit match |
| `dravya.powdered-jaggery` | Powdered jaggery (shakkar) | **alias** | `dravya.jaggery` (Jaggery, skt Guda) | shakkar is granulated gud, same substance |
| `dravya.stevia-leaf` | Stevia leaf | **alias** | `dravya.stevia` (Stevia) | reviewNote: the existing entry is named for the *extract* |
| `dravya.vida-salt` | Vida salt | **restore distinct dravya** | `dravya.vida-salt` (skt Vida Lavana) | **reversed ruling:** pancha lavana names Vida and Sauvarchala separately. Black salt is Sauvarchala lavana; its erroneous `Vida lavana` label created the false exact match. Black salt is corrected and its Vida aliases are removed. |
| `dravya.iodized-salt` | Iodized table salt | **alias** | `dravya.sea-salt` (Salt, sea/table, skt Samudra lavana) | existing alias `table salt`; reviewNote on iodization |
| `recipe.horse-gram-soup` | Horse gram soup (kulthi) | **build** | new recipe | ingredient `dravya.horse-gram` exists; the dish does not |
| `recipe.parwal-sabzi` | Parwal sabzi | **build** | new recipe | `_buildAs` says `dravya` — **wrong, correct to recipe** |
| `recipe.tinda-sabzi` | Tinda sabzi | **build** | new recipe | `_buildAs` says `dravya` — **wrong, correct to recipe** |
| `recipe.amla-chutney` | Amla chutney | **build** | new recipe | nearest are other chutneys, not duplicates |
| `recipe.sol-kadhi` | Sol kadhi | **build** | new recipe | nearest are other kadhis |
| `recipe.khajur-smoothie` | Date-banana smoothie | **build** | new recipe | see §4 viruddha policy |
| `recipe.amla-ginger-shot` | Amla-ginger morning shot | **build** | new recipe | — |
| `recipe.gond-ladoo` | Gond ladoo | **build** | new recipe | nearest are other ladoos |
| `recipe.samak-rice-fasting` | Samak rice bowl (fasting) | **build** | new recipe | — |
| `recipe.singhara-pakora-fasting` | Singhara flour pakora | **build** | new recipe | — |
| `recipe.ugadi-pachadi` | Ugadi pachadi | **build** | new recipe | six-taste teaching dish, no equivalent exists |

---

## 3. Work

1. **Aliases.** Add each duplicate canon name (and its sanskrit, where the existing entry
   lacks one) to the target dravya's `aliases`. Do not create dravyas. Do not
   alter any existing `vpk`, `virya`, or dosha value from the canon record —
   canon's numbers were never reviewed and the shipped entries were.
   Where canon's `vpk` disagrees with the target, record a `reviewNote`; do not
   reconcile.
2. **`_buildAs` correction.** `recipe.parwal-sabzi` and `recipe.tinda-sabzi`
   carry `_buildAs: "dravya"` against a `recipe.` id. Both are dishes, and the
   catalogue already holds a family of `* Sabzi` recipes. Build as recipes.
3. **Recipes.** Author the 11 to the existing batch-r schema. Ingredients link
   to existing dravyas/fdcIds. `qualityState: aiDraft` per fixed decision 5.

**Gate G1.** Dravya count is **706**. Recipe count is **1,511**.
Placeholder band is 900001–900377 — assert it, do not assume it.

**Gate G2.** After aliasing, every one of the 26 canon ids resolves to exactly
one built entity. No canon id resolves to two.

**Gate G3.** No new exact name collision. Run the whole-catalogue name check;
it must still report exactly the **three** known collisions (`Golden milk`,
`Panchamrita`, `Mung Rice Peya`) and no fourth.

---

## 4. Director rulings carried into this packet

- **Vida salt and black salt are distinct.** The pancha lavana are Saindhava,
  Sauvarchala, Vida, Samudra, and Romaka. `dravya.black-salt` is Sauvarchala
  lavana; `dravya.vida-salt` is Vida Lavana. The former `vida-salt →
  black-salt` ruling is reversed because it arose from black salt's incorrect
  Sanskrit label. The malai → cream and powdered-jaggery/shakkar → jaggery
  rulings stand.

- **`Shatapushpa` is claimed twice.** `dravya.fennel-seed` holds it; canon calls
  dill `Shatapushpa Shaka`; `dravya.dill` holds `Shatahva`. Classical usage
  genuinely splits, and fennel-seed already ships. **Do not reassign.** Add a
  `reviewNote` to both entries naming the conflict, and leave it for the vaidya.
- **`recipe.khajur-smoothie` carries `REVIEWER: banana+milk viruddha`.** Fixed
  decision 3 already answers this: viruddha warns, it does not block. Build the
  recipe, flag the combination, and supply the compliant variant exactly as the
  other viruddha-flagged modern dishes do. This is not a new policy question.
- **Two pre-existing duplicate pairs are out of scope here but must be
  recorded**: `dravya.lotus-seed` vs `dravya.makhana` (both Makhanna), and
  `dravya.round-melon-tinda-punjabi` vs `dravya.tinda` — the latter is what
  produced the `D073` IFCT collision in NUT-1 §2. Open an issue; do not merge
  them inside this packet.
- **Alias bug:** `dravya.methi-leaves` carries `kasuri methi (dried)` while
  `dravya.fenugreek-leaf-dry` *is* Kasuri Methi. Fresh leaf is reachable by a
  dried-leaf name. Fix in this packet — it is one line and it is the same
  identity-collision class.
