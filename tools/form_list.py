"""
The alternate forms this mod registers as species of their own.

APPEND-ONLY. A form's engine slot is its position here (FIRST_FORM_SLOT +
index) and is stored in player saves, so an entry is never reordered, removed
or renumbered. New forms go at the end.

Each row: (id, base species id, form name, PokéAPI variety slug).
  * id follows the original national_dex mod's convention (<BASE>_<FORM>), so
    the sprite pack's lookup table (data/dbk_data.lua of g9-battle-sprites) and
    anything else keyed to national_dex links up with no mapping.
  * the dex number a player sees is the base species' (baseDex).

Left out on purpose: Megas and Gigantamax (no Gen 3 battle support), cosmetic
and in-battle forms (totems, Minior colours, Cramorant, Aegislash Blade,
Darmanitan Zen, Palafin Hero, ...), Arceus/Silvally type forms, and gender
forms (Meowstic/Basculegion/Indeedee/Oinkologne Female), which are the same
species with a different sheet.
"""

FIRST_FORM_SLOT = 1090
SLOT_CAP = 1200          # headroom above the last form

FORMS = [
    # regional
    ("DARUMAKA_GALAR", "DARUMAKA", "GALAR", "darumaka-galar"),
    ("DARMANITAN_GALAR_STANDARD", "DARMANITAN", "GALAR_STANDARD", "darmanitan-galar-standard"),
    ("YAMASK_GALAR", "YAMASK", "GALAR", "yamask-galar"),
    ("STUNFISK_GALAR", "STUNFISK", "GALAR", "stunfisk-galar"),
    ("ZORUA_HISUI", "ZORUA", "HISUI", "zorua-hisui"),
    ("ZOROARK_HISUI", "ZOROARK", "HISUI", "zoroark-hisui"),
    ("SAMUROTT_HISUI", "SAMUROTT", "HISUI", "samurott-hisui"),
    ("LILLIGANT_HISUI", "LILLIGANT", "HISUI", "lilligant-hisui"),
    ("BRAVIARY_HISUI", "BRAVIARY", "HISUI", "braviary-hisui"),
    ("SLIGGOO_HISUI", "SLIGGOO", "HISUI", "sliggoo-hisui"),
    ("GOODRA_HISUI", "GOODRA", "HISUI", "goodra-hisui"),
    ("AVALUGG_HISUI", "AVALUGG", "HISUI", "avalugg-hisui"),
    ("DECIDUEYE_HISUI", "DECIDUEYE", "HISUI", "decidueye-hisui"),
    # permanent forms with their own stats or typing
    ("WORMADAM_SANDY", "WORMADAM", "SANDY", "wormadam-sandy"),
    ("WORMADAM_TRASH", "WORMADAM", "TRASH", "wormadam-trash"),
    ("ROTOM_HEAT", "ROTOM", "HEAT", "rotom-heat"),
    ("ROTOM_WASH", "ROTOM", "WASH", "rotom-wash"),
    ("ROTOM_FROST", "ROTOM", "FROST", "rotom-frost"),
    ("ROTOM_FAN", "ROTOM", "FAN", "rotom-fan"),
    ("ROTOM_MOW", "ROTOM", "MOW", "rotom-mow"),
    ("ORICORIO_PAU", "ORICORIO", "PAU", "oricorio-pau"),
    ("ORICORIO_POM_POM", "ORICORIO", "POM_POM", "oricorio-pom-pom"),
    ("ORICORIO_SENSU", "ORICORIO", "SENSU", "oricorio-sensu"),
    ("PUMPKABOO_SMALL", "PUMPKABOO", "SMALL", "pumpkaboo-small"),
    ("PUMPKABOO_LARGE", "PUMPKABOO", "LARGE", "pumpkaboo-large"),
    ("PUMPKABOO_SUPER", "PUMPKABOO", "SUPER", "pumpkaboo-super"),
    ("GOURGEIST_SMALL", "GOURGEIST", "SMALL", "gourgeist-small"),
    ("GOURGEIST_LARGE", "GOURGEIST", "LARGE", "gourgeist-large"),
    ("GOURGEIST_SUPER", "GOURGEIST", "SUPER", "gourgeist-super"),
    ("LYCANROC_MIDNIGHT", "LYCANROC", "MIDNIGHT", "lycanroc-midnight"),
    ("LYCANROC_DUSK", "LYCANROC", "DUSK", "lycanroc-dusk"),
    ("URSHIFU_RAPID_STRIKE", "URSHIFU", "RAPID_STRIKE", "urshifu-rapid-strike"),
    # legendary item / fusion forms (not reachable in Gen 3 except by editing a save)
    ("GIRATINA_ORIGIN", "GIRATINA", "ORIGIN", "giratina-origin"),
    ("DIALGA_ORIGIN", "DIALGA", "ORIGIN", "dialga-origin"),
    ("PALKIA_ORIGIN", "PALKIA", "ORIGIN", "palkia-origin"),
    ("SHAYMIN_SKY", "SHAYMIN", "SKY", "shaymin-sky"),
    ("TORNADUS_THERIAN", "TORNADUS", "THERIAN", "tornadus-therian"),
    ("THUNDURUS_THERIAN", "THUNDURUS", "THERIAN", "thundurus-therian"),
    ("LANDORUS_THERIAN", "LANDORUS", "THERIAN", "landorus-therian"),
    ("ENAMORUS_THERIAN", "ENAMORUS", "THERIAN", "enamorus-therian"),
    ("KYUREM_BLACK", "KYUREM", "BLACK", "kyurem-black"),
    ("KYUREM_WHITE", "KYUREM", "WHITE", "kyurem-white"),
    ("HOOPA_UNBOUND", "HOOPA", "UNBOUND", "hoopa-unbound"),
    ("NECROZMA_DUSK", "NECROZMA", "DUSK", "necrozma-dusk"),
    ("NECROZMA_DAWN", "NECROZMA", "DAWN", "necrozma-dawn"),
    ("CALYREX_ICE", "CALYREX", "ICE", "calyrex-ice"),
    ("CALYREX_SHADOW", "CALYREX", "SHADOW", "calyrex-shadow"),
    ("ZACIAN_CROWNED", "ZACIAN", "CROWNED", "zacian-crowned"),
    ("ZAMAZENTA_CROWNED", "ZAMAZENTA", "CROWNED", "zamazenta-crowned"),
    ("OGERPON_WELLSPRING_MASK", "OGERPON", "WELLSPRING_MASK", "ogerpon-wellspring-mask"),
    ("OGERPON_HEARTHFLAME_MASK", "OGERPON", "HEARTHFLAME_MASK", "ogerpon-hearthflame-mask"),
    ("OGERPON_CORNERSTONE_MASK", "OGERPON", "CORNERSTONE_MASK", "ogerpon-cornerstone-mask"),
    ("URSALUNA_BLOODMOON", "URSALUNA", "BLOODMOON", "ursaluna-bloodmoon"),
    ("ZYGARDE_10", "ZYGARDE", "10", "zygarde-10"),
    ("ZYGARDE_COMPLETE", "ZYGARDE", "COMPLETE", "zygarde-complete"),
    ("FLOETTE_ETERNAL", "FLOETTE", "ETERNAL", "floette-eternal"),
]

# The evolutions between FORMS that Gen 3 can express (level, item or trade).
# (from id, to id, method, level or item slug)
FORM_EVOLUTIONS = [
    ("DARUMAKA_GALAR", "DARMANITAN_GALAR_STANDARD", "EVO_ITEM", "ice-stone"),
    ("ZORUA_HISUI", "ZOROARK_HISUI", "EVO_LEVEL", 30),
    ("PUMPKABOO_SMALL", "GOURGEIST_SMALL", "EVO_TRADE", None),
    ("PUMPKABOO_LARGE", "GOURGEIST_LARGE", "EVO_TRADE", None),
    ("PUMPKABOO_SUPER", "GOURGEIST_SUPER", "EVO_TRADE", None),
]

assert len(FORMS) == 56, len(FORMS)
assert len({f[0] for f in FORMS}) == len(FORMS), "duplicate form id"
assert FIRST_FORM_SLOT + len(FORMS) - 1 < SLOT_CAP
