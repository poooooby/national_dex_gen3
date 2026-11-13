-- The Mod Manager options on Gen 1 / Gen 2 (the manifest's options_schema is Gen 3's). The keys
-- are the Gen 3 ones, so an option means the same thing on every game. Labels: 14 characters.
-- Options.forGeneration(gen) -> the list this game shows (Day & Night is Red / Blue / Yellow's
-- only: Gold / Silver / Crystal have their own day and night). A row's `byGeneration` replaces
-- fields for one generation (the Bigger PC's box count).

local Options = {}

Options.ROWS = {
  {
    key = "modern_moves",
    label = "Modern Moves",
    type = "toggle",
    default = true,
    description = "Let the game's own Pokemon learn the newer moves they learn in today's games, at the same levels, plus their newer egg moves (Gold, Silver, Crystal). Only moves this game can do are added; their own moves stay. Moves a Pokemon already knows are kept when you turn this off.",
  },
  {
    key = "register_owned",
    label = "Register Owned",
    type = "toggle",
    default = true,
    description = "When you open the Pokedex, count every Pokemon in your party and PC as seen and caught. Pokemon added with a save editor never went through a catch, so the game never registered them. Eggs are skipped.",
  },
  {
    key = "day_night",
    label = "Day & Night",
    type = "toggle",
    default = true,
    generations = { [1] = true },
    description = "Tints the outdoors by your device's time of day: morning (4-10), afternoon (the game's own look, 10-17), evening (17-20) and night (20-4). It changes when you enter an area. Indoors, caves, battles and menus are never tinted.",
  },
  {
    key = "big_pc",
    label = "Bigger PC",
    type = "toggle",
    default = true,
    description = "40 PC boxes (800 Pokemon) instead of 12. Turning it off hides boxes 13-40; the Pokemon in them are kept in your save and come back when you turn it on again.",
    byGeneration = { [2] = {
      description = "40 PC boxes (800 Pokemon) instead of 14. Turning it off hides boxes 15-40; the Pokemon in them are kept in your save and come back when you turn it on again.",
    } },
  },
  {
    key = "type_badges",
    label = "Type Badges",
    type = "toggle",
    default = true,
    description = "Show each Pokemon's types as small badges beside its HP box in battle: right of a foe's name and HP bar, left of yours. They follow the battle: a Pokemon that used Conversion or Transform shows its new type.",
  },
  {
    key = "move_split",
    label = "Move Split",
    type = "toggle",
    default = false,
    description = "Decide whether a move is physical or special by the move itself, as in today's games (Shadow Ball special, Crunch and Fire Punch physical), instead of by its type as these games do. It changes how the game's own moves hit too.",
  },
}

function Options.forGeneration(gen)
  local out = {}
  for _, row in ipairs(Options.ROWS) do
    if not row.generations or row.generations[gen] then
      local copy = {}
      for k, v in pairs(row) do
        if k ~= "generations" and k ~= "byGeneration" then copy[k] = v end
      end
      for k, v in pairs(row.byGeneration and row.byGeneration[gen] or {}) do copy[k] = v end
      out[#out + 1] = copy
    end
  end
  return out
end

return Options
