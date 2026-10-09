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
}
