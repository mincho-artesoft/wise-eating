"""Director-reviewed NUT-1 Phase 2 bindings and direct literature values.

These are explicit rulings, not matcher heuristics.  Keep the strict matcher
strict; it imports this file only so its reverse-collision assertion sees the
same manually reviewed bindings that the value applicator uses.
"""

F016_WITHDRAWAL_STATUS = (
    "withdrawn — wrong species, F016 is Eleocharis dulcis; "
    "singhara is Trapa natans. See TASK-NUT1 §2."
)

LATE_WITHDRAWALS = {
    "dravya.fresh-water-chestnut": ("F016", "Water Chestnut"),
}

DIRECT_MATCH_STATUS = (
    "measured — IFCT 2017, direct match confirmed by director review, "
    "TASK-NUT1 Phase 2b"
)

# Ratio 1.000 identity bindings.  These are measured IFCT provenance, never
# derived transformations.  Qualifier tokens prevented strict equality.
DIRECT_BINDINGS = {
    "dravya.amla-fresh": ("E021", "Goosberry"),
    "dravya.green-pea-fresh": ("D061", "Peas, fresh"),
    "dravya.white-mushroom": ("J001", "Button mushroom, fresh"),
    "dravya.lentil-brown": ("B014", "Lentil whole, brown"),
    "dravya.mung-dal-split": ("B010", "Green gram, dal"),
    "dravya.jimikand-pink": ("F017", "Yam, elephant"),
}

DIRECT_DECLINES = {
    "dravya.karonda-ripe": {
        "ifctCode": "E032",
        "ifctName": "Karonda fruit",
        "reason": (
            "Declined by director review: E032 already feeds a karonda dravya, "
            "IFCT does not state maturity, and sugar and acid change materially "
            "during ripening."
        ),
    },
    "dravya.parwal-sweet": {
        "ifctCode": "D060",
        "ifctName": "Parwar",
        "reason": (
            "Declined by director review: D060 already feeds "
            "dravya.pointed-gourd; a named sweet cultivar cannot inherit the "
            "generic row."
        ),
    },
}

PUBLISHED_LITERATURE = {
    "dravya.amla-juice": {
        "source": (
            "Kumari, Parveen, and B. S. Khatkar. “Effect of processing "
            "treatment on nutritional properties and phytochemical contents "
            "of aonla (Emblica officinalis) juice.” Journal of Food Science "
            "and Technology 56(4), 2019, 2010–2015. "
            "https://doi.org/10.1007/s13197-019-03674-0"
        ),
        "spread": (
            "Fresh untreated juice, day 0, triplicate mean ± SD: vitamin C "
            "550.25 ± 1.06 mg/100 g, total polyphenols 3.22 ± 0.02%, and "
            "total sugar 5.87 ± 0.05%."
        ),
        "note": (
            "Direct measurements of filtered, freshly extracted Banarasi "
            "aonla juice; no whole-fruit yield multiplier is used."
        ),
        "values": {
            "macronutrients": {"totalSugars": 5.87},
            "vitamins": {"vitaminC": 550.25},
            "polyphenols": {"total": 3220.0},
        },
    },
    "dravya.water-chestnut-flour": {
        "source": (
            "Ahmed, Jasim, Hasan Al-Attar, and Yasir Ali Arfat. “Effect of "
            "particle size on compositional, functional, pasting and "
            "rheological properties of commercial water chestnut flour.” "
            "Food Hydrocolloids 52, 2016, 888–895. "
            "https://doi.org/10.1016/j.foodhyd.2015.08.028"
        ),
        "spread": (
            "The study reports no variation for the whole-sample proximate "
            "values used here. It reports that sieving significantly changes "
            "ash, so these values apply only to the unsieved whole commercial "
            "flour sample."
        ),
        "note": (
            "Direct measurements of commercial Indian Trapa natans flour. "
            "F016 is deliberately not used because it is Eleocharis dulcis, "
            "a different species in a different family."
        ),
        "values": {
            "macronutrients": {"protein": 8.4, "fat": 0.47},
            "carbDetails": {"starch": 65.86},
            "other": {"water": 7.08, "ash": 2.59},
        },
    },
}

AMBIGUOUS_MATCH_STATUS = (
    "measured — IFCT 2017, ambiguous match resolved by manual review, "
    "TASK-NUT1 Phase 2c"
)

AMBIGUOUS_BINDINGS = {
    "dravya.broad-bean": {
        "binding": ("D047", "Field beans, tender, broad"),
        "reason": (
            "The record is explicitly a broad tender pod; D047 is the only "
            "candidate with that edible form. B007–B009 are dry seed colours, "
            "D003 is scarlet runner bean, D048 is the lean-pod form, and the "
            "E001–E004 apple hits are a Manipuri-name collision."
        ),
    },
    "dravya.dry-dates": {
        "binding": ("E017", "Dates, dry, pale brown"),
        "reason": (
            "The authored chhuara/chuara form is the Hindi Chuhara named on "
            "E017. E018 is the dark-brown form and E019 is processed date."
        ),
    },
    "dravya.pumpkin-red": {
        "binding": ("D066", "Pumpkin, orange, round"),
        "reason": (
            "Red pumpkin/kaddu is the orange round Cucurbita maxima row; "
            "D065 is explicitly green and cylindrical."
        ),
    },
    "dravya.raisins": {
        "binding": ("E058", "Raisins, dried, golden"),
        "reason": (
            "The record's reviewed USDA binding is golden seedless raisins. "
            "E057 is the black form."
        ),
    },
    "dravya.raw-jackfruit": {
        "binding": ("D051", "Jack fruit, raw"),
        "reason": (
            "The record explicitly names raw kathal flesh. D052 is mature "
            "seed and E030 is ripe fruit."
        ),
    },
    "dravya.white-radish": {
        "binding": ("F010", "Radish, elongate, white skin"),
        "reason": (
            "White mooli is the elongate white-root form. F009/F011 are red "
            "and F012 is the separate round-white form."
        ),
    },
}

AMBIGUOUS_DEFERRALS = {
    "dravya.betel-leaf": (
        "The record does not specify large Kolkata or small leaf; both are "
        "Piper betle and neither may be chosen by name alone."
    ),
    "dravya.betel-nut": (
        "The record does not specify fresh versus dried or the brown/red dried "
        "form. Engine exclusion does not make an unsupported choice safe."
    ),
    "dravya.elephant-foot-yam": (
        "F019 is the wrong wild-yam species; F017 is now occupied by the "
        "director-approved pink elephant-yam record. Selecting it again would "
        "create an unruled reverse collision requiring identity/dedup review."
    ),
    "dravya.field-bean": (
        "The record describes fresh shelled avarekalu. IFCT offers dry seed "
        "colour rows and tender broad/lean pod rows, but no fresh shelled-bean "
        "measurement."
    ),
    "dravya.french-bean": (
        "The record does not identify IFCT's country or hybrid cultivar."
    ),
    "dravya.fresh-dates": (
        "Every IFCT candidate is dry or processed; none measures fresh dates."
    ),
    "dravya.gherkin": (
        "All candidates are Cucumis sativus cucumber forms; the authored West "
        "Indian gherkin identity is not established as any of them."
    ),
    "dravya.green-grapes": (
        "Green narrows the set to E023/E026, but the record does not establish "
        "seeded versus seedless."
    ),
    "dravya.green-peas-pod": (
        "B017 is dry pea, while D061 measures fresh peas; the record also "
        "allows whole pods, so the measured edible portion is unresolved."
    ),
    "dravya.hung-curd": (
        "All candidates are jackfruit rows reached through Malayalam chakka; "
        "none measures strained yoghurt."
    ),
    "dravya.jamun": (
        "E013 is Rubus blackberry and E031 is Syzygium samarangense wax apple; "
        "neither is the authored Syzygium cumini jamun."
    ),
    "dravya.khus-root": (
        "G030 pippali and G032 poppy seed are vernacular collisions; neither "
        "is vetiver root."
    ),
    "dravya.manathakkali-greens": (
        "All candidates are Zea mays rows reached through makoi/makoi-like "
        "names; none is black nightshade greens."
    ),
    "dravya.niger-seed": (
        "The record does not specify IFCT's black or gray seed form."
    ),
    "dravya.taro-stem-regional": (
        "The record does not specify IFCT's black or green colocasia stem."
    ),
    "dravya.wild-celery-seed": (
        "G029 is Trachyspermum ammi ajwain and C028 is parsley leaf; neither "
        "is a measured wild-celery seed row."
    ),
}
