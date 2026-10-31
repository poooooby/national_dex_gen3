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
local tms = {}
for n = 51, 164 do tms[#tms + 1] = "tm" .. n end

local HOENN = { "ruby", "sapphire", "emerald" }
local KANTO = { "firered", "leafgreen" }

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
    } },
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
    typeTabs = true },
}
