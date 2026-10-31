-- The vending machines (src/vending.lua, src/vending_screen.lua): stationary NPCs this mod places
-- on a map that open a touch-screen shop of their own. Hand-written, like data/shops.lua.
--
-- places where the machine stands, one per group of carts: `games`, `map` (the map's name
--        WITHOUT the game prefix: EM_ / RU_ / SA_ / FR_ / LG_ are added for the running game),
--        `x`, `y` its tile, `store` the name tools/build_docs.lua lists it under
-- sprite the machine's 16 x 32 overworld picture (one frame; its bottom half stands on the tile)
-- bezel  the screen's frame colours, taken from that picture so the two match: body (the top
--        half), lower (the lower body), trim (the shaded edge), outline, screen (the glass) and
--        accent (the picture on the glass)
-- tabs   what it sells, by tab (item slugs, as data/shops.lua spells them); an ALL tab comes
--        first. typeTabs: one more tab per move type the stock's TMs teach
-- badges how many Gym Badges the player needs before the machine sells an item (by slug, or for
--        a TM by its move); unlisted items need none. Taken from where each item turns up in its
--        newest game with badges (Scarlet / Violet, else Sword / Shield, else Legends: Arceus,
--        by area and gym order); post-game and DLC finds need all 8. An item only in a DLC there
--        takes its tier from the game before (the trade items, the Sweets, Razor Fang, Black
--        Augurite); Metal Alloy has no game before, so it needs 8
local tms = {}
for n = 51, 164 do tms[#tms + 1] = "tm" .. n end

local HOENN = { "ruby", "sapphire", "emerald" }
local KANTO = { "firered", "leafgreen" }

-- { [badges] = { names } } -> { [name] = badges }
local function byBadges(tiers)
  local out = {}
  for n, names in pairs(tiers) do
    for _, name in ipairs(names) do out[name] = n end
  end
  return out
end

return {
  { id = "evo",
    places = {
      { games = HOENN, map = "LILYCOVE_CITY_DEPARTMENT_STORE_2F", x = 5, y = 2,
        store = "Lilycove Dept. Store 2F (evolution item machine)" },
      { games = KANTO, map = "CELADON_CITY_DEPARTMENT_STORE_4F", x = 9, y = 5,
        store = "Celadon Dept. Store 4F (evolution item machine)" },
    },
    title = "EVO EXPRESS",
    sprite = "assets/shop/EVOvendor2.png",
    bezel = { body = { 193, 99, 221 }, lower = { 114, 88, 191 }, trim = { 160, 99, 221 },
              outline = { 82, 82, 106 }, screen = { 211, 234, 234 }, accent = { 24, 180, 164 } },
    tabs = {
      { label = "STONES", add = { "dawn-stone", "dusk-stone", "shiny-stone", "ice-stone",
                                  "black-augurite", "peat-block" } },
      { label = "TRADE", add = { "linking-cord", "protector", "electirizer", "magmarizer",
                                 "dubious-disc", "reaper-cloth", "sachet", "whipped-dream" } },
      { label = "HELD", add = { "razor-claw", "razor-fang", "oval-stone", "leaders-crest",
                                "strawberry-sweet", "berry-sweet", "love-sweet", "star-sweet",
                                "clover-sweet", "flower-sweet", "ribbon-sweet" } },
      { label = "SPECIAL", add = { "tart-apple", "sweet-apple", "syrupy-apple",
                                   "cracked-pot", "chipped-pot", "unremarkable-teacup", "masterpiece-teacup",
                                   "auspicious-armor", "malicious-armor", "metal-alloy",
                                   "scroll-of-darkness", "scroll-of-waters",
                                   "galarica-cuff", "galarica-wreath" } },
    },
    badges = byBadges({
      [1] = { "sachet", "whipped-dream", "cracked-pot" },
      [2] = { "dusk-stone", "linking-cord", "razor-fang", "strawberry-sweet", "berry-sweet", "love-sweet",
              "star-sweet", "clover-sweet", "flower-sweet", "ribbon-sweet" },
      [3] = { "dawn-stone", "shiny-stone", "oval-stone", "peat-block", "black-augurite", "tart-apple",
              "sweet-apple", "chipped-pot", "scroll-of-darkness", "scroll-of-waters", "protector",
              "electirizer", "magmarizer", "dubious-disc", "reaper-cloth" },
      [4] = { "ice-stone", "razor-claw", "auspicious-armor", "malicious-armor" },
      [5] = { "leaders-crest", "syrupy-apple", "unremarkable-teacup", "galarica-cuff", "galarica-wreath" },
      [7] = { "masterpiece-teacup" },
      [8] = { "metal-alloy" },
    }) },
  { id = "tm",
    places = {
      { games = HOENN, map = "LILYCOVE_CITY_DEPARTMENT_STORE_4F", x = 8, y = 2,
        store = "Lilycove Dept. Store 4F (TM machine)" },
      { games = KANTO, map = "CELADON_CITY_DEPARTMENT_STORE_2F", x = 9, y = 5,
        store = "Celadon Dept. Store 2F (TM machine)" },
    },
    title = "TM EXPRESS",
    sprite = "assets/shop/TMvendor2.png",
    bezel = { body = { 88, 116, 232 }, lower = { 79, 165, 200 }, trim = { 88, 155, 232 },
              outline = { 82, 82, 106 }, screen = { 211, 234, 234 }, accent = { 224, 152, 73 } },
    tabs = { { label = "ALL", add = tms } },
    typeTabs = true,
    -- (by move; the rest need none: Ice Fang, Stealth Rock, Tailwind, Nasty Plot, Play Rough...)
    badges = byBadges({
      [1] = { "THUNDER_FANG", "ACROBATICS", "SNARL", "FLING", "DRAIN_PUNCH", "BODY_PRESS", "FLASH_CANNON",
              "POWER_GEM", "LIQUIDATION", "AURA_SPHERE", "HEAVY_SLAM", "ELECTRIC_TERRAIN", "PSYCHIC_TERRAIN",
              "MISTY_TERRAIN", "BUG_BUZZ", "BRAVE_BIRD", "RETALIATE" },
      [2] = { "FIRE_FANG", "CHARGE_BEAM", "BULLDOZE", "HEX", "LOW_SWEEP", "DRAGON_TAIL", "SNOWSCAPE", "U_TURN",
              "SHADOW_CLAW", "FOUL_PLAY", "PSYCHIC_FANGS", "SEED_BOMB", "STOMPING_TANTRUM", "IRON_HEAD",
              "X_SCISSOR", "ENERGY_BALL", "FOCUS_BLAST", "TRICK_ROOM" },
      [3] = { "FLAME_CHARGE", "AVALANCHE", "VOLT_SWITCH", "SMART_STRIKE", "PSYSHOCK", "TOXIC_SPIKES",
              "DARK_PULSE", "EARTH_POWER", "PHANTOM_FORCE", "BRINE" },
      [4] = { "ZEN_HEADBUTT", "POISON_JAB", "GUNK_SHOT", "POLLEN_PUFF", "GIGA_IMPACT", "HURRICANE" },
      [5] = { "DRAGON_PULSE" },
      [6] = { "FLARE_BLITZ", "ASSURANCE" },
      [7] = { "WILD_CHARGE", "STONE_EDGE", "LEAF_STORM" },
      [8] = { "DAZZLING_GLEAM", "ICE_SPINNER", "CLOSE_COMBAT",
              -- (Scarlet / Violet's DLC)
              "GRAVITY", "SMACK_DOWN", "GYRO_BALL", "BUG_BITE", "VACUUM_WAVE", "LUNGE", "HIGH_HORSEPOWER", "SCALD",
              "HEAT_CRASH", "SOLAR_BLADE", "FLIP_TURN", "DUAL_WINGBEAT", "SCALE_SHOT", "PETAL_BLIZZARD",
              "ELECTROWEB", "SLUDGE_WAVE", "EXPANDING_FORCE", "SKITTER_SMACK", "THROAT_CHOP", "BREAKING_SWIPE",
              -- (Sword / Shield's Wyndon and Battle Tower)
              "POWER_SWAP", "GUARD_SWAP", "SPEED_SWAP", "WONDER_ROOM", "MAGIC_ROOM", "RAZOR_SHELL",
              "MYSTICAL_FIRE" },
    }) },
}
