-- Where the evolution items (data/items.lua) are sold. Hand-written: the real
-- games sell almost none of these, so each placement is a design choice, by
-- item type and how far into the game the store is.
--
-- A store is found by its ORIGINAL stock, in order (`match`), not by a ROM
-- address, so one entry covers every game that has that list (the Ruby,
-- Sapphire and Emerald lists agree; FireRed and LeafGreen share theirs).
-- tests/shops_test.lua checks each `match` is exactly one store in each
-- listed game. `add` is by item slug; src/shops.lua resolves each to whatever
-- number that item has in this boot (so another mod's item of the same slug
-- still sells).
--
-- Kanto (FireRed / LeafGreen), Celadon being the mid-game department store,
-- the Sevii islands after the Elite Four:
--   Celadon Dept. Store 4F  stones, and the Gen 6 trade items
--   Celadon Dept. Store 5F  battle items: the held trade items
--   Six Island Mart         the Gen 8-9 items
-- Hoenn (Ruby / Sapphire / Emerald), Lilycove being the late department
-- store (it has no stone floor of its own, so stones join the supplements):
--   Lilycove Dept. Store    stones + Gen 6 trade items (supplements floor),
--                           held trade items (battle-item floor)
--   Mossdeep / Sootopolis / Ever Grande marts: the Gen 8-9 items, by stage
return {
  { games = { "firered", "leafgreen" }, store = "Celadon Dept. Store 4F",
    match = { 80, 132, 95, 96, 97, 98 },
    add = { "dusk-stone", "dawn-stone", "shiny-stone", "ice-stone", "sachet", "whipped-dream" } },
  { games = { "firered", "leafgreen" }, store = "Celadon Dept. Store 5F (battle items)",
    match = { 63, 64, 65, 67, 70, 66 },
    add = { "protector", "electirizer", "magmarizer", "dubious-disc", "reaper-cloth" } },
  { games = { "firered", "leafgreen" }, store = "Six Island Mart",
    match = { 2, 19, 20, 24, 23, 85, 84, 130 },
    add = { "metal-alloy", "black-augurite", "peat-block", "auspicious-armor", "malicious-armor",
            "tart-apple", "sweet-apple", "syrupy-apple",
            "cracked-pot", "chipped-pot", "unremarkable-teacup", "masterpiece-teacup",
            "strawberry-sweet", "berry-sweet", "love-sweet", "star-sweet",
            "clover-sweet", "flower-sweet", "ribbon-sweet" } },

  { games = { "ruby", "sapphire", "emerald" }, store = "Lilycove Dept. Store (supplements)",
    match = { 77, 79, 75, 76, 74, 73, 78 },
    add = { "dusk-stone", "dawn-stone", "shiny-stone", "ice-stone", "sachet", "whipped-dream" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Lilycove Dept. Store (battle items)",
    match = { 64, 67, 65, 70, 66, 63 },
    add = { "protector", "electirizer", "magmarizer", "dubious-disc", "reaper-cloth" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Mossdeep City Mart",
    match = { 2, 6, 7, 21, 23, 24, 84, 75, 76 },
    add = { "tart-apple", "sweet-apple", "syrupy-apple", "cracked-pot", "chipped-pot",
            "strawberry-sweet", "berry-sweet", "love-sweet", "star-sweet",
            "clover-sweet", "flower-sweet", "ribbon-sweet" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Sootopolis City Mart",
    match = { 2, 21, 20, 23, 24, 84, 75, 76, 128 },
    add = { "auspicious-armor", "malicious-armor", "metal-alloy",
            "unremarkable-teacup", "masterpiece-teacup" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Ever Grande City Pokemon League mart",
    match = { 2, 21, 20, 19, 23, 24, 84 },
    add = { "black-augurite", "peat-block" } },
}
