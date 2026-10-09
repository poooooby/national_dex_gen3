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
    # Alcremie's creams (the base ALCREMIE is Vanilla Cream); PokeAPI has no variety for
    # them, so each takes the base's data. Reached by evolving Milcery, see below.
    ("ALCREMIE_RUBY_CREAM", "ALCREMIE", "RUBY_CREAM", "alcremie"),
    ("ALCREMIE_MATCHA_CREAM", "ALCREMIE", "MATCHA_CREAM", "alcremie"),
    ("ALCREMIE_MINT_CREAM", "ALCREMIE", "MINT_CREAM", "alcremie"),
    ("ALCREMIE_LEMON_CREAM", "ALCREMIE", "LEMON_CREAM", "alcremie"),
    ("ALCREMIE_SALTED_CREAM", "ALCREMIE", "SALTED_CREAM", "alcremie"),
    ("ALCREMIE_RUBY_SWIRL", "ALCREMIE", "RUBY_SWIRL", "alcremie"),
    ("ALCREMIE_CARAMEL_SWIRL", "ALCREMIE", "CARAMEL_SWIRL", "alcremie"),
    ("ALCREMIE_RAINBOW_SWIRL", "ALCREMIE", "RAINBOW_SWIRL", "alcremie"),
    # Looks that PokeAPI keeps as forms, not varieties, so each takes the base's data:
    # the east-sea Shellos / Gastrodon and Flabebe's four other flower colours through
    # Floette and Florges (the base is the red one / the west sea).
    ("SHELLOS_EAST", "SHELLOS", "EAST", "shellos"),
    ("GASTRODON_EAST", "GASTRODON", "EAST", "gastrodon"),
    ("FLABEBE_YELLOW", "FLABEBE", "YELLOW", "flabebe"),
    ("FLABEBE_ORANGE", "FLABEBE", "ORANGE", "flabebe"),
    ("FLABEBE_BLUE", "FLABEBE", "BLUE", "flabebe"),
    ("FLABEBE_WHITE", "FLABEBE", "WHITE", "flabebe"),
    ("FLOETTE_YELLOW", "FLOETTE", "YELLOW", "floette"),
    ("FLOETTE_ORANGE", "FLOETTE", "ORANGE", "floette"),
    ("FLOETTE_BLUE", "FLOETTE", "BLUE", "floette"),
    ("FLOETTE_WHITE", "FLOETTE", "WHITE", "floette"),
    ("FLORGES_YELLOW", "FLORGES", "YELLOW", "florges"),
    ("FLORGES_ORANGE", "FLORGES", "ORANGE", "florges"),
    ("FLORGES_BLUE", "FLORGES", "BLUE", "florges"),
    ("FLORGES_WHITE", "FLORGES", "WHITE", "florges"),
    # Basculin's Hisuian look evolves into Basculegion (Basculin itself is the red-striped one);
    # the female Basculegion has her own stats
    ("BASCULIN_WHITE_STRIPED", "BASCULIN", "WHITE_STRIPED", "basculin-white-striped"),
    ("BASCULEGION_FEMALE", "BASCULEGION", "FEMALE", "basculegion-female"),
    # The tea set looks: Cracked Pot / Unremarkable Teacup evolve the base look (phony /
    # counterfeit / unremarkable), Chipped Pot / Masterpiece Teacup the other (antique /
    # artisan / masterpiece), each into the same look, as in the real games.
    ("SINISTEA_ANTIQUE", "SINISTEA", "ANTIQUE", "sinistea"),
    ("POLTEAGEIST_ANTIQUE", "POLTEAGEIST", "ANTIQUE", "polteageist"),
    ("POLTCHAGEIST_ARTISAN", "POLTCHAGEIST", "ARTISAN", "poltchageist"),
    ("SINISTCHA_MASTERPIECE", "SINISTCHA", "MASTERPIECE", "sinistcha"),
]

# The evolutions between FORMS that Gen 3 can express (level, item or trade).
# (from id, to id, method, level or item slug)
FORM_EVOLUTIONS = [
    ("DARUMAKA_GALAR", "DARMANITAN_GALAR_STANDARD", "EVO_ITEM", "ice-stone"),
    ("ZORUA_HISUI", "ZOROARK_HISUI", "EVO_LEVEL", 30),
    ("PUMPKABOO_SMALL", "GOURGEIST_SMALL", "EVO_TRADE", None),
    ("PUMPKABOO_LARGE", "GOURGEIST_LARGE", "EVO_TRADE", None),
    ("PUMPKABOO_SUPER", "GOURGEIST_SUPER", "EVO_TRADE", None),
    ("SHELLOS_EAST", "GASTRODON_EAST", "EVO_LEVEL", 30),
    ("SINISTEA_ANTIQUE", "POLTEAGEIST_ANTIQUE", "EVO_ITEM", "chipped-pot"),
    ("POLTCHAGEIST_ARTISAN", "SINISTCHA_MASTERPIECE", "EVO_ITEM", "masterpiece-teacup"),
] + [
    (f"FLABEBE_{c}", f"FLOETTE_{c}", "EVO_LEVEL", 19) for c in ("YELLOW", "ORANGE", "BLUE", "WHITE")
] + [
    (f"FLOETTE_{c}", f"FLORGES_{c}", "EVO_ITEM", "shiny-stone") for c in ("YELLOW", "ORANGE", "BLUE", "WHITE")
]

# Evolutions of a BASE species the PokeAPI data can't give us: one level step per
# outcome, all at the same level, and src/conditional_evos.lua lets exactly one
# through. A step's `when` holds its conditions, all of which must hold:
#   hold        item slug, or a list (any of them): the mon must be holding it
#   time        "night" (20:00-04:00), "dusk" (19:00-20:00) or "day" (every hour but
#               night, so dusk counts), on the clock the player chose (src/clock.lua)
#   friendship  at least this much
#   pick        [i, n]: the mon's personality falls in bucket i of n, a stable
#               "1 in n" that does not change between checks
#   gender      "F" or "M": the Pokemon's gender (from its personality)
#   recoil      the recoil damage the Pokemon has taken in battle, in total (src/recoil.lua)
#   terrain     "plant", "sandy" or "trash": where its last battle was fought, see
#               src/conditional_evos.lua (grass and water, sand / mountain / cave, buildings)
#   priority    the highest-priority step whose conditions hold wins (default 0)
# A step with no `when` always holds (at priority 0).   dex -> steps
SWEETS = ["strawberry-sweet", "berry-sweet", "love-sweet", "star-sweet",
          "clover-sweet", "flower-sweet", "ribbon-sweet"]


def _cream(bucket: int, time: str) -> dict:
    return {"hold": SWEETS, "time": time, "pick": [bucket, 4], "priority": 1}


def _plain(level: int, target: int | str, gender: str | None = None, terrain: str | None = None) -> dict:
    """A level-up step; target is a dex number, or a form id."""
    step: dict = {"method": "EVO_LEVEL", "level": level}
    step["targetForm" if isinstance(target, str) else "target"] = target
    when = {k: v for k, v in (("gender", gender), ("terrain", terrain)) if v}
    if when:
        step["when"] = when
    return step


CONDITIONAL_EVOLUTIONS = {
    # Gender decides who evolves, or into what (PokeAPI marks these; the plain level-up
    # path would let both genders through). Espurr and Lechonk reach the same species
    # either way: the female sprite sheets are not separate species here.
    # Burmy -> Wormadam (the cloak follows the terrain of its last battle) / Mothim
    412: [_plain(20, 413, "F", "plant"), _plain(20, "WORMADAM_SANDY", "F", "sandy"),
          _plain(20, "WORMADAM_TRASH", "F", "trash"), _plain(20, 414, "M")],
    415: [_plain(21, 416, "F")],                          # Combee -> Vespiquen (female only)
    757: [_plain(33, 758, "F")],                          # Salandit -> Salazzle (female only)
    677: [_plain(25, 678)],                               # Espurr -> Meowstic
    915: [_plain(18, 916)],                               # Lechonk -> Oinkologne
    # The spring Sawsbuck, the base Spewpa / Vivillon: the other looks are not modelled
    585: [_plain(34, 586)],                               # Deerling -> Sawsbuck
    664: [_plain(9, 665)],                                # Scatterbug -> Spewpa
    665: [_plain(12, 666)],                               # Spewpa -> Vivillon
    422: [_plain(30, 423)],                               # Shellos (west) -> Gastrodon (west)
    669: [_plain(19, 670)],                               # Flabebe (red) -> Floette (red)
    710: [{"method": "EVO_TRADE", "target": 711}],        # Pumpkaboo (average) -> Gourgeist
    # the base looks take their own item (the other look is a form, above)
    854: [{"method": "EVO_ITEM", "item": "cracked-pot", "target": 855}],              # Sinistea
    1012: [{"method": "EVO_ITEM", "item": "unremarkable-teacup", "target": 1013}],   # Poltchageist
    744: [   # Rockruff -> Lycanroc: Midday, Midnight (night), Dusk (the hour before night)
        {"method": "EVO_LEVEL", "level": 25, "target": 745},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "LYCANROC_MIDNIGHT",
         "when": {"time": "night", "priority": 1}},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "LYCANROC_DUSK",
         "when": {"time": "dusk", "priority": 2}},
    ],
    868: [   # Milcery -> Alcremie, holding a sweet: one of four creams by day or
             # night, or Rainbow Swirl at dusk
        {"method": "EVO_LEVEL", "level": 25, "target": 869, "when": _cream(0, "day")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_RUBY_CREAM", "when": _cream(1, "day")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_MATCHA_CREAM", "when": _cream(2, "day")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_MINT_CREAM", "when": _cream(3, "day")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_LEMON_CREAM", "when": _cream(0, "night")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_SALTED_CREAM", "when": _cream(1, "night")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_RUBY_SWIRL", "when": _cream(2, "night")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_CARAMEL_SWIRL", "when": _cream(3, "night")},
        {"method": "EVO_LEVEL", "level": 25, "targetForm": "ALCREMIE_RAINBOW_SWIRL",
         "when": {"hold": SWEETS, "time": "dusk", "priority": 2}},
    ],
}

# Evolutions of a FORM with conditions, like CONDITIONAL_EVOLUTIONS but keyed by form id.
# Basculin (white-striped) -> Basculegion after 294 recoil damage, by gender. The engine
# needs a level to evolve at, so it is level 1: the recoil total is the real condition.
FORM_CONDITIONAL_EVOLUTIONS = {
    "BASCULIN_WHITE_STRIPED": [
        {"method": "EVO_LEVEL", "level": 1, "target": 902,
         "when": {"gender": "M", "recoil": 294}},
        {"method": "EVO_LEVEL", "level": 1, "targetForm": "BASCULEGION_FEMALE",
         "when": {"gender": "F", "recoil": 294}},
    ],
}

assert len(FORMS) == 84, len(FORMS)
assert len({f[0] for f in FORMS}) == len(FORMS), "duplicate form id"
assert FIRST_FORM_SLOT + len(FORMS) - 1 < SLOT_CAP
