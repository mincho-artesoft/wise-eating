# D6 implementation report

## Summary

Implemented the deterministic Ayurveda seed pipeline and the additive SwiftData integration described by `DESIGN-D6.md`. The generated bundle contains 714 dravyas, 1,500 recipes, 336 links, 383 placeholders, and 331 primary-food assignments. The app-side insert pass performs the reserved-band check before writes, inserts in batches of 200 in the prescribed order, resolves ingredient foods from one `FoodItem` fetch, and fails open through `SeedManager`.

No source dravya, recipe, `FoodItem`, or other out-of-scope file was edited. No push was performed.

## build_seed output block

```text
build_seed summary
dravyas: 714
recipes: 1500
links: 336
placeholders: 383
primaries: 331
unresolved ingredients: 0
engineExcluded: 2
```

Both deterministic runs wrote SHA-256 `33bdd37da9ab40f61af66d7268db64e48871139ff244eb646f717d7ef189c19d`.

## Contested fdcIds

| fdcId | winner | tier | losers |
|---:|---|---|---|
| 5361 | dravya.tamarind | exact | dravya.tamarind-ripe |
| 5703 | dravya.golden-raisin | exact | dravya.raisins |
| 5729 | dravya.dates | exact | dravya.dry-dates, dravya.fresh-dates |
| 5749 | dravya.plantain-green | exact | dravya.raw-banana |
| 5915 | dravya.amaranth-leaves | exact | dravya.red-amaranth-greens |
| 5946 | dravya.drumstick-leaf | exact | dravya.drumstick |
| 6121 | dravya.lotus-seed | exact | dravya.kamal-gatta-dry |
| 6372 | dravya.white-rice | exact | dravya.rice-white-basmati |
| 6388 | dravya.whole-wheat | exact | dravya.whole-wheat-flour |
| 6590 | dravya.pomegranate | exact | dravya.pomegranate-sour, dravya.pomegranate-sweet |
| 6684 | dravya.eggplant | exact | dravya.long-brinjal, dravya.small-brinjal |
| 6686 | dravya.garlic | exact | dravya.garlic-fresh-bulb |
| 6707 | dravya.button-mushroom | exact | dravya.white-mushroom |
| 7075 | dravya.honey | exact | dravya.honey-aged |
| 7082 | dravya.white-sugar | exact | dravya.mishri |
| 7123 | dravya.proso-millet | exact | dravya.bajra, dravya.ragi |
| 7297 | dravya.mango-ripe | exact | dravya.alphonso-mango, dravya.ripe-mango |
| 7313 | dravya.papaya | exact | dravya.ripe-papaya |
| 7344 | dravya.mung-sprouts | exact | dravya.sprouted-mung |
| 7375 | dravya.celery | exact | dravya.celery-stalk |
| 7387 | dravya.onion | exact | dravya.red-onion, dravya.white-onion |
| 7495 | dravya.red-bell-pepper | exact | dravya.red-yellow-capsicum |
| 7557 | dravya.desiccated-coconut | exact | dravya.dry-coconut |
| 7736 | dravya.green-peas | exact | dravya.green-pea-fresh |
| 7744 | dravya.bell-pepper | exact | dravya.green-capsicum |
| 8142 | dravya.bay-leaf-mediterranean | exact | dravya.bay-leaf |
| 8154 | dravya.mustard-seed-black | near | dravya.mustard-seed-yellow |
| 8262 | dravya.broiler-chicken | exact | dravya.country-chicken |
| 8484 | dravya.chicken-egg | near | dravya.desi-egg |
| 9427 | dravya.brown-lentil | exact | dravya.lentil-brown |
| 9435 | dravya.peas-dry | near | dravya.white-peas |
| 9437 | dravya.peanut | exact | dravya.peanut-raw |
| 9443 | dravya.toor-dal | exact | dravya.whole-toor |
| 10547 | dravya.chickpea | exact | dravya.chana-dal, dravya.chickpea-black, dravya.chickpea-white |
| 10677 | dravya.banana-ripe | exact | dravya.elaichi-banana, dravya.red-banana, dravya.ripe-banana |
| 10962 | dravya.mung-bean | exact | dravya.mung-dal-split, dravya.mung-whole |
| 10990 | dravya.masoor | exact | dravya.masoor-dal |
| 11330 | dravya.grapes | exact | dravya.black-grapes, dravya.green-grapes |
| 11334 | dravya.jackfruit | exact | dravya.raw-jackfruit |
| 12368 | dravya.fenugreek-leaf-dry | near | dravya.methi-leaves |

## Placeholder dravyas

Count: 383.

```text
dravya.aam-panna
dravya.acacia-gum
dravya.achar-masala
dravya.agathi-flower
dravya.agathi-leaf
dravya.ajwain-water
dravya.alkanet-root
dravya.aloe-vera-pulp
dravya.alphonso-mango
dravya.ambali
dravya.ambarella
dravya.amla-dry
dravya.amla-fresh
dravya.amla-juice
dravya.amla-murabba
dravya.anantmool
dravya.ash-gourd-juice
dravya.ash-gourd-juice-flesh
dravya.ash-gourd-strips
dravya.ash-plantain
dravya.baby-corn
dravya.badam-milk
dravya.bael-fruit
dravya.bael-leaf
dravya.bael-murabba
dravya.bajra
dravya.banana-flower
dravya.banana-stem
dravya.barley-water
dravya.barnyard-millet
dravya.basil-holy-seed
dravya.basundi
dravya.bathua
dravya.bay-leaf
dravya.bel-sherbet
dravya.besan-ladoo
dravya.besan-pakora
dravya.betel-leaf
dravya.betel-nut
dravya.bhatt-soybean
dravya.bibhitaki
dravya.black-carrot-kanji
dravya.black-grapes
dravya.black-rice
dravya.boora
dravya.bottle-gourd-juice
dravya.brahmi
dravya.broad-bean
dravya.browntop-millet
dravya.buffalo-ghee
dravya.buransh-juice
dravya.byadgi-chili
dravya.camel-milk
dravya.camphor-edible
dravya.cassia-bark
dravya.castor-oil
dravya.catechu
dravya.catla
dravya.ccf-tea
dravya.celery-stalk
dravya.chaas-masala
dravya.chaat-masala
dravya.chai-masala
dravya.chakramarda-greens
dravya.chana-dal
dravya.chaturjata
dravya.chhena
dravya.chhurpi
dravya.chickpea-black
dravya.chickpea-white
dravya.chirata
dravya.chironji
dravya.chyawanprash
dravya.citron
dravya.cluster-bean
dravya.coconut-chutney
dravya.coconut-rice
dravya.coconut-sugar
dravya.coconut-vinegar
dravya.colocasia-leaf
dravya.colocasia-stem
dravya.colostrum-milk
dravya.copper-water
dravya.country-chicken
dravya.cucumber-seed
dravya.curd-rice
dravya.dal-fry-toor
dravya.dal-tadka-mung
dravya.date-palm-jaggery
dravya.date-syrup
dravya.desi-egg
dravya.dhana-jeera-powder
dravya.dhania-water
dravya.dhokla
dravya.dried-water-chestnut
dravya.dry-coconut
dravya.dry-dates
dravya.edible-lime
dravya.egg-bhurji
dravya.elaichi-banana
dravya.elephant-apple
dravya.elephant-foot-yam
dravya.emmer-wheat
dravya.fenugreek-sprouted
dravya.fermented-rice-kanji
dravya.field-bean
dravya.filter-coffee
dravya.flat-bean
dravya.foxtail-millet
dravya.french-bean
dravya.fresh-dates
dravya.fresh-water-chestnut
dravya.full-cream-milk
dravya.garcinia
dravya.garlic-fresh-bulb
dravya.ghee-cultured
dravya.ghee-spiced
dravya.gherkin
dravya.giloy-satva
dravya.ginger-murabba
dravya.ginger-pickled
dravya.ginger-tender
dravya.goat-liver
dravya.gokshura
dravya.golden-milk
dravya.gond-katira-drink
dravya.gondhoraj-lime
dravya.gooseberry-star
dravya.gotu-kola
dravya.govindbhog-rice
dravya.greater-galangal
dravya.green-capsicum
dravya.green-grapes
dravya.green-pea-fresh
dravya.green-peas-pod
dravya.guduchi
dravya.gulkand
dravya.gunda-dry
dravya.gundruk
dravya.haak
dravya.halwa-carrot
dravya.haritaki
dravya.haritaki-murabba
dravya.hawaijar
dravya.herbal-kadha
dravya.hilsa
dravya.hingvastak-churna
dravya.honey-aged
dravya.horse-gram
dravya.hung-curd
dravya.idli-dosa-batter
dravya.idli-podi
dravya.ivy-gourd
dravya.jackfruit-seed
dravya.jaljeera
dravya.jamun
dravya.jamun-seed-powder
dravya.jamun-vinegar
dravya.jeera-water
dravya.jimikand-pink
dravya.joha-rice
dravya.jowar-bhakri
dravya.kachampuli
dravya.kachnar-buds
dravya.kachri-powder
dravya.kadhi
dravya.kaji-nemu
dravya.kalmegh
dravya.kamal-gatta-dry
dravya.kanda-poha
dravya.karonda-raw
dravya.karonda-ripe
dravya.kaunch-beej
dravya.keema
dravya.ker-berry
dravya.khakhra
dravya.khalpi
dravya.kharvas
dravya.khichadi-vegetable
dravya.khoya
dravya.khus-root
dravya.khus-sherbet
dravya.kinema
dravya.kitchari-mung-rice
dravya.kitchari-tridoshic
dravya.kodo-millet
dravya.kokum
dravya.kokum-sherbet
dravya.lasora
dravya.lassi-digestive
dravya.lassi-sweet
dravya.lemon-rice
dravya.lemongrass-tea
dravya.lentil-brown
dravya.little-millet
dravya.long-brinjal
dravya.long-cucumber
dravya.lotus-seed-fresh
dravya.mahua-flower-dry
dravya.mahua-flower-fresh
dravya.mahua-oil
dravya.makhana
dravya.mamsa-rasa
dravya.manathakkali-greens
dravya.mango-ginger
dravya.mango-pickle
dravya.marathi-moggu
dravya.masala-chai
dravya.masoor-dal
dravya.medu-vada
dravya.methi-water
dravya.mint-chutney
dravya.mishri
dravya.moong-dal-halwa
dravya.moringa-flower
dravya.moringa-leaf-dry
dravya.mosambi-juice
dravya.moth-bean
dravya.mukhwas
dravya.mung-dal-split
dravya.mung-whole
dravya.muskmelon-seed
dravya.musta
dravya.mustard-pods
dravya.mustard-seed-yellow
dravya.nagkesar
dravya.navara-rice
dravya.neem-flower
dravya.neem-leaf
dravya.neera
dravya.nendran-banana
dravya.niger-oil
dravya.niger-seed
dravya.pakhala
dravya.palmyra-jaggery
dravya.panchamrita
dravya.panchmeva
dravya.panta-bhat
dravya.papdi-lilva
dravya.paratha-plain
dravya.parwal-sweet
dravya.paya-soup
dravya.payasam-mung
dravya.peanut-chikki
dravya.peanut-raw
dravya.petha-murabba
dravya.phalsa
dravya.pippali-root
dravya.pointed-gourd
dravya.pomegranate-sour
dravya.pomegranate-sweet
dravya.pomfret
dravya.pongal-sweet
dravya.pongal-ven
dravya.ponnanganni
dravya.psyllium-husk
dravya.pumpkin-red
dravya.pumpkin-tendril
dravya.punarnava-leaf
dravya.puran-poli
dravya.purple-yam
dravya.rabri
dravya.radish-greens
dravya.ragi
dravya.ragi-malt
dravya.raisins
dravya.ramphal
dravya.rasam
dravya.rasam-podi
dravya.raw-banana
dravya.raw-jackfruit
dravya.raw-papaya
dravya.red-amaranth-greens
dravya.red-banana
dravya.red-cowpea
dravya.red-onion
dravya.red-radish
dravya.red-yellow-capsicum
dravya.rice-bean
dravya.rice-flattened
dravya.rice-gruel
dravya.rice-red
dravya.rice-white-basmati
dravya.ripe-banana
dravya.ripe-jackfruit
dravya.ripe-mango
dravya.ripe-papaya
dravya.roasted-chana
dravya.rohu
dravya.rose-apple
dravya.rose-milk
dravya.rose-sherbet
dravya.round-melon-tinda-punjabi
dravya.sabja-seed
dravya.sabudana-khichdi
dravya.safed-musli
dravya.salted-nimbu-pani
dravya.sambar-podi
dravya.sambhar-salt
dravya.sangri
dravya.sapota
dravya.sarda-melon
dravya.sattu-drink
dravya.sattu-flour
dravya.saunf-water
dravya.seer-fish
dravya.seeraga-samba-rice
dravya.sesame-spice-blend
dravya.shankhpushpi
dravya.shatavari-powder
dravya.shilajit
dravya.shrikhand
dravya.silver-leaf
dravya.singhara-atta-halwa
dravya.sinki
dravya.skimmed-milk
dravya.small-brinjal
dravya.snake-gourd
dravya.soibum
dravya.sooji-halwa
dravya.spine-gourd
dravya.sponge-gourd
dravya.spring-garlic-greens
dravya.sprouted-chana
dravya.sprouted-mung
dravya.steamed-modak
dravya.stinging-nettle
dravya.sugarcane-juice
dravya.sugarcane-stick
dravya.sugarcane-vinegar
dravya.sweet-lime
dravya.sweet-nimbu-pani
dravya.sword-bean
dravya.tadgola
dravya.tamarind-rice
dravya.tamarind-ripe
dravya.taro-stem-regional
dravya.tender-bamboo-pickled
dravya.tender-cashew-fruit
dravya.tender-coconut-flesh
dravya.tender-tamarind-leaf
dravya.tender-tamarind-pod
dravya.thandai
dravya.thandai-masala
dravya.thekera
dravya.thepla
dravya.til-ladoo
dravya.til-oil-pickle
dravya.tinda
dravya.tragacanth-gum
dravya.trikatu
dravya.tulsi-tea
dravya.turmeric-black
dravya.turnip-greens-root
dravya.urad-dal
dravya.urad-flour
dravya.urad-papad
dravya.urad-whole
dravya.uttapam
dravya.vanaspati
dravya.veg-pulao
dravya.vermicelli
dravya.vetiver
dravya.vidari-kanda
dravya.warm-water
dravya.water-apple
dravya.water-chestnut-flour
dravya.water-lily-stem
dravya.water-spinach
dravya.wheatgrass
dravya.white-mushroom
dravya.white-onion
dravya.white-peas
dravya.white-radish
dravya.whole-toor
dravya.whole-wheat-flour
dravya.wild-brinjal
dravya.wild-celery-seed
dravya.wild-mustard
dravya.wood-apple
dravya.yak-butter
dravya.yak-milk
dravya.yam-lesser
```

## Gate results

| Gate | Result | Evidence |
|---|---|---|
| Content validator | PASS | `python3 ayurveda-data/validate.py --store /tmp/pre` checked 714 dravyas and 1,500 recipes; all checks passed. |
| Director count gate | PASS | 714 dravyas, 1,500 recipes, 336 links, 383 placeholders, 331 primaries, 0 unresolved ingredients, 2 exclusions. |
| Deterministic gzip | PASS | Two consecutive builds produced identical output and SHA-256 `33bdd37da9ab40f61af66d7268db64e48871139ff244eb646f717d7ef189c19d`; gzip `mtime=0`. |
| Generated-bundle re-check | PASS | 2,214 profiles; unique `foodId` values within both kinds; all 10,571 ingredient references point to store or placeholder foods; 0 recipe-to-recipe ingredient references. |
| Spot values | PASS | Classic mung kitchari ingredient total is 1,852 g; ghee dosha is vata −2 / pitta −2 / kapha +1; only betel nut and vanaspati are engine-excluded. |
| Python syntax | PASS | `build_seed.py` passed `py_compile`. |
| Swift static checks | PASS | New Swift files passed strict `swift-format` lint, Swift parse-only checking, and the force-unwrap scan. This is not an app build. |
| Scope | PASS | Targeted status/diff contains only the eight files in the deliverables table; `FoodItem.swift` is unchanged. |

## Files changed

```text
 WiseEating/Ayurveda/AyurvedaProfile.swift   | 138 ++++++++
 WiseEating/Ayurveda/AyurvedaResolver.swift  |  80 +++++
 WiseEating/Main/DBSeed/AyurvedaSeeder.swift | 419 +++++++++++++++++++++++
 WiseEating/Main/DBSeed/DatabaseSetup.swift  |   3 +-
 WiseEating/Main/DBSeed/SeedManager.swift    |  23 ++
 WiseEating/ayurveda_seed.json.gz            | Bin 0 -> 450200 bytes
 ayurveda-data/REPORT-D6.md                  | 492 ++++++++++++++++++++++++++++
 ayurveda-data/build_seed.py                 | 327 ++++++++++++++++++
 8 files changed, 1481 insertions(+), 1 deletion(-)
```

## Open items for founder gate

- Run a clean Xcode app build; this executor does not claim that an app build passed.
- On a fresh install, verify 2,214 profiles, 336 links, 1,500 recipe `FoodItem`s, at least one non-nil ingredient link per recipe, and 383 placeholders; measure first-launch seed time.
- On an upgrade-simulated boot with the existing `default.store`, verify the reserved bands are free, nutrition foods are not duplicated, and existing flows remain unaffected.
- Invoke `seedAyurvedaIfNeeded` a second time and verify it inserts zero rows.
- Verify whole-recipe kitchari aggregate energy is 1,400–2,100 kcal and confirm the three specified runtime profile/exclusion spot checks.
