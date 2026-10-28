-- Dynamax (Sword / Shield): which species have a Gigantamax form and its G-Max Move, which take
-- Max Soup and how, which can never Dynamax, and the numbers src/dynamax.lua runs on.
--   GMAX[national] = G-Max Move id (the move ids Dynamax Raids' data/raid_gmax.lua uses); a form of
--     the species has it too unless it is a regional form (FORM_EXCLUDE), and FORM_MOVE gives a
--     form its own move (Urshifu's Rapid Strike Style)
return {
  GMAX = {
    [3] = "VINE_LASH", [6] = "WILDFIRE", [9] = "CANNONADE", [12] = "BEFUDDLE", [25] = "VOLT_CRASH",
    [52] = "GOLD_RUSH", [68] = "CHI_STRIKE", [94] = "TERROR", [99] = "FOAM_BURST", [131] = "RESONANCE",
    [133] = "CUDDLE", [143] = "REPLENISH", [569] = "MALODOR", [809] = "MELTDOWN", [812] = "DRUM_SOLO",
    [815] = "FIREBALL", [818] = "HYDROSNIPE", [823] = "WIND_RAGE", [826] = "GRAVITAS", [834] = "STONESURGE",
    [839] = "VOLCALITH", [841] = "TARTNESS", [842] = "SWEETNESS", [844] = "SANDBLAST", [849] = "STUN_SHOCK",
    [851] = "CENTIFERNO", [858] = "SMITE", [861] = "SNOOZE", [869] = "FINALE", [879] = "STEELSURGE",
    [884] = "DEPLETION", [892] = "ONE_BLOW",
  },
  FORM_MOVE = { URSHIFU_RAPID_STRIKE = "RAPID_FLOW" },
  -- a regional form has no Gigantamax form (Alolan / Galarian Meowth)
  FORM_EXCLUDE = { "_ALOLA", "_GALAR", "_HISUI", "_PALDEA" },
  -- Max Soup: never for Melmetal; Urshifu's takes a Max Honey besides the three Max Mushrooms
  NO_SOUP = { [809] = true },
  SOUP_HONEY = { [892] = true },
  SOUP_MUSHROOMS = 3,
  -- never Dynamax (their forms too): Zacian, Zamazenta, Eternatus
  NO_DYNAMAX = { [888] = true, [889] = true, [890] = true },
  -- Dynamax Level 0..MAX; HP x (HP_BASE + HP_PER x level) while Dynamaxed
  MAX_LEVEL = 10, HP_BASE = 1.5, HP_PER = 0.05,
  -- a raid catch's starting level by the den's stars (rank = stars - 1): base rank + 1 (6 at 5★),
  -- plus a roll of 0 .. SPREAD - 1
  RAID_LEVEL = { [1] = { 1, 2 }, [2] = { 2, 2 }, [3] = { 3, 2 }, [4] = { 4, 2 }, [5] = { 6, 3 } },

  EVIDENCE = {
    GMAX = { class = "verified", source = "Bulbapedia 'Gigantamax' / 'G-Max Move': the 32 species with a Gigantamax form in Sword / Shield and their moves; Urshifu's styles One Blow / Rapid Flow", confidence = "high" },
    FORM_EXCLUDE = { class = "verified", source = "Bulbapedia 'Gigantamax': only Kantonian Meowth Gigantamaxes; every Alcremie flavour shares one Gigantamax form", confidence = "high" },
    NO_SOUP = { class = "verified", source = "Bulbapedia 'Gigantamax': every species with a Gigantamax form but Melmetal can drink Max Soup", confidence = "high" },
    SOUP_HONEY = { class = "verified", source = "Serebii 'Max Soup': Urshifu's needs 3 Max Mushrooms and 1 Max Honey; Max Soup on a Pokemon that has the factor removes it", confidence = "high" },
    NO_DYNAMAX = { class = "verified", source = "Serebii 'Dynamax': Zacian, Zamazenta and Eternatus cannot Dynamax; Dynamax Candy cannot be used on them", confidence = "high" },
    HP = { class = "verified", source = "Serebii 'Dynamax': level 0 x1.5, +0.05 a level, x2 at 10; current and max HP alike", confidence = "high" },
    RAID_LEVEL = { class = "verified", source = "PKHeX EncounterStatic8N.GetInitialDynamaxLevel: baseValue = rank == 4 ? 6 : rank + 1; + rand(rank == 4 ? 3 : 2)", confidence = "high" },
  },
}
