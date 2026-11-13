"""
What an ability does, as data: the `behaviour` block of abilityById (data/gen12/api/abilities.lua,
tools/build_api.py). Written by hand from the games' mechanics, for a battle mod that switches
on the effect kinds instead of reading the text.

  behaviour = { trigger, scope, chance, effects = { { kind, ... }, ... } }

  trigger   switch_in | passive | turn_end | on_hit_by | on_contact_taken | on_switch_out |
            on_status | on_weather | on_terrain
  scope     self | foes | allies | field
  chance    a percent (default 100)
  kinds     stat_multiplier { stat, factor }        accuracy_multiplier { factor }
            damage_dealt_multiplier { factor, moveType?, when? }
            damage_taken_multiplier { factor, moveType?, when? }
            crit_change { amount | always }         priority_change { amount }
            status_immunity { status }               type_immunity { moveType }
            heal { fraction, when? }                 damage_self { fraction, when? }
            stat_change { stat, stages, when? }      set_weather { weather }
            set_terrain { terrain }                  inflict_status { status }
            damage { fraction } (to the Pokemon that touched it)

  stat      PokéAPI's names: attack, defense, special-attack, special-defense, speed, accuracy,
            evasion
  moveType  the modern type in capitals (FIRE, PSYCHIC); src/gen12/dex_api.lua writes the running
            game's own id in its place (PSYCHIC_TYPE on Red / Gold)
  status    paralysis, freeze, burn, sleep, poison, confusion, flinch; major = the five major
            ones; any = everything
  weather   rain, sun, sandstorm, hail (Snow Warning's snow is hail here)
  terrain   electric, grassy, misty, psychic
  when      free text; three phrasings have a meaning: "each turn ..." (at the end of each turn,
            in the named weather), "hit by ..." (when a move of that type hits), and Rivalry's
            "same gender" / "opposite gender"

`expressible` says whether the block captures the ability; when it does not, `notes` names what
is missing (the condition lives in the battle code: HP, weather, a move flag, ...).
"""

from __future__ import annotations


def b(trigger: str, *effects: dict, scope: str = "self", chance: int | None = None,
      notes: str | None = None, expressible: bool | None = None) -> dict:
    behaviour: dict = {"trigger": trigger, "scope": scope, "effects": list(effects)}
    if chance is not None:
        behaviour["chance"] = chance
    out: dict = {"behaviour": behaviour}
    out["expressible"] = (notes is None) if expressible is None else expressible
    if notes:
        out["notes"] = notes
    return out


def stat(stat_name: str, factor: float) -> dict:
    return {"kind": "stat_multiplier", "stat": stat_name, "factor": factor}


def dealt(factor: float, move_type: str | None = None, when: str | None = None) -> dict:
    e = {"kind": "damage_dealt_multiplier", "factor": factor}
    if move_type:
        e["moveType"] = move_type
    if when:
        e["when"] = when
    return e


def taken(factor: float, move_type: str | None = None, when: str | None = None) -> dict:
    e = {"kind": "damage_taken_multiplier", "factor": factor}
    if move_type:
        e["moveType"] = move_type
    if when:
        e["when"] = when
    return e


def immune(status: str) -> dict:
    return {"kind": "status_immunity", "status": status}


def type_immune(move_type: str) -> dict:
    return {"kind": "type_immunity", "moveType": move_type}


def heal(fraction: float, when: str | None = None) -> dict:
    e = {"kind": "heal", "fraction": fraction}
    if when:
        e["when"] = when
    return e


def change(stat_name: str, stages: int, when: str | None = None) -> dict:
    e = {"kind": "stat_change", "stat": stat_name, "stages": stages}
    if when:
        e["when"] = when
    return e


def weather(name: str) -> dict:
    return {"kind": "set_weather", "weather": name}


def terrain(name: str) -> dict:
    return {"kind": "set_terrain", "terrain": name}


AURA = round(5448 / 4096, 4)
PARADOX_BOOST = round(5461 / 4096, 4)

BEHAVIOUR: dict[str, dict] = {
    # accuracy and evasion
    "COMPOUNDEYES": b("passive", {"kind": "accuracy_multiplier", "factor": 1.3}),
    "HUSTLE": b("passive", dealt(1.5), {"kind": "accuracy_multiplier", "factor": 0.8},
                notes="physical moves only"),
    "VICTORYSTAR": b("passive", {"kind": "accuracy_multiplier", "factor": 1.1}, scope="allies"),
    "SANDVEIL": b("on_weather", stat("evasion", 1.25), notes="in a sandstorm"),
    "SNOWCLOAK": b("on_weather", stat("evasion", 1.25), notes="in hail or snow"),
    "TANGLEDFEET": b("passive", stat("evasion", 2), notes="while confused"),

    # critical hits
    "SUPERLUCK": b("passive", {"kind": "crit_change", "amount": 1}),
    "MERCILESS": b("passive", {"kind": "crit_change", "always": True}, notes="against a poisoned target"),

    # damage dealt, by type
    "BLAZE": b("passive", dealt(1.5, "FIRE", "HP at or below 1/3"), notes="at 1/3 HP or less"),
    "OVERGROW": b("passive", dealt(1.5, "GRASS", "HP at or below 1/3"), notes="at 1/3 HP or less"),
    "TORRENT": b("passive", dealt(1.5, "WATER", "HP at or below 1/3"), notes="at 1/3 HP or less"),
    "SWARM": b("passive", dealt(1.5, "BUG", "HP at or below 1/3"), notes="at 1/3 HP or less"),
    "STEELWORKER": b("passive", dealt(1.5, "STEEL")),
    "ROCKYPAYLOAD": b("passive", dealt(1.5, "ROCK")),
    "TRANSISTOR": b("passive", dealt(1.3, "ELECTRIC")),
    "DRAGONSMAW": b("passive", dealt(1.5, "DRAGON")),
    "STEELYSPIRIT": b("passive", dealt(1.5, "STEEL"), scope="allies"),
    "SANDFORCE": b("on_weather", dealt(1.3, "ROCK"), dealt(1.3, "GROUND"), dealt(1.3, "STEEL"),
                   notes="in a sandstorm; also immune to sandstorm damage"),
    "DARKAURA": b("passive", dealt(AURA, "DARK"), scope="field"),
    "FAIRYAURA": b("passive", dealt(AURA, "FAIRY"), scope="field"),
    "FLASHFIRE": b("on_hit_by", type_immune("FIRE"), dealt(1.5, "FIRE"),
                   notes="the boost only after a Fire move has hit it"),
    "WATERBUBBLE": b("passive", dealt(2, "WATER"), taken(0.5, "FIRE"), immune("burn")),

    # damage dealt, by condition
    "ADAPTABILITY": b("passive", dealt(2, when="STAB"), notes="same-type bonus is 2x instead of 1.5x"),
    "TECHNICIAN": b("passive", dealt(1.5), notes="moves of 60 power or less"),
    "RIVALRY": b("passive", dealt(1.25, when="same gender"), dealt(0.75, when="opposite gender")),
    "NEUROFORCE": b("passive", dealt(1.25), notes="super-effective hits"),
    "TINTEDLENS": b("passive", dealt(2), notes="not-very-effective hits"),
    "IRONFIST": b("passive", dealt(1.2), notes="punching moves"),
    "MEGALAUNCHER": b("passive", dealt(1.5), notes="pulse and aura moves"),
    "STRONGJAW": b("passive", dealt(1.5), notes="biting moves"),
    "SHARPNESS": b("passive", dealt(1.5), notes="slicing moves"),
    "TOUGHCLAWS": b("passive", dealt(1.3), notes="contact moves"),
    "RECKLESS": b("passive", dealt(1.2), notes="moves with recoil or crash damage"),
    "ANALYTIC": b("passive", dealt(1.3), notes="when moving last"),
    "ELECTROMORPHOSIS": b("on_hit_by", dealt(2), notes="the next Electric move after being hit"),
    "WINDPOWER": b("on_hit_by", dealt(2), notes="the next Electric move after a wind move hits it"),
    "STAKEOUT": b("passive", dealt(2), notes="against a Pokemon that switched in this turn"),
    "SHEERFORCE": b("passive", dealt(1.3), notes="moves with added effects, which it removes"),
    "BATTERY": b("passive", dealt(1.3), scope="allies", notes="allies' special moves"),
    "POWERSPOT": b("passive", dealt(1.3), scope="allies"),

    # damage taken
    "THICKFAT": b("passive", taken(0.5, "FIRE"), taken(0.5, "ICE")),
    "HEATPROOF": b("passive", taken(0.5, "FIRE"), notes="also halves burn damage"),
    "PURIFYINGSALT": b("passive", taken(0.5, "GHOST"), immune("major")),
    "MULTISCALE": b("passive", taken(0.5), notes="at full HP"),
    "SHADOWSHIELD": b("passive", taken(0.5), notes="at full HP"),
    "FILTER": b("passive", taken(0.75), notes="super-effective hits"),
    "SOLIDROCK": b("passive", taken(0.75), notes="super-effective hits"),
    "PRISMARMOR": b("passive", taken(0.75), notes="super-effective hits"),
    "FLUFFY": b("passive", taken(0.5, when="contact"), taken(2, "FIRE")),
    "FURCOAT": b("passive", taken(0.5), notes="physical moves"),
    "ICESCALES": b("passive", taken(0.5), notes="special moves"),
    "FRIENDGUARD": b("passive", taken(0.75), scope="allies"),

    # healing
    "DRYSKIN": b("on_weather", type_immune("WATER"), heal(0.25, "hit by a Water-type move"),
                 heal(0.125, "each turn in rain"),
                 {"kind": "damage_self", "fraction": 0.125, "when": "each turn in harsh sunlight"},
                 notes="also takes 1.25x from Fire moves"),
    "ICEBODY": b("turn_end", heal(0.0625, "each turn in snow")),
    "RAINDISH": b("turn_end", heal(0.0625, "each turn in rain")),
    "POISONHEAL": b("turn_end", heal(0.125), notes="while poisoned, instead of losing HP"),
    "HOSPITALITY": b("switch_in", heal(0.25), scope="allies"),
    "REGENERATOR": b("on_switch_out", heal(round(1 / 3, 4))),

    # priority
    "PRANKSTER": b("passive", {"kind": "priority_change", "amount": 1}, notes="status moves"),
    "TRIAGE": b("passive", {"kind": "priority_change", "amount": 3}, notes="healing moves"),
    "GALEWINGS": b("passive", {"kind": "priority_change", "amount": 1}, notes="Flying moves at full HP"),

    # curing status
    "SHEDSKIN": b("turn_end", chance=33),
    "HEALER": b("turn_end", scope="allies", chance=30),
    "HYDRATION": b("turn_end", notes="cures its status at the end of each turn in rain"),
    "NATURALCURE": b("on_switch_out", notes="cures its status when it switches out"),

    # status immunities
    "INNERFOCUS": b("passive", immune("flinch")),
    "MAGMAARMOR": b("passive", immune("freeze")),
    "LIMBER": b("passive", immune("paralysis")),
    "OWNTEMPO": b("passive", immune("confusion")),
    "OBLIVIOUS": b("passive", immune("confusion"), notes="also blocks infatuation and Taunt"),
    "INSOMNIA": b("passive", immune("sleep")),
    "VITALSPIRIT": b("passive", immune("sleep")),
    "SWEETVEIL": b("passive", immune("sleep"), scope="allies"),
    "IMMUNITY": b("passive", immune("poison")),
    "PASTELVEIL": b("passive", immune("poison"), scope="allies"),
    "WATERVEIL": b("passive", immune("burn")),
    "THERMALEXCHANGE": b("passive", immune("burn"), change("attack", 1, "hit by a Fire-type move")),
    "COMATOSE": b("passive", immune("major")),
    "LEAFGUARD": b("on_weather", immune("major"), notes="in harsh sunlight"),
    "SHIELDSDOWN": b("passive", immune("major"), notes="above half HP"),

    # stats
    "CHLOROPHYLL": b("on_weather", stat("speed", 2), notes="in harsh sunlight"),
    "SWIFTSWIM": b("on_weather", stat("speed", 2), notes="in rain"),
    "SANDRUSH": b("on_weather", stat("speed", 2), notes="in a sandstorm"),
    "SLUSHRUSH": b("on_weather", stat("speed", 2), notes="in hail or snow"),
    "SOLARPOWER": b("on_weather", stat("special-attack", 1.5),
                    {"kind": "damage_self", "fraction": 0.125, "when": "each turn in harsh sunlight"},
                    notes="in harsh sunlight"),
    "SURGESURFER": b("on_terrain", stat("speed", 2), notes="on Electric Terrain"),
    "GRASSPELT": b("on_terrain", stat("defense", 1.5), notes="on Grassy Terrain"),
    "DEFEATIST": b("passive", stat("attack", 0.5), stat("special-attack", 0.5), notes="at half HP or less"),
    "FLAREBOOST": b("on_status", stat("special-attack", 1.5), notes="while burned"),
    "TOXICBOOST": b("on_status", stat("attack", 1.5), notes="while poisoned"),
    "HUGEPOWER": b("passive", stat("attack", 2)),
    "PUREPOWER": b("passive", stat("attack", 2)),
    "GORILLATACTICS": b("passive", stat("attack", 1.5), notes="locked into its first move"),
    "QUICKFEET": b("on_status", stat("speed", 1.5), notes="with a status condition"),
    "GUTS": b("on_status", stat("attack", 1.5), notes="with a status condition"),
    "MARVELSCALE": b("on_status", stat("defense", 1.5), notes="with a status condition"),
    "PLUS": b("passive", stat("special-attack", 1.5), notes="with an ally that has Plus or Minus"),
    "MINUS": b("passive", stat("special-attack", 1.5), notes="with an ally that has Plus or Minus"),
    "SLOWSTART": b("switch_in", stat("attack", 0.5), stat("speed", 0.5), notes="for five turns"),
    "ORICHALCUMPULSE": b("switch_in", weather("sun"), stat("attack", PARADOX_BOOST),
                         notes="the Attack boost in harsh sunlight"),
    "HADRONENGINE": b("switch_in", terrain("electric"), stat("special-attack", PARADOX_BOOST),
                      notes="the Sp. Atk boost on Electric Terrain"),

    # weather and terrain
    "DRIZZLE": b("switch_in", weather("rain"), scope="field"),
    "DROUGHT": b("switch_in", weather("sun"), scope="field"),
    "SANDSTREAM": b("switch_in", weather("sandstorm"), scope="field"),
    "SNOWWARNING": b("switch_in", weather("hail"), scope="field"),
    "DESOLATELAND": b("switch_in", weather("sun"), scope="field", notes="extremely harsh sunlight"),
    "PRIMORDIALSEA": b("switch_in", weather("rain"), scope="field", notes="heavy rain"),
    "ELECTRICSURGE": b("switch_in", terrain("electric"), scope="field"),
    "GRASSYSURGE": b("switch_in", terrain("grassy"), scope="field"),
    "MISTYSURGE": b("switch_in", terrain("misty"), scope="field"),
    "PSYCHICSURGE": b("switch_in", terrain("psychic"), scope="field"),
    "SEEDSOWER": b("on_hit_by", terrain("grassy"), scope="field"),

    # stat changes on entry
    "INTIMIDATE": b("switch_in", change("attack", -1), scope="foes"),
    "SUPERSWEETSYRUP": b("switch_in", change("evasion", -1), scope="foes", notes="once per battle"),
    "INTREPIDSWORD": b("switch_in", change("attack", 1), notes="once per battle"),
    "DAUNTLESSSHIELD": b("switch_in", change("defense", 1), notes="once per battle"),

    # absorbing a type
    "WATERABSORB": b("on_hit_by", type_immune("WATER"), heal(0.25, "hit by a Water-type move")),
    "VOLTABSORB": b("on_hit_by", type_immune("ELECTRIC"), heal(0.25, "hit by an Electric-type move")),
    "EARTHEATER": b("on_hit_by", type_immune("GROUND"), heal(0.25, "hit by a Ground-type move")),
    "SAPSIPPER": b("on_hit_by", type_immune("GRASS"), change("attack", 1, "hit by a Grass-type move")),
    "MOTORDRIVE": b("on_hit_by", type_immune("ELECTRIC"), change("speed", 1, "hit by an Electric-type move")),
    "LIGHTNINGROD": b("on_hit_by", type_immune("ELECTRIC"),
                      change("special-attack", 1, "hit by an Electric-type move"),
                      notes="also draws Electric moves to itself"),
    "STORMDRAIN": b("on_hit_by", type_immune("WATER"), change("special-attack", 1, "hit by a Water-type move"),
                    notes="also draws Water moves to itself"),
    "WELLBAKEDBODY": b("on_hit_by", type_immune("FIRE"), change("defense", 2, "hit by a Fire-type move")),
    "WINDRIDER": b("on_hit_by", change("attack", 1, "hit by a wind move"), notes="immune to wind moves"),
    "LEVITATE": b("passive", type_immune("GROUND")),

    # stat changes when hit
    "JUSTIFIED": b("on_hit_by", change("attack", 1, "hit by a Dark-type move")),
    "RATTLED": b("on_hit_by", change("speed", 1, "hit by a Bug-, Ghost- or Dark-type move")),
    "STEAMENGINE": b("on_hit_by", change("speed", 6, "hit by a Fire- or Water-type move")),
    "WATERCOMPACTION": b("on_hit_by", change("defense", 2, "hit by a Water-type move")),
    "STAMINA": b("on_hit_by", change("defense", 1, "hit by a damaging move")),
    "WEAKARMOR": b("on_hit_by", change("defense", -1), change("speed", 2),
                   notes="when hit by a physical move"),
    "GOOEY": b("on_contact_taken", change("speed", -1), scope="foes"),
    "TANGLINGHAIR": b("on_contact_taken", change("speed", -1), scope="foes"),
    "COTTONDOWN": b("on_hit_by", change("speed", -1), scope="foes", notes="every other Pokemon"),
    "ANGERPOINT": b("on_hit_by", change("attack", 12), notes="after a critical hit"),
    "STEADFAST": b("passive", change("speed", 1), notes="when it flinches"),
    "SPEEDBOOST": b("turn_end", change("speed", 1)),
    "MOXIE": b("passive", change("attack", 1), notes="after knocking out a Pokemon"),
    "CHILLINGNEIGH": b("passive", change("attack", 1), notes="after knocking out a Pokemon"),
    "GRIMNEIGH": b("passive", change("special-attack", 1), notes="after knocking out a Pokemon"),

    # status on contact
    "STATIC": b("on_contact_taken", {"kind": "inflict_status", "status": "paralysis"}, scope="foes", chance=30),
    "FLAMEBODY": b("on_contact_taken", {"kind": "inflict_status", "status": "burn"}, scope="foes", chance=30),
    "POISONPOINT": b("on_contact_taken", {"kind": "inflict_status", "status": "poison"}, scope="foes", chance=30),
    "CUTECHARM": b("on_contact_taken", {"kind": "inflict_status", "status": "infatuation"}, scope="foes",
                   chance=30),
    "EFFECTSPORE": b("on_contact_taken", {"kind": "inflict_status", "status": "poison"},
                     {"kind": "inflict_status", "status": "paralysis"},
                     {"kind": "inflict_status", "status": "sleep"}, scope="foes", chance=30,
                     notes="one of the three"),
    "POISONTOUCH": b("passive", {"kind": "inflict_status", "status": "poison"}, scope="foes", chance=30,
                     notes="on its own contact moves"),
    "STENCH": b("passive", {"kind": "inflict_status", "status": "flinch"}, scope="foes", chance=10,
                notes="on its own damaging moves"),

    # retaliation
    "ROUGHSKIN": b("on_contact_taken", {"kind": "damage", "fraction": 0.125}, scope="foes"),
    "IRONBARBS": b("on_contact_taken", {"kind": "damage", "fraction": 0.125}, scope="foes"),
    "AFTERMATH": b("on_contact_taken", {"kind": "damage", "fraction": 0.25}, scope="foes",
                   notes="when knocked out by a contact move"),
}
