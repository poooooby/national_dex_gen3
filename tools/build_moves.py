#!/usr/bin/env python3
"""Generate data/moves.lua: real moves newer than Gen 3 that work like a Gen 3 move.

The Gen 3 battle engine runs every move through an effect id from the cart's own effect
table (EFFECT_HIT, EFFECT_BURN_HIT, ...); a mod can register a move row with any of those
effects (src/mods/Schemas.lua R.moves, index up to 1023) but cannot add a new effect. So a
newer move becomes a real move when its effect is one Gen 3 already has:

  effect    PokeAPI gives each move its effect description, shared word for word by every
            move with that effect. The cart's 354 moves pair each description with the cart's
            effect id (the most common one, where a description covers a special case too);
            a newer move whose description is one of those gets that effect. Every other
            newer move keeps its closest-Gen-3 substitute (tools/move_map.py).
  numbers   power, accuracy, PP, priority, secondary chance: PokeAPI (today's values)
  target    PokeAPI's target, as the cart pairs it with its own target ids
  flags     contact / Protect / Magic Coat / Snatch / Mirror Move from Pokemon Showdown's move
            data (they agree with the cart's own flags for 96-99% of its moves); King's Rock
            for a damaging move with no secondary effect, as the cart mostly does
  contest   category and appeal effect (Ruby/Sapphire/Emerald), PokeAPI paired with the
            cart's own contest data the same way
  name      the English name in capitals, at most 12 letters (Gen 3's limit; NAME_OVERRIDES
            shortens the longer ones)
  text      an English flavor text that fits each summary box: FireRed/LeafGreen 4 lines of
            19, Ruby/Sapphire/Emerald 2 lines of 28
  type      FAIRY moves are registered as NORMAL and turned FAIRY by src/types.lua

Only moves the species of this mod learn (level-up or egg) are built. Indices start at 355
and are append-only (a move's index is saved in a Pokemon's moves): a move already in
data/moves.lua keeps its index.

    python tools/build_moves.py
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import urllib.request
from pathlib import Path
from typing import Any

import build_species as bs
import form_list
import move_map

ROOT = Path(__file__).resolve().parent.parent
FIRST_INDEX = 355
NAME_LIMIT = 12
FRLG_COLS, FRLG_ROWS = 19, 4
RSE_COLS, RSE_ROWS = 28, 2
SHOWDOWN = "https://play.pokemonshowdown.com/data/moves.json"

# names over 12 letters, shortened the way the Gen 3 games shorten theirs (DYNAMICPUNCH,
# SELFDESTRUCT): words run together or clipped
NAME_OVERRIDES: dict[str, str] = {
    "BABY-DOLL EYES": "BABYDOLLEYES",
    "DISARMING VOICE": "DISARM VOICE",
    "DAZZLING GLEAM": "DAZZLE GLEAM",
    "MYSTICAL FIRE": "MYSTICALFIRE",
    "HIGH HORSEPOWER": "HIGHHORSEPWR",
    "DUAL WINGBEAT": "DUALWINGBEAT",
    "PSYCHIC FANGS": "PSYCHICFANGS",
    "PRISMATIC LASER": "PRISM LASER",
    "PHOTON GEYSER": "PHOTONGEYSER",
    "DRAGON HAMMER": "DRAGONHAMMER",
    "FALSE SURRENDER": "FALSESURRNDR",
    "STEAM ERUPTION": "STEAM ERUPTN",
    "DOUBLE IRON BASH": "DBL IRONBASH",
    "STRANGE STEAM": "STRANGESTEAM",
    "METEOR ASSAULT": "METEOR ASSLT",
    "DRAGON ENERGY": "DRAGONENERGY",
    "FREEZING GLARE": "FREEZE GLARE",
    "GLACIAL LANCE": "GLACIALLANCE",
    "ASTRAL BARRAGE": "ASTRLBARRAGE",
    "NATURE'S MADNESS": "NATURMADNESS",
    "THOUSAND WAVES": "THOUSNDWAVES",
    "DRAINING KISS": "DRAININGKISS",
    "POWER-UP PUNCH": "POWERUPPUNCH",
    "BREAKING SWIPE": "BREAKNGSWIPE",
    "SKITTER SMACK": "SKITTERSMACK",
    "PARABOLIC CHARGE": "PARABOLICCHG",
    "EERIE IMPULSE": "EERIEIMPULSE",
    "DIAMOND STORM": "DIAMONDSTORM",
    "OBLIVION WING": "OBLIVIONWING",
    "HYPERSPACE FURY": "HYPRSPACFURY",
    "FLORAL HEALING": "FLORALHEALNG",
    "CLANGING SCALES": "CLANGNGSCALE",
    "SHELL SIDE ARM": "SHELLSIDEARM",
    "THUNDEROUS KICK": "THUNDERSKICK",
}

# Summary text, in the Gen 3 manner, for moves whose official texts are too long for the
# boxes (Ruby/Sapphire/Emerald's is 2 lines). Used in both boxes. Our own words.
DESCRIPTIONS = {
    "NIGHT_SLASH": "Slashes at a vital spot. High critical-hit ratio.",
    "DISCHARGE": "A flare of electricity hits all around. May paralyze.",
    "MOONBLAST": "Attacks with the moon's power. May lower SP. ATK.",
    "BABY_DOLL_EYES": "An innocent look that lowers the foe's ATTACK first.",
    "AIR_SLASH": "Attacks with a blade of air. It may cause flinching.",
    "DRAGON_PULSE": "Fires a shock wave from its gaping mouth.",
    "AQUA_JET": "Lunges at the foe at speed. It strikes first.",
    "SEED_BOMB": "Slams a barrage of hard seeds down on the foe.",
    "SWITCHEROO": "Swaps items with the foe faster than the eye can see.",
    "EARTH_POWER": "Makes the ground erupt. It may lower SP. DEF.",
    "FAIRY_WIND": "Stirs up a fairy wind and strikes the foe with it.",
    "AQUA_TAIL": "Swings its tail like a vicious wave in a storm.",
    "SHADOW_SNEAK": "Extends its shadow to attack. It strikes first.",
    "BULLDOZE": "Stomps down on the ground. Lowers the foe's SPEED.",
    "ZEN_HEADBUTT": "A focused headbutt. It may cause flinching.",
    "DISARMING_VOICE": "Lets out a charming cry that never misses.",
    "DAZZLING_GLEAM": "Damages the foes with a powerful flash.",
    "ENERGY_BALL": "Fires a ball of nature's power. May lower SP. DEF.",
    "BUG_BUZZ": "A damaging sound wave. It may lower SP. DEF.",
    "GIGA_IMPACT": "A powerful charge. The user must rest next turn.",
    "DRAGON_RUSH": "A menacing tackle that may cause flinching.",
    "POWER_GEM": "Attacks with a ray of light that sparkles like gems.",
    "PLAY_NICE": "Befriends the foe to lower its ATTACK. Never misses.",
    "BRAVE_BIRD": "A low dive that also hurts the user quite a lot.",
    "HURRICANE": "Wraps the foe in a fierce wind. It may confuse.",
    "LIQUIDATION": "Slams into the foe with water. May lower DEFENSE.",
    "X_SCISSOR": "Slashes the foe with crossed scythes or claws.",
    "ICE_SHARD": "Hurls chunks of ice at the foe. It strikes first.",
    "POWER_WHIP": "Lashes the foe violently with vines or tentacles.",
    "POISON_JAB": "Stabs with a toxic barb. It may poison the foe.",
    "WILD_CHARGE": "An electric charge that also hurts the user a bit.",
    "ICICLE_CRASH": "Drops large icicles on the foe. It may cause flinching.",
    "FLASH_CANNON": "Fires a burst of light energy. May lower SP. DEF.",
    "AVALANCHE": "Hits harder if the user was hurt this turn.",
    "PSYCHO_CUT": "Cuts with psychic blades. High critical-hit ratio.",
    "INFESTATION": "Swarms the foe for 2 to 5 turns. It can't flee.",
    "BRUTAL_SWING": "Swings its body around violently to strike.",
    "AURA_SPHERE": "Fires a blast of aura power. It never misses.",
    "SNARL": "Yells as if ranting. Lowers the foe's SP. ATK.",
    "NUZZLE": "Rubs its electric cheeks on the foe to paralyze it.",
    "RAGE_POWDER": "Scatters powder to draw the foe's attacks to itself.",
    "GUNK_SHOT": "Shoots filthy garbage at the foe. May poison.",
    "SHADOW_CLAW": "Slashes with a shadow claw. High critical-hit ratio.",
    "LAVA_PLUME": "A blast of fire hits all around. It may burn.",
    "INFERNO": "Engulfs the foe in an intense fire. It may burn.",
    "MYSTICAL_FIRE": "Breathes a special hot fire. Lowers the foe's SP. ATK.",
    "CROSS_POISON": "A slash that may poison. High critical-hit ratio.",
    "TAIL_SLAP": "Strikes the foe with its hard tail 2 to 5 times.",
    "HIGH_HORSEPOWER": "Fiercely attacks the foe using its entire body.",
    "SLUDGE_WAVE": "A giant wave of sludge hits all around. May poison.",
    "DRILL_RUN": "Spins its body like a drill. High critical-hit ratio.",
    "BRANCH_POKE": "Pokes the foe with a sharply pointed branch.",
    "VACUUM_WAVE": "Punches a vacuum wave at the foe. It strikes first.",
    "LEAF_TORNADO": "Engulfs the foe in sharp leaves. May lower accuracy.",
    "SOLAR_BLADE": "Absorbs light, then slashes with it on the next turn.",
    "BULLET_PUNCH": "A punch as fast as a bullet. It strikes first.",
    "ROCK_WRECKER": "Launches a huge boulder. The user must rest next turn.",
    "NIGHT_DAZE": "Looses a dark shock wave. It may lower accuracy.",
    "GEAR_GRIND": "Throws two steel gears to hit the foe twice.",
    "THOUSAND_WAVES": "Sends a wave through the ground. The foe can't flee.",
    "LANDS_WRATH": "Gathers the land's energy to strike the foes.",
    "PSYCHIC_FANGS": "Bites with psychic power. Breaks REFLECT and the like.",
    "PRISMATIC_LASER": "Fires a prism laser. The user must rest next turn.",
    "ROAR_OF_TIME": "A roar that warps time. The user must rest next turn.",
    "DRAGON_HAMMER": "Swings its body like a hammer to strike the foe.",
    "ZING_ZAP": "A strong electric blast. It may cause flinching.",
    "SPIRIT_BREAK": "Attacks with great force. Lowers the foe's SP. ATK.",
    "FALSE_SURRENDER": "Bows its head, then stabs the foe. It never misses.",
    "FOCUS_BLAST": "Unleashes all its mental power. May lower SP. DEF.",
    "ATTACK_ORDER": "Its underlings strike. High critical-hit ratio.",
    "DEFEND_ORDER": "Underlings shield it. Raises DEF and SP. DEF.",
    "DARK_VOID": "Drags the foe into a world of darkness to sleep.",
    "HEAD_CHARGE": "A charge with its hard head that also hurts the user.",
    "SEARING_SHOT": "Torches everything around in fire. It may burn.",
    "BOLT_STRIKE": "A huge electric charge. It may paralyze.",
    "BLUE_FLARE": "Engulfs the foe in a blue flame. It may burn.",
    "SHADOW_BONE": "Strikes with a haunted bone. May lower DEFENSE.",
    "DOUBLE_IRON_BASH": "Spins and hits twice with the nut on its chest.",
    "DRUM_BEATING": "Roots strike to the drum's beat. Lowers SPEED.",
    "SNAP_TRAP": "Snares the foe in a trap for 2 to 5 turns.",
    "PYRO_BALL": "Kicks a burning stone at the foe. It may burn.",
    "OVERDRIVE": "Strums a guitar or bass to hit the foes.",
    "THUNDER_CAGE": "Traps the foe in an electric cage for 2 to 5 turns.",
    "DRAGON_ENERGY": "Turns its life force into power. Stronger at full HP.",
    "FREEZING_GLARE": "Shoots psychic power from its eyes. It may freeze.",
    "FIERY_WRATH": "An aura of wrath hits the foes. May cause flinching.",
    "GLACIAL_LANCE": "Hurls a blizzard-cloaked lance of ice at the foes.",
    "ASTRAL_BARRAGE": "Sends out a frightful mass of small ghosts.",
    "NASTY_PLOT": "Thinks bad thoughts. Sharply raises SP. ATK.",
    "HONE_CLAWS": "Sharpens its claws. Raises ATTACK and accuracy.",
    "CLOSE_COMBAT": "Fights up close. Lowers its own DEF and SP. DEF.",
    "HEAL_PULSE": "Emits a healing pulse. Restores half the HP.",
    "NOBLE_ROAR": "A noble roar. Lowers the foe's ATTACK and SP. ATK.",
    "LIFE_DEW": "Scatters mystical water. Restores some HP.",
    "TEARFUL_LOOK": "Gets teary. Lowers the foe's ATTACK and SP. ATK.",
    "LUNGE": "Lunges at the foe with all its might. Lowers ATTACK.",
    "POWER_UP_PUNCH": "Each hard punch raises the user's ATTACK.",
    "AUTOTOMIZE": "Sheds part of its body. Sharply raises SPEED.",
    "LOW_SWEEP": "A swift low attack. Lowers the foe's SPEED.",
    "COTTON_GUARD": "Wraps itself in fluff. Drastically ups DEFENSE.",
    "BREAKING_SWIPE": "Swings its tough tail. Lowers the foes' ATTACK.",
    "SHIFT_GEAR": "Spins its gears. Raises ATTACK, sharply ups SPEED.",
    "ELECTROWEB": "Traps the foes in an electric net. Lowers SPEED.",
    "CONFIDE": "Tells the foe a secret. Lowers the foe's SP. ATK.",
    "CHATTER": "Chatters noisily at the foe. It confuses the foe.",
    "RELIC_SONG": "Sings an ancient song. It may put foes to sleep.",
    "GLACIATE": "Blows freezing air at the foes. Lowers SPEED.",
    "V_CREATE": "A fiery charge. Lowers its own DEF, SP. DEF, SPEED.",
    "DIAMOND_STORM": "A storm of diamonds. May sharply raise DEFENSE.",
    "HYPERSPACE_FURY": "Unleashes many arms in a flurry. Lowers its DEF.",
    "FLORAL_HEALING": "Restores half the foe's HP with flowers.",
    "TROP_KICK": "An intense tropical kick. Lowers the foe's ATTACK.",
    "CLANGING_SCALES": "Rubs its scales loudly. Lowers its own DEFENSE.",
    "AURA_WHEEL": "Fires its stored energy. Raises the user's SPEED.",
    "APPLE_ACID": "Attacks with acidic apple juice. Lowers SP. DEF.",
    "GRAV_APPLE": "Drops an apple from high up. Lowers DEFENSE.",
    "SHELL_SIDE_ARM": "Fires a shell at the foe. It may poison the foe.",
    "THUNDEROUS_KICK": "A lightning-fast kick. Lowers the foe's DEFENSE.",
}

# Moves whose effect Gen 3 lacks but whose PokeAPI `meta` describes it completely (stat changes,
# a status chance, flinch, drain/recoil, healing): src/move_effects.lua runs that description.
# A status move gets effect byte CUSTOM_EFFECT (unused by the cart, mapped to that handler);
# an attack is a plain hit (effect 0) and its extra runs after the hit.
CUSTOM_EFFECT = 250
GENERIC_CATEGORIES = {"net-good-stats", "damage-raise", "damage-lower", "damage-ailment", "heal", "damage-heal"}
# in those categories, but with a condition or mechanic the description leaves out
GENERIC_EXCLUDE = {
    "aromatic-mist", "decorate", "magnetic-flux", "gear-up",          # a partner only
    "captivate", "venom-drench", "rototiller", "stuff-cheeks",         # conditions
    "parting-shot", "throat-chop",                                     # switching, silencing
    "geomancy", "freeze-shock", "ice-burn",                            # a charging turn
    "clangorous-soul", "no-retreat",                                   # HP cost, trapping itself
}
STAT_KEY = {"attack": "attack", "defense": "defense", "special-attack": "spAtk",
            "special-defense": "spDef", "speed": "speed", "accuracy": "accuracy", "evasion": "evasion"}
AILMENT = {"burn": "BURN", "freeze": "FREEZE", "paralysis": "PARALYSIS", "poison": "POISON",
           "sleep": "SLEEP", "confusion": "CONFUSION"}
SELF_TARGETS = {"user", "user-and-allies", "users-field"}


def generic_extra(m: dict[str, Any]) -> dict[str, Any] | None:
    """The extra effect src/move_effects.lua runs, from PokeAPI's meta; None if it can't."""
    if m["name"] in GENERIC_EXCLUDE:
        return None
    meta = m.get("meta") or {}
    cat = (meta.get("category") or {}).get("name")
    if cat not in GENERIC_CATEGORIES:
        return None
    changes = {}
    for sc in m.get("stat_changes") or []:
        key = STAT_KEY.get(sc["stat"]["name"])
        if not key:
            return None
        changes[key] = sc["change"]
    ail = (meta.get("ailment") or {}).get("name", "none")
    if ail != "none" and ail not in AILMENT:
        return None
    extra: dict[str, Any] = {"kind": "hit" if (m["power"] or 0) > 0 else "status"}
    selfish = cat == "damage-raise" or m["target"]["name"] in SELF_TARGETS
    if changes:
        extra["self" if selfish else "foe"] = changes
        extra["chance"] = meta.get("stat_chance") or 100
    if ail != "none":
        extra["ailment"] = AILMENT[ail]
        extra["ailmentChance"] = meta.get("ailment_chance") or 100
    if meta.get("flinch_chance"):
        extra["flinch"] = meta["flinch_chance"]
    if meta.get("drain"):
        extra["drain"] = meta["drain"]
    if meta.get("healing"):
        extra["heal"] = meta["healing"]
        extra["healTarget"] = "self" if m["target"]["name"] in SELF_TARGETS else "foe"
    if m["name"] == "shore-up":
        extra["sandHeal"] = 67
    if len(extra) == 1:
        return None
    return extra


# PokeAPI contest_type -> the cart's contest category (pokeemerald CONTEST_CATEGORY_*)
CONTEST_CATEGORY = {"cool": 0, "beauty": 1, "cute": 2, "smart": 3, "tough": 4}


def en(entries: list[dict[str, Any]], key: str) -> str | None:
    for e in entries:
        if e["language"]["name"] == "en":
            return e[key]
    return None


def effect_text(move: dict[str, Any]) -> str | None:
    t = en(move.get("effect_entries", []), "short_effect")
    return t.strip() if t else None


def url_id(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[1])


def majority(pairs: dict[Any, collections.Counter]) -> dict[Any, int]:
    return {k: c.most_common(1)[0][0] for k, c in pairs.items()}


def parse_contest(path: Path) -> dict[int, dict[str, int]]:
    """id -> {category, effect} from an imported cart's pokemon/contest_moves.lua."""
    src = path.read_text(encoding="utf-8")
    body = src[src.find("  moves = {"):]
    out = {}
    for m in re.finditer(r"\[(\d+)\] = \{\s*category = (\d+),.*?effect = (\d+),", body, re.S):
        out[int(m.group(1))] = {"category": int(m.group(2)), "effect": int(m.group(3))}
    return out


def showdown(cache: Path) -> dict[str, Any]:
    path = cache / "showdown_moves.json"
    if not path.exists():
        req = urllib.request.Request(SHOWDOWN, headers={"User-Agent": "national_dex_gen3-builder/1.0"})
        path.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    return json.loads(path.read_text(encoding="utf-8"))


def sd_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def wrap(text: str, cols: int, rows: int) -> str | None:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        if len(w) > cols:
            return None
        if not cur:
            cur = w
        elif len(cur) + 1 + len(w) <= cols:
            cur += " " + w
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return "\n".join(lines) if 0 < len(lines) <= rows else None


def flavor_candidates(move: dict[str, Any]) -> list[str]:
    seen, out = set(), []
    for e in reversed(move.get("flavor_text_entries", [])):
        if e["language"]["name"] != "en":
            continue
        t = re.sub(r"\s+", " ", e["flavor_text"].replace("\u00ad", "")).strip()
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def describe(move: dict[str, Any], cols: int, rows: int) -> str | None:
    """The newest English flavor text that fits, else the first sentence of one that does."""
    texts = flavor_candidates(move)
    for t in texts:
        w = wrap(t, cols, rows)
        if w:
            return w
    for t in sorted(texts, key=len):
        first = re.split(r"(?<=[.!])\s", t)[0]
        w = wrap(first, cols, rows)
        if w:
            return w
    return None


def text_for(rid: str, move: dict[str, Any], cols: int, rows: int) -> str | None:
    """The hand-written text if there is one, else an official one that fits; Gen 3 spells it
    POKeMON (with the accent)."""
    t = wrap(DESCRIPTIONS[rid], cols, rows) if rid in DESCRIPTIONS else describe(move, cols, rows)
    return t.replace("Pokémon", "POKéMON") if t else None


def display_name(move: dict[str, Any]) -> str:
    name = (en(move["names"], "name") or move["name"]).upper().replace("\u2019", "'")
    return NAME_OVERRIDES.get(name, name)


def engine_id(move: dict[str, Any]) -> str:
    return bs.engine_id(move["name"])


def used_moves(api: bs.API) -> dict[int, int]:
    """Newer move id -> how many species and forms learn it (level-up or egg)."""
    use: collections.Counter = collections.Counter()

    def mons():
        for dex in range(bs.FIRST_DEX, bs.LAST_DEX + 1):
            sp = api.get(f"/pokemon-species/{dex}")
            yield api.get(next(v for v in sp["varieties"] if v["is_default"])["pokemon"]["url"])
        for fid, base, _form, slug in form_list.FORMS:
            try:
                yield api.get(f"/pokemon/{slug}")
            except Exception:
                continue

    for pokemon in mons():
        ids = {mid for _, mid in bs.modern_learnset(pokemon)}
        for move in pokemon["moves"]:
            for d in move["version_group_details"]:
                if d["move_learn_method"]["name"] == "egg":
                    ids.add(url_id(move["move"]["url"]))
        for mid in ids:
            if mid > bs.MAX_MOVE_ID:
                use[mid] += 1
    return dict(use)


def existing_indices(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    src = path.read_text(encoding="utf-8")
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'id = "(\w+)", index = (\d+)', src)}


def build(api: bs.API, cart_dir: Path, contest_path: Path, cache: Path, out: Path) -> tuple[list[dict], list]:
    cart = move_map.parse_cart(cart_dir)
    contest = parse_contest(contest_path)
    sd = showdown(cache)
    effect_pairs: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    target_pairs: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    ceffect_pairs: dict[int, collections.Counter] = collections.defaultdict(collections.Counter)
    for i in range(1, bs.MAX_MOVE_ID + 1):
        m = api.get(f"/move/{i}")
        effect_pairs[effect_text(m)][cart[i]["effect"]] += 1
        target_pairs[m["target"]["name"]][cart[i]["target"]] += 1
        if m.get("contest_effect") and i in contest:
            ceffect_pairs[url_id(m["contest_effect"]["url"])][contest[i]["effect"]] += 1
    effect_of, target_of, ceffect_of = majority(effect_pairs), majority(target_pairs), majority(ceffect_pairs)
    # an effect's cart moves are all attacks, all status moves, or a mix
    damaging: dict[int, set[bool]] = collections.defaultdict(set)
    for i in range(1, bs.MAX_MOVE_ID + 1):
        damaging[cart[i]["effect"]].add(cart[i]["power"] > 0)

    # the closest cart move (tools/move_map.py's scoring): its animation is borrowed
    use_ids = sorted(used_moves(api))
    api_moves = {i: api.get(f"/move/{i}") for i in range(1, bs.MAX_MOVE_ID + 1)}
    api_moves.update({i: api.get(f"/move/{i}") for i in use_ids})
    mapper = move_map.MoveMapper(cart, api_moves, bs.MAX_MOVE_ID)

    keep = existing_indices(out)
    next_index = max([FIRST_INDEX - 1, *keep.values()]) + 1
    rows, skipped = [], []
    use = used_moves(api)
    for mid in sorted(use, key=lambda k: (-use[k], k)):
        m = api.get(f"/move/{mid}")
        text = effect_text(m)
        extra = None
        effect = effect_of.get(text)
        if effect is not None and ((m["power"] or 0) > 0) not in damaging[effect]:
            # an attack must map onto an attacking effect, a status move onto a status one
            # (Thousand Waves shares Mean Look's text, but Mean Look's effect deals no damage)
            effect = None
        if effect is None:
            extra = generic_extra(m)
            if extra:
                effect = CUSTOM_EFFECT if extra["kind"] == "status" else 0
        if effect is None or m["target"]["name"] not in target_of:
            skipped.append((use[mid], m["name"], text))
            continue
        s = sd.get(sd_key(m["name"]), {})
        f = s.get("flags", {})
        power = m["power"] or 0
        flags = ((1 if f.get("contact") else 0) | (2 if f.get("protect") else 0)
                 | (4 if f.get("reflectable") else 0) | (8 if f.get("snatch") else 0)
                 | (16 if f.get("mirror") else 0)
                 | (32 if power > 0 and not (s.get("secondary") or s.get("secondaries")) else 0))
        mtype = m["type"]["name"].upper()
        rid = engine_id(m)
        name = display_name(m)
        row = {
            "id": rid, "index": keep.get(rid, 0), "api": mid, "name": name,
            "full": (en(m["names"], "name") or m["name"]).replace("’", "'"),
            "type": mtype, "power": power, "accuracy": m["accuracy"] or 0, "pp": m["pp"] or 5,
            "effect": effect, "secondaryChance": 0 if extra else (m.get("effect_chance") or 0),
            "extra": extra,
            "target": target_of[m["target"]["name"]], "priority": m["priority"] or 0, "flags": flags,
            "frlg": text_for(rid, m, FRLG_COLS, FRLG_ROWS), "rse": text_for(rid, m, RSE_COLS, RSE_ROWS),
            "contest": {
                "category": CONTEST_CATEGORY.get((m.get("contest_type") or {}).get("name"), 0),
                "effect": ceffect_of.get(url_id(m["contest_effect"]["url"]), 0) if m.get("contest_effect") else 0,
            },
            "look": (mapper.ranked(mid) or [1])[0],
            "uses": use[mid],
        }
        if not row["index"]:
            row["index"] = next_index
            next_index += 1
        rows.append(row)
    rows.sort(key=lambda r: r["index"])
    return rows, skipped


def lua_value(v: Any) -> str:
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua_value(x)}" for k, x in v.items()) + " }"
    if isinstance(v, str):
        return lua_str(v)
    return str(v)


def lua_str(s: str | None) -> str:
    if s is None:
        return "nil"
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def write(rows: list[dict], path: Path) -> None:
    lines = [
        "-- Generated by tools/build_moves.py. Do not edit by hand.",
        "-- Moves newer than Gen 3 that work like a Gen 3 move (the cart's own effect ids), at",
        "-- append-only indices from 355 (saved in Pokemon's moves). type FAIRY is registered as",
        "-- NORMAL and turned Fairy by src/types.lua. frlg/rse: the summary text for each box.",
        "-- look: the cart move whose battle animation the move borrows.",
        "return {",
    ]
    for r in rows:
        c = r["contest"]
        lines.append(
            f'  {{ id = "{r["id"]}", index = {r["index"]}, api = {r["api"]}, name = {lua_str(r["name"])}, '
            f'full = {lua_str(r["full"])}, '
            f'type = "{r["type"]}", power = {r["power"]}, accuracy = {r["accuracy"]}, pp = {r["pp"]}, '
            f'effect = {r["effect"]}, secondaryChance = {r["secondaryChance"]}, target = {r["target"]}, '
            f'priority = {r["priority"]}, flags = {r["flags"]}, look = {r["look"]}, '
            f'contest = {{ category = {c["category"]}, effect = {c["effect"]} }},'
            + (f' extra = {lua_value(r["extra"])},' if r.get("extra") else '') + '\n'
            f'    frlg = {lua_str(r["frlg"])},\n    rse = {lua_str(r["rse"])} }},')
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    gen1 = ROOT.parent / "gen1recomp"
    p.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    p.add_argument("--cart", type=Path, default=gen1 / "firered" / "data" / "generated" / "gba" / "pokemon")
    p.add_argument("--contest", type=Path,
                   default=gen1 / "emerald" / "data" / "generated" / "gba" / "pokemon" / "contest_moves.lua")
    p.add_argument("--out", type=Path, default=ROOT / "data" / "moves.lua")
    args = p.parse_args()
    rows, skipped = build(bs.API(args.cache), args.cart, args.contest, args.cache, args.out)
    problems = [r for r in rows if len(r["name"]) > NAME_LIMIT or not r["frlg"] or not r["rse"]]
    for r in problems:
        why = []
        if len(r["name"]) > NAME_LIMIT:
            why.append(f"name {r['name']!r} is {len(r['name'])} letters")
        if not r["frlg"]:
            why.append("no FRLG text fits")
        if not r["rse"]:
            why.append("no RSE text fits")
        print(f"  FIX {r['id']}: {'; '.join(why)}")
    write(rows, args.out)
    report = args.cache / "moves_new.txt"
    report.write_text("\n".join(f"{n:4} {name}: {text}" for n, name, text in sorted(skipped, reverse=True)),
                      encoding="utf-8")
    real = sum(r["uses"] for r in rows)
    print(f"{len(rows)} real moves ({real} species/form uses) -> {args.out}; "
          f"{len(skipped)} keep a substitute (list: {report})")


if __name__ == "__main__":
    main()
