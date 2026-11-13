-- Gold's held items, for Red / Blue / Yellow (src/gen12/held_red.lua registers them there, sold at
-- the Celadon Dept. Store 4F; src/gen12/mech/held.lua gives them their battle effects). Written
-- for this mod from the Gen 2 games' behaviour, in our own words: `effect` is ours, `param` its
-- number (a 1-in-256 chance, HP, a percent). Gold runs its own held items, so this is Red only.
--   heal      restores `param` HP once its holder is at half HP or less
--   cure      cures its holder's `param` status (PAR / SLP / BRN / FRZ / PSN / CONFUSION / ALL)
--   pp        restores `param` PP to a move that runs out
--   leftovers restores 1/16 of max HP at the end of every turn
--   flinch    `param` / 256 to flinch the target with a damaging move
--   quickClaw `param` / 256 to move first when priorities tie
--   evasion   `param` / 256 to make a move miss its holder
--   crit      raises its holder's critical-hit chance
--   focusBand `param` / 256 to survive a KO with 1 HP
--   boost     a move of type `type` hits `param` percent harder
--   species   doubles `stat` for its `species` (Light Ball, Thick Club, Metal Powder; crit: the
--             Lucky Punch, the Stick)
--   berserk   on entry: Attack +2 and confusion, then it is used up
--   everstone, escape   out of battle (no evolution; a sure escape from a wild battle)
return {
  { id = "BERRY", name = "BERRY", price = 100, effect = "heal", param = 10 },
  { id = "GOLD_BERRY", name = "GOLD BERRY", price = 400, effect = "heal", param = 30 },
  { id = "PRZCUREBERRY", name = "PRZCUREBERRY", price = 100, effect = "cure", param = "PAR" },
  { id = "MINT_BERRY", name = "MINT BERRY", price = 100, effect = "cure", param = "SLP" },
  { id = "ICE_BERRY", name = "ICE BERRY", price = 100, effect = "cure", param = "BRN" },
  { id = "BURNT_BERRY", name = "BURNT BERRY", price = 100, effect = "cure", param = "FRZ" },
  { id = "PSNCUREBERRY", name = "PSNCUREBERRY", price = 100, effect = "cure", param = "PSN" },
  { id = "BITTER_BERRY", name = "BITTER BERRY", price = 100, effect = "cure", param = "CONFUSION" },
  { id = "MIRACLEBERRY", name = "MIRACLEBERRY", price = 300, effect = "cure", param = "ALL" },
  { id = "MYSTERYBERRY", name = "MYSTERYBERRY", price = 300, effect = "pp", param = 5 },
  { id = "LEFTOVERS", name = "LEFTOVERS", price = 4000, effect = "leftovers" },
  { id = "QUICK_CLAW", name = "QUICK CLAW", price = 4000, effect = "quickClaw", param = 60 },
  { id = "BRIGHTPOWDER", name = "BRIGHTPOWDER", price = 4000, effect = "evasion", param = 20 },
  { id = "SCOPE_LENS", name = "SCOPE LENS", price = 4000, effect = "crit" },
  { id = "FOCUS_BAND", name = "FOCUS BAND", price = 4000, effect = "focusBand", param = 30 },
  { id = "CHARCOAL", name = "CHARCOAL", price = 1000, effect = "boost", type = "FIRE", param = 10 },
  { id = "MYSTIC_WATER", name = "MYSTIC WATER", price = 1000, effect = "boost", type = "WATER", param = 10 },
  { id = "MIRACLE_SEED", name = "MIRACLE SEED", price = 1000, effect = "boost", type = "GRASS", param = 10 },
  { id = "MAGNET", name = "MAGNET", price = 1000, effect = "boost", type = "ELECTRIC", param = 10 },
  { id = "TWISTEDSPOON", name = "TWISTEDSPOON", price = 1000, effect = "boost", type = "PSYCHIC", param = 10 },
  { id = "NEVERMELTICE", name = "NEVERMELTICE", price = 1000, effect = "boost", type = "ICE", param = 10 },
  { id = "DRAGON_FANG", name = "DRAGON FANG", price = 1000, effect = "boost", type = "DRAGON", param = 10 },
  { id = "BLACKGLASSES", name = "BLACKGLASSES", price = 1000, effect = "boost", type = "DARK", param = 10 },
  { id = "SILVERPOWDER", name = "SILVERPOWDER", price = 1000, effect = "boost", type = "BUG", param = 10 },
  { id = "HARD_STONE", name = "HARD STONE", price = 1000, effect = "boost", type = "ROCK", param = 10 },
  { id = "SOFT_SAND", name = "SOFT SAND", price = 1000, effect = "boost", type = "GROUND", param = 10 },
  { id = "SHARP_BEAK", name = "SHARP BEAK", price = 1000, effect = "boost", type = "FLYING", param = 10 },
  { id = "POISON_BARB", name = "POISON BARB", price = 1000, effect = "boost", type = "POISON", param = 10 },
  { id = "BLACKBELT", name = "BLACKBELT", price = 1000, effect = "boost", type = "FIGHTING", param = 10 },
  { id = "SPELL_TAG", name = "SPELL TAG", price = 1000, effect = "boost", type = "GHOST", param = 10 },
  { id = "PINK_BOW", name = "PINK BOW", price = 1000, effect = "boost", type = "NORMAL", param = 10 },
  { id = "LIGHT_BALL", name = "LIGHT BALL", price = 1000, effect = "species", species = { "PIKACHU" }, stat = "spAtk" },
  { id = "THICK_CLUB", name = "THICK CLUB", price = 1000, effect = "species", species = { "CUBONE", "MAROWAK" }, stat = "attack" },
  { id = "METAL_POWDER", name = "METAL POWDER", price = 1000, effect = "species", species = { "DITTO" }, stat = "defense" },
  { id = "LUCKY_PUNCH", name = "LUCKY PUNCH", price = 1000, effect = "species", species = { "CHANSEY" }, stat = "crit" },
  { id = "STICK", name = "STICK", price = 1000, effect = "species", species = { "FARFETCHD", "FARFETCH_D" }, stat = "crit" },
  { id = "BERSERK_GENE", name = "BERSERK GENE", price = 1000, effect = "berserk" },
  { id = "EVERSTONE", name = "EVERSTONE", price = 1000, effect = "everstone" },
  { id = "SMOKE_BALL", name = "SMOKE BALL", price = 1000, effect = "escape" },
}
