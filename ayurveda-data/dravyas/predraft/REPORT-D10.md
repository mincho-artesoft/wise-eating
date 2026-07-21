# TASK D10 Dravya Predraft Report

## Output

Produced **525 mechanical predrafts** in 21 files (`predraft-10.json` through
`predraft-30.json`), with 25 items in every file. Every item contains identity
fields, canon hints where supplied, USDA bindings or a search note, serving
sizes, and `_facetsPending: true`. No Ayurvedic facets were authored outside
the copied `canonHints.vpk`, `canonHints.virya`, and `canonHints.note` values.

Category totals: `animal` 30, `beverage` 33, `dairy` 17, `dry-fruit-nut` 13, `fermented` 12, `fruit` 44, `grain` 23, `leafy-green` 20, `legume` 29, `medicinal` 43, `oil-fat` 11, `preparation` 59, `regional` 32, `salt-mineral` 9, `seed` 9, `spice` 61, `sweetener` 10, `vegetable` 70.

## USDA match rates

| File | Exact | Near | None | Any match |
| --- | ---: | ---: | ---: | ---: |
| predraft-10 | 13 (52%) | 7 (28%) | 5 (20%) | 20 (80%) |
| predraft-11 | 2 (8%) | 3 (12%) | 20 (80%) | 5 (20%) |
| predraft-12 | 1 (4%) | 1 (4%) | 23 (92%) | 2 (8%) |
| predraft-13 | 2 (8%) | 7 (28%) | 16 (64%) | 9 (36%) |
| predraft-14 | 6 (24%) | 5 (20%) | 14 (56%) | 11 (44%) |
| predraft-15 | 2 (8%) | 10 (40%) | 13 (52%) | 12 (48%) |
| predraft-16 | 4 (16%) | 9 (36%) | 12 (48%) | 13 (52%) |
| predraft-17 | 3 (12%) | 7 (28%) | 15 (60%) | 10 (40%) |
| predraft-18 | 1 (4%) | 1 (4%) | 23 (92%) | 2 (8%) |
| predraft-19 | 0 (0%) | 0 (0%) | 25 (100%) | 0 (0%) |
| predraft-20 | 4 (16%) | 0 (0%) | 21 (84%) | 4 (16%) |
| predraft-21 | 0 (0%) | 0 (0%) | 25 (100%) | 0 (0%) |
| predraft-22 | 1 (4%) | 1 (4%) | 23 (92%) | 2 (8%) |
| predraft-23 | 0 (0%) | 2 (8%) | 23 (92%) | 2 (8%) |
| predraft-24 | 4 (16%) | 11 (44%) | 10 (40%) | 15 (60%) |
| predraft-25 | 10 (40%) | 3 (12%) | 12 (48%) | 13 (52%) |
| predraft-26 | 7 (28%) | 3 (12%) | 15 (60%) | 10 (40%) |
| predraft-27 | 3 (12%) | 6 (24%) | 16 (64%) | 9 (36%) |
| predraft-28 | 6 (24%) | 4 (16%) | 15 (60%) | 10 (40%) |
| predraft-29 | 9 (36%) | 3 (12%) | 13 (52%) | 12 (48%) |
| predraft-30 | 5 (20%) | 3 (12%) | 17 (68%) | 8 (32%) |
| **Total** | **83 (15.8%)** | **86 (16.4%)** | **356 (67.8%)** | **169 (32.2%)** |

Every bound `fdcId` was resolved from `/tmp/pre`, and `check.py` compared the
stored `ZNAME` with the predraft name byte-for-byte. Specialized foods were
left unbound when the store offered no defensible same-food row; no lookalike
or merely similarly named food was forced into a binding.

## Authored-overlap handling

Skipped **108 exact-ID overlaps** with the 210 authored dravyas.
The following 23 non-identical IDs were also skipped after identity/name review:

| Canon/worklist ID | Authored ID | Reason |
| --- | --- | --- |
| `dravya.long-pepper` | `dravya.pippali` | alias/name match |
| `dravya.fennel` | `dravya.fennel-seed` | alias/name match |
| `dravya.fenugreek` | `dravya.fenugreek-seed` | alias/name match |
| `dravya.cardamom-green` | `dravya.cardamom` | alias/name match |
| `dravya.cardamom-black` | `dravya.black-cardamom` | alias/name match |
| `dravya.holy-basil` | `dravya.tulsi` | alias/name match |
| `dravya.coriander-leaf` | `dravya.cilantro` | alias/name match |
| `dravya.dry-mango-powder` | `dravya.amchur` | alias/name match |
| `dravya.rice-brown` | `dravya.brown-rice` | alias/name match |
| `dravya.wheat-whole` | `dravya.whole-wheat` | alias/name match |
| `dravya.finger-millet` | `dravya.ragi` | alias/name match |
| `dravya.pearl-millet` | `dravya.bajra` | alias/name match |
| `dravya.sorghum` | `dravya.jowar` | alias/name match |
| `dravya.amaranth` | `dravya.amaranth-grain` | alias/name match |
| `dravya.ghee-plain` | `dravya.ghee` | alias/name match |
| `dravya.kidney-bean` | `dravya.rajma` | normalized name match |
| `dravya.taro-root` | `dravya.taro` | normalized name match |
| `dravya.drumstick-pod` | `dravya.drumstick` | alias/name match |
| `dravya.asparagus-culinary` | `dravya.asparagus` | normalized name match |
| `dravya.dry-apricot` | `dravya.dried-apricot` | alias/name match |
| `dravya.prune` | `dravya.prunes` | alias/name match |
| `dravya.chia-seed` | `dravya.chia` | alias/name match |
| `dravya.rock-sugar` | `dravya.mishri` | normalized name match |

Potentially distinct form/alias pairs retained for director review rather than
silently merged:

- `dravya.garlic-fresh-bulb` / authored `dravya.garlic` — canon explicitly narrows the new ID to the fresh bulb form.
- `dravya.french-bean` / authored `dravya.green-beans` — canon uses the French-bean identity; cultivar scope may overlap.
- `dravya.red-radish` / authored `dravya.radish` — color-specific canon form versus the generic authored record.
- `dravya.fenugreek-greens` / authored `dravya.methi-leaves` — separate canon ID but likely overlapping fresh-leaf identity.
- `dravya.dill-greens` / authored `dravya.dill` — separate canon greens form versus the authored culinary herb.
- `dravya.plain-chaas` / authored `dravya.buttermilk` — canon specifies the plain chaas product form.
- `dravya.khus-root` / `dravya.vetiver` — two unauthored canon IDs normalize to the same English name, “Vetiver root”; `check.py` reports this as a warning.

Canon exception copied without invention: `dravya.langsat` is named
`Langsat? — placeholder REJECTED` in canon-08, whose note directs a reviewer to
delete/replace it. The predraft preserves that identity and note for director
resolution rather than selecting a new regional fruit.

## Unmatched items

**356 items** have `usda: []`. Each record contains a `usdaNote`
listing the English, Hindi, and Sanskrit terms searched when available.

### predraft-10 (5)

- `dravya.rohu` — Rohu (freshwater fish)
- `dravya.catla` — Catla
- `dravya.hilsa` — Hilsa
- `dravya.pomfret` — Pomfret
- `dravya.seer-fish` — Seer fish (surmai)

### predraft-11 (20)

- `dravya.kitchari-mung-rice` — Mung and rice kitchari
- `dravya.kitchari-tridoshic` — Tridoshic kitchari
- `dravya.ghee-cultured` — Cultured ghee
- `dravya.ghee-spiced` — Spiced ghee
- `dravya.ccf-tea` — Cumin-coriander-fennel tea
- `dravya.golden-milk` — Golden milk
- `dravya.lassi-sweet` — Sweet lassi
- `dravya.lassi-digestive` — Cumin lassi
- `dravya.panchamrita` — Panchamrita
- `dravya.dal-tadka-mung` — Mung dal tadka
- `dravya.pongal-ven` — Ven pongal
- `dravya.pongal-sweet` — Sweet pongal
- `dravya.khichadi-vegetable` — Vegetable khichadi
- `dravya.halwa-carrot` — Carrot halwa
- `dravya.payasam-mung` — Mung payasam
- `dravya.chyawanprash` — Chyawanprash
- `dravya.sattu-drink` — Sattu drink
- `dravya.barley-water` — Barley water
- `dravya.rice-gruel` — Rice gruel
- `dravya.roti` — Roti (chapati)

### predraft-12 (23)

- `dravya.amla-dry` — Dried amla
- `dravya.haritaki` — Haritaki (chebulic myrobalan)
- `dravya.bibhitaki` — Bibhitaki (belleric myrobalan)
- `dravya.triphala-churna` — Triphala
- `dravya.shatavari-powder` — Shatavari root powder
- `dravya.guduchi` — Guduchi (giloy) stem
- `dravya.giloy-satva` — Giloy satva (starch extract)
- `dravya.brahmi` — Brahmi (bacopa)
- `dravya.gotu-kola` — Gotu kola
- `dravya.shankhpushpi` — Shankhpushpi
- `dravya.vidari-kanda` — Vidari kanda
- `dravya.safed-musli` — Safed musli
- `dravya.kaunch-beej` — Mucuna seed
- `dravya.gokshura` — Gokshura (tribulus)
- `dravya.punarnava-leaf` — Punarnava leaf
- `dravya.moringa-leaf-dry` — Moringa leaf powder
- `dravya.neem-leaf` — Neem leaf
- `dravya.neem-flower` — Neem flower
- `dravya.aloe-vera-pulp` — Aloe vera pulp
- `dravya.psyllium-husk` — Psyllium husk
- `dravya.wheatgrass` — Wheatgrass
- `dravya.chirata` — Chirata
- `dravya.kalmegh` — Kalmegh (andrographis)

### predraft-13 (16)

- `dravya.sponge-gourd` — Sponge gourd (gilki)
- `dravya.snake-gourd` — Snake gourd
- `dravya.pointed-gourd` — Pointed gourd (parwal)
- `dravya.ivy-gourd` — Ivy gourd (tindora)
- `dravya.tinda` — Round gourd (tinda)
- `dravya.pumpkin-red` — Red pumpkin (kaddu)
- `dravya.long-cucumber` — Long cucumber (kakri)
- `dravya.spine-gourd` — Spine gourd (kantola)
- `dravya.purple-yam` — Purple yam (kand)
- `dravya.elephant-foot-yam` — Elephant foot yam (suran)
- `dravya.white-radish` — White radish (mooli)
- `dravya.red-radish` — Red radish
- `dravya.fresh-water-chestnut` — Fresh water chestnut (singhara)
- `dravya.raw-papaya` — Raw papaya
- `dravya.french-bean` — French bean
- `dravya.cluster-bean` — Cluster bean (gawar)

### predraft-14 (14)

- `dravya.broad-bean` — Broad bean pod (sem)
- `dravya.flat-bean` — Flat bean (papdi)
- `dravya.baby-corn` — Baby corn
- `dravya.banana-flower` — Banana flower
- `dravya.banana-stem` — Banana stem
- `dravya.jackfruit-seed` — Jackfruit seed
- `dravya.kachnar-buds` — Kachnar buds
- `dravya.moringa-flower` — Moringa flower
- `dravya.ash-gourd-strips` — Ash gourd (tender, for sabzi)
- `dravya.ginger-tender` — Tender ginger (sabzi/pickle)
- `dravya.yam-lesser` — Lesser yam
- `dravya.colocasia-stem` — Colocasia stem
- `dravya.pumpkin-flower` — Pumpkin flower
- `dravya.agathi-flower` — Agathi flower

### predraft-15 (13)

- `dravya.sweet-lime` — Sweet lime (mosambi)
- `dravya.citron` — Citron (bijora)
- `dravya.amla-fresh` — Fresh amla
- `dravya.bael-fruit` — Bael fruit
- `dravya.jamun` — Jamun (java plum)
- `dravya.ber` — Indian jujube (ber)
- `dravya.karonda-ripe` — Ripe karonda
- `dravya.phalsa` — Phalsa
- `dravya.ripe-jackfruit` — Ripe jackfruit
- `dravya.ramphal` — Ramphal (bullock's heart)
- `dravya.sapota` — Sapota (chikoo)
- `dravya.sarda-melon` — Sarda melon
- `dravya.tender-coconut-flesh` — Tender coconut flesh

### predraft-16 (12)

- `dravya.water-apple` — Water apple (jamrul)
- `dravya.wood-apple` — Wood apple (kaith)
- `dravya.tadgola` — Ice apple (tadgola/nungu)
- `dravya.sugarcane-stick` — Sugarcane (chewing)
- `dravya.gooseberry-star` — Star gooseberry (harfarauri)
- `dravya.rose-apple` — Rose apple (gulab jamun phal)
- `dravya.lasora` — Lasora (gunda berry, fresh)
- `dravya.ambarella` — Ambarella (amtekai)
- `dravya.elephant-apple` — Elephant apple (ou-tenga)
- `dravya.langsat` — Langsat? — placeholder REJECTED
- `dravya.chironji` — Chironji (charoli)
- `dravya.makhana` — Fox nut (makhana)

### predraft-17 (15)

- `dravya.rice-red` — Red rice
- `dravya.rice-flattened` — Flattened rice
- `dravya.foxtail-millet` — Foxtail millet
- `dravya.little-millet` — Little millet
- `dravya.kodo-millet` — Kodo millet
- `dravya.barnyard-millet` — Barnyard millet
- `dravya.water-chestnut-flour` — Water chestnut flour
- `dravya.maize` — Maize (dry corn)
- `dravya.navara-rice` — Navara rice
- `dravya.black-rice` — Black rice
- `dravya.seeraga-samba-rice` — Seeraga samba rice
- `dravya.govindbhog-rice` — Govindbhog rice
- `dravya.emmer-wheat` — Emmer wheat (khapli)
- `dravya.browntop-millet` — Browntop millet
- `dravya.vermicelli` — Vermicelli (seviyan)

### predraft-18 (23)

- `dravya.ker-berry` — Ker (desert caper berry)
- `dravya.sangri` — Sangri (desert bean)
- `dravya.gunda-dry` — Gunda (dried lasora)
- `dravya.mahua-flower-fresh` — Mahua flower (fresh)
- `dravya.mahua-flower-dry` — Mahua flower (dried)
- `dravya.bhatt-soybean` — Black soybean (bhatt)
- `dravya.buransh-juice` — Rhododendron juice (buransh)
- `dravya.stinging-nettle` — Stinging nettle greens (sisnu)
- `dravya.fiddlehead-fern` — Fiddlehead fern (lingda)
- `dravya.taro-stem-regional` — Taro stem (regional curry)
- `dravya.nendran-banana` — Nendran banana
- `dravya.joha-rice` — Joha rice
- `dravya.gondhoraj-lime` — Gondhoraj lime
- `dravya.kaji-nemu` — Kaji nemu (Assam lemon)
- `dravya.thekera` — Thekera (Assam garcinia)
- `dravya.kachampuli` — Kachampuli vinegar
- `dravya.sugarcane-vinegar` — Sugarcane vinegar (sirka)
- `dravya.coconut-vinegar` — Coconut vinegar
- `dravya.jamun-vinegar` — Jamun vinegar
- `dravya.betel-nut` — Betel nut (supari)
- `dravya.catechu` — Catechu (katha)
- `dravya.mukhwas` — Mukhwas (fennel mouth-freshener)
- `dravya.tender-tamarind-leaf` — Tender tamarind leaf

### predraft-19 (25)

- `dravya.chhurpi` — Chhurpi (Himalayan hard cheese)
- `dravya.yak-milk` — Yak milk
- `dravya.yak-butter` — Yak butter
- `dravya.kharvas` — Kharvas (colostrum pudding)
- `dravya.panta-bhat` — Panta bhat
- `dravya.singhara-atta-halwa` — Singhara flour halwa
- `dravya.til-oil-pickle` — Gingelly oil pickle base
- `dravya.warm-water` — Warm boiled water
- `dravya.copper-water` — Copper-stored water
- `dravya.sugarcane-juice` — Sugarcane juice
- `dravya.sweet-nimbu-pani` — Sweet lime water
- `dravya.salted-nimbu-pani` — Salted lime water
- `dravya.jaljeera` — Jaljeera
- `dravya.aam-panna` — Aam panna
- `dravya.bel-sherbet` — Bael sherbet
- `dravya.kokum-sherbet` — Kokum sherbet
- `dravya.khus-sherbet` — Khus sherbet
- `dravya.rose-sherbet` — Rose sherbet
- `dravya.gond-katira-drink` — Gond katira cooler
- `dravya.thandai` — Thandai
- `dravya.badam-milk` — Badam milk
- `dravya.rose-milk` — Rose milk
- `dravya.masala-chai` — Masala chai
- `dravya.tulsi-tea` — Tulsi tea
- `dravya.lemongrass-tea` — Lemongrass tea

### predraft-20 (21)

- `dravya.filter-coffee` — South Indian filter coffee
- `dravya.mosambi-juice` — Sweet lime juice
- `dravya.ash-gourd-juice` — Ash gourd juice
- `dravya.bottle-gourd-juice` — Bottle gourd juice
- `dravya.herbal-kadha` — Herbal kadha
- `dravya.saunf-water` — Fennel water
- `dravya.jeera-water` — Cumin water
- `dravya.ajwain-water` — Ajwain water
- `dravya.methi-water` — Fenugreek water
- `dravya.dhania-water` — Coriander seed water
- `dravya.ragi-malt` — Ragi malt (beverage)
- `dravya.black-carrot-kanji` — Black carrot kanji
- `dravya.pakhala` — Fermented rice water-rice (pakhala)
- `dravya.ambali` — Fermented ragi porridge (ambali)
- `dravya.gundruk` — Gundruk (fermented greens)
- `dravya.sinki` — Sinki (fermented radish)
- `dravya.soibum` — Fermented bamboo shoot (soibum)
- `dravya.kinema` — Kinema (fermented soybean)
- `dravya.hawaijar` — Hawaijar (fermented soybean)
- `dravya.neera` — Neera (fresh palm sap)
- `dravya.khalpi` — Khalpi (fermented cucumber)

### predraft-21 (25)

- `dravya.idli-dosa-batter` — Fermented idli-dosa batter
- `dravya.fermented-rice-kanji` — Rice kanji (fermented gruel)
- `dravya.mamsa-rasa` — Meat broth (mamsa rasa)
- `dravya.goat-liver` — Goat liver
- `dravya.paya-soup` — Trotters soup (paya)
- `dravya.keema` — Minced mutton (keema)
- `dravya.egg-bhurji` — Egg bhurji
- `dravya.paratha-plain` — Plain paratha
- `dravya.puri` — Puri
- `dravya.jowar-bhakri` — Jowar bhakri
- `dravya.thepla` — Methi thepla
- `dravya.khakhra` — Khakhra
- `dravya.sambar` — Sambar
- `dravya.rasam` — Rasam
- `dravya.kadhi` — Kadhi
- `dravya.dal-fry-toor` — Dal fry (toor)
- `dravya.curd-rice` — Curd rice
- `dravya.lemon-rice` — Lemon rice
- `dravya.tamarind-rice` — Tamarind rice (puliyodarai)
- `dravya.coconut-rice` — Coconut rice
- `dravya.veg-pulao` — Vegetable pulao
- `dravya.sabudana-khichdi` — Sabudana khichdi
- `dravya.kanda-poha` — Kanda poha
- `dravya.dhokla` — Dhokla
- `dravya.uttapam` — Uttapam

### predraft-22 (23)

- `dravya.medu-vada` — Medu vada
- `dravya.besan-pakora` — Besan pakora
- `dravya.sooji-halwa` — Sooji halwa (sheera)
- `dravya.moong-dal-halwa` — Moong dal halwa
- `dravya.besan-ladoo` — Besan ladoo
- `dravya.til-ladoo` — Til-gud ladoo
- `dravya.peanut-chikki` — Peanut chikki
- `dravya.steamed-modak` — Steamed modak
- `dravya.puran-poli` — Puran poli
- `dravya.shrikhand` — Shrikhand
- `dravya.basundi` — Basundi
- `dravya.rabri` — Rabri
- `dravya.coconut-chutney` — Coconut chutney
- `dravya.mint-chutney` — Mint chutney
- `dravya.mango-pickle` — Mango pickle (achar)
- `dravya.urad-papad` — Urad papad
- `dravya.musta` — Nutgrass tuber
- `dravya.gulkand` — Rose petal preserve
- `dravya.bael-leaf` — Bael leaf
- `dravya.jamun-seed-powder` — Jamun seed powder
- `dravya.shilajit` — Shilajit
- `dravya.amla-juice` — Amla juice
- `dravya.fenugreek-sprouted` — Sprouted fenugreek

### predraft-23 (23)

- `dravya.greater-galangal` — Greater galangal
- `dravya.anantmool` — Indian sarsaparilla
- `dravya.khus-root` — Vetiver root
- `dravya.amla-murabba` — Amla murabba
- `dravya.haritaki-murabba` — Haritaki murabba
- `dravya.bael-murabba` — Bael murabba
- `dravya.ginger-murabba` — Ginger murabba
- `dravya.petha-murabba` — Ash gourd murabba (petha)
- `dravya.green-peas-pod` — Green peas in pod (fresh sabzi)
- `dravya.mustard-pods` — Tender mustard pods
- `dravya.gherkin` — Indian gherkin (kundru-dondakaya kin)
- `dravya.round-melon-tinda-punjabi` — Punjabi tinda (apple gourd)
- `dravya.wild-brinjal` — Wild brinjal (kantakari class)
- `dravya.tender-tamarind-pod` — Tender tamarind pod
- `dravya.papdi-lilva` — Fresh hyacinth beans (lilva)
- `dravya.tender-cashew-fruit` — Cashew apple
- `dravya.sword-bean` — Sword bean
- `dravya.ash-plantain` — Ash plantain
- `dravya.karonda-raw` — Raw karonda (pickle berry)
- `dravya.jimikand-pink` — Pink elephant yam
- `dravya.ash-gourd-juice-flesh` — Ash gourd (juicing flesh)
- `dravya.tender-bamboo-pickled` — Tender bamboo (fresh, unfermented)
- `dravya.water-lily-stem` — Water lily stem

### predraft-24 (10)

- `dravya.lotus-seed-fresh` — Fresh lotus seed
- `dravya.turnip-greens-root` — Baby turnip with greens
- `dravya.parwal-sweet` — Sweet parwal variant
- `dravya.urad-dal` — Split black gram
- `dravya.urad-whole` — Whole black gram
- `dravya.moth-bean` — Moth bean
- `dravya.horse-gram` — Horse gram
- `dravya.sprouted-chana` — Sprouted black chickpea
- `dravya.sattu-flour` — Roasted gram flour (sattu)
- `dravya.roasted-chana` — Roasted chana (bhuna)

### predraft-25 (12)

- `dravya.rice-bean` — Rice bean
- `dravya.field-bean` — Field bean (avarekalu)
- `dravya.red-cowpea` — Red cowpea
- `dravya.urad-flour` — Urad flour
- `dravya.kokum` — Kokum rind
- `dravya.garcinia` — Garcinia fruit
- `dravya.trikatu` — Trikatu spice blend
- `dravya.chaturjata` — Chaturjata spice blend
- `dravya.sambar-podi` — Sambar spice blend
- `dravya.rasam-podi` — Rasam spice blend
- `dravya.chai-masala` — Chai spice blend
- `dravya.ginger-pickled` — Pickled ginger

### predraft-26 (15)

- `dravya.turmeric-black` — Black turmeric
- `dravya.vetiver` — Vetiver root
- `dravya.camphor-edible` — Edible camphor
- `dravya.betel-leaf` — Betel leaf
- `dravya.sesame-spice-blend` — Sesame chutney spice blend
- `dravya.stone-flower` — Stone flower
- `dravya.nagkesar` — Cobra saffron
- `dravya.marathi-moggu` — Kapok bud
- `dravya.mango-ginger` — Mango ginger
- `dravya.kachri-powder` — Wild melon powder
- `dravya.alkanet-root` — Alkanet root
- `dravya.wild-mustard` — Wild mustard
- `dravya.wild-celery-seed` — Wild celery seed
- `dravya.dhana-jeera-powder` — Coriander-cumin powder
- `dravya.chaat-masala` — Chaat masala

### predraft-27 (16)

- `dravya.byadgi-chili` — Byadgi chili
- `dravya.pippali-root` — Long pepper root
- `dravya.cassia-bark` — Cassia bark
- `dravya.bay-leaf-mediterranean` — Bay leaf (Mediterranean)
- `dravya.idli-podi` — Idli podi (gunpowder)
- `dravya.achar-masala` — Pickle masala
- `dravya.chaas-masala` — Buttermilk masala
- `dravya.thandai-masala` — Thandai masala
- `dravya.hingvastak-churna` — Hingvastak churna
- `dravya.red-amaranth-greens` — Red amaranth greens (lal chaulai)
- `dravya.green-amaranth-greens` — Green amaranth greens
- `dravya.bathua` — Bathua (chenopodium)
- `dravya.colocasia-leaf` — Colocasia leaf (arbi patta)
- `dravya.drumstick-leaf` — Drumstick leaf (fresh)
- `dravya.gongura` — Gongura (sorrel)
- `dravya.water-spinach` — Water spinach (kalmi)

### predraft-28 (15)

- `dravya.radish-greens` — Radish greens
- `dravya.spring-garlic-greens` — Spring garlic greens
- `dravya.haak` — Haak (Kashmiri collard)
- `dravya.agathi-leaf` — Agathi leaf
- `dravya.ponnanganni` — Dwarf copperleaf (ponnanganni)
- `dravya.manathakkali-greens` — Black nightshade greens
- `dravya.pumpkin-tendril` — Pumpkin tendrils and leaves
- `dravya.chakramarda-greens` — Chakvad greens (cassia tora)
- `dravya.soft-dates` — Soft dates (khajur)
- `dravya.dried-water-chestnut` — Dried water chestnut
- `dravya.kamal-gatta-dry` — Dried lotus seed (kamal gatta)
- `dravya.panchmeva` — Panchmeva (five dry fruits)
- `dravya.sabja-seed` — Sweet basil seed (sabja)
- `dravya.muskmelon-seed` — Muskmelon seed
- `dravya.cucumber-seed` — Cucumber seed (magaz)

### predraft-29 (13)

- `dravya.niger-seed` — Niger seed (ramtil)
- `dravya.lotus-seed-popped` — Popped lotus seed
- `dravya.basil-holy-seed` — Tulsi seed
- `dravya.camel-milk` — Camel milk
- `dravya.khoya` — Khoya (mawa)
- `dravya.chhena` — Chhena (fresh curd cheese)
- `dravya.hung-curd` — Hung curd (chakka)
- `dravya.colostrum-milk` — Colostrum milk (kharvas base)
- `dravya.buffalo-ghee` — Buffalo ghee
- `dravya.cultured-butter` — Cultured butter
- `dravya.skimmed-milk` — Skimmed milk
- `dravya.full-cream-milk` — Full-cream milk (packaged)
- `dravya.castor-oil` — Castor oil (dietary)

### predraft-30 (17)

- `dravya.niger-oil` — Niger seed oil
- `dravya.mahua-oil` — Mahua oil
- `dravya.vanaspati` — Vanaspati (hydrogenated)
- `dravya.cane-jaggery` — Cane jaggery (gud)
- `dravya.date-palm-jaggery` — Date palm jaggery (nolen gur)
- `dravya.palmyra-jaggery` — Palmyra jaggery (tala gud)
- `dravya.boora` — Boora sugar
- `dravya.powdered-jaggery` — Powdered jaggery (shakkar)
- `dravya.coconut-sugar` — Coconut sugar
- `dravya.date-syrup` — Date syrup
- `dravya.honey-aged` — Aged honey
- `dravya.sambhar-salt` — Sambhar lake salt
- `dravya.vida-salt` — Vida salt
- `dravya.edible-lime` — Edible lime (chuna)
- `dravya.acacia-gum` — Edible acacia gum (gond)
- `dravya.tragacanth-gum` — Tragacanth gum (gond katira)
- `dravya.silver-leaf` — Edible silver leaf (vark)

## Final checker output

```text
Store rows loaded: 12601
Authored ids loaded: 210
predraft-10.json: items=25 exact=13 near=7 none=5
predraft-11.json: items=25 exact=2 near=3 none=20
predraft-12.json: items=25 exact=1 near=1 none=23
predraft-13.json: items=25 exact=2 near=7 none=16
predraft-14.json: items=25 exact=6 near=5 none=14
predraft-15.json: items=25 exact=2 near=10 none=13
predraft-16.json: items=25 exact=4 near=9 none=12
predraft-17.json: items=25 exact=3 near=7 none=15
predraft-18.json: items=25 exact=1 near=1 none=23
predraft-19.json: items=25 exact=0 near=0 none=25
predraft-20.json: items=25 exact=4 near=0 none=21
predraft-21.json: items=25 exact=0 near=0 none=25
predraft-22.json: items=25 exact=1 near=1 none=23
predraft-23.json: items=25 exact=0 near=2 none=23
predraft-24.json: items=25 exact=4 near=11 none=10
predraft-25.json: items=25 exact=10 near=3 none=12
predraft-26.json: items=25 exact=7 near=3 none=15
predraft-27.json: items=25 exact=3 near=6 none=16
predraft-28.json: items=25 exact=6 near=4 none=15
predraft-29.json: items=25 exact=9 near=3 none=13
predraft-30.json: items=25 exact=5 near=3 none=17
Predraft files checked: 21
Predraft items checked: 525
Warnings: 1
WARNING: predraft-26.json/dravya.vetiver: normalized predraft name also used by dravya.khus-root (retain as canon alias ambiguity for report)
Errors: 0
All predraft checks passed.
```

No commits were pushed.


## Director verification addendum (Fable 5)
- Patched 10 missed USDA bindings (roti, triphala, pumpkin flower, fiddlehead, puri, sambar, stone flower, Mediterranean bay leaf, gongura~sorrel, ber~jujube).
- Removed dravya.maize as duplicate of authored dravya.corn (batch-03). Predraft total: 524.
- Residual false-negative rate after patch estimated <1%. APPROVED.
