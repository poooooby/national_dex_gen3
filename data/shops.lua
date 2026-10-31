-- Where this mod's items are sold in the Marts. Hand-written: the real games sell almost none of
-- these, so each placement is a design choice.
--
-- A store is found by its ORIGINAL stock, in order (`match`), not by a ROM
-- address, so one entry covers every game that has that list (the Ruby,
-- Sapphire and Emerald lists agree; FireRed and LeafGreen share theirs).
-- tests/shops_test.lua checks each `match` is exactly one store in each
-- listed game. `add` is by item slug; src/shops.lua resolves each to whatever
-- number that item has in this boot (so another mod's item of the same slug
-- still sells).
--
-- The evolution items and the new TMs are sold by the vending machines (data/vending.lua) in
-- every game: Celadon Dept. Store 4F / 2F in Kanto, Lilycove Dept. Store 4F in Hoenn. The Marts
-- keep only Dynamax Candy, Max Mushrooms and Max Honey, beside the vitamins:
--   Celadon Dept. Store 5F  (FireRed / LeafGreen)
--   Lilycove Dept. Store    (Ruby / Sapphire / Emerald)
return {
  { games = { "firered", "leafgreen" }, store = "Celadon Dept. Store 5F (battle items)",
    match = { 63, 64, 65, 67, 70, 66 },
    add = { "dynamax-candy", "max-mushrooms", "max-honey" } },

  { games = { "ruby", "sapphire", "emerald" }, store = "Lilycove Dept. Store (battle items)",
    match = { 64, 67, 65, 70, 66, 63 },
    add = { "dynamax-candy", "max-mushrooms", "max-honey" } },
}
