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
--   Celadon Dept. Store 4F  stones, the Linking Cord and the Gen 6 trade items
--   Celadon Dept. Store 5F  battle items: the held trade items; Dynamax Candy, Max Mushrooms and
--                           Max Honey beside the vitamins (Lilycove's vitamin counter too)
--   Six Island Mart         the Gen 8-9 items
-- Hoenn (Ruby / Sapphire / Emerald), Lilycove being the late department
-- store (it has no stone floor of its own, so stones join the supplements):
--   Lilycove Dept. Store    stones, Linking Cord + Gen 6 trade items (supplements floor),
--                           held trade items (battle-item floor)
--   Mossdeep / Sootopolis / Ever Grande marts: the Gen 8-9 items, by stage
-- The new TMs (data/tms.lua, TM51-TM164) are sold where each game sells TMs: Celadon Dept.
-- Store 2F in Kanto, and Lilycove Dept. Store's two TM counters in Hoenn (TM51-107, TM108-164).
return {
  { games = { "firered", "leafgreen" }, store = "Celadon Dept. Store 4F",
    match = { 80, 132, 95, 96, 97, 98 },
    add = { "dusk-stone", "dawn-stone", "shiny-stone", "ice-stone", "sachet", "whipped-dream",
            "linking-cord" } },
  { games = { "firered", "leafgreen" }, store = "Celadon Dept. Store 5F (battle items)",
    match = { 63, 64, 65, 67, 70, 66 },
    add = { "protector", "electirizer", "magmarizer", "dubious-disc", "reaper-cloth",
            "razor-claw", "razor-fang", "oval-stone", "leaders-crest",
            "dynamax-candy", "max-mushrooms", "max-honey" } },
  { games = { "firered", "leafgreen" }, store = "Six Island Mart",
    match = { 2, 19, 20, 24, 23, 85, 84, 130 },
    add = { "metal-alloy", "black-augurite", "peat-block", "auspicious-armor", "malicious-armor",
            "tart-apple", "sweet-apple", "syrupy-apple",
            "cracked-pot", "chipped-pot", "unremarkable-teacup", "masterpiece-teacup",
            "strawberry-sweet", "berry-sweet", "love-sweet", "star-sweet",
            "clover-sweet", "flower-sweet", "ribbon-sweet",
            "scroll-of-darkness", "scroll-of-waters", "galarica-cuff", "galarica-wreath" } },

  { games = { "ruby", "sapphire", "emerald" }, store = "Lilycove Dept. Store (supplements)",
    match = { 77, 79, 75, 76, 74, 73, 78 },
    add = { "dusk-stone", "dawn-stone", "shiny-stone", "ice-stone", "sachet", "whipped-dream",
            "linking-cord" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Lilycove Dept. Store (battle items)",
    match = { 64, 67, 65, 70, 66, 63 },
    add = { "protector", "electirizer", "magmarizer", "dubious-disc", "reaper-cloth",
            "razor-claw", "razor-fang", "oval-stone", "leaders-crest",
            "dynamax-candy", "max-mushrooms", "max-honey" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Mossdeep City Mart",
    match = { 2, 6, 7, 21, 23, 24, 84, 75, 76 },
    add = { "tart-apple", "sweet-apple", "syrupy-apple", "cracked-pot", "chipped-pot",
            "strawberry-sweet", "berry-sweet", "love-sweet", "star-sweet",
            "clover-sweet", "flower-sweet", "ribbon-sweet",
            "scroll-of-darkness", "scroll-of-waters", "galarica-cuff", "galarica-wreath" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Sootopolis City Mart",
    match = { 2, 21, 20, 23, 24, 84, 75, 76, 128 },
    add = { "auspicious-armor", "malicious-armor", "metal-alloy",
            "unremarkable-teacup", "masterpiece-teacup" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Ever Grande City Pokemon League mart",
    match = { 2, 21, 20, 19, 23, 24, 84 },
    add = { "black-augurite", "peat-block" } },

  { games = { "firered", "leafgreen" }, store = "Celadon Dept. Store 2F (TMs)",
    match = { 293, 303, 316, 319, 331, 333 },
    add = { "tm51", "tm52", "tm53", "tm54", "tm55", "tm56", "tm57", "tm58", "tm59", "tm60", "tm61", "tm62",
            "tm63", "tm64", "tm65", "tm66", "tm67", "tm68", "tm69", "tm70", "tm71", "tm72", "tm73", "tm74",
            "tm75", "tm76", "tm77", "tm78", "tm79", "tm80", "tm81", "tm82", "tm83", "tm84", "tm85", "tm86",
            "tm87", "tm88", "tm89", "tm90", "tm91", "tm92", "tm93", "tm94", "tm95", "tm96", "tm97", "tm98",
            "tm99", "tm100", "tm101", "tm102", "tm103", "tm104", "tm105", "tm106", "tm107", "tm108", "tm109", "tm110",
            "tm111", "tm112", "tm113", "tm114", "tm115", "tm116", "tm117", "tm118", "tm119", "tm120", "tm121", "tm122",
            "tm123", "tm124", "tm125", "tm126", "tm127", "tm128", "tm129", "tm130", "tm131", "tm132", "tm133", "tm134",
            "tm135", "tm136", "tm137", "tm138", "tm139", "tm140", "tm141", "tm142", "tm143", "tm144", "tm145", "tm146",
            "tm147", "tm148", "tm149", "tm150", "tm151", "tm152", "tm153", "tm154", "tm155", "tm156", "tm157", "tm158",
            "tm159", "tm160", "tm161", "tm162", "tm163", "tm164" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Lilycove Dept. Store (TMs, first counter)",
    match = { 326, 313, 302, 303 },
    add = { "tm51", "tm52", "tm53", "tm54", "tm55", "tm56", "tm57", "tm58", "tm59", "tm60", "tm61", "tm62",
            "tm63", "tm64", "tm65", "tm66", "tm67", "tm68", "tm69", "tm70", "tm71", "tm72", "tm73", "tm74",
            "tm75", "tm76", "tm77", "tm78", "tm79", "tm80", "tm81", "tm82", "tm83", "tm84", "tm85", "tm86",
            "tm87", "tm88", "tm89", "tm90", "tm91", "tm92", "tm93", "tm94", "tm95", "tm96", "tm97", "tm98",
            "tm99", "tm100", "tm101", "tm102", "tm103", "tm104", "tm105", "tm106", "tm107" } },
  { games = { "ruby", "sapphire", "emerald" }, store = "Lilycove Dept. Store (TMs, second counter)",
    match = { 305, 308, 321, 304 },
    add = { "tm108", "tm109", "tm110", "tm111", "tm112", "tm113", "tm114", "tm115", "tm116", "tm117", "tm118", "tm119",
            "tm120", "tm121", "tm122", "tm123", "tm124", "tm125", "tm126", "tm127", "tm128", "tm129", "tm130", "tm131",
            "tm132", "tm133", "tm134", "tm135", "tm136", "tm137", "tm138", "tm139", "tm140", "tm141", "tm142", "tm143",
            "tm144", "tm145", "tm146", "tm147", "tm148", "tm149", "tm150", "tm151", "tm152", "tm153", "tm154", "tm155",
            "tm156", "tm157", "tm158", "tm159", "tm160", "tm161", "tm162", "tm163", "tm164" } },
}
