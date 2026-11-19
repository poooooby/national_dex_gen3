-- mod.exports.artHeightOf / artHeights: how tall each WoobleSprite front picture really stands, for
-- other mods' height charts (WoobleOS's Pokedex). Every game, Red to Emerald. Added in 1.17.0;
-- test for them by presence.
--
--   local dex = mod.find("national_dex_gen3")
--   local h = dex and dex.exports.artHeightOf and dex.exports.artHeightOf("ONIX")
--   -- h = { id = "ONIX", dex = 95, slot = 95, pokedex = 8.8, standing = 3.813, art = 3.813,
--   --       width = 3.71, long = true }
--
--   artHeightOf(idOrDex)  one sprite's row, or nil. A string is a sprite id as in the WoobleSprite
--                         pack (species ids, forms such as "VULPIX_ALOLA", "MEOWSTIC_FEMALE"); a
--                         number is a National Dex number (the base species)
--   artHeights()          every row, keyed by id
--
-- In metres: pokedex the Pokedex height (PokeAPI's own for forms); standing the resting picture,
-- feet to top (how tall it is drawn standing still: the height for a chart beside a person);
-- art feet to the top of the art over the whole animation (WoobleView's battle size); width the
-- resting picture's width; long true when the Pokedex number is a length (serpents, fish), which
-- is why their standing is lower. Measured by poke-scale-realism on WoobleSprite's front sprites
-- (data/art_heights.lua, tools/build_art_heights.py); a mod drawing other pictures can still use
-- standing as how tall the Pokemon stands. Every return is a copy. The data is read on first use.

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- mod: this mod; opts: { read = function(path) -> the loaded data file | nil }
return function(mod, opts)
  local exports = mod.exports
  if type(exports) ~= "table" then return end
  local rows, byDex
  local function load()
    if rows then return rows end
    local ok, data = pcall(opts.read, "data/art_heights.lua")
    rows, byDex = {}, {}
    if ok and type(data) == "table" then
      for id, r in pairs(data) do
        if type(r) == "table" then
          r.id = id
          rows[id] = r
          -- (the base species answers for its number: the row whose slot is its own)
          local d = tonumber(r.dex)
          if d and r.slot and (not byDex[d] or (byDex[d].slot or 0) > r.slot) then byDex[d] = r end
        end
      end
    end
    return rows
  end

  exports.artHeightOf = function(idOrDex)
    load()
    local r
    if type(idOrDex) == "string" then
      r = rows[idOrDex] or rows[idOrDex:upper()]
    elseif tonumber(idOrDex) then
      r = byDex[tonumber(idOrDex)]
    end
    return r and copy(r) or nil
  end

  exports.artHeights = function()
    return copy(load())
  end
end
