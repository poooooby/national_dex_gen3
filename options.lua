-- Mod Manager option schema for national_dex_gen3.
-- Labels are limited to 14 characters.

return {
  {
    key = "clock_source",
    label = "Clock Source",
    type = "choice",
    default = "game",
    choices = {
      { "In-game", "game" },
      { "Device", "device" },
    },
    description = "Which clock the time of day comes from: the Day & Night look and the time-of-day evolutions (Midnight Lycanroc, the night and day Alcremie creams, Budew, Riolu, Chingling and Snom). In-game is the cart's own clock; Device is the real time on your device. FireRed and LeafGreen have no clock of their own and always use the device.",
  },
  {
    key = "day_night",
    label = "Day & Night",
    type = "toggle",
    default = true,
    description = "Tints the outdoors by time of day: morning (4-10), afternoon (the game's own look, 10-17), evening (17-20) and night (20-4). It changes when you enter an area. Follows Clock Source. Indoors, caves, battles and menus are never tinted.",
  },
  {
    key = "unlock_national",
    label = "National Dex",
    type = "toggle",
    default = false,
    description = "Turn the National Pokedex on from the start, instead of earning it in the story. Nothing is written to your save, so turning this off puts the game back as it was.",
  },
  {
    key = "modern_moves",
    label = "Modern Moves",
    type = "toggle",
    default = true,
    description = "Let the original 386 Pokemon learn the newer moves they learn in today's games, at the same levels (Clefairy learns Moonblast at 44), plus their newer egg moves. Their own Gen 3 moves stay. Moves a Pokemon already knows are kept when you turn this off.",
  },
  {
    key = "big_pc",
    label = "Bigger PC",
    type = "toggle",
    default = true,
    description = "40 PC boxes (1200 Pokemon) instead of 14. Turning it off hides boxes 15-40; the Pokemon in them are kept in your save and come back when you turn it on again.",
  },
  {
    key = "register_owned",
    label = "Register Owned",
    type = "toggle",
    default = true,
    description = "When you open the Pokedex, count every Pokemon in your party and PC as seen and caught. Pokemon added with a save editor never went through a catch, so the game never registered them. Eggs are skipped.",
  },
}
