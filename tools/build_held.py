#!/usr/bin/env python3
"""
Build the held items newer than each game (data/held_items.lua) and their Bag icons
(assets/items/held_icons.png, 24x24 cells).

Every game gets the held items of the generations after it: Red / Blue / Yellow the Gen 3-9 ones
(Gold's own come from data/gen12/held.lua), Gold / Silver / Crystal the Gen 3-9 ones, FireRed to
Emerald the Gen 4-9 ones. One list serves all three: at load a game skips an item it already has
(matched by name, so Emerald keeps its own CHOICE BAND), and the rest are registered as its items.
What each item does in battle is `effect` below, written for this mod from the games' behaviour
(src/held/effects.lua runs it on every game).

HELD is append-only: an item's position is its number (INDEX_BASE + position - 1), and that number
is what saves keep in a Pokemon's held item and the Bag. Add new items at the end.

Names, prices and Bag text come from PokéAPI (cached in tools/.cache); icons from the pokesprite
pack (--icons <pokesprite>/items) or, for the newest items, the Gen 9 Pack's Graphics/Items
(--extra-icons). Neither pack ships: the atlas is built from them.

Usage:
    python tools/build_held.py --icons <pokesprite>/items --extra-icons "<Gen 9 Pack>/Graphics/Items"
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_species as bs  # noqa: E402
from desc_width import LIMIT, width  # noqa: E402

INDEX_BASE = 1300     # Gen 3 item numbers (cap 2047); TMs are 1100+, the evolution items 900+
ICON_SIZE = 24
NAME_MAX = 12         # Gold's item names hold 12 characters (Red's and Gen 3's more)
GOLD_COLUMNS = 18     # Gold's Pack description: two lines of 18


def e(kind: str, **kw: Any) -> dict[str, Any]:
    kw["kind"] = kind
    return kw


TYPES = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
         "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
PLATES = {"flame": "fire", "splash": "water", "zap": "electric", "meadow": "grass",
          "icicle": "ice", "fist": "fighting", "toxic": "poison", "earth": "ground",
          "sky": "flying", "mind": "psychic", "insect": "bug", "stone": "rock",
          "spooky": "ghost", "draco": "dragon", "dread": "dark", "iron": "steel", "pixie": "fairy"}
RESIST = {"occa": "fire", "passho": "water", "wacan": "electric", "rindo": "grass",
          "yache": "ice", "chople": "fighting", "kebia": "poison", "shuca": "ground",
          "coba": "flying", "payapa": "psychic", "tanga": "bug", "charti": "rock",
          "kasib": "ghost", "haban": "dragon", "colbur": "dark", "babiri": "steel",
          "chilan": "normal", "roseli": "fairy"}

# (slug, effect). Gen 3's own held items and berries come first (new on Red and Gold), then
# Gen 4 to 9's. APPEND-ONLY.
HELD: list[tuple[str, dict[str, Any]]] = [
    # Gen 3
    ("choice-band", e("choice", stat="attack")),
    ("shell-bell", e("shellBell")),
    ("white-herb", e("whiteHerb")),
    ("mental-herb", e("mentalHerb")),
    ("macho-brace", e("halfSpeed")),
    ("soothe-bell", e("friendship")),
    ("lax-incense", e("evasion", mult=0.9)),
    ("sea-incense", e("boostType", type="WATER", mult=1.2)),
    ("silk-scarf", e("boostType", type="NORMAL", mult=1.2)),
    ("deep-sea-tooth", e("speciesStat", species=[366], stat="spAtk", mult=2)),
    ("deep-sea-scale", e("speciesStat", species=[366], stat="spDef", mult=2)),
    ("soul-dew", e("speciesType", species=[380, 381], types=["PSYCHIC", "DRAGON"], mult=1.2)),
    ("exp-share", e("expShare")),
    ("cheri-berry", e("berryCure", status="PAR")),
    ("chesto-berry", e("berryCure", status="SLP")),
    ("pecha-berry", e("berryCure", status="PSN")),
    ("rawst-berry", e("berryCure", status="BRN")),
    ("aspear-berry", e("berryCure", status="FRZ")),
    ("leppa-berry", e("berryPP", amount=10)),
    ("oran-berry", e("berryHeal", amount=10)),
    ("persim-berry", e("berryCure", status="CONFUSION")),
    ("lum-berry", e("berryCure", status="ALL")),
    ("sitrus-berry", e("berryHeal", fraction=0.25)),
    ("figy-berry", e("berryPinch", fraction=1 / 3, dislike="attack")),
    ("wiki-berry", e("berryPinch", fraction=1 / 3, dislike="spAtk")),
    ("mago-berry", e("berryPinch", fraction=1 / 3, dislike="speed")),
    ("aguav-berry", e("berryPinch", fraction=1 / 3, dislike="spDef")),
    ("iapapa-berry", e("berryPinch", fraction=1 / 3, dislike="defense")),
    ("liechi-berry", e("berryStat", stat="attack")),
    ("ganlon-berry", e("berryStat", stat="defense")),
    ("salac-berry", e("berryStat", stat="speed")),
    ("petaya-berry", e("berryStat", stat="spAtk")),
    ("apicot-berry", e("berryStat", stat="spDef")),
    ("lansat-berry", e("berryCrit")),
    ("starf-berry", e("berryStarf")),
    ("enigma-berry", e("berryEnigma")),
    # Gen 4
    ("choice-scarf", e("choice", stat="speed")),
    ("choice-specs", e("choice", stat="spAtk")),
    ("life-orb", e("lifeOrb")),
    ("expert-belt", e("expertBelt")),
    ("muscle-band", e("boostCategory", category="physical", mult=1.1)),
    ("wise-glasses", e("boostCategory", category="special", mult=1.1)),
    ("metronome", e("metronome")),
    ("focus-sash", e("focusSash")),
    ("black-sludge", e("blackSludge")),
    ("toxic-orb", e("inflictSelf", status="TOX")),
    ("flame-orb", e("inflictSelf", status="BRN")),
    ("sticky-barb", e("stickyBarb")),
    ("iron-ball", e("ironBall")),
    ("lagging-tail", e("moveLast")),
    ("full-incense", e("moveLast")),
    ("shed-shell", e("shedShell")),
    ("big-root", e("bigRoot")),
    ("grip-claw", e("gripClaw")),
    ("light-clay", e("lightClay")),
    ("damp-rock", e("weatherRock", weather="rain")),
    ("heat-rock", e("weatherRock", weather="sun")),
    ("smooth-rock", e("weatherRock", weather="sand")),
    ("icy-rock", e("weatherRock", weather="hail")),
    ("power-herb", e("powerHerb")),
    ("zoom-lens", e("zoomLens")),
    ("wide-lens", e("accuracy", mult=1.1)),
    ("razor-claw", e("critUp")),
    ("razor-fang", e("flinch", chance=10)),
    ("quick-powder", e("speciesStat", species=[132], stat="speed", mult=2)),
    ("adamant-orb", e("speciesType", species=[483], types=["STEEL", "DRAGON"], mult=1.2)),
    ("lustrous-orb", e("speciesType", species=[484], types=["WATER", "DRAGON"], mult=1.2)),
    ("griseous-orb", e("speciesType", species=[487], types=["GHOST", "DRAGON"], mult=1.2)),
    ("odd-incense", e("boostType", type="PSYCHIC", mult=1.2)),
    ("rock-incense", e("boostType", type="ROCK", mult=1.2)),
    ("rose-incense", e("boostType", type="GRASS", mult=1.2)),
    ("wave-incense", e("boostType", type="WATER", mult=1.2)),
    ("luck-incense", e("money")),
    ("pure-incense", e("encounters")),
    ("destiny-knot", e("destinyKnot")),
    ("power-weight", e("powerItem", stat="hp")),
    ("power-bracer", e("powerItem", stat="attack")),
    ("power-belt", e("powerItem", stat="defense")),
    ("power-lens", e("powerItem", stat="spAtk")),
    ("power-band", e("powerItem", stat="spDef")),
    ("power-anklet", e("powerItem", stat="speed")),
]
HELD += [(f"{name}-plate", e("boostType", type=t.upper(), mult=1.2)) for name, t in PLATES.items()]
HELD += [(f"{name}-berry", e("berryResist", type=t.upper())) for name, t in RESIST.items()
         if name != "roseli"]
HELD += [
    ("micle-berry", e("berryMicle")),
    ("custap-berry", e("berryCustap")),
    ("jaboca-berry", e("berryRetaliate", category="physical")),
    ("rowap-berry", e("berryRetaliate", category="special")),
    # Gen 5
    ("eviolite", e("eviolite")),
    ("rocky-helmet", e("rockyHelmet")),
    ("air-balloon", e("airBalloon")),
    ("red-card", e("redCard")),
    ("ring-target", e("ringTarget")),
    ("binding-band", e("bindingBand")),
    ("absorb-bulb", e("statOnHit", type="WATER", stats={"spAtk": 1})),
    ("cell-battery", e("statOnHit", type="ELECTRIC", stats={"attack": 1})),
    ("eject-button", e("ejectButton")),
    ("float-stone", e("floatStone")),
]
HELD += [(f"{t}-gem", e("gem", type=t.upper())) for t in TYPES if t != "fairy"]
HELD += [
    # Gen 6
    ("assault-vest", e("assaultVest")),
    ("safety-goggles", e("safetyGoggles")),
    ("weakness-policy", e("statOnHit", superEffective=True, stats={"attack": 2, "spAtk": 2})),
    ("luminous-moss", e("statOnHit", type="WATER", stats={"spDef": 1})),
    ("snowball", e("statOnHit", type="ICE", stats={"attack": 1})),
    ("roseli-berry", e("berryResist", type="FAIRY")),
    ("kee-berry", e("statOnHit", category="physical", stats={"defense": 1}, berry=True)),
    ("maranga-berry", e("statOnHit", category="special", stats={"spDef": 1}, berry=True)),
    ("fairy-gem", e("gem", type="FAIRY")),
    # Gen 7
    ("protective-pads", e("protectivePads")),
    ("terrain-extender", e("terrainExtender")),
    ("electric-seed", e("seed", terrain="ELECTRIC", stat="defense")),
    ("grassy-seed", e("seed", terrain="GRASSY", stat="defense")),
    ("misty-seed", e("seed", terrain="MISTY", stat="spDef")),
    ("psychic-seed", e("seed", terrain="PSYCHIC", stat="spDef")),
    ("adrenaline-orb", e("adrenalineOrb")),
    # Gen 8
    ("heavy-duty-boots", e("heavyDutyBoots")),
    ("utility-umbrella", e("utilityUmbrella")),
    ("blunder-policy", e("blunderPolicy")),
    ("throat-spray", e("throatSpray")),
    ("eject-pack", e("ejectPack")),
    ("room-service", e("roomService")),
    # Gen 9
    ("covert-cloak", e("covertCloak")),
    ("clear-amulet", e("clearAmulet")),
    ("loaded-dice", e("loadedDice")),
    ("punching-glove", e("punchingGlove")),
    ("mirror-herb", e("mirrorHerb")),
    ("booster-energy", e("boosterEnergy")),
    ("ability-shield", e("abilityShield")),
    ("fairy-feather", e("boostType", type="FAIRY", mult=1.2)),
]

# Shorter names where the item's own is longer than NAME_MAX; and the classic spellings.
NAME_OVERRIDES = {
    "heavy-duty-boots": "HEAVY BOOTS", "utility-umbrella": "UMBRELLA", "protective-pads": "PROT. PADS",
    "terrain-extender": "TERRAIN EXT.", "weakness-policy": "WEAKNESS POL", "blunder-policy": "BLUNDER POL.",
    "adrenaline-orb": "ADRENA. ORB", "booster-energy": "BOOSTER NRG", "punching-glove": "PUNCH GLOVE",
    "ability-shield": "ABIL. SHIELD", "safety-goggles": "GOGGLES", "deep-sea-tooth": "DEEPSEATOOTH",
    "deep-sea-scale": "DEEPSEASCALE", "electric-seed": "ELEC. SEED", "psychic-seed": "PSYCHIC SEED",
    "luminous-moss": "LUMIN. MOSS", "griseous-orb": "GRISEOUS ORB", "lustrous-orb": "LUSTROUS ORB",
    "binding-band": "BINDING BAND", "aspear-berry": "ASPEAR BERRY", "petaya-berry": "PETAYA BERRY",
    "apicot-berry": "APICOT BERRY", "iapapa-berry": "IAPAPA BERRY", "liechi-berry": "LIECHI BERRY",
    "ganlon-berry": "GANLON BERRY", "lansat-berry": "LANSAT BERRY", "enigma-berry": "ENIGMA BERRY",
    "chesto-berry": "CHESTO BERRY", "persim-berry": "PERSIM BERRY", "sitrus-berry": "SITRUS BERRY",
    "maranga-berry": "MARANGA BRY", "custap-berry": "CUSTAP BERRY", "jaboca-berry": "JABOCA BERRY",
    "passho-berry": "PASSHO BERRY", "chople-berry": "CHOPLE BERRY", "payapa-berry": "PAYAPA BERRY",
    "charti-berry": "CHARTI BERRY", "babiri-berry": "BABIRI BERRY", "chilan-berry": "CHILAN BERRY",
    "colbur-berry": "COLBUR BERRY", "roseli-berry": "ROSELI BERRY", "electric-gem": "ELECTRIC GEM",
    "fighting-gem": "FIGHTING GEM", "psychic-gem": "PSYCHIC GEM", "meadow-plate": "MEADOW PLATE",
    "icicle-plate": "ICICLE PLATE", "insect-plate": "INSECT PLATE", "spooky-plate": "SPOOKY PLATE",
    "splash-plate": "SPLASH PLATE", "eject-button": "EJECT BUTTON", "fairy-feather": "FAIRY FEATHR",
    "power-anklet": "POWER ANKLET", "power-bracer": "POWER BRACER", "power-weight": "POWER WEIGHT",
    "rose-incense": "ROSE INCENSE", "rock-incense": "ROCK INCENSE", "wave-incense": "WAVE INCENSE",
    "luck-incense": "LUCK INCENSE", "pure-incense": "PURE INCENSE", "full-incense": "FULL INCENSE",
    "odd-incense": "ODD INCENSE", "lax-incense": "LAX INCENSE", "sea-incense": "SEA INCENSE",
}

# Shop prices where PokéAPI has none (0)
DEFAULT_PRICE = {"berry": 200, "gem": 200, "plate": 1000, "": 3000}

# PNGs in the Gen 9 Pack named without separators; pokesprite names: berries and gems by their
# first word, plates by theirs
EXTRA_ICON = {"covert-cloak", "clear-amulet", "loaded-dice", "punching-glove", "mirror-herb",
              "booster-energy", "ability-shield", "fairy-feather"}


def engine_id(slug: str) -> str:
    return slug.upper().replace("-", "_")


def display_name(api: bs.API, slug: str) -> str:
    if slug in NAME_OVERRIDES:
        return NAME_OVERRIDES[slug]
    name = (bs.english(api.get(f"/item/{slug}").get("names", []), "name") or slug.replace("-", " "))
    name = name.upper().replace("É", "E")
    if len(name) > NAME_MAX:
        raise SystemExit(f"{slug}: '{name}' is longer than {NAME_MAX}; add it to NAME_OVERRIDES")
    return name


def lines_fit(text: str, limit_fn, max_lines: int) -> list[str] | None:
    words, lines, cur = text.split(), [], ""
    for w in words:
        nxt = (cur + " " + w).strip()
        if limit_fn(nxt):
            cur = nxt
        else:
            if not cur:
                return None
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines if len(lines) <= max_lines else None


STAT_WORD = {"attack": "ATTACK", "defense": "DEFENSE", "spAtk": "SP. ATK", "spDef": "SP. DEF",
             "speed": "SPEED", "hp": "HP"}


def own_text(effect: dict[str, Any]) -> str | None:
    """A short sentence of our own for what the item does, for when no official text fits."""
    k = effect["kind"]
    t = effect.get("type", "").title() if effect.get("type") else ""
    st = STAT_WORD.get(effect.get("stat", ""), "")
    return {
        "choice": f"Boosts {st} but allows only one move.",
        "boostType": f"Powers up {t}-type moves.",
        "boostCategory": ("Powers up physical moves." if effect.get("category") == "physical"
                          else "Powers up special moves."),
        "gem": f"Powers up a {t}-type move once.",
        "berryResist": f"Weakens a super-effective {t}-type hit.",
        "berryCure": "A BERRY that heals a status problem.",
        "berryHeal": "A BERRY that restores HP in a pinch.",
        "berryPinch": "A BERRY that restores HP in a pinch.",
        "berryStat": f"A BERRY that raises {st} in a pinch.",
        "berryPP": "A BERRY that restores PP.",
        "berryCrit": "A BERRY that ups critical hits in a pinch.",
        "berryStarf": "A BERRY that sharply raises a stat in a pinch.",
        "berryEnigma": "A BERRY that heals when hit super effectively.",
        "berryMicle": "A BERRY that ups accuracy in a pinch.",
        "berryCustap": "A BERRY that lets it move first in a pinch.",
        "berryRetaliate": "A BERRY that hurts the foe when hit.",
        "lifeOrb": "Boosts moves, but costs HP each hit.",
        "expertBelt": "Powers up super-effective moves.",
        "metronome": "Powers up a move used in a row.",
        "focusSash": "Survives a KO from full HP once.",
        "eviolite": "Boosts defenses if it can still evolve.",
        "assaultVest": "Raises SP. DEF but bars status moves.",
        "rockyHelmet": "Hurts a foe that makes contact.",
        "airBalloon": "Floats above GROUND moves until hit.",
        "statOnHit": "Raises stats when hit by some moves.",
        "weatherRock": "Makes the user's weather last longer.",
        "lightClay": "Makes the user's screens last longer.",
        "terrainExtender": "Makes the user's terrain last longer.",
        "seed": "Raises a stat on a terrain, once.",
        "speciesStat": "Boosts a certain POKeMON's stat.",
        "speciesType": "Boosts a certain POKeMON's moves.",
        "powerItem": f"Raises {st} growth but lowers SPEED.",
        "halfSpeed": "Promotes growth but lowers SPEED.",
        "inflictSelf": "Gives its holder a status in battle.",
        "moveLast": "Makes its holder move last.",
        "blackSludge": "Heals POISON types; hurts the rest.",
        "stickyBarb": "Hurts its holder; it may stick to foes.",
        "ironBall": "Lowers SPEED and grounds its holder.",
        "shedShell": "Lets its holder always switch out.",
        "bigRoot": "Ups the HP restored by draining.",
        "gripClaw": "Makes binding moves last longer.",
        "bindingBand": "Powers up binding moves.",
        "powerHerb": "Skips a move's charge turn once.",
        "zoomLens": "Ups accuracy if it moves after the foe.",
        "accuracy": "Slightly ups the accuracy of moves.",
        "critUp": "Ups the critical-hit ratio.",
        "flinch": "May make the foe flinch.",
        "money": "Doubles the prize money from battles.",
        "encounters": "Repels wild POKeMON a little.",
        "destinyKnot": "Shares infatuation with the foe.",
        "evasion": "Slightly lowers the foe's accuracy.",
        "friendship": "Helps its holder grow fond of you.",
        "expShare": "Shares EXP. POINTS from battles.",
        "redCard": "Sends out the attacker's partner when hit.",
        "ringTarget": "Removes its holder's type immunities.",
        "ejectButton": "Switches its holder out when hit.",
        "floatStone": "Halves its holder's weight.",
        "safetyGoggles": "Protects from weather and powder.",
        "protectivePads": "Protects from contact effects.",
        "adrenalineOrb": "Raises SPEED when intimidated.",
        "heavyDutyBoots": "Protects from entry hazards.",
        "utilityUmbrella": "Shields its holder from rain and sun.",
        "blunderPolicy": "Sharply raises SPEED on a miss.",
        "throatSpray": "Raises SP. ATK after a sound move.",
        "ejectPack": "Switches out when its stats fall.",
        "roomService": "Lowers SPEED in TRICK ROOM.",
        "covertCloak": "Protects from added effects of moves.",
        "clearAmulet": "Stops foes lowering its stats.",
        "loadedDice": "Multi-strike moves hit more often.",
        "punchingGlove": "Powers up punches, no contact.",
        "mirrorHerb": "Copies a foe's stat boosts once.",
        "boosterEnergy": "Powers up Paradox POKeMON once.",
        "abilityShield": "Keeps its holder's ability safe.",
        "whiteHerb": "Restores lowered stats once.",
        "mentalHerb": "Frees it from move-limiting effects.",
        "shellBell": "Restores HP as it deals damage.",
        "choiceLock": None,
    }.get(k)


def descriptions(api: bs.API, slug: str, effect: dict[str, Any] | None = None) -> tuple[str, str]:
    """(Gen 3 Bag text: 3 lines within LIMIT px; Gold's: 2 lines of 18), from the newest English
    flavor text that fits each."""
    item = api.get(f"/item/{slug}")
    texts = [x["text"] for x in item.get("flavor_text_entries", [])
             if x.get("language", {}).get("name") == "en"]
    texts = [" ".join(bs._flavor_clean(t).replace("’", "'").replace("é", "e").split()) for t in texts]
    g3 = g2 = None
    for t in reversed(texts):
        if g3 is None:
            ls = lines_fit(t, lambda s: width(s) <= LIMIT, 3)
            if ls:
                g3 = "\n".join(ls)
        if g2 is None:
            ls = lines_fit(t.upper(), lambda s: len(s) <= GOLD_COLUMNS, 2)
            if ls:
                g2 = "<NEXT>".join(ls)
    mine = effect and own_text(effect)
    if mine:
        if g3 is None:
            ls = lines_fit(mine, lambda s: width(s) <= LIMIT, 3)
            if ls:
                g3 = "\n".join(ls)
        if g2 is None:
            ls = lines_fit(mine.upper(), lambda s: len(s) <= GOLD_COLUMNS, 2)
            if ls:
                g2 = "<NEXT>".join(ls)
    berry = slug.endswith("-berry")
    g3 = g3 or ("A BERRY to be\nheld in battle." if berry else "An item to be held\nby a POKeMON.")
    g2 = g2 or ("A BERRY TO BE<NEXT>HELD IN BATTLE." if berry else "AN ITEM TO BE<NEXT>HELD IN BATTLE.")
    return g3, g2


def price(api: bs.API, slug: str) -> int:
    cost = api.get(f"/item/{slug}").get("cost") or 0
    if cost > 0:
        return min(cost, 99999)
    for key in ("berry", "gem", "plate"):
        if slug.endswith("-" + key):
            return DEFAULT_PRICE[key]
    return DEFAULT_PRICE[""]


def find_icon(icons: Path | None, extra: Path | None, slug: str) -> Path | None:
    stems = [slug]
    if slug.endswith("-berry"):
        stems.append(slug[:-6])
    if slug.endswith("-gem"):
        stems.append(slug[:-4])
    if slug.endswith("-plate"):
        stems.append(slug[:-6])
    if icons and slug not in EXTRA_ICON:
        sub = "berry" if slug.endswith("-berry") else "gem" if slug.endswith("-gem") \
            else "plate" if slug.endswith("-plate") else None
        roots = [icons / sub] if sub else [icons]
        for root in roots:
            for stem in stems:
                hit = sorted(root.rglob(f"{stem}.png"))
                if hit:
                    return hit[0]
    if extra:
        p = extra / (slug.replace("-", "").upper() + ".png")
        if p.exists():
            return p
    return None


def fit_cell(icon: Image.Image) -> Image.Image:
    icon = icon.convert("RGBA")
    box = icon.getbbox()
    if box:
        icon = icon.crop(box)
    w, h = icon.size
    if max(w, h) > ICON_SIZE:
        k = ICON_SIZE / max(w, h)
        icon = icon.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    cell = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    cell.paste(icon, ((ICON_SIZE - icon.width) // 2, (ICON_SIZE - icon.height) // 2), icon)
    return cell


def lua(v: Any, indent: str = "") -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 6))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua(x)}" for k, x in v.items()) + " }"
    raise TypeError(type(v))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--icons", type=Path, default=None)
    ap.add_argument("--extra-icons", type=Path, default=None)
    ap.add_argument("--cache", type=Path, default=ROOT / "tools" / ".cache")
    args = ap.parse_args()
    api = bs.API(args.cache)
    seen = set()
    rows, cells, missing = [], [], []
    for n, (slug, effect) in enumerate(HELD):
        if slug in seen:
            raise SystemExit(f"{slug} twice in HELD")
        seen.add(slug)
        g3, g2 = descriptions(api, slug, effect)
        row = {"slug": slug, "id": engine_id(slug), "index": INDEX_BASE + n, "name": display_name(api, slug),
               "price": price(api, slug), "desc": g3, "desc2": g2, "effect": effect}
        icon = find_icon(args.icons, args.extra_icons, slug)
        if icon:
            row["icon"] = len(cells)
            cells.append(fit_cell(Image.open(icon)))
        else:
            missing.append(slug)
        rows.append(row)
    out = ROOT / "data" / "held_items.lua"
    with out.open("w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/build_held.py from PokeAPI. Do not edit by hand; rerun the tool.\n")
        f.write("-- The held items newer than each game: every game registers the ones it lacks (by name)\n")
        f.write("-- and src/held/effects.lua runs `effect`. `index` is the item's number (saves keep it),\n")
        f.write("-- `icon` its cell in assets/items/held_icons.png (24x24), `desc` the Gen 3 Bag text,\n")
        f.write("-- `desc2` Gold's.\n")
        f.write("return {\n")
        for r in rows:
            f.write("  " + lua(r) + ",\n")
        f.write("}\n")
    if cells:
        cols = 16
        sheet = Image.new("RGBA", (cols * ICON_SIZE, ((len(cells) + cols - 1) // cols) * ICON_SIZE), (0, 0, 0, 0))
        for i, c in enumerate(cells):
            sheet.paste(c, ((i % cols) * ICON_SIZE, (i // cols) * ICON_SIZE))
        (ROOT / "assets" / "items").mkdir(parents=True, exist_ok=True)
        sheet.save(ROOT / "assets" / "items" / "held_icons.png", optimize=True)
    print(f"{len(rows)} held items -> {out}; {len(cells)} icons" + (f"; no icon: {', '.join(missing)}" if missing else ""))


if __name__ == "__main__":
    main()
