-- WoobleDex's achievements (src/achievements.lua), for the Recomp Achievements mod. Written by
-- hand. An id is in the player's save (mod:national_dex_gen3:<id>): never change or reuse one.
--
-- Each one counts Pokemon the Pokedex has as caught (or, `seen = true`, as seen):
--   range = { first, last }   National Dex numbers first..last
--   dex = { ... }             these National Dex numbers
--   flag = "legendary"        every species with that flag (legendary / mythical)
--   forms = "regional"        every regional variant (region = "ALOLA" for one region's)
--   forms = "all"             every alternate form
--   family = "ROTOM"          the species with that id and every form of it
--   goal = n                  only n of them are needed (a milestone)
-- Several keys add up (the master dex is range + forms).

local NATIONAL = { 1, 1025 }

return {
  -- National Dex numbers by group (Bulbapedia's lists)
  groups = {
    -- the first stage of every generation's three starters
    starters = { 1, 4, 7, 152, 155, 158, 252, 255, 258, 387, 390, 393, 495, 498, 501, 650, 653, 656,
      722, 725, 728, 810, 813, 816, 906, 909, 912 },
    -- the newer species carry legendary / mythical themselves; these are the cart's 386
    legendary = { 144, 145, 146, 150, 243, 244, 245, 249, 250, 377, 378, 379, 380, 381, 382, 383, 384 },
    mythical = { 151, 251, 385, 386 },
    eeveelutions = { 134, 135, 136, 196, 197, 470, 471, 700 },
    ultraBeasts = { 793, 794, 795, 796, 797, 798, 799, 803, 804, 805, 806 },
    paradox = { 984, 985, 986, 987, 988, 989, 990, 991, 992, 993, 994, 995, 1005, 1006, 1009, 1010,
      1020, 1021, 1022, 1023 },
    fossils = { 138, 139, 140, 141, 142, 345, 346, 347, 348, 408, 409, 410, 411, 564, 565, 566, 567,
      696, 697, 698, 699, 880, 881, 882, 883 },
    babies = { 172, 173, 174, 175, 236, 238, 239, 240, 298, 360, 406, 433, 438, 439, 440, 446, 447,
      458, 848 },
  },
  -- a regional variant's `form` starts with its region (GALAR_STANDARD, PALDEA_AQUA_BREED)
  regions = { "ALOLA", "GALAR", "HISUI", "PALDEA" },

  list = {
    { id = "dex_complete", title = "National Dex Complete", points = 100, category = "NATIONAL DEX",
      description = "Catch all 1025 Pokemon in the National Dex.", range = NATIONAL },
    { id = "dex_seen", title = "Seen Them All", points = 50, category = "NATIONAL DEX", seen = true,
      description = "See all 1025 Pokemon in the National Dex.", range = NATIONAL },
    { id = "dex_master", title = "Master Collector", points = 100, category = "NATIONAL DEX",
      description = "Catch all 1025 Pokemon and every one of their alternate forms.",
      range = NATIONAL, forms = "all" },

    { id = "dex_100", title = "Rising Collector", points = 5, category = "NATIONAL DEX",
      description = "Catch 100 different Pokemon.", range = NATIONAL, goal = 100 },
    { id = "dex_250", title = "Seasoned Collector", points = 10, category = "NATIONAL DEX",
      description = "Catch 250 different Pokemon.", range = NATIONAL, goal = 250 },
    { id = "dex_500", title = "Expert Collector", points = 25, category = "NATIONAL DEX",
      description = "Catch 500 different Pokemon.", range = NATIONAL, goal = 500 },
    { id = "dex_750", title = "Elite Collector", points = 50, category = "NATIONAL DEX",
      description = "Catch 750 different Pokemon.", range = NATIONAL, goal = 750 },

    { id = "gen_1", title = "Generation I Complete", points = 25, category = "GENERATIONS",
      description = "Catch all 151 Pokemon first found in Kanto (#001-#151).", range = { 1, 151 } },
    { id = "gen_2", title = "Generation II Complete", points = 15, category = "GENERATIONS",
      description = "Catch all 100 Pokemon first found in Johto (#152-#251).", range = { 152, 251 } },
    { id = "gen_3", title = "Generation III Complete", points = 20, category = "GENERATIONS",
      description = "Catch all 135 Pokemon first found in Hoenn (#252-#386).", range = { 252, 386 } },
    { id = "gen_4", title = "Generation IV Complete", points = 15, category = "GENERATIONS",
      description = "Catch all 107 Pokemon first found in Sinnoh (#387-#493).", range = { 387, 493 } },
    { id = "gen_5", title = "Generation V Complete", points = 25, category = "GENERATIONS",
      description = "Catch all 156 Pokemon first found in Unova (#494-#649).", range = { 494, 649 } },
    { id = "gen_6", title = "Generation VI Complete", points = 10, category = "GENERATIONS",
      description = "Catch all 72 Pokemon first found in Kalos (#650-#721).", range = { 650, 721 } },
    { id = "gen_7", title = "Generation VII Complete", points = 15, category = "GENERATIONS",
      description = "Catch all 88 Pokemon first found in Alola (#722-#809).", range = { 722, 809 } },
    { id = "gen_8", title = "Generation VIII Complete", points = 15, category = "GENERATIONS",
      description = "Catch all 96 Pokemon first found in Galar and Hisui (#810-#905).", range = { 810, 905 } },
    { id = "gen_9", title = "Generation IX Complete", points = 20, category = "GENERATIONS",
      description = "Catch all 120 Pokemon first found in Paldea (#906-#1025).", range = { 906, 1025 } },

    { id = "starters", title = "Starter Collection", points = 25, category = "COLLECTIONS",
      description = "Catch the first stage of all 27 starter Pokemon, from Bulbasaur to Quaxly.",
      dex = "starters" },
    { id = "legendary", title = "Legend Hunter", points = 50, category = "COLLECTIONS",
      description = "Catch every Legendary Pokemon.", flag = "legendary" },
    { id = "mythical", title = "Myth Seeker", points = 50, category = "COLLECTIONS",
      description = "Catch every Mythical Pokemon.", flag = "mythical" },
    { id = "ultra_beasts", title = "Beast Within", points = 25, category = "COLLECTIONS",
      description = "Catch all 11 Ultra Beasts.", dex = "ultraBeasts" },
    { id = "paradox", title = "Past and Future", points = 25, category = "COLLECTIONS",
      description = "Catch all 20 Paradox Pokemon.", dex = "paradox" },
    { id = "fossils", title = "Living Fossils", points = 10, category = "COLLECTIONS",
      description = "Catch all 25 Pokemon revived from fossils, and their evolutions.", dex = "fossils" },
    { id = "babies", title = "Nursery", points = 10, category = "COLLECTIONS",
      description = "Catch all 19 baby Pokemon.", dex = "babies" },

    { id = "regional_alola", title = "Alolan Variants", points = 10, category = "VARIANTS",
      description = "Catch all 18 Alolan forms.", forms = "regional", region = "ALOLA" },
    { id = "regional_galar", title = "Galarian Variants", points = 10, category = "VARIANTS",
      description = "Catch all 19 Galarian forms.", forms = "regional", region = "GALAR" },
    { id = "regional_hisui", title = "Hisuian Variants", points = 10, category = "VARIANTS",
      description = "Catch all 16 Hisuian forms.", forms = "regional", region = "HISUI" },
    { id = "regional_paldea", title = "Paldean Variants", points = 5, category = "VARIANTS",
      description = "Catch all 4 Paldean forms.", forms = "regional", region = "PALDEA" },
    { id = "regional_all", title = "World Traveler", points = 25, category = "VARIANTS",
      description = "Catch all 57 regional forms: Alolan, Galarian, Hisuian and Paldean.", forms = "regional" },

    { id = "family_eevee", title = "Eeveelutions", points = 10, category = "VARIANTS",
      description = "Catch all 8 of Eevee's evolutions.", dex = "eeveelutions" },
    { id = "family_alcremie", title = "Sweet Tooth", points = 10, category = "VARIANTS",
      description = "Catch all 9 Alcremie creams.", family = "ALCREMIE" },
    { id = "family_rotom", title = "Appliance Store", points = 10, category = "VARIANTS",
      description = "Catch Rotom and all 5 of its appliance forms.", family = "ROTOM" },
    { id = "family_lycanroc", title = "Day, Dusk and Night", points = 5, category = "VARIANTS",
      description = "Catch Midday, Midnight and Dusk Lycanroc.", family = "LYCANROC" },
    { id = "family_oricorio", title = "Dance Card", points = 5, category = "VARIANTS",
      description = "Catch Oricorio in all 4 of its dance styles.", family = "ORICORIO" },
  },
}
