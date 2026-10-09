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
    description = "Which clock the time-of-day evolutions read (Midnight Lycanroc, the night and day Alcremie creams, Budew, Riolu, Chingling and Snom). In-game is the cart's own clock; Device is the real time on your device. FireRed and LeafGreen have no clock of their own and always use the device.",
  },
  {
    key = "unlock_national",
    label = "National Dex",
    type = "toggle",
    default = false,
    description = "Turn the National Pokedex on from the start, instead of earning it in the story. Nothing is written to your save, so turning this off puts the game back as it was.",
  },
  {
    key = "register_owned",
    label = "Register Owned",
    type = "toggle",
    default = true,
    description = "When you open the Pokedex, count every Pokemon in your party and PC as seen and caught. Pokemon added with a save editor never went through a catch, so the game never registered them. Eggs are skipped.",
  },
}
