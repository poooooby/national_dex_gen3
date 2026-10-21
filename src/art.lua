-- The art seam. This mod ships no pictures; a sprite mod supplies them:
--
--   local dex = mod:find("national_dex_gen3")
--   if dex then
--     dex.exports.setArtProvider(function(speciesId, side, slot, shiny, kind)
--       return mod.assets:path("front/" .. speciesId .. ".png")   -- or nil
--     end)
--   end
--
-- `side` is "front" or "back"; `shiny` is true for a shiny Pokemon's picture and
-- `kind` says where it is drawn ("battle", "dex", ...), both from the engine's
-- sprite ctx (providers written for three arguments simply ignore them). Return
-- a PNG path (any size; the engine centres and crops it to 64x64) or nil to let
-- the next provider answer.
-- Only this mod's species are asked about; the cart's own 386 are untouched.
--
-- Wired through the Gen 3 pokemon.sprite hook (src/mods/Gen3Compat.lua), whose
-- ctx carries the species slot as gen3Species; a returned `.rgba` path is
-- ignored by the engine, so providers must return an image file.

local Art = {}

function Art.install(mod, registered)
  local bySlot = {}
  for _, r in ipairs(registered) do bySlot[r.slot] = r end
  local providers = {}

  mod.hooks:wrap("pokemon.sprite", function(nextFn, path, ctx)
    local out = nextFn(path, ctx)
    local slot = type(ctx) == "table" and tonumber(ctx.gen3Species) or nil
    local record = slot and bySlot[slot]
    if not record then return out end
    for _, provider in ipairs(providers) do
      local ok, result = pcall(provider, record.id, ctx.side, slot, ctx.shiny == true, ctx.kind)
      if ok and type(result) == "string" and result ~= ""
        and not result:lower():find("%.rgba$") then
        return result
      end
    end
    return out
  end)

  return {
    add = function(fn)
      if type(fn) ~= "function" then return false end
      providers[#providers + 1] = fn
      return true
    end,
    count = function() return #providers end,
  }
end

return Art
