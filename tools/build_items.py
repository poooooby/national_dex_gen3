#!/usr/bin/env python3
"""
Build national_dex_gen3's evolution-item payload and icon atlas.

Some of this mod's own evolutions (data/species/*.lua, data/species/crossgen.lua)
call for an item no Gen 3 game has (Dusk Stone, Protector, ...). Species.itemIndex
waits for ANY installed mod to provide one; this tool builds the one THIS mod now
provides itself: data/items.lua (what to register) and assets/items/icons.png +
data/item_icons.lua (their Bag icons, for games that have one).

ORDER below is append-only: an item's `index` is its position in that list, and
`index` is what the engine stores in saves (storage.items[i].id) and in
src/item_art.lua's UI hook. Reordering or removing an entry would change what a
previously-saved item turns into. Add new items at the end.

Icons come from the third-party pokesprite pack (not shipped; --icons points at
a local checkout). An item ORDER lists but the pack has no icon for keeps
working -- it just has no Bag icon (src/item_art.lua falls through to the
game's own, which draws nothing for an unknown id).

Usage:
    python tools/build_items.py --icons <pokesprite>/items
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from desc_width import LIMIT, width  # noqa: E402
INDEX_BASE = 900   # first slot; comfortably above every Gen 3 game's own
                   # item ids (the highest this engine knows of is 365)
ICON_SIZE = 24     # the Bag's own icon slot, both FRLG's and RSE's bag_chrome

# Append-only. Slug: the PokeAPI/evolution-data id (data/species/*.lua `item`
# fields and data/species/crossgen.lua). Do not reorder, remove, or insert.
ORDER = [
    "dawn-stone", "dubious-disc", "dusk-stone", "electirizer", "ice-stone",
    "magmarizer", "protector", "reaper-cloth", "sachet", "shiny-stone",
    "sweet-apple", "tart-apple", "whipped-dream",
    # the Gen 9 items below: not in every "icones animados"/pokesprite
    # checkout; registered regardless (see ORDER's own docstring above)
    "auspicious-armor", "black-augurite", "malicious-armor", "metal-alloy",
    "peat-block", "syrupy-apple",
    # Sinistea / Poltchageist: two items each (phony/antique, counterfeit/artisan)
    "cracked-pot", "chipped-pot", "unremarkable-teacup", "masterpiece-teacup",
    # Milcery -> Alcremie: any one of the seven sweets, held
    "strawberry-sweet", "berry-sweet", "love-sweet", "star-sweet", "clover-sweet",
    "flower-sweet", "ribbon-sweet",
    # held-item evolutions (Sneasel, Gligar, Happiny, Bisharp) and Kubfu's scrolls
    "razor-claw", "razor-fang", "oval-stone", "leaders-crest",
    "scroll-of-darkness", "scroll-of-waters",
]

# Items whose icon is not in the pokesprite folder (--icons) but in the Gen 9 Pack's
# Graphics/Items (--extra-icons, one 48x48 PNG per item, named without separators).
EXTRA_ICON_FILES = {"leaders-crest": "LEADERSCREST", "scroll-of-darkness": "SCROLLOFDARKNESS",
                    "scroll-of-waters": "SCROLLOFWATERS"}

# slug -> file stem when the pack spells the item differently (pokesprite
# calls the teacups "teapot")
ICON_ALIASES = {"unremarkable-teacup": "unremarkable-teapot",
                "masterpiece-teacup": "masterpiece-teapot"}


def engine_id(slug: str) -> str:
    return slug.upper().replace("-", "_")


# The cart's item names hold 14 characters, so the longer ones are abbreviated.
NAME_OVERRIDES = {"leaders-crest": "Leader's Crest", "scroll-of-darkness": "Dark Scroll",
                  "scroll-of-waters": "Water Scroll", "auspicious-armor": "Auspic. Armor",
                  "malicious-armor": "Malic. Armor", "unremarkable-teacup": "Unremark. Cup",
                  "masterpiece-teacup": "Masterpc. Cup", "strawberry-sweet": "Strawbry Sweet"}


# What the marts and the Bag show under each item: what the item is, in the cart's own style,
# never what it is for. The mart's description box is about 21
# characters wide and 3 lines high (anything wider runs under the item list), so every line
# stays within LIMIT by tools/desc_width.py's estimate. A backslash-n separates lines.
DESCRIPTIONS = {
    "dawn-stone": "A peculiar stone\nthat sparkles like\na glittering eye.",
    "dubious-disc": "A transparent\ndevice overflowing\nwith dubious data.",
    "dusk-stone": "A peculiar stone, as\ndark as dark can be.",
    "electirizer": "A box packed with\nelectric energy.",
    "ice-stone": "A peculiar stone\nwith a snowflake\npattern.",
    "magmarizer": "A box packed with\nfire energy.",
    "protector": "Protective gear\nthat is very hard.",
    "reaper-cloth": "A cloth imbued with\nhorrifying energy.",
    "sachet": "A sachet filled with\nlovely perfume.",
    "shiny-stone": "A peculiar stone\nthat shines.",
    "sweet-apple": "A very sweet apple.",
    "tart-apple": "A very tart apple.",
    "whipped-dream": "A soft and sweet\ntreat of sugar.",
    "auspicious-armor": "Armor fit for a\nchampion.",
    "black-augurite": "A black, glossy\nstone.",
    "malicious-armor": "Armor filled\nwith spite.",
    "metal-alloy": "A mysterious metal\nof fused metals.",
    "peat-block": "Plant matter that\nsmolders eerily.",
    "syrupy-apple": "A very syrupy\napple.",
    "cracked-pot": "A cracked,\nworthless pot.",
    "chipped-pot": "A chipped antique\npot.",
    "unremarkable-teacup": "A plain, ordinary\nteacup.",
    "masterpiece-teacup": "A splendid teacup, a\nwork of art.",
    "strawberry-sweet": "A sweet with a\nstrawberry on top.",
    "berry-sweet": "A sweet with a\nberry on top.",
    "love-sweet": "A sweet with a\nheart on top.",
    "star-sweet": "A sweet with a\nstar on top.",
    "clover-sweet": "A sweet with a\nclover on top.",
    "flower-sweet": "A sweet with a\nflower on top.",
    "ribbon-sweet": "A sweet with a\nribbon on top.",
    "razor-claw": "A sharply hooked\nclaw.",
    "razor-fang": "A sharp, hard fang.",
    "oval-stone": "A peculiar,\negg-shaped stone.",
    "leaders-crest": "A crest worn by\na leader.",
    "scroll-of-darkness": "A scroll of the\ndark style.",
    "scroll-of-waters": "A scroll of the\nwater style.",
}

for _slug, _text in DESCRIPTIONS.items():
    _lines = _text.split("\n")
    assert len(_lines) <= 3, _slug
    assert all(width(_l) <= LIMIT for _l in _lines), (_slug, _text)


def display_name(slug: str) -> str:
    # all caps, like the cart's own item names (THUNDERSTONE, KING'S ROCK)
    return (NAME_OVERRIDES.get(slug) or slug.replace("-", " ").title()).upper()


def find_icon(icons_root: Path, slug: str) -> Path | None:
    # pokesprite names files with hyphens; hand-added ones may use underscores
    alias = ICON_ALIASES.get(slug, slug)
    for name in (slug, slug.replace("-", "_"), alias, alias.replace("-", "_")):
        hit = sorted(icons_root.rglob(f"{name}.png"))
        if hit:
            return hit[0]
    return None


DEFAULT_PRICE = 2100   # the classic Gen 3 evolution stone price, when the wiki has none


# Shop prices Bulbapedia lists directly as the buy price, where 2x the sell price would
# be wrong (the Chipped Pot sells for 19,000 but is bought for 3,000).
BUY_PRICES = {"cracked-pot": 3000, "chipped-pot": 3000}


def derive_price(slug: str, prices: dict) -> tuple[int, str]:
    """Shop buy price: twice the sell price of the earliest game that lists
    one (a shop buys at half what it sells for), from tools/item_prices.json
    (tools/fetch_item_prices.py, Bulbapedia). Returns (price, why)."""
    if slug in BUY_PRICES:
        return BUY_PRICES[slug], "Bulbapedia buy price"
    for row in (prices.get(slug) or {}).get("prices", []):
        if row.get("sell"):
            return row["sell"] * 2, "2x sell price %d (%s)" % (row["sell"], ",".join(row["games"]))
    return DEFAULT_PRICE, "no price data; classic stone price"


def write_items(path: Path, prices: dict) -> None:
    lines = [
        "-- Generated by tools/build_items.py. Do not edit by hand; rerun the",
        "-- tool instead (see tools/build_items.py's ORDER for why entries are",
        "-- append-only).",
        "--",
        "-- The evolution items no Gen 3 game has, that this mod's own evolutions",
        "-- (data/species, data/species/crossgen.lua) call for. src/items.lua",
        "-- registers each at its own fixed slot (index = 900 + position here). price is",
        "-- the shop price from tools/item_prices.json (Bulbapedia): 2x the earliest sell price.",
        "return {",
    ]
    for i, slug in enumerate(ORDER):
        price, why = derive_price(slug, prices)
        lines.append(f'  {{ slug = "{slug}", id = "{engine_id(slug)}", '
                     f'name = "{display_name(slug)}", index = {INDEX_BASE + i}, '
                     f'price = {price}, description = {json.dumps(DESCRIPTIONS[slug], ensure_ascii=False)} }}, -- {why}')
    lines += ["}", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def fit_cell(icon: Image.Image) -> Image.Image:
    """The icon in a 24x24 cell without blurring a pixel. The art has empty margin, so it is
    cropped to its content and centred 1:1 when that fits; only larger art is scaled, with
    nearest neighbour (no resampling filter: a smoothing one rings and bleeds at the edges)."""
    box = icon.getchannel("A").getbbox()
    cell = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    if box is None:
        return cell
    art = icon.crop(box)
    longest = max(art.size)
    if longest > ICON_SIZE:
        scale = ICON_SIZE / longest
        art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))), Image.NEAREST)
    cell.paste(art, ((ICON_SIZE - art.width) // 2, (ICON_SIZE - art.height) // 2))
    return cell


def build_icons(icons_root: Path | None, out_png: Path, out_lua: Path,
                extra_root: Path | None = None) -> None:
    found: dict[str, Path] = {}
    if icons_root and icons_root.is_dir():
        for slug in ORDER:
            hit = find_icon(icons_root, slug)
            if hit:
                found[slug] = hit
    if extra_root and extra_root.is_dir():
        for slug, stem in EXTRA_ICON_FILES.items():
            path = extra_root / f"{stem}.png"
            if slug not in found and path.exists():
                found[slug] = path
    missing = [s for s in ORDER if s not in found]

    cols = max(1, min(len(found), 16))
    rows = -(-max(1, len(found)) // cols)
    sheet = Image.new("RGBA", (cols * ICON_SIZE, rows * ICON_SIZE), (0, 0, 0, 0))
    cells: dict[int, tuple[int, int]] = {}
    for i, slug in enumerate(s for s in ORDER if s in found):
        with Image.open(found[slug]) as im:
            icon = fit_cell(im.convert("RGBA"))
        x, y = (i % cols) * ICON_SIZE, (i // cols) * ICON_SIZE
        sheet.paste(icon, (x, y))
        cells[ORDER.index(slug)] = (x, y)
    out_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_png, optimize=True, compress_level=9)

    lines = [
        "-- Generated by tools/build_items.py. Do not edit by hand; rerun the tool",
        "-- instead. index -> where its 24x24 icon sits in assets/items/icons.png,",
        "-- for whichever of this mod's items the icon pack had art for.",
        "return {",
        f"  size = {ICON_SIZE},",
        "  cells = {",
    ]
    for i, slug in enumerate(ORDER):
        if i in cells:
            x, y = cells[i]
            lines.append(f"    [{INDEX_BASE + i}] = {{ x = {x}, y = {y} }}, -- {slug}")
    lines += ["  },", "}", ""]
    out_lua.write_text("\n".join(lines), encoding="utf-8")

    print(f"items: {len(ORDER)}, icons: {len(found)}/{len(ORDER)}")
    if missing:
        print("no icon for: " + ", ".join(missing))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--icons", type=Path, default=None,
                    help="root of a local pokesprite-style item icon pack "
                         "(searched recursively for <slug>.png); omit to skip icons")
    ap.add_argument("--extra-icons", type=Path, default=None,
                    help="the Gen 9 Pack's Graphics/Items folder, for the items the "
                         "pokesprite pack has no icon for (Leader's Crest, the scrolls)")
    ap.add_argument("--out", type=Path, default=ROOT)
    args = ap.parse_args()

    price_file = Path(__file__).resolve().parent / "item_prices.json"
    prices = json.loads(price_file.read_text(encoding="utf-8")) if price_file.exists() else {}
    write_items(args.out / "data" / "items.lua", prices)
    build_icons(args.icons, args.out / "assets" / "items" / "icons.png",
               args.out / "data" / "item_icons.lua", args.extra_icons)
    print("wrote", args.out / "data" / "items.lua")


if __name__ == "__main__":
    main()
